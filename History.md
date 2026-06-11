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

**SQL Server bronze layer — `OPEX_statistics` (localhost)**

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

---

## 2026-06-11

**Pipeline handover documentation**

Created `docs/pipeline-setup-instructions.md` — a self-contained guide for whoever sets up the daily refresh pipeline on a new machine. Covers two options:

*Option A — operator's Windows machine (Task Scheduler):* Same setup as Michael's machine. Suitable when the operator's PC is on and network-connected most working days. Steps: install Git, Python 3.12, ODBC Driver 17; clone repo with PAT; create credentials files; register Task Scheduler task with hourly repetition.

*Option B — SQL Server (SQL Server Agent):* Full pipeline runs on `INTSQLSERVER01`, independent of any operator machine. Requires IT to install Git and Python on the server and confirm outbound HTTPS to github.com. SQL Agent job runs `morning_refresh.ps1` via CmdExec at 07:00 daily.

**GitHub PAT for private repo access**

The repo is private — git clone/pull requires a GitHub Personal Access Token. Setup:
- Account-level: github.com → profile → Settings → Developer settings → Fine-grained tokens
- Permissions: Contents: Read-only (Metadata: Read granted automatically)
- Expiration: No expiration (project must outlive any single operator)
- Scope: single repository only

Token stored locally in `credentials/github_token.txt` (git-ignored). The script does not read this file — git/Windows Credential Manager handles auth after the initial clone. The file exists purely for handover reference.

**Why credentials/ stays git-ignored despite the repo being private**

Git history is permanent. Credentials committed now would be visible forever via `git log` even after deletion, to anyone ever granted repo access. The small inconvenience of out-of-band credential sharing is worth it.

---

## 2026-06-09

**morning_refresh.ps1 — git pull bug fixed**

The script was silently dying at "Step 1/3 git pull" on days when GitHub Actions had committed new snapshot files (i.e. when git pull actually downloaded content). Root cause: git writes download progress to stderr; `2>&1` in PowerShell 5.1 captures native command stderr as `ErrorRecord` objects; `$ErrorActionPreference = "Stop"` terminates on the first `ErrorRecord`. The fix wraps each native command call (`git pull`, `& $PYTHON`) with `$ErrorActionPreference = "Continue"` before and `$ErrorActionPreference = "Stop"` after, while still checking `$LASTEXITCODE` for real failures.

**Power BI — Linear pages 1, 2, 3 built**

Focus shifted from Freshdesk to Linear. Three Linear report pages built in Power BI Desktop.

*Page 1 — Overview:*
Mirrors the Freshdesk page structure. KPI cards with period Δ (Created, Closed, Open, Incidents, Oldest Issue). Period toggle (Week/Month) via disconnected `PeriodType` table. Bar+line chart: Created + Closed bars per month, Open Issues line on secondary axis. Chart cross-filtering to KPI cards disabled via Edit Interactions (conflicts with TODAY()-based period measures).

*Page 2 — Trends:*
Month dropdown slicer (DimDate[Month Label], sorted by month_sort). Two KPI cards slicer-connected (avg/median days to close via USERELATIONSHIP on closed_at). One KPI card slicer-independent (oldest open issue, uses ALL(FactLinear) to ignore all filters). Visual labels distinguish "Filtered by selected period" from "All time". Two line charts with 3-month moving averages: volume trend (Created 3M MA, Closed 3M MA) and lifecycle stage duration (Created→Started, Started→Closed, Created→Closed). MA measures use ALL(DimDate) and direct FactLinear date filters to look back across the 3-month window regardless of slicer state. MA charts slicer-disconnected via Edit Interactions.

*Page 3 — Distribution:*
Month slicer connected to all visuals. KPIs: avg and median days to close. Issues per Project Group horizontal bar chart. Project Group summary table (avg + median days to close per project, sorted by avg descending — closed issues in selected period only). Lead Time bucket chart with 6 buckets (1 day through >90 days), colour-coded green→red via Format → Visual → Bars → fx → Rules based on Lead Time Sort column. Blank bucket (open issues) excluded via visual-level filter.

*Calculated columns added to FactLinear in Power BI:*
- `Project Group`: SWITCH on project_name → iChemistry / iPublisher / Chemsoft / Unassigned / Other
- `Lead Time Bucket`: SWITCH on days_to_close into 6 text ranges; BLANK for open issues
- `Lead Time Sort`: numeric 1–6 sort key for Lead Time Bucket

*DimDate calculated column added in Power BI:*
- `Month Label`: `"'" & RIGHT(FORMAT(year,"0000"),2) & " " & month_short` — sorted by `month_sort`. Ensures months display as "'25 Jan" etc. and sort chronologically in slicers and charts.
- `Is Current Month`: flags the current calendar month — used as a visual-level filter to exclude the in-progress month from trend charts.

*Power BI measure naming convention established:*
Measure tables are named `_L Measures`, `_L Measures 2`, `_L Measures 3`, `_L Measures 4` (not `_L2 Measures` etc.). Measure names are plain and descriptive without page prefixes — e.g. `Avg Days to Close`, not `L2 Avg Days to Close`. All future measure suggestions should follow this convention.

*identifier and title restored to silver and gold:*
`identifier` (e.g. "OPEX-42") and `title` were initially dropped from silver as "not needed for reporting." This was a mistake — they are essential for identifying specific issues in tooltips and drillthrough. Restored by: (1) adding `ALTER TABLE` guards to `06_silver_create_tables_linear.sql` so the columns are added safely to the existing table without dropping it; (2) adding `identifier` and `title` to the CTE SELECT and INSERT in `07_silver_load_linear.sql`; (3) passing them through in `09_gold_create_views.sql`. Run scripts 06 → 07 → 09 in order in SSMS after any future handover.

*Lead Time bucket fix — duplicate bars:*
The Lead Time Sort column used `<= 1` for sort value 1, which matched both `days_to_close = 0` (Same day) and `days_to_close = 1` (next day). The Lead Time column assigned both "Same day" and "Up to one week" labels to overlapping ranges. Power BI split "Up to one week" into two bars (one per sort key). Fixed by aligning Lead Time Sort thresholds exactly to the Lead Time column logic.

*Day counting — inclusive "days worked on":*
`DATEDIFF(DAY, created_at, closed_at)` returns 0 for same-day closures. Changed to `DATEDIFF(...) + 1` throughout `sql/09_gold_create_views.sql` so that same-day = 1, next day = 2 — matching the intuitive "days worked on" interpretation. Applied to `days_to_start`, `days_to_close`, and `age_days`. Lead Time bucket `= 0` updated to `= 1` accordingly, as is Lead Time Sort. All other bucket thresholds unchanged.

*Key DAX lessons from this session:*
- DAX reserved words: `start` and `end` cannot be used as variable names — use `periodStart`/`periodEnd`
- Measure references inside CALCULATE filter arguments fail — capture as VAR first
- COALESCE(..., 0) needed for measures that should return 0 rather than BLANK on empty periods
- For slicer-independent measures: `CALCULATE(..., REMOVEFILTERS())` or `ALL(FactLinear)` inside FILTER
- For role-playing date relationships in measures: `USERELATIONSHIP(DimDate[date_key], FactLinear[closed_at])`
- Moving average pattern: `VAR monthEnd = MAX(DimDate[date_key])` captured before `ALL(DimDate)` clears the context, then direct date filters on FactLinear columns

*Linear data note:*
Linear adoption at Intersolia ramped up in Feb 2026. Only 13 issues have created_at before Feb 2026 (6 in Oct '25, 4 in Nov '25, 2 in Dec '25, 1 in Jan '26). This is real data, not a pipeline gap.

---

## 2026-06-08

**Silver loader — `script/silver_loader.py`**

Created `silver_loader.py` to run the two silver rebuild scripts programmatically via pyodbc, replacing the need for `sqlcmd` on the operator's machine.

- Reads the same `credentials/sql_connection.txt` as `bronze_loader.py`
- Splits each SQL file on `GO` statements and executes batches in order
- Pre-flight safety check: queries row count of the relevant bronze table before running each script; exits with a clear error if bronze is empty (prevents wiping silver with nothing to rebuild from)
- `autocommit=True` so the SQL scripts' own `BEGIN TRANSACTION / COMMIT / ROLLBACK` logic works as intended
- Run order: Freshdesk silver first (`05_silver_load_freshdesk.sql`), then Linear silver (`07_silver_load_linear.sql`)

**Automation decision — Windows Task Scheduler**

GitHub Actions (Microsoft-hosted runners) cannot reach `INTSQLSERVER01` because it is on the internal network. SQL Server Agent was also ruled out because the operator does not have OS-level server access, only database credentials. Decision: automate via Windows Task Scheduler on the operator's own machine, which already has network/VPN access to the server.

**Morning refresh script — `script/morning_refresh.ps1`**

Created `morning_refresh.ps1` to fully automate the daily database refresh.

Key design decisions:

- **Connection-first pattern**: tests the ODBC connection before doing anything. Handles office (direct) and remote (VPN) transparently — same code path, different network conditions.
- **Idempotent**: writes the success date to `logs/last_success.txt`. If the task fires multiple times in one day (hourly repetition), subsequent runs exit immediately.
- **Retry via Task Scheduler**: the script exits with code 1 if the DB is unreachable; the Task Scheduler trigger (weekdays, 07:00-20:00, every hour) retries naturally.
- **StartWhenAvailable**: if the laptop was off during a scheduled run, the task fires as soon as the machine wakes up.
- **SOS alert**: if it is past 16:00 on a weekday and no successful run has occurred today *or* on the previous working day, a Windows Forms balloon notification fires and a flag `.txt` file is written to the Desktop.
- **Encoding**: all string literals use ASCII only. Em-dashes and other Unicode characters in PowerShell 5.1 scripts cause parse errors when the file is read as Windows-1252 (the runtime default); the UTF-8 byte sequence for `—` contains `0x94`, which Windows-1252 reads as a right double-quote, breaking all subsequent string literals.
- Uses the repo's `.venv\Scripts\python.exe` if present; falls back to system Python.

Registration:
```powershell
powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1" -Register
```

The hourly repetition (PT1H for PT13H duration) must be set manually in Task Scheduler GUI because PowerShell 5.1's CIM layer does not always support direct property assignment on the `Repetition` object of a `MSFT_TaskWeeklyTrigger`.

**Full pipeline — confirmed working**

Complete end-to-end flow verified:
1. GitHub Actions commits nightly snapshot JSON files to the repo (automated)
2. `git pull` fetches new files to the local machine
3. `bronze_loader.py` loads new/updated records into bronze tables (incremental)
4. `silver_loader.py` rebuilds both silver tables from bronze (TRUNCATE + full rebuild)
5. Gold views (`FactFreshdesk`, `FactLinear`) are always current — no rebuild step needed
6. Power BI connects to gold layer

**Note on VPN**: the operator must be on the Intersolia network (office or VPN) for steps 2-4 to reach `INTSQLSERVER01`. The morning_refresh.ps1 retry logic handles days when VPN connects later than 07:00.

**Power BI — Linear Page 4 (People) built**

Fourth Linear report page added. Tab names set: Overview, Trends, Distribution, People.

*Layout:* Month slicer at top. Line chart (full width, slicer-disconnected) showing Created issues per assignee per month — one line per person via the `Assignee` calculated column in the Legend field. No separate people slicer — the line chart's own legend acts as the colour guide; Ctrl+click on a legend item highlights that person's line. Table and clustered horizontal bar below (both slicer-connected): Assignee | Created | Closed | Open Issues Assignee | Avg Days to Close | Incidents; bar shows Created + Closed side by side.

*Measures:* `_L Measures 3` table created for page 4 with `Created` (COUNTROWS), `Closed` (USERELATIONSHIP on closed_at), and `Incidents`. `Open Issues Assignee` placed in `_L Measures 2` (REMOVEFILTERS(DimDate), ISBLANK(closed_at) — all-time backlog per person). `Avg Days to Close` reused from `_L Measures 2` as-is.

*Why no Chiclet Slicer:* Chiclet Slicer was installed but dropped — it only supports global selected/unselected colours, not per-item colours. Using the line chart legend instead is cleaner and natively supported.

*Why new measures instead of reusing `Linear Created`:* `Linear Created` uses the period toggle logic (VAR periodStart/periodEnd from the PeriodType table), which collapses the month axis into a single period value. New plain `Created = COUNTROWS(FactLinear)` responds purely to DimDate filter context and Assignee legend, which is what the trend line chart needs.

Report sent to client (2026-06-09) for review and feedback.

---

## 2026-06-05

**Migration till produktionsserver — `InternalStatistics` på `INTSQLSERVER01`**

IT skapade databasen `InternalStatistics` på `INTSQLSERVER01` (SQL Server 2022). Schemas `bronze`, `silver`, `gold` skapades manuellt. Alla SQL-skript uppdaterades från `USE OPEX_statistics` till `USE InternalStatistics`.

Serverinställningar:
- Kollation: `Latin1_General_100_CI_AS` — CI (case-insensitive), kompatibel med alla LIKE-filter i silver
- Data och logg på separata diskar (`F:\data\` och `F:\log\`) — IT:s standarduppsättning
- Autogrow: 64 MB fast (inte procent) — korrekt inställt av IT
- Recovery model: Full — acceptabelt, IT hanterar loggbackuper på servernivå
- Max storlek: Unlimited (data), 2 TB (logg)

Autentisering: SQL Server Authentication. Connection string lagras i `credentials/sql_connection.txt` (git-ignorerad). Ingen GitHub Secret behövs ännu eftersom `bronze_loader.py` körs lokalt — om GitHub Actions-automation av bronze-laddning implementeras i framtiden läggs `SQL_CONNECTION_STRING` till som repository secret.

Localhost-databasen `OPEX_statistics` finns kvar som lokal test/dev-miljö.

Datamigrering: alla SQL-skript (01–07) kördes mot den nya servern. `bronze_loader.py` laddade alla JSON-filer från `raw/` inkrementellt. Silver rebuildes från brons med script 05 och 07.

---

**Gold layer — design och dim_date**

Beslutad gold-arkitektur:
- `gold.dim_date` — riktig tabell (en rad per dag), populeras en gång och uppdateras vid behov
- `gold.fact_freshdesk` — SQL-vy över silver (planerad)
- `gold.fact_linear` — SQL-vy över silver (planerad)

Vyer valdes för faktatabellerna istället för riktiga tabeller: alltid aktuella mot silver, inget extra rebuild-steg i morning refresh. Vid dessa datamängder (tusental rader) är prestandan identisk med riktiga tabeller i Power BI Import-läge.

**dim_date-design:**
- Datumtyp: `DATE` (inte INT/YYYYMMDD). Power BI hanterar DATE-relationer nativt och silver-tabellerna har redan DATE-kolumner — inga konverteringar i joins.
- Intervall: **2025-01-01 till 2035-12-31** (4 018 dagar). Medvetet val — tillräckligt långt för projektet utan onödig overhead. Se instruktioner i `sql/08_gold_dim_date.sql` för att utöka.
- `month_sort` (INT, YYYYMM) och `year_week` (NVARCHAR, 'YYYY-WNN') är Power BI-specifika sorteringskolumner — används inte i rapporter, bara som sort keys bakom kulisserna.
- `working_days_in_week`: antal arbetsdagar i ISO-veckan. Veckor med helgdag visar 4 istället för 5 — möjliggör normalisering av veckovolymer i Power BI.
- Veckoidentifiering görs via "torsdagen i ISO-veckan" som partitionsnyckel, vilket hanterar årsbrytnings-veckor korrekt (t.ex. 2035-12-29 tillhör ISO-vecka 1 år 2036).
- Explicita CASE-mappningar för månads- och dagnamn — undviker språkberoende DATENAME-resultat på servrar med svenska locale-inställningar.
- Svenska helgdagar: officiella röda dagar. Julafton, Midsommarafton och Nyårsafton är INTE inkluderade (officiellt inte röda dagar).
- Påskdatum 2025–2035 hårdkodade. Nästa block: 2036-04-13, 2037-04-05, 2038-04-25, 2039-04-10, 2040-04-01.

SQL: `sql/08_gold_dim_date.sql`

---

**Gold layer — FactFreshdesk and FactLinear views**

Created `sql/09_gold_create_views.sql` with both gold fact views (CREATE OR ALTER VIEW — safe to re-run).

**`gold.FactFreshdesk`** — view over `silver.freshdesk_tickets`:
- `status_label`: human-readable name for each Freshdesk status code. Standard codes (2–5) map to Open/Pending/Resolved/Closed; OPEX codes (6/7/12) map to 'Passed triage'; 17 maps to 'Waiting for triage'; unknown codes fall through to 'Other (NN)'.
- `triage_status`: single-column summary for Power BI slicer — 'Waiting', 'Passed', 'Denied' (was passed, then regressed to 17), or 'Other'. The 'Denied' state is detected by combining `denied_triage = 1` AND `status = 17`, so it only applies to tickets currently sitting in the triage queue after a regression — not tickets that were denied but have since moved on.

**`gold.FactLinear`** — view over `silver.linear_issues`:
- `state_label`: collapses `state_type` 'backlog' and 'unstarted' into 'Backlog / Unstarted' — removes the two-value split that would otherwise appear in Power BI slicers.
- `priority_label`: maps 0–4 to No priority / Urgent / High / Medium / Low (matches Linear's own UI labels).
- `days_to_start`: DATEDIFF(DAY, created_at, started_at) — NULL when started_at is NULL.
- `days_to_close`: DATEDIFF(DAY, created_at, closed_at) — NULL when closed_at is NULL.
- `age_days`: for open issues only (closed_at IS NULL) — days since created_at. NULL for closed/cancelled issues; use days_to_close for those.

All silver columns are passed through unchanged so Power BI has direct access to dates and flags.

Gold layer is now complete. Next step: connect Power BI Desktop to `InternalStatistics` on `INTSQLSERVER01` and build the report from `gold.DimDate`, `gold.FactFreshdesk`, `gold.FactLinear`.
