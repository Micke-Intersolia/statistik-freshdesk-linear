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

**Active track: Power BI visuals — Summary page complete, sent to client for review**

Summary page built (2026-06-12). Six detail pages built (Linear + Freshdesk). Report sent to client; awaiting feedback.

**Report structure — 7 pages + 2 tooltip pages (9 tabs total)**

Tab order: Summary | Freshdesk | Linear - Overview | Linear - Trends | Linear - Distribution | Linear - Assignee | Linear - Assignee (details) | Tooltip - Oldest Issue | Tooltip - Assignee Weekly

---

**Page 1 — Summary** (tab: `Summary`)
- Stakeholder landing page — overwork narrative at a glance
- Intersolia logo (top left); "SUMMARY" title (top right)
- Period toggle slicer: Week / Month; Period label cards: `Period Label`, `Prev Period Label`
- KPI row 1 (Linear): Created Issues (Δ%), Closed Issues (Δ%), Open Issues (Δ), Incidents (Δ), Oldest Open Issue (red, with identifier below)
- KPI row 2 (Freshdesk): Waiting for Triage (Δ%), Passed Triage (Δ%), Escalated Tickets % (Δpp)
- Chart: bar+line — Created + Closed bars, Open Issues backlog line (last 4 months); same chart as Linear - Overview
- Cross-filtering from chart to KPI cards disabled via Edit Interactions
- No Linear or Freshdesk source logos — summary covers both sources

---

**Page 2 — Freshdesk** (tab: `Freshdesk`)
- Period toggle slicer: Week / Month; Period label cards: `Period Label`, `Prev Period Label`
- KPI cards: Created Tickets (with Δ%), Waiting for Triage (with Δ%), Passed Triage (with Δ%), Escalated Tickets % (with Δpp), Denied Triage (with Δ)
- Right column: "Tickets waiting longer than X days" card (driven by `Wait Threshold` what-if parameter, default 30 days)
- Chart: Created Tickets + Escalation Rate % over time (bar + line)
- Note: Freshdesk page is functional but not the current reporting focus; all Freshdesk visuals filtered to current year only (remove ~June 2027 once 12 months of data have accumulated)

**Page 3 — Linear - Overview** (tab: `Linear - Overview`)
- KPI cards: Created Issues, Closed Issues, Open Issues, Incidents, Oldest Issue (all with period Δ except Oldest Issue)
- Oldest Open Issue card shows value in red with identifier (e.g. OPEX-763) below it
- Period toggle slicer: Week / Month (disconnected `PeriodType` table)
- Period label cards: `Period Label` and `Prev Period Label`
- Chart: Line and clustered column — Created + Closed bars, Open Issues line (secondary axis, max=100)
- Chart visual filter: last 4 months (on DimDate[date_key]); chart shows live current month
- Cross-filtering from chart to KPI cards disabled via Edit Interactions

**Page 4 — Linear - Trends** (tab: `Linear - Trends`)
- Month slicer (DimDate[Month], dropdown, multi-select)
- KPI cards (slicer-connected): Days to close avg, Days to close median
- KPI card (all-time, slicer-disconnected): Oldest open issue (age in days) — shown in red; `Oldest Open Identifier` and `Oldest Open Title` cards alongside
- Chart 1: Line chart — Created 3M MA + Closed 3M MA (slicer disconnected)
- Chart 2: Line chart — Avg Created→Closed 3M, Avg Created→Started 3M, Avg Started→Closed 3M (slicer disconnected)

**Page 5 — Linear - Distribution** (tab: `Linear - Distribution`)
- Month slicer (same style as page 3, slicer connected to both charts and table)
- KPI cards: Days to close avg + median (same measures as page 3, slicer connected)
- Left chart: Issues per Project Group (horizontal bar, slicer connected via created_at)
- Table below left chart: Project Group | Avg days to close | Median days to close — sorted by avg descending; subtitle "Closed issues in selected period"
- Right chart: Lead Time buckets (horizontal bar, conditional colours via Rules on Lead Time Sort, slicer connected via closed_at; visual filter excludes Blank bucket)

**Page 6 — Linear - Assignee** (tab: `Linear - Assignee`)
- Month slicer: **tile/button style** (row of tiles across top), `DimDate[Month]`, multi-select, Select All enabled; connected to table and bar chart; disconnected from line chart
- Page-level filter: last 12 months
- Excluded assignees (page-level filter on `FactLinear[Assignee]`): **Kasper Mikkelsen, Pål Brattberg, Thomas Andersson** — excluded because they skew data and are not relevant to ongoing OPEX reporting; note displayed as text box on page
- Line chart: Created per assignee per month — X: DimDate[Month], Y: `_L Measures 3[Created]`, Legend: `FactLinear[Assignee]`; slicer disconnected so full trend always visible; `Is Current Month = 0` filter; Ctrl+click legend items to highlight
- Table: Assignee | Created | Closed | Open | Days to Close | Incidents; slicer connected; sorted by Created descending
- Clustered horizontal bar: Created + Closed per assignee; slicer connected; sorted by Created descending
- `Assignee` calculated column on FactLinear: `IF(ISBLANK(assignee_name), "Unassigned", assignee_name)`

**Page 7 — Linear - Assignee (details)** (tab: `Linear - Assignee (details)`)
- No month slicer — both visuals use a fixed rolling 3 months + current month page-level filter
- Assignee slicer (tile/button style, top of page); connected to all visuals; selecting one person isolates their data across the whole page
- Page-level filter: rolling 3 months + current month
- Excluded assignees (same as page 5): Kasper Mikkelsen, Pål Brattberg, Thomas Andersson
- KPI card: `_L Measures 3[Open]` — current open backlog for selected assignee(s)
- KPI card: `_L Measures 2[Avg Days to Close]` — avg days to close in the 3-month window for selected assignee(s)
- Matrix (heat map): title "Created (blue) and Closed (green) issues last 3 months"; Rows=`FactLinear[Assignee]`, Columns=`DimDate[Month]`, Values=`_L Measures 3[Created]` (white→blue gradient) + `_L Measures 3[Closed]` (white→green gradient); field well headers renamed to single space; Tooltip page = "Tooltip - Assignee Weekly"
- Line chart: "Backlog trend last three months" — X: `DimDate[Month]`, Y: `_L Measures 3[Open at Month End]`, Legend: `FactLinear[Assignee]`; `Is Current Month = 0` filter; Assignee slicer connected

**Tooltip page 1 — Tooltip Oldest Issue** (tab: `Tooltip Oldest Issue`)
- Triggered by hovering over the Oldest Open Issue card on the Linear pages
- Contains a text box showing `_L Measures 2[Oldest Open Title]` — the full title of the currently oldest open Linear issue
- Gives context to the age number (e.g. "FD263108: Investigate missing detailed data for restriction lists...")

**Tooltip page 2 — Tooltip - Assignee Weekly** (tab: `Tooltip - Assignee Weekly`)
- Triggered by hovering over any cell in the heat map matrix on page 6
- Horizontal bar chart: Y axis = `DimDate[Month]`, values = Created (blue) + Closed (green)
- Filter context (assignee + month) is passed automatically from the hovered matrix cell

`_L Measures 3[Open at Month End]` — new measure added this session:
```dax
Open at Month End =
VAR monthEnd = MIN(MAX(DimDate[date_key]), TODAY())
RETURN
CALCULATE(
    COUNTROWS(FILTER(
        FactLinear,
        FactLinear[created_at] <= monthEnd &&
        (ISBLANK(FactLinear[closed_at]) || FactLinear[closed_at] > monthEnd)
    )),
    REMOVEFILTERS(DimDate)
)
```
Assignee-aware version of `Linear Open Issues (Chart)` — uses `FactLinear` (not ALL) so Assignee legend filter passes through; REMOVEFILTERS(DimDate) replaces axis filter with monthEnd ceiling.

**Planned: chart-to-KPI drill interaction**
- Clicking a month bar should show that month vs. previous month in the KPI cards
- Currently disabled via Edit Interactions (chart does not cross-filter KPI cards) to prevent measure conflicts
- Requires rewriting all period measures to detect ISFILTERED(DimDate) and switch between rolling-period logic and selected-month logic

**Temporary report filter — remove when data matures**
- All Freshdesk visuals currently filtered to current year only due to limited backfill history
- Once 12+ months of nightly snapshots have accumulated, remove the year filter to restore full rolling 12-month view
- Linear data is sparse before Feb 2026 (6 issues Oct '25, 4 Nov '25, 2 Dec '25, 1 Jan '26) — reflects actual team adoption, not a pipeline gap

**Automation summary (complete)**
- Nightly snapshots: GitHub Actions → JSON files committed to repo (fully automated)
- Daily database refresh: Windows Task Scheduler on the operator's machine → `morning_refresh.ps1`
  - Checks DB connection first (handles office vs. VPN automatically)
  - Retries every hour; SOS alert if no success by 16:00 on a working day
  - Runs: git pull → bronze_loader.py → silver_loader.py
  - Logs to `logs/refresh.log`, last success date to `logs/last_success.txt`
- Gold views: always current (SQL views over silver, no rebuild step)

**Planned: email summary on pipeline completion**
- Add `Send-MailMessage` to `morning_refresh.ps1` to send a daily summary email on success and on failure
- Intersolia uses Microsoft 365 — requires SMTP relay setup (needs IT/admin access to configure an app password or shared mailbox SMTP credentials)
- GitHub Actions failure emails already work natively via GitHub's built-in notifications
- GitHub Actions workflow has `ALERT_EMAIL` env var ready for wiring in an SMTP action for success emails too

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
| `identifier` | NVARCHAR(50) | Human-readable ID e.g. "OPEX-42" |
| `title` | NVARCHAR(500) | Issue title |
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
| `id`, `identifier`, `title` | From silver — identifier is the human-readable "OPEX-42" style label |
| `state_name`, `state_type` | From silver |
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

## Power BI report model

**Relationships (DATE-to-DATE, set up once at model creation):**
- `DimDate.date_key` → `FactLinear.created_at` (active)
- `DimDate.date_key` → `FactLinear.closed_at` (inactive, role-playing)
- `DimDate.date_key` → `FactLinear.completed_at` (inactive, extra — not used by any USERELATIONSHIP)
- `DimDate.date_key` → `FactFreshdesk.created_at` (active)
- `DimDate.date_key` → `FactFreshdesk.first_waiting_at` (inactive, role-playing)
- `DimDate.date_key` → `FactFreshdesk.first_passed_at` (inactive, role-playing)
- `DimDate.date_key` → `FactFreshdesk.denied_triage_at` (inactive, extra — not used by any USERELATIONSHIP)

**DimDate calculated columns (added in Power BI, not in SQL):**

| Column | DAX | Sort by |
|---|---|---|
| `Month` | `month_short & " '" & RIGHT(FORMAT(year,"0000"),2)` — e.g. "Jun '26" | `month_sort` |
| `Is Current Month` | `IF(month_sort = YEAR(TODAY())*100+MONTH(TODAY()),1,0)` | — |
| `Quarter Label` | `"Q" & CEILING(DimDate[month_num] / 3, 1) & " '" & RIGHT(FORMAT(DimDate[year],"0000"),2)` — e.g. "Q2 '26". Note: uses `month_num` (integer), not `month` (text column) | `Quarter Sort` |
| `Quarter Sort` | `DimDate[year] * 10 + CEILING(DimDate[month_num] / 3, 1)` | — |

**Date Hierarchy** (right-click `Quarter Label` in Fields pane → Add to hierarchy → Create new hierarchy):
Levels in order: `Quarter Label` → `Month` → `year_week` → `date_key`
Enables drill-down on any chart: Quarter → Month → Week → Day.

**FactLinear calculated columns (added in Power BI):**

| Column | Purpose |
|---|---|
| `Project Group` | SWITCH on project_name → iChemistry / iPublisher / Chemsoft / Unassigned / Other |
| `Assignee` | `IF(ISBLANK(assignee_name), "Unassigned", assignee_name)` — shows "(Blank)" as "Unassigned" in visuals |
| `Lead Time` | SWITCH on days_to_close: `= 1` → "Same day", `<= 7` → "2–7 days", `<= 14` → "8–14 days", `<= 30` → "15–30 days", `<= 90` → "31–90 days", else "+90 days", BLANK for open issues |
| `Lead Time Sort` | Numeric 1–6 sort key for Lead Time column: `= 1` → 1, `<= 7` → 2, etc. (99 for BLANK) |

**Note on day counting:** `days_to_close`, `days_to_start`, and `age_days` in the gold view all use `DATEDIFF(...) + 1` — "days worked on" inclusive counting where same-day = 1, next day = 2. Lead Time bucket `= 1` correctly captures same-day issues.

**Disconnected tables (Enter Data, no relationships):**

| Table | Purpose |
|---|---|
| `PeriodType` | One column "Period" with rows "Week" and "Month" — drives the period toggle slicer on Linear page 1 |

**What-if parameters:**
- `Wait Threshold` — GENERATESERIES(1,180,1), default 30. Auto-generates `[Wait Threshold Value]` measure. Used on Freshdesk page for "tickets waiting over X days" card.

**Measures tables — naming convention:**
Table names: `_L Measures 1`, `_L Measures 2`, `_L Measures 3`, `_Helper Measures`, `_FD Measures`. No `_L Measures 4`.
Measure names are plain and descriptive — NO page prefix (e.g. `Avg Days to Close`, not `L2 Avg Days to Close`).

`_Helper Measures` — shared period logic used by both Freshdesk and Linear page 1:
- `Selected Period`, `Period Start`, `Period End`, `Prev Period Start`, `Prev Period End`, `Period Label`, `Prev Period Label`
- Also contains debug/dev helpers: `Check Week`, `Debug Week Flag`, `Last Completed Week`, `Last Date in Data`, `Start of Last Week`, `End of Last Week` — can be removed once no longer needed

`_L Measures 1` — Linear page 1 KPI and chart measures:
- `Linear Created`, `Linear Created Prev`, `Linear Created Δ%`
- `Linear Closed`, `Linear Closed Prev`, `Linear Closed Δ%`
- `Linear Open at Period End`, `Linear Open at Prev Period End`, `Linear Open Δ`
- `Linear Incidents`, `Linear Incidents Prev`, `Linear Incidents Δ`
- `Linear Avg Days to Close`, `Linear Avg Days to Close Prev`, `Linear Avg Days to Close Δ`
- `Linear Oldest Issue` (standalone, no Prev/Δ)
- `Linear Created (Chart)`, `Linear Closed (Chart)`, `Linear Open Issues (Chart)` — chart measure uses `ALL(FactLinear)` + `MIN(MAX(DimDate[date_key]), TODAY())` + historical logic (`ISBLANK OR closed_at > monthEnd`)

`_L Measures 2` — Linear pages 2–3 measures, plus one shared page 4 measure:
- `Avg Days to Close` — USERELATIONSHIP(closed_at), slicer-aware
- `Median Days to Close` — USERELATIONSHIP(closed_at), slicer-aware
- `Oldest Open Issue` — ALL(FactLinear), completely slicer-independent
- `Oldest Open Identifier` — identifier of the oldest open issue (ALL, slicer-independent)
- `Oldest Open Title` — title of the oldest open issue (ALL, slicer-independent)
- `Created 3M MA`, `Closed 3M MA` — 3-month rolling average of issue volume
- `Avg Created to Started 3M`, `Avg Started to Closed 3M`, `Avg Created to Closed 3M` — 3-month rolling average of days per lifecycle stage (cohort = closed in window)
`_L Measures 3` — Linear page 4 (People) measures:
- `Created` — COUNTROWS(FactLinear), responds to DimDate active relationship + Assignee legend/row context
- `Closed` — USERELATIONSHIP(DimDate[date_key], FactLinear[closed_at]), NOT ISBLANK(closed_at)
- `Open` — REMOVEFILTERS(DimDate), ISBLANK(closed_at) — all-time current open backlog per person; used on page 4 table
- `Incidents` — COUNTROWS where is_incident = TRUE()

`_FD Measures` — Freshdesk page measures (set aside, not current focus)

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
1. Get a GitHub PAT from the outgoing person (or generate one: github.com → profile → Settings → Developer settings → Fine-grained tokens → read-only, Contents permission, no expiration, scoped to this repo)
2. Clone the repo: `git clone https://Micke-Intersolia:<TOKEN>@github.com/Micke-Intersolia/statistik-freshdesk-linear.git`
3. Create `credentials/sql_connection.txt` with the connection string (format: `DRIVER={ODBC Driver 17 for SQL Server};SERVER=INTSQLSERVER01;DATABASE=InternalStatistics;UID=xxx;PWD=xxx;`)
4. Create `credentials/github_token.txt` with the PAT — for future reference and re-cloning
5. Register the Task Scheduler task (as Administrator): `powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1" -Register`
6. In Task Scheduler: open the task → Triggers → Edit → tick "Repeat task every: 1 hour" for 13 hours

Full instructions for handover (including Option B — SQL Server Agent): `docs/pipeline-setup-instructions.md`

**GitHub Actions** (already configured — no action needed)
- Snapshot scripts run nightly automatically
- Secrets `LINEAR_API_KEY` and `FRESHDESK_API_KEY` are already stored in the repo's GitHub Secrets

---

## Security constraints

- `credentials/` is git-ignored — never commit API keys or connection strings, even though the repo is private (git history is permanent; repo access may expand)
- `credentials/sql_connection.txt` — SQL Server connection string
- `credentials/github_token.txt` — GitHub PAT for git clone/pull (read-only, no expiration)
- API keys: `FRESHDESK_API_KEY`, `LINEAR_API_KEY` (env vars or `credentials/*.txt`)
- GitHub Secrets configured: `LINEAR_API_KEY`, `FRESHDESK_API_KEY`
