# Claude Code — Project Brief
# statistik-freshdesk-linear

This file is read automatically by Claude Code at session start.
Keep it up to date as the project evolves.

---

## What this project is

A Bronze → Silver → Gold data pipeline for Power BI reporting at Intersolia.
- **Sources:** Freshdesk (support tickets) + Linear (product issues)
- **Pipeline:** GitHub Actions → raw JSON → SQL Server → Power BI
- **Database:** `InternalStatistics` on `INTSQLSERVER01` (SQL Server 2022)
- **Schemas:** `bronze`, `silver`, `gold`
- **Auth:** SQL Server Authentication — connection string in `credentials/sql_connection.txt`
- **Localhost:** `OPEX_statistics` on localhost still exists as dev/test environment

Full architecture in README.md. Full decision history in History.md.

---

## Current state (update this section when layers change)

| Layer | Freshdesk | Linear |
|---|---|---|
| Bronze tables | ✅ Done | ✅ Done |
| Bronze loader (Python) | ✅ Done | ✅ Done |
| Silver table | ✅ Done | ✅ Done |
| Silver load script | ✅ Done | ✅ Done |
| Silver refresh automation | ✅ Done | ✅ Done (shared) |
| Gold dim_date | ✅ Done | ✅ Done (shared) |
| Gold fact views | ✅ Done | ✅ Done |
| Power BI | 🔄 In progress | 🔄 In progress |

**Active track: Power BI visuals**
- Connect Power BI Desktop → Get Data → SQL Server
- Server: `INTSQLSERVER01`, Database: `InternalStatistics`
- Import `gold.DimDate`, `gold.FactFreshdesk`, `gold.FactLinear`
- Create DATE relationships: DimDate.date_key → FactFreshdesk.created_at and FactLinear.created_at
- Add role-playing date relationships for first_passed_at, first_waiting_at, closed_at

**Automation summary (complete)**
- Nightly snapshots: GitHub Actions → JSON files committed to repo (fully automated)
- Daily database refresh: Windows Task Scheduler on the operator's machine → `morning_refresh.ps1`
  - Checks DB connection first (handles office vs. VPN automatically)
  - Retries every hour; SOS alert if no success by 16:00 on a working day
  - Runs: git pull → bronze_loader.py → silver_loader.py
  - Logs to `logs/refresh.log`, last success date to `logs/last_success.txt`
- Gold views: always current (SQL views over silver, no rebuild step)

---

## Key files

| File | Purpose |
|---|---|
| `script/bronze_loader.py` | Incremental Python loader: JSON → bronze tables |
| `script/silver_loader.py` | Python runner for the two silver SQL scripts (with bronze safety check) |
| `script/morning_refresh.ps1` | Daily automation: git pull → bronze → silver. Also registers the Task Scheduler entry (`-Register` flag). |
| `script/freshdesk_snapshot_claude.py` | Nightly Freshdesk API snapshot |
| `script/linear_snapshot_claude.py` | Nightly Linear GraphQL snapshot |
| `sql/01_bronze_create_tables.sql` | CREATE TABLE for all bronze tables |
| `sql/04_silver_create_tables_freshdesk.sql` | CREATE TABLE for silver.freshdesk_tickets |
| `sql/05_silver_load_freshdesk.sql` | TRUNCATE + full rebuild of silver.freshdesk_tickets |
| `sql/06_silver_create_tables_linear.sql` | CREATE TABLE for silver.linear_issues |
| `sql/07_silver_load_linear.sql` | TRUNCATE + full rebuild of silver.linear_issues |
| `sql/08_gold_dim_date.sql` | CREATE + populate gold.DimDate (2025-2035, Swedish holidays) |
| `sql/09_gold_create_views.sql` | CREATE OR ALTER VIEW for gold.FactFreshdesk and gold.FactLinear |
| `.github/workflows/nightly-snapshots.yml` | GitHub Actions automation |
| `credentials/` | API keys + SQL connection string — never committed (git-ignored) |

---

## Architecture decisions (the non-obvious ones)

**Bronze is append-style, not upsert.**
Same ticket/issue ID can appear in multiple rows from different snapshots.
`bronze.import_log` prevents re-loading the same file twice.

**Silver is TRUNCATE + full rebuild.**
Not incremental upsert. This is intentional: `denied_triage` and the date
columns depend on the full bronze history and cannot be computed row-by-row.

**Retention uses filename timestamp, not file mtime.**
GitHub Actions resets all file timestamps on checkout. Both snapshot scripts
parse the date from the filename regex `(\d{8}T\d{6}Z)`.

**ISO 8601 strings in bronze, DATE in silver.**
Bronze stores raw strings (e.g. `"2026-06-04T11:14:51.968Z"`).
Silver converts with `TRY_CAST(LEFT(col, 10) AS DATE)`.
ISO 8601 UTC strings compare correctly as strings (lexicographic = chronological).

**group_id and product_id are BIGINT.**
Freshdesk IDs reach ~14 billion — exceeds INT max (~2.1B).

---

## Freshdesk silver schema

`silver.freshdesk_tickets` — one row per ticket, latest state.

| Column | Type | Notes |
|---|---|---|
| `id` | INT PK | |
| `status` | TINYINT | 17=Waiting triage, 6/7/12=Passed triage, 2/3/4/5=Open/Pending/Resolved/Closed |
| `created_at` | DATE | |
| `updated_at` | DATE | |
| `product_id` | BIGINT | |
| `first_waiting_at` | DATE | First bronze row with status=17 |
| `first_passed_at` | DATE | First bronze row with status IN (6,7,12) |
| `denied_triage` | BIT | Had 6/7/12, then returned to 17 |
| `denied_triage_at` | DATE | Date of that regression |

Excluded from silver: `subject`, `priority`, `due_by`, `group_id`.
Excluded tickets: `group_id` ending in `1939` or `8846`.

---

## Linear silver schema

`silver.linear_issues` — one row per issue, latest state.

| Column | Type | Notes |
|---|---|---|
| `id` | NVARCHAR(50) PK | Linear GUID |
| `state_name` | NVARCHAR | Current status text |
| `state_type` | NVARCHAR | unstarted/started/completed/cancelled (backlog≈unstarted, resolve in gold) |
| `priority` | TINYINT | 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low |
| `created_at` | DATE | |
| `started_at` | DATE | When work began |
| `completed_at` | DATE | Linear's own field — completed-type states only |
| `closed_at` | DATE | COALESCE(completed_at, canceled_at) — all done states |
| `project_name` | NVARCHAR | |
| `assignee_name` | NVARCHAR | |
| `labels` | NVARCHAR | Pipe-separated |
| `trashed` | BIT | |
| `is_incident` | BIT | labels LIKE '%incident%' (CI collation = case-insensitive) |

Filter: NOT (identifier LIKE 'DEV%' AND team_name = 'Development') — AND, not OR.

---

## Gold layer schema

Gold naming: **PascalCase** — `DimDate`, `FactFreshdesk`, `FactLinear`. All created by `sql/09_gold_create_views.sql` (CREATE OR ALTER VIEW — safe to re-run).

**`gold.FactFreshdesk`** — view over silver.freshdesk_tickets

| Column | Notes |
|---|---|
| `id`, `status` | From silver |
| `status_label` | 'Open', 'Pending', 'Resolved', 'Closed', 'Waiting for triage', 'Passed triage', 'Other (NN)' |
| `triage_status` | 'Denied' / 'Waiting' / 'Passed' / 'Other' — main slicer for triage workflow |
| `created_at`, `updated_at`, `product_id` | From silver |
| `first_waiting_at`, `first_passed_at` | Period-based reporting dates |
| `denied_triage`, `denied_triage_at` | Regression flag and date |

**`gold.FactLinear`** — view over silver.linear_issues

| Column | Notes |
|---|---|
| `id`, `state_name`, `state_type` | From silver |
| `state_label` | 'Backlog / Unstarted', 'In Progress', 'Completed', 'Cancelled', 'Other' — collapses backlog+unstarted |
| `priority`, `priority_label` | 0=No priority … 4=Low (matches Linear's own labels) |
| `created_at`, `started_at`, `completed_at`, `closed_at` | From silver |
| `days_to_start` | DATEDIFF(DAY, created_at, started_at) |
| `days_to_close` | DATEDIFF(DAY, created_at, closed_at) |
| `age_days` | For open issues only — days since created_at, NULL when closed |
| `project_name`, `assignee_name`, `labels`, `trashed`, `is_incident` | From silver |

**Power BI relationships (DATE-to-DATE):**
- `DimDate.date_key` → `FactFreshdesk.created_at` (primary)
- `DimDate.date_key` → `FactFreshdesk.first_waiting_at` (role-playing)
- `DimDate.date_key` → `FactFreshdesk.first_passed_at` (role-playing)
- `DimDate.date_key` → `FactLinear.created_at` (primary)
- `DimDate.date_key` → `FactLinear.closed_at` (role-playing)

---

## Daily refresh (automated via Task Scheduler)

`morning_refresh.ps1` runs automatically every weekday hour via Windows Task Scheduler on the operator's machine. Manual run if needed:

```powershell
powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1"
```

Sequence: git pull → bronze_loader.py → silver_loader.py. Logs to `logs/refresh.log`.

**Why not GitHub Actions?** Microsoft-hosted runners cannot reach `INTSQLSERVER01` (internal server). The Task Scheduler approach runs on a machine that already has network/VPN access.

## Power BI connection point

Power BI connects to the **gold layer only** — never silver or bronze directly.
Silver rebuilds (TRUNCATE + full reload) are not time-critical; Power BI does not
run live queries against silver, so the seconds-long truncation window is not a problem.

---

## Handover — setting up on a new machine

When this project transfers to a new operator, they need to do the following once. Full instructions are also in `README.md`.

**Prerequisites**
- Git for Windows installed
- Python 3.10+ with `pip install requests pyodbc`
- ODBC Driver 17 for SQL Server installed
- Access to Intersolia network (office or VPN)
- The SQL connection string for `INTSQLSERVER01` — this is **not** in GitHub Secrets; get it from IT or the outgoing person

**One-time setup**
1. Clone the repo: `git clone https://github.com/Micke-Intersolia/statistik-freshdesk-linear.git`
2. Create `credentials/sql_connection.txt` with the connection string (format: `DRIVER={ODBC Driver 17 for SQL Server};SERVER=INTSQLSERVER01;DATABASE=InternalStatistics;UID=xxx;PWD=xxx;`)
3. Register the Task Scheduler task (as Administrator): `powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1" -Register`
4. In Task Scheduler: open the task → Triggers → Edit → tick "Repeat task every: 1 hour" for 13 hours
5. Authenticate git to GitHub once by running `git pull` in the repo — Windows Credential Manager will cache the token

**GitHub Actions** (already configured — no action needed)
- Snapshot scripts run nightly automatically
- Secrets `LINEAR_API_KEY` and `FRESHDESK_API_KEY` are already stored in the repo's GitHub Secrets

---

## Security constraints

- `credentials/` is git-ignored — never commit API keys or connection strings
- API keys: `FRESHDESK_API_KEY`, `LINEAR_API_KEY` (env vars or `credentials/*.txt`)
- SQL connection string: `SQL_CONNECTION_STRING` env var or `credentials/sql_connection.txt`
- GitHub Secrets configured: `LINEAR_API_KEY`, `FRESHDESK_API_KEY`
