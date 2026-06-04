#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
freshdesk_snapshot_claude.py
Hämtar en nightly snapshot från Freshdesk och sparar en timestampad råfil i ../raw/freshdesk/.
Strömmar data per sida till disk och skriver atomiskt (tmp -> slutfil).

Standardkörning (nightly — aktiva tickets, ~30 dagar):
  python script/freshdesk_snapshot_claude.py

Backfill från ett specifikt datum:
  python script/freshdesk_snapshot_claude.py 2025-05-01

Krav:
  pip install requests

Miljövariabler (valfria):
  FRESHDESK_API_KEY  — om satt används den istället för credentials/Freshdesk_API-key.txt
  FRESHDESK_DOMAIN   — default: intersolia
"""

from pathlib import Path
from datetime import datetime, timedelta, timezone
import json
import logging
import logging.handlers
import os
import re
import sys
import time
import requests
from requests.auth import HTTPBasicAuth

# -------------------------
# Konfiguration
# -------------------------
try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

RAW_DIR          = (SCRIPT_DIR.parent / "raw" / "freshdesk").resolve()
LOG_DIR          = (SCRIPT_DIR.parent / "logs").resolve()
CREDENTIALS_PATH = (SCRIPT_DIR.parent / "credentials" / "Freshdesk_API-key.txt").resolve()

FRESHDESK_DOMAIN  = os.environ.get("FRESHDESK_DOMAIN", "intersolia")
FRESHDESK_API_URL = f"https://{FRESHDESK_DOMAIN}.freshdesk.com/api/v2/tickets"

# Inga expanded includes behövs — alla kvarvarande fält är core-fält i bas-svaret
INCLUDE_FIELDS = ""

PAGE_SIZE      = 100
MAX_PAGES      = 300          # Freshdesks hårdgräns: 300 × 100 = 30 000 tickets
MAX_RETRIES    = 5
RETRY_BACKOFF  = 2
RETENTION_DAYS = 30
USER_AGENT     = "puttaren-agent/1.0"
SCRIPT_VERSION = "2.1"


# -------------------------
# Logging
# -------------------------
def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    file_handler = logging.handlers.RotatingFileHandler(
        LOG_DIR / "freshdesk_snapshot.log",
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
    key = os.environ.get("FRESHDESK_API_KEY", "").strip()
    if key:
        logging.info("Använder FRESHDESK_API_KEY från miljövariabel.")
        return key
    logging.info("Läser API-nyckel från: %s", CREDENTIALS_PATH)
    if not CREDENTIALS_PATH.exists():
        raise FileNotFoundError(f"API-nyckel saknas: {CREDENTIALS_PATH}")
    key = CREDENTIALS_PATH.read_text(encoding="utf-8").strip()
    if not key:
        raise ValueError("API-nyckeln är tom.")
    return key


# -------------------------
# Fältextraktion
# Plattar ut nested objekt (requester, company, stats, custom_fields)
# till en platt struktur — bättre för SQL-laddning.
# -------------------------
def extract_fields(ticket: dict) -> dict:
    return {
        "id":         ticket.get("id"),
        "subject":    ticket.get("subject"),
        "status":     ticket.get("status"),
        "priority":   ticket.get("priority"),
        "created_at": ticket.get("created_at"),
        "updated_at": ticket.get("updated_at"),
        "due_by":     ticket.get("due_by"),
        "group_id":   ticket.get("group_id"),
        "product_id": ticket.get("product_id"),
    }


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
    m = re.search(r"(\d{8}T\d{6}Z)", path.name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def enforce_retention() -> None:
    """Använder tidsstämpeln i filnamnet (inte mtime) — fungerar korrekt på GitHub Actions."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    removed = 0
    for old in RAW_DIR.glob("freshdesk_snapshot_*.json"):
        snap_dt = _snapshot_date(old)
        if snap_dt and snap_dt < cutoff:
            old.unlink()
            logging.info("Retention: raderade %s (>%dd).", old.name, RETENTION_DAYS)
            removed += 1
    if removed:
        logging.info("Retention: totalt %d fil(er) raderade.", removed)


# -------------------------
# Fetch + stream till disk
# -------------------------
def fetch_and_stream_snapshot(
    api_key: str,
    out_path: Path,
    updated_since: str | None = None,
) -> tuple[int, int]:
    """
    Hämtar tickets med page-pagination, extraherar överenskomna fält,
    och strömmar dem till out_path som en JSON-array.
    Returnerar (total_tickets, antal_sidor).
    """
    auth = HTTPBasicAuth(api_key, "X")
    headers = {"Content-Type": "application/json", "User-Agent": USER_AGENT}

    base_params = {
        "per_page":   PAGE_SIZE,
        "order_by":   "created_at",
        "order_type": "asc",
    }
    if INCLUDE_FIELDS:
        base_params["include"] = INCLUDE_FIELDS
    if updated_since:
        base_params["updated_since"] = updated_since
        logging.info("Hämtar tickets uppdaterade sedan: %s", updated_since)
    else:
        logging.info("Hämtar aktiva tickets (standard ~30-dagars fönster).")

    page  = 0
    total = 0
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    logging.info("Stream-sparar till tmp: %s", tmp_path.name)

    try:
        with tmp_path.open("w", encoding="utf-8") as f:
            f.write("[\n")
            first_item = True

            while True:
                page += 1

                if page > MAX_PAGES:
                    logging.warning(
                        "Nådde MAX_PAGES (%d). Kör med updated_since för att dela upp i intervall.",
                        MAX_PAGES,
                    )
                    break

                params  = {**base_params, "page": page}
                attempt = 0

                while True:
                    attempt += 1
                    try:
                        r = requests.get(
                            FRESHDESK_API_URL,
                            auth=auth,
                            headers=headers,
                            params=params,
                            timeout=60,
                        )
                    except requests.RequestException as ex:
                        logging.warning("RequestException sida %d försök %d: %s", page, attempt, ex)
                        if attempt >= MAX_RETRIES:
                            raise
                        wait = RETRY_BACKOFF ** attempt
                        logging.info("Väntar %ds innan retry...", wait)
                        time.sleep(wait)
                        continue

                    if r.status_code == 401:
                        raise RuntimeError(
                            "Autentisering misslyckades (401) — "
                            "kontrollera FRESHDESK_API_KEY eller credentials/Freshdesk_API-key.txt"
                        )

                    if r.status_code == 403:
                        raise RuntimeError("Åtkomst nekad (403) — API-nyckeln saknar behörighet.")

                    if r.status_code == 429:
                        logging.warning("Rate limited (429) sida %d försök %d", page, attempt)
                        if attempt >= MAX_RETRIES:
                            r.raise_for_status()
                        wait = int(r.headers.get("Retry-After", RETRY_BACKOFF ** attempt))
                        logging.info("Väntar %ds (Retry-After)...", wait)
                        time.sleep(wait)
                        continue

                    if r.status_code >= 500:
                        logging.warning("Serverfel %d sida %d försök %d", r.status_code, page, attempt)
                        if attempt >= MAX_RETRIES:
                            r.raise_for_status()
                        time.sleep(RETRY_BACKOFF ** attempt)
                        continue

                    break

                try:
                    block = r.json()
                except ValueError:
                    logging.error("Ogiltigt JSON-svar sida %d: %s", page, r.text[:1000])
                    raise RuntimeError("Ogiltigt JSON-svar från Freshdesk")

                if isinstance(block, dict) and "errors" in block:
                    logging.error("Freshdesk API-fel sida %d: %s", page, block)
                    raise RuntimeError(f"Freshdesk API-fel: {block}")

                if not isinstance(block, list):
                    logging.error("Oväntat svar sida %d (typ %s): %s", page, type(block), str(block)[:300])
                    raise RuntimeError("Oväntat svar från Freshdesk — förväntade list")

                logging.info("Sida %d: %d tickets hämtade", page, len(block))

                for ticket in block:
                    row = extract_fields(ticket)
                    if not first_item:
                        f.write(",\n")
                    else:
                        first_item = False
                    json.dump(row, f, ensure_ascii=False)
                    total += 1

                if len(block) < PAGE_SIZE:
                    break

            f.write("\n]\n")

    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise

    if total == 0:
        tmp_path.unlink(missing_ok=True)
        logging.critical("Snapshot innehåller 0 tickets — avbryter för att skydda bronze-lagret.")
        raise SystemExit(2)

    tmp_path.replace(out_path)
    logging.info("Atomiskt promoted: %s", out_path.name)
    return total, page


# -------------------------
# Sidecar metadata
# -------------------------
def write_meta(meta_path: Path, ts: str, total: int, pages: int, updated_since: str | None) -> None:
    meta = {
        "ts":            ts,
        "total_tickets": total,
        "pages":         pages,
        "script_version": SCRIPT_VERSION,
        "page_size":     PAGE_SIZE,
        "include_fields": INCLUDE_FIELDS,
        "updated_since": updated_since,
        "domain":        FRESHDESK_DOMAIN,
        "fields": [
            "id", "subject", "status", "priority",
            "created_at", "updated_at", "due_by",
            "group_id", "product_id",
        ],
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    logging.info("Metafil sparad: %s", meta_path.name)


# -------------------------
# Main
# -------------------------
def main() -> None:
    setup_logging()
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    updated_since: str | None = None
    if len(sys.argv) > 1:
        raw_date = sys.argv[1].strip()
        if len(raw_date) == 10:
            raw_date = f"{raw_date}T00:00:00Z"
        updated_since = raw_date
        logging.info("Mottog updated_since-argument: %s", updated_since)

    try:
        cleanup_stale_tmp_files()
        enforce_retention()

        api_key = read_api_key()
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

        if updated_since:
            date_tag  = updated_since[:10].replace("-", "")
            out_file  = RAW_DIR / f"freshdesk_snapshot_{ts}_since_{date_tag}.json"
            meta_file = RAW_DIR / f"freshdesk_snapshot_{ts}_since_{date_tag}.meta.json"
        else:
            out_file  = RAW_DIR / f"freshdesk_snapshot_{ts}.json"
            meta_file = RAW_DIR / f"freshdesk_snapshot_{ts}.meta.json"

        logging.info("=== Startar Freshdesk snapshot v%s ===", SCRIPT_VERSION)
        total, pages = fetch_and_stream_snapshot(api_key, out_file, updated_since)
        write_meta(meta_file, ts, total, pages, updated_since)

        cleanup_stale_tmp_files()

        logging.info("=== Klar: %s | %d tickets | %d sidor ===", out_file.name, total, pages)

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
