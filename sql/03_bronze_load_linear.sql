-- ============================================================
-- 03_bronze_load_linear.sql
-- Loads one Linear JSON file into bronze.linear_issues.
--
-- HOW TO USE:
--   1. Edit the two variables in Step 1.
--   2. Select All and run (F5).
--   3. Safe to re-run — skips if file already in import_log.
--
-- Run order for initial load:
--   First:  the backfill file  (linear_backfill_*.json)
--   Second: the latest snapshot (linear_snapshot_*.json)
--   Future: each new nightly snapshot as it arrives
--
-- KEY DIFFERENCE FROM FRESHDESK:
--   Linear's JSON contains nested objects (state, assignee, team,
--   etc.) and an array (labels). Each nested object is accessed
--   with dot-notation in JSON_VALUE, e.g. '$.state.id'.
--   The labels array is collapsed into a pipe-separated string
--   using a correlated subquery with STRING_AGG.
-- ============================================================

USE OPEX_statistics;
GO

-- ── Step 1: Set these two values before running ──────────────
DECLARE @file_name  NVARCHAR(260) = 'linear_backfill_20250501_20260604.json';
DECLARE @file_path  NVARCHAR(260) = 'C:\Users\michael.brostrom\Documents\GitHub\statistik-freshdesk-linear\raw\linear\linear_backfill_20250501_20260604.json';

-- ── Step 2: Idempotency check ────────────────────────────────
IF EXISTS (SELECT 1 FROM bronze.import_log WHERE file_name = @file_name)
BEGIN
    PRINT 'SKIPPED — already loaded: ' + @file_name;
    RETURN;
END

PRINT 'Loading: ' + @file_name;

-- ── Step 3: Insert rows from the JSON file ───────────────────
DECLARE @sql NVARCHAR(MAX) = N'
INSERT INTO bronze.linear_issues
    (id, number, identifier, title, description,
     created_at, updated_at, archived_at, completed_at,
     canceled_at, started_at, due_date,
     priority, estimate, trashed,
     state_id, state_name, state_type,
     assignee_id, assignee_name, assignee_email,
     project_id, project_name,
     team_id, team_name,
     parent_id, parent_identifier,
     cycle_id, cycle_name, cycle_starts_at, cycle_ends_at,
     labels,
     _snapshot_file)
SELECT
    -- Core scalar fields
         JSON_VALUE(value, ''$.id'')                    AS id,
    CAST(JSON_VALUE(value, ''$.number'')    AS INT)     AS number,
         JSON_VALUE(value, ''$.identifier'')            AS identifier,
         JSON_VALUE(value, ''$.title'')                 AS title,
         JSON_VALUE(value, ''$.description'')           AS description,

    -- Timestamps — stored as raw ISO 8601 strings (converted in silver)
         JSON_VALUE(value, ''$.createdAt'')             AS created_at,
         JSON_VALUE(value, ''$.updatedAt'')             AS updated_at,
         JSON_VALUE(value, ''$.archivedAt'')            AS archived_at,
         JSON_VALUE(value, ''$.completedAt'')           AS completed_at,
         JSON_VALUE(value, ''$.canceledAt'')            AS canceled_at,
         JSON_VALUE(value, ''$.startedAt'')             AS started_at,
         JSON_VALUE(value, ''$.dueDate'')               AS due_date,

    -- Scalar fields
    CAST(JSON_VALUE(value, ''$.priority'')  AS TINYINT) AS priority,
    CAST(JSON_VALUE(value, ''$.estimate'')  AS FLOAT)   AS estimate,
    CAST(JSON_VALUE(value, ''$.trashed'')   AS BIT)     AS trashed,

    -- state{} — nested object, accessed with dot notation
    -- JSON_VALUE returns NULL automatically if the object is null
         JSON_VALUE(value, ''$.state.id'')              AS state_id,
         JSON_VALUE(value, ''$.state.name'')            AS state_name,
         JSON_VALUE(value, ''$.state.type'')            AS state_type,

    -- assignee{} — nullable (unassigned issues return null here)
         JSON_VALUE(value, ''$.assignee.id'')           AS assignee_id,
         JSON_VALUE(value, ''$.assignee.name'')         AS assignee_name,
         JSON_VALUE(value, ''$.assignee.email'')        AS assignee_email,

    -- project{} — nullable
         JSON_VALUE(value, ''$.project.id'')            AS project_id,
         JSON_VALUE(value, ''$.project.name'')          AS project_name,

    -- team{}
         JSON_VALUE(value, ''$.team.id'')               AS team_id,
         JSON_VALUE(value, ''$.team.name'')             AS team_name,

    -- parent{} — nullable (only present on sub-issues)
         JSON_VALUE(value, ''$.parent.id'')             AS parent_id,
         JSON_VALUE(value, ''$.parent.identifier'')     AS parent_identifier,

    -- cycle{} — nullable
         JSON_VALUE(value, ''$.cycle.id'')              AS cycle_id,
         JSON_VALUE(value, ''$.cycle.name'')            AS cycle_name,
         JSON_VALUE(value, ''$.cycle.startsAt'')        AS cycle_starts_at,
         JSON_VALUE(value, ''$.cycle.endsAt'')          AS cycle_ends_at,

    -- labels — stored as {"nodes":[{"name":"Bug"},{"name":"OwlMonitor"}]}
    -- JSON_QUERY extracts the nodes array, then OPENJSON splits it into rows,
    -- and STRING_AGG joins the names back as a pipe-separated string.
    -- Result: NULL if no labels, or e.g. ''Bug|OwlMonitor''.
    (
        SELECT STRING_AGG(JSON_VALUE(lbl.value, ''$.name''), ''|'')
        FROM OPENJSON(JSON_QUERY(value, ''$.labels.nodes'')) AS lbl
    )                                                       AS labels,

    ''' + @file_name + N'''                               AS _snapshot_file

FROM OPENROWSET(
    BULK ''' + @file_path + N''',
    SINGLE_CLOB
) AS raw_file
CROSS APPLY OPENJSON(raw_file.BulkColumn);
';

EXEC sp_executesql @sql;

-- ── Step 4: Count and log ────────────────────────────────────
DECLARE @rows INT = (
    SELECT COUNT(*)
    FROM bronze.linear_issues
    WHERE _snapshot_file = @file_name
);

INSERT INTO bronze.import_log (source, file_name, row_count)
VALUES ('linear', @file_name, @rows);

PRINT 'Done — inserted ' + CAST(@rows AS NVARCHAR(10)) + ' rows from ' + @file_name;
GO
