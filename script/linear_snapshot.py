#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
linear_snapshot.py
Hämtar en full snapshot från Linear och sparar en timestampad råfil i ../raw/linear/.
Sparar i ett atomiskt skrivsteg och strömmar data till disk per sida (chunk-sparande)
så att hela datasetet inte behöver ligga i minnet.

Kör:
  python script/linear_snapshot.py

Krav:
  pip install requests python-dateutil
"""

from pathlib import Path
from datetime import datetime, timezone
import json
import time
import logging
import requests

# -------------------------
# Konfiguration (relativa sökvägar)
# -------------------------
try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

RAW_DIR = (SCRIPT_DIR.parent / "raw" / "linear").resolve()
RAW_DIR.mkdir(parents=True, exist_ok=True)

CREDENTIALS_PATH = (SCRIPT_DIR.parent / "credentials" / "Linear_API-key.txt").resolve()
LINEAR_API_URL = "https://api.linear.app/graphql"

# Pagination / retry
PAGE_SIZE = 100
MAX_RETRIES = 5
RETRY_BACKOFF = 2  # sekunder, exponentiell backoff

# User-Agent enligt önskemål
USER_AGENT = "puttaren-agent/1.0"

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


# -------------------------
# Hjälpfunktioner
# -------------------------
def read_api_key(path: Path = CREDENTIALS_PATH) -> str:
    """
    Läser Linear API-nyckel från fil. Returnerar rå token (utan 'Bearer ').
    """
    logging.info("Läser API-nyckel från: %s", path)
    if not path.exists():
        raise FileNotFoundError(f"API-nyckel saknas: {path}")
    key = path.read_text(encoding="utf-8").strip()
    if not key:
        raise ValueError("API-nyckeln är tom.")
    # Linear kräver rå token i Authorization-header (ingen 'Bearer ' prefix)
    if key.lower().startswith("bearer "):
        key = key.split(None, 1)[1].strip()
        logging.info("Tog bort 'Bearer ' prefix från filinnehållet.")
    return key


# -------------------------
# GraphQL query och stream-fetch
# -------------------------
GRAPHQL_QUERY = """
query($first:Int!, $after:String) {
  issues(first:$first, after:$after, includeArchived:true) {
    nodes {
      id number identifier title description createdAt updatedAt archivedAt
      priority estimate trashed
      state { id name type }
      assignee { id name email }
      project { id name }
      team { id name }
      labels { nodes { name } }
    }
    pageInfo { hasNextPage endCursor }
  }
}
"""


def fetch_and_stream_snapshot(api_key: str, out_path: Path, page_size: int = PAGE_SIZE) -> int:
    """
    Hämtar issues med pagination och skriver dem löpande till out_path som en JSON-array.
    Returnerar totalt antal noder skrivna.
    """
    headers = {
        "Authorization": api_key,
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    }

    cursor = None
    page = 0
    total = 0

    # Skriv till temporär fil först
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    logging.info("Stream-sparar snapshot till temporär fil: %s", tmp_path)

    # Öppna fil och skriv öppningsbracket för JSON-array
    with tmp_path.open("w", encoding="utf-8") as f:
        f.write("[\n")
        first_item = True

        while True:
            page += 1
            payload = {"query": GRAPHQL_QUERY, "variables": {"first": page_size, "after": cursor}}
            attempt = 0

            while True:
                attempt += 1
                try:
                    r = requests.post(LINEAR_API_URL, headers=headers, json=payload, timeout=60)
                except requests.RequestException as ex:
                    logging.warning("RequestException page %d attempt %d: %s", page, attempt, ex)
                    if attempt >= MAX_RETRIES:
                        raise
                    wait = RETRY_BACKOFF ** attempt
                    logging.info("Väntar %ds innan retry...", wait)
                    time.sleep(wait)
                    continue

                # Hantera rate limit och serverfel
                if r.status_code == 429:
                    logging.warning("Rate limited (429) page %d attempt %d", page, attempt)
                    if attempt >= MAX_RETRIES:
                        r.raise_for_status()
                    wait = RETRY_BACKOFF ** attempt
                    time.sleep(wait)
                    continue

                if r.status_code >= 500:
                    logging.warning("Server error %d page %d attempt %d", r.status_code, page, attempt)
                    if attempt >= MAX_RETRIES:
                        r.raise_for_status()
                    wait = RETRY_BACKOFF ** attempt
                    time.sleep(wait)
                    continue

                break  # lyckad request (eller annan 4xx som vi låter gå vidare till JSON-parsning)

            # Försök parsa JSON
            try:
                data = r.json()
            except ValueError:
                logging.error("Kunde inte parsa JSON från Linear (truncated): %s", r.text[:1000])
                raise RuntimeError("Kunde inte parsa JSON från Linear")

            if "errors" in data:
                logging.error("GraphQL errors: %s", data["errors"])
                raise RuntimeError(f"GraphQL error: {data['errors']}")

            block = data.get("data", {}).get("issues", {}).get("nodes", [])
            logging.info("Sida %d: hämtade %d noder", page, len(block))

            # Skriv varje nod direkt till fil (som JSON, komma-separerad)
            for node in block:
                if not first_item:
                    f.write(",\n")
                else:
                    first_item = False
                json.dump(node, f, ensure_ascii=False)
                total += 1

            pageInfo = data.get("data", {}).get("issues", {}).get("pageInfo", {})
            if pageInfo.get("hasNextPage"):
                cursor = pageInfo.get("endCursor")
            else:
                break

        # Stäng JSON-arrayen
        f.write("\n]\n")

    # Atomisk ersättning: byt tmp -> out_path
    tmp_path.replace(out_path)
    logging.info("Atomiskt flyttade %s -> %s", tmp_path, out_path)
    return total


# -------------------------
# Huvud
# -------------------------
def main():
    try:
        api_key = read_api_key()
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out_file = RAW_DIR / f"linear_snapshot_{ts}.json"

        logging.info("Startar full pull från Linear...")
        total = fetch_and_stream_snapshot(api_key, out_file, page_size=PAGE_SIZE)
        logging.info("Sparade snapshot: %s (%d noder)", out_file, total)
    except KeyboardInterrupt:
        logging.warning("Avbröts av användare")
        raise
    except Exception as e:
        logging.exception("Fel vid snapshot: %s", e)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
