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

**SQL Server database:** `InternalStatistics` on `INTSQLSERVER01` (SQL Server 2022) — schemas `bronze`, `silver`, `gold`. Tables: `bronze.freshdesk_tickets`, `bronze.linear_issues`, `bronze.import_log`. Connection string in `credentials/sql_connection.txt` (git-ignored).

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

### ⚪ Silver Layer — Normalized & Cleaned _(in progress)_

The silver layer is rebuilt from scratch (TRUNCATE + full reload) every time it runs. Each source record is keyed by its ID — one row per ticket/issue, latest version wins. Safe to re-run at any time.

**Freshdesk silver — `silver.freshdesk_tickets` ✅ Complete**

Fields (8 + audit):

| Column | Type | Notes |
|---|---|---|
| `id` | INT PK | Ticket ID |
| `status` | TINYINT | Raw status code — mapping done in Gold/Power BI |
| `created_at` | DATE | ISO 8601 string → DATE (time discarded) |
| `updated_at` | DATE | ISO 8601 string → DATE (time discarded) |
| `product_id` | BIGINT | Portal/product ID — kept for product-level analysis |
| `first_waiting_at` | DATE | First observed date with status 17 — proxy for ticket entering triage queue |
| `first_passed_at` | DATE | First observed date with status 6/7/12 — proxy for OPEX decision date |
| `denied_triage` | BIT | Flag: ticket ever had 6/7/12 then returned to 17 |
| `denied_triage_at` | DATE | Date of that regression (NULL if not denied) |

The four derived columns (`first_waiting_at`, `first_passed_at`, `denied_triage`, `denied_triage_at`) enable period-based reporting: "how many tickets were passed triage this week?" uses `first_passed_at`, not `updated_at`. Dates are approximations based on the `updated_at` of the bronze snapshot row where each status was first observed — accurate enough for daily/weekly reporting given nightly snapshots.

Fields dropped from bronze: `subject`, `priority`, `due_by`, `group_id` — not needed for reporting.

**Status codes** (Freshdesk):

| Code | Meaning |
|---|---|
| 17 | Waiting for triage (set by support) |
| 6, 7, 12 | Passed triage (decided by OPEX meeting) |
| 2, 3, 4, 5 | Open, Pending, Resolved, Closed |

**Transformations applied (SQL: `sql/04_silver_create_tables_freshdesk.sql`, `sql/05_silver_load_freshdesk.sql`):**

- **Filter:** tickets where `group_id` ends in `1939` or `8846` are excluded. Tickets with NULL `group_id` are kept.
- **Deduplication:** `ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC, _row_id DESC)` — latest snapshot row per ticket wins.
- **Date conversion:** `TRY_CAST(LEFT(col, 10) AS DATE)` extracts the `YYYY-MM-DD` portion of the ISO 8601 string (e.g. `"2026-06-04T11:14:51.968Z"` → `2026-06-04`).
- **Denied triage flag:** `denied_triage = 1` if the ticket has ever had status 6, 7, or 12 and subsequently returned to status 17. Detected from the full bronze append-history by comparing `updated_at` strings (lexicographic = chronological for UTC ISO 8601). The flag is permanent — once set it is never cleared.

**Linear silver — `silver.linear_issues` ✅ Complete**

Fields kept (10 + audit):

| Column | Type | Notes |
|---|---|---|
| `id` | NVARCHAR PK | Linear GUID |
| `state_name` | NVARCHAR | Current status text, e.g. "In Progress" |
| `state_type` | NVARCHAR | Category: `unstarted`, `started`, `completed`, `cancelled` |
| `priority` | TINYINT | 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low |
| `created_at` | DATE | When issue was created |
| `started_at` | DATE | When work began |
| `completed_at` | DATE | Linear's own field — completed-type states only |
| `closed_at` | DATE | `COALESCE(completed_at, canceled_at)` — all done states |
| `project_name` | NVARCHAR | |
| `assignee_name` | NVARCHAR | |
| `labels` | NVARCHAR | Pipe-separated, e.g. `"Bug\|Incident"` |
| `trashed` | BIT | |
| `is_incident` | BIT | 1 if labels contains "incident" (case-insensitive) |

Fields dropped from bronze: `identifier`, `number`, `title`, `description`, `state_id`, `assignee_id/email`, `team_id/name`, `project_id`, `parent_*`, `cycle_*`, `archived_at`, `canceled_at`, `due_date`, `estimate`.

**Filter:** issues where `identifier LIKE 'DEV%'` AND `team_name = 'Development'` — both conditions must be true to exclude. Issues in the Development team without a DEV-prefix identifier, or DEV-prefix issues in other teams, are kept.

`completed_at` and `state_type` are both kept in silver for cross-verification. The gold layer will choose which to expose to Power BI. The `backlog` vs `unstarted` distinction in `state_type` will be resolved in gold.

---

### 🟡 Gold Layer — Star Schema ✅ Complete

The gold layer is optimised for Power BI consumption. `dim_date` is a real table; the fact tables are SQL views over silver — always current, no rebuild step needed.

**`gold.DimDate` ✅ Complete** — one row per day, 2025-01-01 to 2035-12-31.

> **Note for future maintainers:** The date range is hard-coded to 2035-12-31. To extend it, update `'2035-12-31'` in `sql/08_gold_dim_date.sql`, add Easter dates for the new years to the `easter` CTE, and re-run the script. Next Easter dates: 2036-04-13, 2037-04-05, 2038-04-25, 2039-04-10, 2040-04-01.

| Column | Notes |
|---|---|
| `date_key` | DATE — primary key, join target for fact views |
| `year`, `quarter_num/name` | Standard calendar grouping |
| `month_num`, `month_name`, `month_short` | English names (explicit mapping, language-independent) |
| `month_sort` | INT (YYYYMM) — use as sort key in Power BI so months sort Jan→Dec |
| `iso_week`, `year_week` | ISO week number + `'YYYY-WNN'` string — sorts correctly as text |
| `day_of_week_num`, `day_name`, `day_short` | ISO: 1=Monday … 7=Sunday |
| `is_weekend` | Saturday or Sunday |
| `is_public_holiday` | Swedish public holidays (röda dagar) only. Christmas Eve, Midsummer Eve and New Year's Eve are **not** official red days and are not flagged. |
| `is_working_day` | NOT weekend AND NOT public holiday |
| `working_days_in_week` | Working days in this ISO week (0–5). Weeks with a holiday show 4 or less — useful for normalising weekly ticket volumes. |

**Object naming in gold:** PascalCase — `DimDate`, `FactFreshdesk`, `FactLinear`. Standard data warehouse convention; Power BI shows table names directly in the report tool.

**No separate dimension tables** for status, priority, or state — labels are computed columns embedded directly in the fact views. The Power BI model is intentionally flat:

```
                         ┌──────────┐
                         │ DimDate  │
                         └────┬─────┘
              ┌───────────────┴──────────────┐
              │                              │
     ┌────────┴────────┐           ┌─────────┴───────┐
     │  FactFreshdesk  │           │   FactLinear    │
     │  (view)         │           │   (view)        │
     │                 │           │                 │
     │ status_label    │           │ state_label     │
     │ triage_status   │           │ priority        │
     │ product_id      │           │ assignee_name   │
     │ denied_triage   │           │ project_name    │
     │ first_waiting.. │           │ days_to_start   │
     │ first_passed..  │           │ days_to_close   │
     │                 │           │ is_incident     │
     └─────────────────┘           └─────────────────┘
```

DimDate connects to both fact views on `date_key = created_at` (and optionally on other date columns such as `first_passed_at` or `closed_at` for additional role-playing date relationships in Power BI).

**`gold.FactFreshdesk` ✅ Complete** — view over `silver.freshdesk_tickets`. Adds `status_label` (human-readable status name), `triage_status` ('Waiting' / 'Passed' / 'Denied' / 'Other' — main slicer for OPEX triage reporting).

**`gold.FactLinear` ✅ Complete** — view over `silver.linear_issues`. Adds `state_label` (collapses `backlog`/`unstarted` → 'Backlog / Unstarted'), `priority_label`, `days_to_start`, `days_to_close`, `age_days` (open issues only).

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
│   ├── 01_bronze_create_tables.sql           # CREATE TABLE for bronze layer
│   ├── 02_bronze_load_freshdesk.sql          # Manual T-SQL loader for Freshdesk files
│   ├── 03_bronze_load_linear.sql             # Manual T-SQL loader for Linear files
│   ├── 04_silver_create_tables_freshdesk.sql # CREATE TABLE for silver.freshdesk_tickets
│   ├── 05_silver_load_freshdesk.sql          # TRUNCATE + rebuild silver.freshdesk_tickets
│   ├── 06_silver_create_tables_linear.sql    # CREATE TABLE for silver.linear_issues
│   ├── 07_silver_load_linear.sql             # TRUNCATE + rebuild silver.linear_issues
│   ├── 08_gold_dim_date.sql                  # CREATE + populate gold.DimDate
│   └── 09_gold_create_views.sql              # CREATE OR ALTER VIEW for gold.FactFreshdesk and gold.FactLinear
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

### Morning refresh (manual, local)

GitHub Actions commits new snapshot files to the repo every night. Each morning, run these three steps in order to bring the local database up to date:

```powershell
# 1. Pull the latest snapshot files committed by GitHub Actions
git pull

# 2. Load any new/updated records into the bronze tables
python script/bronze_loader.py

# 3. Rebuild silver from bronze (run in SSMS or via sqlcmd)
sqlcmd -S INTSQLSERVER01 -d InternalStatistics -U dittanvändarnamn -P dittlösenord -i "sql\05_silver_load_freshdesk.sql"
sqlcmd -S INTSQLSERVER01 -d InternalStatistics -U dittanvändarnamn -P dittlösenord -i "sql\07_silver_load_linear.sql"
```

> **Note:** Step 3 will expand as the silver and gold layers grow. A `script/morning_refresh.ps1` automation script is planned for when all layers are complete. For production use, SQL Server Agent or SSIS will replace this manual process.

---

## Automation

GitHub Actions runs both snapshot scripts nightly. See `.github/workflows/nightly-snapshots.yml` for the full schedule and retry logic.

Two repository secrets must be configured under **Settings → Secrets and variables → Actions**:
- `LINEAR_API_KEY`
- `FRESHDESK_API_KEY`
