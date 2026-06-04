# Project History

A running logbook of decisions, changes, and milestones for the Linear / Freshdesk data pipeline.

---

## 2026-06-01

**Initial exploration**

Started exploring a pipeline approach for Linear data. Downloaded weekly snapshots using an older script format (`linear_raw_*` naming convention, weekly date ranges). This approach was later replaced in favour of full nightly snapshots with a cleaner naming and retention scheme.

---

## 2026-06-04

**Architecture decision — Bronze-Silver-Gold pipeline**

Decided on a bronze-silver-gold lakehouse pattern with Power BI as the final reporting layer. Raw timestamped JSON snapshots form the bronze layer. Key constraints established:

- Credentials never committed to git (`credentials/` excluded via `.gitignore`)
- Scripts must run unattended and independently on GitHub Actions
- Atomic writes only — `.tmp` file promoted to final name on success, never a partial file in `raw/`
- 90-day rolling retention for nightly snapshot files; backfill files are permanent

---

**Linear snapshot script — `script/linear_snapshot_claude.py`**

Reviewed and rewrote the existing Linear snapshot script. Key decisions:

- GraphQL cursor-based pagination with `includeArchived: true` and no date filter — always a complete dump of all issues
- Retention uses the timestamp embedded in the filename, not file `mtime`. Critical for GitHub Actions: `git checkout` resets all file timestamps to today, which would cause mtime-based retention to immediately delete all historical files
- Empty snapshot guard: exits with code 2 and deletes the tmp file rather than writing a 0-node file to `raw/`
- API key read from `LINEAR_API_KEY` environment variable with fallback to `credentials/Linear_API-key.txt`
- Output: `raw/linear/linear_snapshot_YYYYMMDDTHHMMSSZ.json` + sidecar `.meta.json`
- Verified locally: 1,088 issues, 11 pages, ~9 seconds

**Linear backfill — `script/snapshot_trial.ipynb`**

Rewrote the existing notebook to perform a one-time backfill from 2025-05-01 using the same GraphQL query and field set as the nightly script. Output: `raw/linear/linear_backfill_20250501_20260604.json` (1,089 issues, 1.3 MB).

Note: since the Linear API has no server-side date filter, every nightly snapshot is already a full dump. The backfill notebook exists purely as a documented one-time run; nightly snapshots are self-sufficient going forward.

---

**Freshdesk snapshot script — `script/freshdesk_snapshot_claude.py`**

Created a Freshdesk equivalent of the Linear script. Key differences from Linear:

- Page-based pagination (not cursor-based). Freshdesk hard limit: 300 pages × 100 tickets = 30,000 tickets per query
- Without `updated_since`, the API returns only the last ~30 days of active tickets — this is the intended nightly behaviour
- Supports an optional CLI date argument for manual backfill runs: `python script/freshdesk_snapshot_claude.py 2025-05-01`
- Auth uses `HTTPBasicAuth(api_key, "X")` — standard Freshdesk API key pattern
- The `include` parameter must be omitted entirely when empty; sending an empty string causes a 400 validation error from the API

**Freshdesk field review**

Audited all available Freshdesk ticket fields against actual reporting needs. Generated a Word document (`freshdesk_field_review.docx`) and two review CSV files for manual inspection.

Decision: keep only 9 core fields sufficient for ticket volume and status reporting:

| Field | Notes |
|---|---|
| `id` | Primary key |
| `subject` | Ticket title |
| `status` | Main logic field (2=Open, 3=Pending, 4=Resolved, 5=Closed) |
| `priority` | Ticket urgency |
| `created_at` | Volume over time |
| `updated_at` | Change tracking |
| `due_by` | SLA reference |
| `group_id` | Filter: exclude groups ending in 1939 and 8846 |
| `product_id` | Product/system matching (secondary value) |

Dropped fields: all requester/customer fields, company fields, SLA timing metrics (first_responded_at, resolved_at), tags, and custom fields. Rationale: the bronze layer should serve actual reporting needs. A complete API mirror adds storage cost and ETL complexity without reporting value.

**Freshdesk backfill — `script/freshdesk_backfill.ipynb`**

Created a one-time backfill notebook. Key challenge: Freshdesk's 300-page hard limit was hit when querying from 2025-05-01 — more than 30,000 tickets in scope. Solved by splitting into monthly windows, filtering client-side by `updated_at` to avoid overlap between windows, and deduplicating by ticket ID (keeping the latest `updated_at` per ticket). Output: `raw/freshdesk/freshdesk_backfill_*.json`.

---

**GitHub Actions workflow — `.github/workflows/nightly-snapshots.yml`**

Created the nightly automation. Design decisions:

- **Schedule:** 22:00–04:00 UTC, one run per hour. Two starting times (22:00 and 23:00 UTC) cover midnight in both CEST (summer, UTC+2) and CET (winter, UTC+1) without manual DST adjustment
- **Idempotency:** each run checks whether today's snapshot file already exists in the repo before running. If found, the run exits silently — no duplicate files, no wasted API calls
- **Silent retries:** runs at 22:00–03:00 UTC use `continue-on-error: true` on the script steps. A transient API failure does not send a notification — the next hourly run simply tries again
- **Final alert:** the 03:00 UTC run (= 05:00 CEST, summer) and 04:00 UTC run (= 05:00 CET, winter) check whether a snapshot was committed for today. If not, the workflow fails loudly → GitHub sends a failure notification to repo watchers
- **Alert email:** stored as `ALERT_EMAIL` env var at the top of the workflow file for easy editing. Currently using GitHub's built-in failure notifications; the env var is ready to wire into an SMTP action when needed
- **Commit:** successful snapshots are committed back to the repo as `github-actions[bot]`
- **Concurrency lock:** only one workflow run active at a time; additional scheduled runs queue rather than run in parallel

**Secrets configured in GitHub repository:**
- `LINEAR_API_KEY`
- `FRESHDESK_API_KEY`

**First automated run:** manual trigger via GitHub Actions UI succeeded. Both snapshot files committed by `github-actions[bot]` and confirmed locally after `git pull`.

---

**Retention updated to 90 days**

Both scripts updated from `RETENTION_DAYS = 30` to `RETENTION_DAYS = 90`. Reasoning: provides comfortable buffer for the bronze layer ETL to process files, and 90 days of snapshots at current file sizes (~120 KB Linear + ~400 KB Freshdesk per day) totals ~46 MB — well within GitHub's storage limits.

---

**SQL Server bronze layer — `OPEX_statistics`**

Set up SQL Server 2022 Developer Edition locally. Database `OPEX_statistics` created with three schemas: `bronze`, `silver`, `gold`.

Bronze table design decisions:
- Append-style (not upsert) — same ticket/issue ID can appear in multiple rows from different snapshot files
- Surrogate `IDENTITY` primary key (`_row_id`) per table — each row is globally unique
- `_snapshot_file` column on every row — traces data back to its source file
- `_loaded_at` audit timestamp set automatically on insert
- Date fields stored as `NVARCHAR(50)` preserving raw ISO 8601 strings from the APIs (e.g. `2026-06-04T11:14:51.968Z`). Conversion to SQL date types deferred to silver layer
- `group_id` and `product_id` typed as `BIGINT` — Freshdesk IDs exceed the INT range (~14 billion)
- Linear nested objects (state, assignee, project, team, parent, cycle) flattened into individual columns; labels stored as pipe-separated string
- `bronze.import_log` tracks which files have been loaded with a UNIQUE constraint on `file_name` — prevents double imports

T-SQL loader scripts created in `sql/` for manual one-off loads. Use `OPENROWSET(BULK ...)` + `OPENJSON` to read JSON files directly in T-SQL without external tools. Dynamic SQL required because `OPENROWSET` demands a string literal for the file path.

**Python bronze loader — `script/bronze_loader.py`**

Created `bronze_loader.py` to automate incremental loading from JSON files to SQL Server. Key decisions:

- **Backfill files** (`*_backfill_*.json`): full load on first run, skipped thereafter via `import_log`
- **Snapshot files** (`*_snapshot_*.json`): incremental — loads only rows where the ticket/issue `id` is new, or where `updated_at` is newer than the version already in bronze. Prevents the table growing by ~70,000 unchanged rows every night
- Existing records loaded into a Python dict `{id: max_updated_at}` once per file — filtering done in Python before any SQL insert, avoiding per-row database lookups
- Bulk insert via `executemany` in batches of 500 rows
- Connection string read from `SQL_CONNECTION_STRING` env var (for GitHub Actions) or `credentials/sql_connection.txt` (local). Changing this one file is all that is needed to point the loader at a production server
- Linear nested JSON objects flattened in Python (`flatten_linear()`) before insert — cleaner than doing it in T-SQL
- `pyodbc` with ODBC Driver 17 for SQL Server

First successful run: backfill files already in `import_log` (loaded manually earlier) were skipped; snapshot files loaded incrementally.

---

**Silver layer design — Freshdesk**

Decided on a minimal silver schema for `silver.freshdesk_tickets`. Rationale: the dashboard needs ticket volume and status reporting only — no subject, no priority, no SLA fields.

Fields kept: `id`, `status` (raw code), `created_at` (DATE), `updated_at` (DATE), `product_id`, `denied_triage`.

Fields dropped from bronze: `subject`, `priority`, `due_by`, `group_id`. None of these are needed for the planned reporting views.

Status codes relevant for reporting:

| Code | Meaning |
|---|---|
| 17 | Waiting for triage (support sets this) |
| 6, 7, 12 | Passed triage (OPEX meeting decision) |
| 2, 3, 4, 5 | Open, Pending, Resolved, Closed |

**Denied triage detection**

No dedicated status code exists in Freshdesk for "denied triage". Instead, the flag is derived from the bronze append-history: a ticket is `denied_triage = 1` if it has at least one row with status 6/7/12 at time T1 AND a later row with status 17 at T2 > T1. ISO 8601 UTC strings compare correctly lexicographically, so no date conversion is needed for the comparison. The flag is permanent — once set it is not cleared if the ticket changes status again, because the regression actually occurred.

**Silver load strategy: TRUNCATE + full rebuild**

The silver script (`sql/05_silver_load_freshdesk.sql`) truncates the table and rebuilds it entirely on every run, inside a transaction (rolls back on error). This is simpler and more correct than incremental upserts, because denied_triage depends on the full history and cannot be determined row-by-row. Acceptable at current data volumes.

**SQL files created:**
- `sql/04_silver_create_tables_freshdesk.sql` — CREATE TABLE with IF NOT EXISTS guard
- `sql/05_silver_load_freshdesk.sql` — TRUNCATE + full rebuild, with group filter, deduplication, date conversion, and denied_triage CTE

---

**Silver layer revision — statusövergångsdatum tillagda**

The initial silver design stored only the current status per ticket (one row, latest state). This was sufficient for snapshot-style reporting ("how many tickets are currently in waiting?") but not for period-based reporting ("how many tickets entered triage this week?").

Decision: add three date columns derived from the full bronze append-history, alongside the existing `denied_triage` BIT flag:

| Column | Meaning |
|---|---|
| `first_waiting_at` | Earliest `updated_at` in bronze where status=17 — proxy for when ticket entered the triage queue |
| `first_passed_at` | Earliest `updated_at` in bronze where status IN (6,7,12) — proxy for the OPEX decision date |
| `denied_triage_at` | Earliest `updated_at` of a status=17 row that follows a status IN (6,7,12) row — the regression date |

These are approximations, not exact Freshdesk event timestamps. Because snapshots are nightly, the dates are accurate to ±1 day. This is sufficient for weekly/monthly period reporting in Power BI.

`denied_triage` (BIT) is kept alongside `denied_triage_at` for simple filtering in Power BI without needing a NULL check.

Both SQL files updated to include the new columns and the corresponding CTEs in the load script.

---

**Silver layer — Linear**

Created `silver.linear_issues` following the same TRUNCATE + full rebuild pattern as Freshdesk silver.

Key design decisions:

**Filter:** Exclude issues where BOTH `identifier LIKE 'DEV%'` AND `team_name = 'Development'`. Both conditions must be true — an AND filter, not OR. This avoids accidentally excluding edge-case issues that share a prefix but belong to another team.

**Field selection:** Minimal — only what's needed for flow analysis and reporting. Dropped: `identifier`, `number`, `title`, `description`, all `*_id` fields, `team_*`, `parent_*`, `cycle_*`, `archived_at`, `due_date`, `estimate`. Kept `trashed` for potential analysis.

**Three key dates for flow analysis:**
- `created_at` — issue created (unstarted)
- `started_at` — work begun / assigned (Linear's `startedAt` field)
- `closed_at` — COALESCE(completed_at, canceled_at) — covers completed + cancelled + duplicate

Linear has proper timestamp fields for these events (unlike Freshdesk where we inferred from the append-history). No history CTEs needed.

**completed_at vs closed_at:** Both are kept in silver. `completed_at` is Linear's own field, set only for "completed"-type states. `closed_at` is the derived field that covers all done states. Gold layer will decide which to expose to Power BI.

**backlog vs unstarted:** Both `state_type` values appear in Linear data. Treated as equivalent for now — will be resolved in the gold layer.

**is_incident flag:** Derived from `labels LIKE '%incident%'`. The CI collation (SQL_Latin1_General_CP1_CI_AS) makes this case-insensitive, handling "Incident", "incident", "INCIDENT" etc. NULL labels safely evaluate to 0.

**SQL files created:**
- `sql/06_silver_create_tables_linear.sql` — CREATE TABLE with IF NOT EXISTS guard
- `sql/07_silver_load_linear.sql` — TRUNCATE + full rebuild

---

**Morning refresh procedure (local, manual)**

GitHub Actions commits new snapshot JSON files to the repo every night. The full sequence to bring the local SQL Server database up to date each morning is:

1. `git pull` — fetch the new files from the repo
2. `python script/bronze_loader.py` — incremental load of new/updated records into bronze
3. Run silver scripts in SSMS (or via `sqlcmd`) — rebuild silver from bronze

Steps must run in this order. Skipping step 1–2 means silver is rebuilt from yesterday's bronze data.

`sqlcmd` command for step 3 (no SSMS required):
```
sqlcmd -S localhost -d OPEX_statistics -E -i "sql\05_silver_load_freshdesk.sql"
```

A `script/morning_refresh.ps1` automation script is planned for when both silver layers (Freshdesk + Linear) and the gold layer are complete. For production deployment, SQL Server Agent or SSIS will replace the manual process.
