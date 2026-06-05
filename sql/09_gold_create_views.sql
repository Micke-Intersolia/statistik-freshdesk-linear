-- ============================================================
-- 09_gold_create_views.sql
-- Creates gold.FactFreshdesk and gold.FactLinear as SQL views
-- over the silver layer.
--
-- Safe to re-run — CREATE OR ALTER replaces existing views.
-- Views are always current — no rebuild step needed.
--
-- Gold naming: PascalCase (FactFreshdesk, FactLinear).
-- No separate dimension tables — status/state labels are
-- computed columns embedded directly in the views.
--
-- Power BI relationships (DATE-to-DATE, no integer key needed):
--   DimDate.date_key → FactFreshdesk.created_at
--   DimDate.date_key → FactFreshdesk.first_waiting_at  (role-playing)
--   DimDate.date_key → FactFreshdesk.first_passed_at   (role-playing)
--   DimDate.date_key → FactLinear.created_at
--   DimDate.date_key → FactLinear.closed_at             (role-playing)
-- ============================================================

USE InternalStatistics;
GO


-- ── gold.FactFreshdesk ────────────────────────────────────────
-- One row per support ticket (from silver.freshdesk_tickets).
-- Adds human-readable labels and a triage_status summary column.
--
-- status_label: readable name for the Freshdesk status code.
--   Known OPEX codes: 17 = Waiting, 6/7/12 = Passed.
--   Standard Freshdesk codes: 2=Open, 3=Pending, 4=Resolved, 5=Closed.
--   Any other code falls through to 'Other (NN)'.
--
-- triage_status: single column summarising where a ticket stands
--   in the triage workflow — use this as the main slicer in Power BI.
--
-- denied_triage / denied_triage_at: permanent flag set in silver.
CREATE OR ALTER VIEW gold.FactFreshdesk AS
SELECT
    id,
    status,

    CASE status
        WHEN 2  THEN 'Open'
        WHEN 3  THEN 'Pending'
        WHEN 4  THEN 'Resolved'
        WHEN 5  THEN 'Closed'
        WHEN 6  THEN 'Passed triage'
        WHEN 7  THEN 'Passed triage'
        WHEN 12 THEN 'Passed triage'
        WHEN 17 THEN 'Waiting for triage'
        ELSE         'Other (' + CAST(status AS NVARCHAR(5)) + ')'
    END                                              AS status_label,

    -- triage_status: current position in the OPEX triage lifecycle.
    -- 'Denied'   — was passed, then returned to waiting (regression).
    -- 'Waiting'  — currently in the triage queue.
    -- 'Passed'   — OPEX approved (any of 6/7/12), not subsequently denied.
    -- 'Other'    — standard Freshdesk lifecycle states (open/pending/etc.).
    CASE
        WHEN denied_triage = 1 AND status = 17 THEN 'Denied'
        WHEN status = 17                        THEN 'Waiting'
        WHEN status IN (6, 7, 12)               THEN 'Passed'
        ELSE                                         'Other'
    END                                              AS triage_status,

    created_at,
    updated_at,
    product_id,
    first_waiting_at,
    first_passed_at,
    denied_triage,
    denied_triage_at

FROM silver.freshdesk_tickets;
GO


-- ── gold.FactLinear ───────────────────────────────────────────
-- One row per Linear issue (from silver.linear_issues).
-- Adds human-readable state label and duration metrics.
--
-- state_label: readable name for state_type + state_name.
--   Collapses 'backlog' and 'unstarted' into 'Backlog / Unstarted'
--   to avoid the two-value split in Power BI slicers.
--
-- days_to_start:  calendar days from created_at to started_at.
-- days_to_close:  calendar days from created_at to closed_at.
-- age_days:       for open issues — days since created_at (today's date).
--                 NULL for closed/cancelled issues (use days_to_close instead).
--
-- DATEDIFF(DAY, ...) returns NULL if either argument is NULL — correct
-- behaviour since we don't want a metric when the date is unknown.
CREATE OR ALTER VIEW gold.FactLinear AS
SELECT
    id,
    state_name,
    state_type,

    CASE state_type
        WHEN 'backlog'    THEN 'Backlog / Unstarted'
        WHEN 'unstarted'  THEN 'Backlog / Unstarted'
        WHEN 'started'    THEN 'In Progress'
        WHEN 'completed'  THEN 'Completed'
        WHEN 'cancelled'  THEN 'Cancelled'
        ELSE                   'Other'
    END                                              AS state_label,

    priority,

    -- priority_label matches Linear's own labels (0=None is intentional)
    CASE priority
        WHEN 0 THEN 'No priority'
        WHEN 1 THEN 'Urgent'
        WHEN 2 THEN 'High'
        WHEN 3 THEN 'Medium'
        WHEN 4 THEN 'Low'
        ELSE        'Unknown'
    END                                              AS priority_label,

    created_at,
    started_at,
    completed_at,
    closed_at,

    DATEDIFF(DAY, created_at, started_at)            AS days_to_start,
    DATEDIFF(DAY, created_at, closed_at)             AS days_to_close,

    -- age_days: only meaningful for issues that are not yet closed.
    -- Using CAST(GETUTCDATE() AS DATE) keeps it consistent with silver
    -- DATE columns (no time component).
    CASE
        WHEN closed_at IS NULL
        THEN DATEDIFF(DAY, created_at, CAST(GETUTCDATE() AS DATE))
        ELSE NULL
    END                                              AS age_days,

    project_name,
    assignee_name,
    labels,
    trashed,
    is_incident

FROM silver.linear_issues;
GO


-- ── Verify ────────────────────────────────────────────────────
PRINT 'gold.FactFreshdesk:';
SELECT TOP 5
    id, status, status_label, triage_status,
    created_at, first_waiting_at, first_passed_at,
    denied_triage
FROM gold.FactFreshdesk
ORDER BY id;

PRINT 'gold.FactLinear:';
SELECT TOP 5
    id, state_type, state_label, priority_label,
    created_at, closed_at, days_to_close, age_days,
    is_incident
FROM gold.FactLinear
ORDER BY id;
GO
