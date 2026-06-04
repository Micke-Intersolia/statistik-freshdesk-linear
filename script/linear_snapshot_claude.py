#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
linear_snapshot_claude.py
Hämtar en full snapshot från Linear och sparar en timestampad råfil i ../raw/linear/.
Strömmar data per sida till disk (låg minnesfotavtryck) och skriver atomiskt (tmp -> slutfil).

Kör:
  python script/linear_snapshot_claude.py

Krav:
  pip install requests

Miljövariabler (valfria):
  LINEAR_API_KEY  — om satt används den istället för credentials/Linear_API-key.txt
"""

from pathlib import Path
from datetime import datetime, timedelta, timezone
import json
import logging
import logging.handlers
import os
import re
import time
import requests

# -------------------------
# Konfiguration
# -------------------------
try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

RAW_DIR = (SCRIPT_DIR.parent / "raw" / "linear").resolve()
LOG_DIR = (SCRIPT_DIR.parent / "logs").resolve()
CREDENTIALS_PATH = (SCRIPT_DIR.parent / "credentials" / "Linear_API-key.txt").resolve()
LINEAR_API_URL = "https://api.linear.app/graphql"

PAGE_SIZE = 100
MAX_RETRIES = 5
RETRY_BACKOFF = 2        # sekunder, bas för exponentiell backoff
RETENTION_DAYS = 30
USER_AGENT = "puttaren-agent/1.0"
SCRIPT_VERSION = "2.0"


# -------------------------
# Logging (roterande fil + konsol)
# -------------------------
def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    file_handler = logging.handlers.RotatingFileHandler(
        LOG_DIR / "linear_snapshot.log",
        maxBytes=5_000_000,
        backupCount=10,
        encoding="utf-8",
    )
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler.setFormatter(fmt)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(fmt)
    logging.basicConfig(level=logging.INFO, handlers=[file_handler, console_handler])


# -------------------------
# API-nyckel
# -------------------------
def read_api_key() -> str:
    key = os.environ.get("LINEAR_API_KEY", "").strip()
    if key:
        logging.info("Använder LINEAR_API_KEY från miljövariabel.")
        return key
    logging.info("Läser API-nyckel från: %s", CREDENTIALS_PATH)
    if not CREDENTIALS_PATH.exists():
        raise FileNotFoundError(f"API-nyckel saknas: {CREDENTIALS_PATH}")
    key = CREDENTIALS_PATH.read_text(encoding="utf-8").strip()
    if not key:
        raise ValueError("API-nyckeln är tom.")
    if key.lower().startswith("bearer "):
        key = key.split(None, 1)[1].strip()
    return key


# -------------------------
# Underhåll av raw-katalog
# -------------------------
def cleanup_stale_tmp_files() -> None:
    stale = list(RAW_DIR.glob("*.tmp"))
    for f in stale:
        logging.warning("Rensar gammal tmp-fil: %s", f.name)
        f.unlink(missing_ok=True)
    if stale:
        logging.info("Rensade %d gammal(a) tmp-fil(er).", len(stale))


def _snapshot_date(path: Path) -> datetime | None:
    """Parsar snapshot-tidsstämpel ur filnamnet (YYYYMMDDTHHMMSSZ)."""
    m = re.search(r"(\d{8}T\d{6}Z)", path.name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def enforce_retention() -> None:
    """Tar bort snapshot-filer (inkl. .meta.json) äldre än RETENTION_DAYS.
    Använder tidsstämpeln i filnamnet — inte mtime — så att det fungerar
    korrekt även på GitHub Actions där alla filer får dagens mtime vid checkout.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    removed = 0
    for old in RAW_DIR.glob("linear_snapshot_*.json"):
        snap_dt = _snapshot_date(old)
        if snap_dt and snap_dt < cutoff:
            old.unlink()
            logging.info("Retention: raderade %s (>%dd).", old.name, RETENTION_DAYS)
            removed += 1
    if removed:
        logging.info("Retention: totalt %d fil(er) raderade.", removed)


# -------------------------
# GraphQL query
# -------------------------
GRAPHQL_QUERY = """
query($first: Int!, $after: String) {
  issues(first: $first, after: $after, includeArchived: true) {
    nodes {
      id
      number
      identifier
      title
      description
      createdAt
      updatedAt
      archivedAt
      completedAt
      canceledAt
      startedAt
      dueDate
      priority
      estimate
      trashed
      state        { id name type }
      assignee     { id name email }
      project      { id name }
      team         { id name }
      labels       { nodes { name } }
      parent       { id identifier }
      cycle        { id name startsAt endsAt }
    }
    pageInfo { hasNextPage endCursor }
  }
}
"""


# -------------------------
# Fetch + stream till disk
# -------------------------
def fetch_and_stream_snapshot(api_key: str, out_path: Path) -> tuple[int, int]:
    """
    Hämtar alla issues med cursor-pagination och skriver dem löpande till out_path.
    Returnerar (total_noder, antal_sidor).
    Tar bort tmp-filen vid fel — kastar annars aldrig en tom fil till raw.
    """
    headers = {
        "Authorization": api_key,
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    }

    cursor = None
    page = 0
    total = 0
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    logging.info("Stream-sparar till tmp: %s", tmp_path.name)

    try:
        with tmp_path.open("w", encoding="utf-8") as f:
            f.write("[\n")
            first_item = True

            while True:
                page += 1
                payload = {
                    "query": GRAPHQL_QUERY,
                    "variables": {"first": PAGE_SIZE, "after": cursor},
                }
                attempt = 0

                # --- Retry-loop ---
                while True:
                    attempt += 1
                    try:
                        r = requests.post(
                            LINEAR_API_URL, headers=headers, json=payload, timeout=60
                        )
                    except requests.RequestException as ex:
                        logging.warning(
                            "RequestException sida %d försök %d: %s", page, attempt, ex
                        )
                        if attempt >= MAX_RETRIES:
                            raise
                        wait = RETRY_BACKOFF ** attempt
                        logging.info("Väntar %ds innan retry...", wait)
                        time.sleep(wait)
                        continue

                    if r.status_code == 401:
                        raise RuntimeError(
                            "Autentisering misslyckades (401) — "
                            "kontrollera LINEAR_API_KEY eller credentials/Linear_API-key.txt"
                        )

                    if r.status_code == 429:
                        logging.warning("Rate limited (429) sida %d försök %d", page, attempt)
                        if attempt >= MAX_RETRIES:
                            r.raise_for_status()
                        # Respektera Retry-After om Linear skickar den
                        wait = int(r.headers.get("Retry-After", RETRY_BACKOFF ** attempt))
                        logging.info("Väntar %ds (Retry-After)...", wait)
                        time.sleep(wait)
                        continue

                    if r.status_code >= 500:
                        logging.warning(
                            "Serverfel %d sida %d försök %d", r.status_code, page, attempt
                        )
                        if attempt >= MAX_RETRIES:
                            r.raise_for_status()
                        time.sleep(RETRY_BACKOFF ** attempt)
                        continue

                    break  # 2xx eller annan 4xx — gå vidare till JSON-parsning

                # --- JSON-parsning ---
                try:
                    data = r.json()
                except ValueError:
                    logging.error(
                        "Ogiltigt JSON-svar från Linear (sida %d): %s", page, r.text[:1000]
                    )
                    raise RuntimeError("Ogiltigt JSON-svar från Linear")

                if "errors" in data:
                    logging.error("GraphQL errors sida %d: %s", page, data["errors"])
                    raise RuntimeError(f"GraphQL error: {data['errors']}")

                issues_data = data.get("data") or {}
                if not issues_data:
                    logging.error(
                        "Saknar 'data' i API-svar (sida %d): %s", page, str(data)[:500]
                    )
                    raise RuntimeError("Oväntat API-svar: saknar 'data'-nyckel")

                block = issues_data.get("issues", {}).get("nodes", [])
                logging.info("Sida %d: %d noder hämtade", page, len(block))

                for node in block:
                    if not first_item:
                        f.write(",\n")
                    else:
                        first_item = False
                    json.dump(node, f, ensure_ascii=False)
                    total += 1

                page_info = issues_data.get("issues", {}).get("pageInfo", {})
                if page_info.get("hasNextPage"):
                    cursor = page_info.get("endCursor")
                    if not cursor:
                        # Defensiv: bryt hellre än att loopa om för evigt
                        logging.error(
                            "hasNextPage=True men endCursor saknas (sida %d) — avslutar paginering",
                            page,
                        )
                        break
                else:
                    break

            f.write("\n]\n")

    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise

    # Guard: tom snapshot ska aldrig nå raw/
    if total == 0:
        tmp_path.unlink(missing_ok=True)
        logging.critical(
            "Snapshot innehåller 0 noder — avbryter för att skydda bronze-lagret."
        )
        raise SystemExit(2)

    tmp_path.replace(out_path)
    logging.info("Atomiskt promoted: %s", out_path.name)
    return total, page


# -------------------------
# Sidecar metadata
# -------------------------
def write_meta(meta_path: Path, ts: str, total: int, pages: int) -> None:
    meta = {
        "ts": ts,
        "total_nodes": total,
        "pages": pages,
        "script_version": SCRIPT_VERSION,
        "page_size": PAGE_SIZE,
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    logging.info("Metafil sparad: %s", meta_path.name)


# -------------------------
# Main
# -------------------------
def main() -> None:
    setup_logging()
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    try:
        cleanup_stale_tmp_files()
        enforce_retention()

        api_key = read_api_key()
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out_file = RAW_DIR / f"linear_snapshot_{ts}.json"
        meta_file = RAW_DIR / f"linear_snapshot_{ts}.meta.json"

        logging.info("=== Startar Linear snapshot v%s ===", SCRIPT_VERSION)
        total, pages = fetch_and_stream_snapshot(api_key, out_file)
        write_meta(meta_file, ts, total, pages)

        # Rensa eventuella kvarglömda tmp-filer efter lyckad körning
        cleanup_stale_tmp_files()

        logging.info("=== Klar: %s | %d noder | %d sidor ===", out_file.name, total, pages)

    except KeyboardInterrupt:
        logging.warning("Avbröts av användare.")
        raise
    except SystemExit:
        raise
    except Exception as e:
        logging.exception("Fel vid snapshot: %s", e)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
