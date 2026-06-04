<img src="Grafisk profil/Intersolia_logo_black_2021_600.png" alt="Intersolia" width="300">

# Freshdesk & Linear — BI Pipeline

**Author:** Michael Brostrom  
**Context:** LIA Internship at [Intersolia](https://www.intersolia.com) — BI Analyst, YH Akademin

---

## Overview

This project builds a structured data pipeline that pulls raw support and project data from two source systems — **Freshdesk** (customer support tickets) and **Linear** (product issue tracking) — and transforms it into a Power BI dashboard for operational reporting.

The pipeline follows the **medallion architecture** (Bronze → Silver → Gold), a standard pattern in modern analytics engineering that separates raw ingestion from transformation and reporting.

```
Freshdesk API ──┐
                ├──► Bronze (raw JSON) ──► Silver (normalized SQL) ──► Gold (star schema) ──► Power BI
Linear API    ──┘
```

---

## Architecture

### 🟤 Bronze Layer — Raw Snapshots & SQL Load ✅ Complete

Nightly Python scripts pull data directly from the Freshdesk and Linear APIs and write timestamped JSON files to `raw/freshdesk/` and `raw/linear/`. A separate loader script (`bronze_loader.py`) reads those files and inserts them into SQL Server.

**Automation:** GitHub Actions runs the pipeline at midnight CET/CEST with hourly retries until 05:00 CET. Successful snapshots are committed back to the repository automatically.

**Retention:** nightly snapshot files are kept for 90 days and then deleted by the script itself. Backfill files (one-time historical loads) are permanent.

| Source | Field count | ~File size | Frequency |
|---|---|---|---|
| Freshdesk | 9 fields | ~400 KB/day | Nightly |
| Linear | Full issue object | ~120 KB/day | Nightly (full dump) |

**Freshdesk fields captured:** `id`, `subject`, `status`, `priority`, `created_at`, `updated_at`, `due_by`, `group_id`, `product_id`

**SQL Server database:** `OPEX_statistics` — schemas `bronze`, `silver`, `gold`. Tables: `bronze.freshdesk_tickets`, `bronze.linear_issues`, `bronze.import_log`.

**Loader logic:**
- Backfill files: full load, runs once (guarded by `import_log`)
- Nightly snapshots: incremental — only rows that are new or have a newer `updated_at` than what is already in bronze
- Connection string read from `SQL_CONNECTION_STRING` env var or `credentials/sql_connection.txt` — change this one file to point at a production server

**Key design decisions:**
- Atomic writes via `.tmp` → rename — no partial files ever land in `raw/`
- Retention uses the timestamp in the filename, not the file's modified date (GitHub Actions resets all timestamps on checkout)
- API keys stored as GitHub Secrets — never committed to the repository
- Empty snapshot guard: scripts exit with code 2 rather than write a 0-record file
- Dates stored as `NVARCHAR(50)` in bronze (raw ISO 8601 strings) — converted to proper SQL types in silver

---

### ⚪ Silver Layer — Normalized & Cleaned _(planned)_

The silver layer loads all bronze JSON files into a relational SQL database, standardises the data, and builds dimension tables. Each source record is keyed by its ID — re-loading the same snapshot is idempotent (upsert, not append).

Planned transformations:

- **Status and priority codes → human-readable labels** (e.g. Freshdesk status 2 → "Open")
- **Timestamps → local time (Europe/Stockholm)**
- **Deduplication** across overlapping snapshot windows — latest record per ID wins
- **Freshdesk filter:** exclude tickets where `group_id` ends in `1939` or `8846`
- **Dimension tables:** dates, statuses, priorities, groups, products (Freshdesk); teams, projects, states, assignees (Linear)

---

### 🟡 Gold Layer — Star Schema _(planned)_

The gold layer reshapes the silver tables into a star schema optimised for Power BI. Aggregated and pre-joined — query performance in the dashboard does not depend on the source table structure.

**Freshdesk fact table:** one row per ticket, with foreign keys to all dimensions  
**Linear fact table:** one row per issue, with foreign keys to all dimensions  
**Shared date dimension:** covers the full reporting range, one row per day

```
                    ┌─────────────┐
                    │  dim_date   │
                    └──────┬──────┘
┌──────────────┐           │           ┌──────────────────┐
│  dim_group   ├───────────┤           │  dim_status      │
└──────────────┘           │           └──────────────────┘
                    ┌──────┴──────┐
┌──────────────┐    │fact_tickets │    ┌──────────────────┐
│  dim_product ├────┤  (FD)       ├────┤  dim_priority    │
└──────────────┘    └─────────────┘    └──────────────────┘

                    ┌─────────────┐
┌──────────────┐    │ fact_issues │    ┌──────────────────┐
│  dim_team    ├────┤  (Linear)   ├────┤  dim_state       │
└──────────────┘    └──────┬──────┘    └──────────────────┘
                           │
                    ┌──────┴──────┐
                    │ dim_assignee│
                    └─────────────┘
```

---

### 📊 Power BI Dashboard _(planned)_

Two report sections fed from the gold layer:

**Freshdesk — Support Ticket Statistics**
- Ticket volume over time (daily / weekly / monthly)
- Status distribution (open, pending, resolved, closed)
- Breakdown by group and product
- SLA and response trends

**Linear — Issue Tracking**
- Issue volume and throughput by team and project
- Status and priority distribution
- Cycle time and completion trends

---

## Repository Structure

```
├── .github/
│   └── workflows/
│       └── nightly-snapshots.yml   # GitHub Actions automation
├── Grafisk profil/                 # Intersolia brand assets
├── credentials/                    # API keys — never committed (git-ignored)
├── logs/                           # Runtime logs — never committed (git-ignored)
├── raw/
│   ├── freshdesk/                  # Bronze: Freshdesk JSON snapshots + backfill
│   └── linear/                     # Bronze: Linear JSON snapshots + backfill
├── script/
│   ├── freshdesk_snapshot_claude.py   # Nightly Freshdesk snapshot
│   ├── freshdesk_backfill.ipynb       # One-time Freshdesk historical backfill
│   ├── linear_snapshot_claude.py      # Nightly Linear snapshot
│   ├── snapshot_trial.ipynb           # One-time Linear historical backfill
│   └── bronze_loader.py               # Loads JSON files into SQL Server bronze tables
├── sql/
│   ├── 01_bronze_create_tables.sql    # CREATE TABLE statements for bronze layer
│   ├── 02_bronze_load_freshdesk.sql   # Manual T-SQL loader for Freshdesk files
│   └── 03_bronze_load_linear.sql      # Manual T-SQL loader for Linear files
├── History.md                      # Project logbook
└── README.md                       # This file
```

---

## Running the Scripts Locally

**Requirements:** Python 3.10+, `pip install requests pyodbc`

```bash
# Nightly snapshot (last ~30 days for Freshdesk, full dump for Linear)
python script/freshdesk_snapshot_claude.py
python script/linear_snapshot_claude.py

# Freshdesk backfill from a specific date
python script/freshdesk_snapshot_claude.py 2025-05-01

# Load all new JSON files into SQL Server bronze tables
python script/bronze_loader.py
```

API keys are read from environment variables (`FRESHDESK_API_KEY`, `LINEAR_API_KEY`) or from `credentials/Freshdesk_API-key.txt` and `credentials/Linear_API-key.txt`.

SQL Server connection string is read from `SQL_CONNECTION_STRING` env var or `credentials/sql_connection.txt`.

---

## Automation

GitHub Actions runs both snapshot scripts nightly. See `.github/workflows/nightly-snapshots.yml` for the full schedule and retry logic.

Two repository secrets must be configured under **Settings → Secrets and variables → Actions**:
- `LINEAR_API_KEY`
- `FRESHDESK_API_KEY`
