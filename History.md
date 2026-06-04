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
