#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
silver_loader.py
Rebuilds the silver layer from bronze by running the two silver SQL scripts.

Run after bronze_loader.py has loaded new snapshot data:
  python script/silver_loader.py

Both scripts are safe to re-run — they TRUNCATE silver and do a full rebuild.

Connection (choose one):
  1. Env var:  SQL_CONNECTION_STRING=DRIVER=...;SERVER=...;DATABASE=InternalStatistics;...
  2. File:     credentials/sql_connection.txt  (same file used by bronze_loader.py)
"""

import logging
import os
import re
import sys
from pathlib import Path

import pyodbc

# ──────────────────────────────────────────────
# Paths
# ──────────────────────────────────────────────
try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

PROJECT_ROOT     = SCRIPT_DIR.parent
SQL_DIR          = PROJECT_ROOT / "sql"
CREDENTIALS_PATH = PROJECT_ROOT / "credentials" / "sql_connection.txt"

# Scripts executed in this order every run, with the bronze table to check first
SILVER_SCRIPTS = [
    (SQL_DIR / "05_silver_load_freshdesk.sql", "bronze.freshdesk_tickets"),
    (SQL_DIR / "07_silver_load_linear.sql",    "bronze.linear_issues"),
]

# ──────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
def get_connection_string() -> str:
    conn_str = os.environ.get("SQL_CONNECTION_STRING", "").strip()
    if conn_str:
        return conn_str
    if CREDENTIALS_PATH.exists():
        conn_str = CREDENTIALS_PATH.read_text(encoding="utf-8").strip()
        if conn_str:
            return conn_str
    log.error(
        "No connection string found. "
        "Set SQL_CONNECTION_STRING env var or create credentials/sql_connection.txt"
    )
    sys.exit(1)


def split_on_go(sql_text: str) -> list[str]:
    """Split a T-SQL script into batches on standalone GO lines (case-insensitive)."""
    batches = re.split(r"^\s*GO\s*$", sql_text, flags=re.IGNORECASE | re.MULTILINE)
    return [b.strip() for b in batches if b.strip()]


def check_bronze(conn_str: str, table: str) -> int:
    """Return row count of a bronze table. Exits if the table is empty."""
    conn = pyodbc.connect(conn_str, autocommit=True, timeout=10)
    try:
        row = conn.cursor().execute(f"SELECT COUNT(*) FROM {table}").fetchone()
        count = row[0] if row else 0
    finally:
        conn.close()
    if count == 0:
        log.error(
            "%s is empty — bronze_loader.py has not loaded any data yet. "
            "Run bronze_loader.py first, then re-run this script.",
            table,
        )
        sys.exit(1)
    log.info("  Bronze check: %s has %d rows.", table, count)
    return count


def run_script(conn_str: str, script_path: Path) -> None:
    """Execute all GO-separated batches in a SQL file."""
    sql_text = script_path.read_text(encoding="utf-8")
    batches = split_on_go(sql_text)
    log.info("Running %-40s  (%d batch(es))", script_path.name, len(batches))

    # autocommit=True: the SQL scripts manage their own transactions
    # (BEGIN TRANSACTION / COMMIT / ROLLBACK THROW inside each script).
    conn = pyodbc.connect(conn_str, autocommit=True)
    try:
        cursor = conn.cursor()
        for batch in batches:
            cursor.execute(batch)
    finally:
        conn.close()

    log.info("  -> %s done.", script_path.name)


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
def main() -> None:
    conn_str = get_connection_string()

    log.info("Connecting to SQL Server...")
    try:
        probe = pyodbc.connect(conn_str, autocommit=True, timeout=10)
        probe.close()
    except pyodbc.Error as e:
        log.error("Cannot connect to SQL Server: %s", e)
        sys.exit(1)
    log.info("Connected.")

    for script, bronze_table in SILVER_SCRIPTS:
        if not script.exists():
            log.error("SQL script not found: %s", script)
            sys.exit(1)
        check_bronze(conn_str, bronze_table)
        try:
            run_script(conn_str, script)
        except pyodbc.Error as e:
            log.error("Error executing %s:\n%s", script.name, e)
            sys.exit(1)

    log.info("Silver layer rebuild complete.")


if __name__ == "__main__":
    main()
