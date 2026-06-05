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
| Gold layer | ❌ Not started | ❌ Not started |
| Power BI | ❌ Not started | ❌ Not started |

**Next task: Gold layer**
- Both silver layers complete — ready to design gold (star schema)
- Discuss reporting requirements before building
- Gold will resolve: backlog vs unstarted in state_type, which of completed_at/closed_at to expose

---

## Key files

| File | Purpose |
|---|---|
| `script/bronze_loader.py` | Incremental Python loader: JSON → bronze tables |
| `script/freshdesk_snapshot_claude.py` | Nightly Freshdesk API snapshot |
| `script/linear_snapshot_claude.py` | Nightly Linear GraphQL snapshot |
| `sql/01_bronze_create_tables.sql` | CREATE TABLE for all bronze tables |
| `sql/04_silver_create_tables_freshdesk.sql` | CREATE TABLE for silver.freshdesk_tickets |
| `sql/05_silver_load_freshdesk.sql` | TRUNCATE + full rebuild of silver.freshdesk_tickets |
| `sql/06_silver_create_tables_linear.sql` | CREATE TABLE for silver.linear_issues |
| `sql/07_silver_load_linear.sql` | TRUNCATE + full rebuild of silver.linear_issues |
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

## Morning refresh (manual, local)

```powershell
git pull
python script/bronze_loader.py
sqlcmd -S INTSQLSERVER01 -d InternalStatistics -U dittanvändarnamn -P dittlösenord -i "sql\05_silver_load_freshdesk.sql"
sqlcmd -S INTSQLSERVER01 -d InternalStatistics -U dittanvändarnamn -P dittlösenord -i "sql\07_silver_load_linear.sql"
```

A `script/morning_refresh.ps1` will be created when all layers are complete.

## Power BI connection point

Power BI connects to the **gold layer only** — never silver or bronze directly.
Silver rebuilds (TRUNCATE + full reload) are not time-critical; Power BI does not
run live queries against silver, so the seconds-long truncation window is not a problem.

---

## Planned automation (future)

- `script/morning_refresh.ps1` — one script for git pull + bronze + all silver + gold
- Windows Task Scheduler or SQL Server Agent for unattended runs
- SSIS / SQL Server Agent when moved to a production server

---

## Security constraints

- `credentials/` is git-ignored — never commit API keys or connection strings
- API keys: `FRESHDESK_API_KEY`, `LINEAR_API_KEY` (env vars or `credentials/*.txt`)
- SQL connection string: `SQL_CONNECTION_STRING` env var or `credentials/sql_connection.txt`
- GitHub Secrets configured: `LINEAR_API_KEY`, `FRESHDESK_API_KEY`
