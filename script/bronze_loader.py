#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bronze_loader.py
Laddar JSON-filer från raw/freshdesk/ och raw/linear/ till SQL Server-bronslagret.

Körning:
  python script/bronze_loader.py

Krav:
  pip install pyodbc

Anslutning (välj ett alternativ):
  1. Miljövariabel:  SQL_CONNECTION_STRING=DRIVER=...;SERVER=...;DATABASE=OPEX_statistics;...
  2. Credentials-fil: credentials/sql_connection.txt med connection string på första raden

Exempel på connection string (Windows-autentisering, lokal server):
  DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=OPEX_statistics;Trusted_Connection=yes;

Exempel på connection string (SQL-autentisering, för GitHub Actions):
  DRIVER={ODBC Driver 17 for SQL Server};SERVER=myserver;DATABASE=OPEX_statistics;UID=myuser;PWD=mypassword;

Logik:
  - Backfill-filer (*_backfill_*.json): full load, körs bara en gång (import_log-kontroll)
  - Snapshot-filer (*_snapshot_*.json): inkrementell — bara nya eller uppdaterade poster
  - Meta-filer (*.meta.json) och övriga filer ignoreras
"""

from pathlib import Path
from datetime import datetime, timezone
import json
import logging
import logging.handlers
import os
import sys
import pyodbc

# -------------------------
# Konfiguration
# -------------------------
try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

PROJECT_ROOT     = SCRIPT_DIR.parent
RAW_FRESHDESK    = PROJECT_ROOT / "raw" / "freshdesk"
RAW_LINEAR       = PROJECT_ROOT / "raw" / "linear"
LOG_DIR          = PROJECT_ROOT / "logs"
CREDENTIALS_PATH = PROJECT_ROOT / "credentials" / "sql_connection.txt"

BATCH_SIZE = 500   # antal rader per executemany-anrop — balans mellan minne och prestanda


# -------------------------
# Logging
# -------------------------
def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    file_handler = logging.handlers.RotatingFileHandler(
        LOG_DIR / "bronze_loader.log",
        maxBytes=5_000_000,
        backupCount=5,
        encoding="utf-8",
    )
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler.setFormatter(fmt)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(fmt)
    logging.basicConfig(level=logging.INFO, handlers=[file_handler, console_handler])


# -------------------------
# Anslutning
# -------------------------
def read_connection_string() -> str:
    conn_str = os.environ.get("SQL_CONNECTION_STRING", "").strip()
    if conn_str:
        logging.info("Använder SQL_CONNECTION_STRING från miljövariabel.")
        return conn_str
    logging.info("Läser connection string från: %s", CREDENTIALS_PATH)
    if not CREDENTIALS_PATH.exists():
        raise FileNotFoundError(
            f"Connection string saknas: {CREDENTIALS_PATH}\n"
            "Skapa filen med connection string på första raden, t.ex.:\n"
            "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;"
            "DATABASE=OPEX_statistics;Trusted_Connection=yes;"
        )
    conn_str = CREDENTIALS_PATH.read_text(encoding="utf-8").splitlines()[0].strip()
    if not conn_str:
        raise ValueError("Connection string är tom.")
    return conn_str


# -------------------------
# Import-log helpers
# -------------------------
def get_loaded_files(conn: pyodbc.Connection) -> set[str]:
    """Returnerar mängden av filnamn som redan finns i import_log."""
    cursor = conn.cursor()
    cursor.execute("SELECT file_name FROM bronze.import_log")
    return {row[0] for row in cursor.fetchall()}


def log_import(conn: pyodbc.Connection, source: str, file_name: str, row_count: int) -> None:
    """Skriver en rad till import_log efter lyckad inladdning."""
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO bronze.import_log (source, file_name, row_count) VALUES (?, ?, ?)",
        source, file_name, row_count,
    )
    conn.commit()


# -------------------------
# Befintliga poster (för inkrementell logik)
# -------------------------
def get_existing_freshdesk(conn: pyodbc.Connection) -> dict[int, str]:
    """
    Returnerar {ticket_id: senaste updated_at} för alla rader i bronze.
    Används för att avgöra om en post ska laddas in eller hoppas över.
    """
    cursor = conn.cursor()
    cursor.execute("SELECT id, MAX(updated_at) FROM bronze.freshdesk_tickets GROUP BY id")
    return {row[0]: (row[1] or "") for row in cursor.fetchall()}


def get_existing_linear(conn: pyodbc.Connection) -> dict[str, str]:
    """Returnerar {issue_id: senaste updated_at} för alla rader i bronze."""
    cursor = conn.cursor()
    cursor.execute("SELECT id, MAX(updated_at) FROM bronze.linear_issues GROUP BY id")
    return {row[0]: (row[1] or "") for row in cursor.fetchall()}


# -------------------------
# Batch-insert-hjälpfunktion
# -------------------------
def bulk_insert(cursor: pyodbc.Cursor, sql: str, rows: list) -> int:
    """
    Infogar rader i batchar för att undvika minnesproblem med stora filer.
    Returnerar totalt antal infogade rader.
    """
    total = 0
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i: i + BATCH_SIZE]
        cursor.executemany(sql, batch)
        total += len(batch)
    return total


# -------------------------
# Freshdesk-loader
# -------------------------
def load_freshdesk_file(
    conn: pyodbc.Connection,
    file_path: Path,
    file_name: str,
    incremental: bool,
) -> int:
    """
    Laddar en Freshdesk JSON-fil till bronze.freshdesk_tickets.
    incremental=True: hoppar över poster som redan finns med samma eller nyare updated_at.
    incremental=False: laddar alla poster oavsett (används för backfill).
    Returnerar antal infogade rader.
    """
    logging.info("Läser: %s", file_name)
    with file_path.open(encoding="utf-8") as f:
        tickets = json.load(f)
    logging.info("  %d tickets i filen", len(tickets))

    existing = get_existing_freshdesk(conn) if incremental else {}

    rows_to_insert = []
    skipped = 0

    for t in tickets:
        tid = t.get("id")
        updated_at = t.get("updated_at") or ""

        if incremental and tid in existing and updated_at <= existing[tid]:
            # Posten finns redan i bronze och är inte nyare — hoppa över
            skipped += 1
            continue

        rows_to_insert.append((
            tid,
            t.get("subject"),
            t.get("status"),
            t.get("priority"),
            t.get("created_at"),
            updated_at or None,
            t.get("due_by"),
            t.get("group_id"),
            t.get("product_id"),
            file_name,
        ))

    if skipped:
        logging.info("  %d oförändrade poster hoppades över", skipped)

    if not rows_to_insert:
        logging.info("  Inga nya poster att ladda.")
        return 0

    insert_sql = """
        INSERT INTO bronze.freshdesk_tickets
            (id, subject, status, priority, created_at, updated_at, due_by,
             group_id, product_id, _snapshot_file)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    cursor = conn.cursor()
    inserted = bulk_insert(cursor, insert_sql, rows_to_insert)
    conn.commit()
    logging.info("  Infogade %d rader", inserted)
    return inserted


# -------------------------
# Linear-loader
# -------------------------
def flatten_linear(node: dict, file_name: str) -> tuple:
    """
    Plattar ut ett Linear issue-objekt till en tuple som matchar
    kolumnordningen i INSERT-satsen nedan.
    Nested objekt (state, assignee, project, team, parent, cycle)
    hämtas med .get() så att null-värden i JSON ger None i Python.
    Labels (array) joinas till en pipe-separerad sträng.
    """
    state    = node.get("state")    or {}
    assignee = node.get("assignee") or {}
    project  = node.get("project")  or {}
    team     = node.get("team")     or {}
    parent   = node.get("parent")   or {}
    cycle    = node.get("cycle")    or {}

    label_nodes = (node.get("labels") or {}).get("nodes") or []
    labels = "|".join(n.get("name", "") for n in label_nodes) or None

    return (
        node.get("id"),
        node.get("number"),
        node.get("identifier"),
        node.get("title"),
        node.get("description"),
        node.get("createdAt"),
        node.get("updatedAt"),
        node.get("archivedAt"),
        node.get("completedAt"),
        node.get("canceledAt"),
        node.get("startedAt"),
        node.get("dueDate"),
        node.get("priority"),
        node.get("estimate"),
        node.get("trashed"),
        state.get("id"),
        state.get("name"),
        state.get("type"),
        assignee.get("id"),
        assignee.get("name"),
        assignee.get("email"),
        project.get("id"),
        project.get("name"),
        team.get("id"),
        team.get("name"),
        parent.get("id"),
        parent.get("identifier"),
        cycle.get("id"),
        cycle.get("name"),
        cycle.get("startsAt"),
        cycle.get("endsAt"),
        labels,
        file_name,
    )


def load_linear_file(
    conn: pyodbc.Connection,
    file_path: Path,
    file_name: str,
    incremental: bool,
) -> int:
    """
    Laddar en Linear JSON-fil till bronze.linear_issues.
    Samma inkrementella logik som Freshdesk — jämför updated_at.
    """
    logging.info("Läser: %s", file_name)
    with file_path.open(encoding="utf-8") as f:
        issues = json.load(f)
    logging.info("  %d issues i filen", len(issues))

    existing = get_existing_linear(conn) if incremental else {}

    rows_to_insert = []
    skipped = 0

    for node in issues:
        iid = node.get("id")
        updated_at = node.get("updatedAt") or ""

        if incremental and iid in existing and updated_at <= existing[iid]:
            skipped += 1
            continue

        rows_to_insert.append(flatten_linear(node, file_name))

    if skipped:
        logging.info("  %d oförändrade poster hoppades över", skipped)

    if not rows_to_insert:
        logging.info("  Inga nya poster att ladda.")
        return 0

    insert_sql = """
        INSERT INTO bronze.linear_issues
            (id, number, identifier, title, description,
             created_at, updated_at, archived_at, completed_at,
             canceled_at, started_at, due_date,
             priority, estimate, trashed,
             state_id, state_name, state_type,
             assignee_id, assignee_name, assignee_email,
             project_id, project_name,
             team_id, team_name,
             parent_id, parent_identifier,
             cycle_id, cycle_name, cycle_starts_at, cycle_ends_at,
             labels, _snapshot_file)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """
    cursor = conn.cursor()
    inserted = bulk_insert(cursor, insert_sql, rows_to_insert)
    conn.commit()
    logging.info("  Infogade %d rader", inserted)
    return inserted


# -------------------------
# Filupptäckt
# -------------------------
def find_files(raw_dir: Path, prefix: str, loaded: set[str]) -> list[tuple[Path, str, bool]]:
    """
    Returnerar lista av (sökväg, filnamn, är_inkrementell) för filer
    som ännu inte finns i import_log.
    Meta-filer (*.meta.json) och filer med okänt prefix ignoreras.
    Sorteras på filnamn (= tidsstämpelordning för snapshots).
    """
    result = []
    for path in sorted(raw_dir.glob(f"{prefix}_*.json")):
        if path.name.endswith(".meta.json"):
            continue
        if path.name in loaded:
            logging.info("Redan laddad, hoppar över: %s", path.name)
            continue
        is_snapshot = "_snapshot_" in path.name
        result.append((path, path.name, is_snapshot))  # is_snapshot → incremental
    return result


# -------------------------
# Main
# -------------------------
def main() -> None:
    setup_logging()
    logging.info("=== Startar bronze_loader ===")

    try:
        conn_str = read_connection_string()
        conn = pyodbc.connect(conn_str, autocommit=False)
        logging.info("Ansluten till SQL Server.")

        loaded = get_loaded_files(conn)
        logging.info("%d filer redan laddade enligt import_log.", len(loaded))

        # Hitta filer att ladda
        fd_files  = find_files(RAW_FRESHDESK, "freshdesk", loaded)
        lin_files = find_files(RAW_LINEAR,    "linear",    loaded)

        if not fd_files and not lin_files:
            logging.info("Inga nya filer att ladda. Klart.")
            return

        # Ladda Freshdesk
        for path, file_name, incremental in fd_files:
            mode = "inkrementell" if incremental else "full"
            logging.info("--- Freshdesk %s: %s", mode, file_name)
            try:
                inserted = load_freshdesk_file(conn, path, file_name, incremental)
                log_import(conn, "freshdesk", file_name, inserted)
            except Exception as e:
                logging.exception("Fel vid inladdning av %s: %s", file_name, e)
                conn.rollback()
                raise

        # Ladda Linear
        for path, file_name, incremental in lin_files:
            mode = "inkrementell" if incremental else "full"
            logging.info("--- Linear %s: %s", mode, file_name)
            try:
                inserted = load_linear_file(conn, path, file_name, incremental)
                log_import(conn, "linear", file_name, inserted)
            except Exception as e:
                logging.exception("Fel vid inladdning av %s: %s", file_name, e)
                conn.rollback()
                raise

        conn.close()
        logging.info("=== Klar ===")

    except KeyboardInterrupt:
        logging.warning("Avbröts av användare.")
        raise
    except Exception as e:
        logging.exception("bronze_loader misslyckades: %s", e)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
