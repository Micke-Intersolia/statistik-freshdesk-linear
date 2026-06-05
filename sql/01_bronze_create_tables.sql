-- ============================================================
-- 01_bronze_create_tables.sql
-- Creates the three bronze-layer tables in InternalStatistics.
--
-- Run this once when setting up the database on a new server.
-- It will fail gracefully if the tables already exist (due to
-- the IF NOT EXISTS guards) so it is safe to re-run.
--
-- Tables created:
--   bronze.import_log          — tracks which JSON files have been loaded
--   bronze.freshdesk_tickets   — raw Freshdesk ticket data
--   bronze.linear_issues       — raw Linear issue data
--
-- Design decisions:
--   • _row_id    : surrogate IDENTITY key — each row is unique even
--                  when the same ticket/issue appears in multiple snapshots.
--   • _snapshot_file: records which JSON file the row came from,
--                  so data can be traced back to its source file.
--   • _loaded_at : UTC timestamp of when the row was inserted.
--   • Date fields are stored as NVARCHAR(50) in the bronze layer,
--                  preserving the raw ISO 8601 string from the API
--                  (e.g. '2026-06-04T11:14:51.968Z'). Conversion to
--                  proper SQL date types happens in the silver layer.
--   • All text columns use NVARCHAR (Unicode) to safely store
--                  Swedish characters (å, ä, ö) and any other Unicode content.
-- ============================================================

USE InternalStatistics;
GO


-- ── import_log ───────────────────────────────────────────────
-- One row per JSON file that has been successfully loaded.
-- The UNIQUE constraint on file_name is the idempotency guard:
-- trying to load the same file twice will either be caught by
-- the loader script (preferred) or fail here as a safety net.
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'bronze' AND t.name = 'import_log'
)
BEGIN
    CREATE TABLE bronze.import_log (
        import_id       INT             NOT NULL IDENTITY(1,1),
        source          NVARCHAR(20)    NOT NULL,   -- 'freshdesk' or 'linear'
        file_name       NVARCHAR(260)   NOT NULL,   -- filename only, not full path
        row_count       INT             NOT NULL,   -- rows inserted from this file
        imported_at     DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_bronze_import_log      PRIMARY KEY (import_id),
        CONSTRAINT UQ_bronze_import_log_file UNIQUE (file_name)
    );
    PRINT 'Created: bronze.import_log';
END
ELSE
    PRINT 'Already exists: bronze.import_log';
GO


-- ── freshdesk_tickets ────────────────────────────────────────
-- Append-style table: one row per ticket per snapshot file.
-- The same ticket ID will appear multiple times if it has been
-- included in several daily snapshots — this is intentional.
-- The silver layer handles deduplication and picks the latest version.
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'bronze' AND t.name = 'freshdesk_tickets'
)
BEGIN
    CREATE TABLE bronze.freshdesk_tickets (
        -- Surrogate key — uniquely identifies this row in this table
        _row_id         INT             NOT NULL IDENTITY(1,1),

        -- Source fields — 9 agreed fields from the Freshdesk API
        id              INT             NOT NULL,           -- Freshdesk ticket ID
        subject         NVARCHAR(1000)  NULL,               -- ticket title
        status          TINYINT         NULL,               -- 2=Open 3=Pending 4=Resolved 5=Closed
        priority        TINYINT         NULL,               -- 1=Low 2=Medium 3=High 4=Urgent
        created_at      NVARCHAR(50)    NULL,               -- ISO 8601 UTC string
        updated_at      NVARCHAR(50)    NULL,               -- ISO 8601 UTC string
        due_by          NVARCHAR(50)    NULL,               -- ISO 8601 UTC string, nullable
        group_id        BIGINT          NULL,               -- support group (BIGINT: Freshdesk IDs exceed INT range)
        product_id      BIGINT          NULL,               -- product/portal (BIGINT: same reason)

        -- Audit / loader metadata
        _snapshot_file  NVARCHAR(260)   NOT NULL,           -- filename this row came from
        _loaded_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_bronze_freshdesk_tickets PRIMARY KEY (_row_id)
    );
    PRINT 'Created: bronze.freshdesk_tickets';
END
ELSE
    PRINT 'Already exists: bronze.freshdesk_tickets';
GO


-- ── linear_issues ────────────────────────────────────────────
-- Append-style table: one row per issue per snapshot file.
-- Nested JSON objects (state, assignee, project, team, parent, cycle)
-- are flattened into individual columns here — e.g. state.id → state_id.
-- Labels (an array) are stored as a pipe-separated string: 'Bug|OwlMonitor'.
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'bronze' AND t.name = 'linear_issues'
)
BEGIN
    CREATE TABLE bronze.linear_issues (
        -- Surrogate key
        _row_id             INT             NOT NULL IDENTITY(1,1),

        -- Core fields
        id                  NVARCHAR(50)    NOT NULL,   -- Linear UUID, e.g. 'b159b5fe-bd24-...'
        number              INT             NULL,        -- sequential issue number
        identifier          NVARCHAR(50)    NULL,        -- human-readable ID, e.g. 'OPEX-927'
        title               NVARCHAR(1000)  NULL,
        description         NVARCHAR(MAX)   NULL,        -- markdown text, can be long

        -- Timestamps (ISO 8601 strings — converted to dates in silver)
        created_at          NVARCHAR(50)    NULL,
        updated_at          NVARCHAR(50)    NULL,
        archived_at         NVARCHAR(50)    NULL,
        completed_at        NVARCHAR(50)    NULL,
        canceled_at         NVARCHAR(50)    NULL,
        started_at          NVARCHAR(50)    NULL,
        due_date            NVARCHAR(50)    NULL,        -- date only, e.g. '2026-07-01'

        -- Scalar fields
        priority            TINYINT         NULL,        -- 0=None 1=Urgent 2=High 3=Medium 4=Low
        estimate            FLOAT           NULL,        -- story point estimate, nullable
        trashed             BIT             NULL,        -- soft-deleted issues

        -- state{} flattened
        state_id            NVARCHAR(50)    NULL,
        state_name          NVARCHAR(200)   NULL,        -- e.g. 'In Progress', 'Done'
        state_type          NVARCHAR(50)    NULL,        -- e.g. 'started', 'completed', 'cancelled'

        -- assignee{} flattened — nullable (unassigned issues)
        assignee_id         NVARCHAR(50)    NULL,
        assignee_name       NVARCHAR(200)   NULL,
        assignee_email      NVARCHAR(200)   NULL,

        -- project{} flattened — nullable
        project_id          NVARCHAR(50)    NULL,
        project_name        NVARCHAR(200)   NULL,

        -- team{} flattened
        team_id             NVARCHAR(50)    NULL,
        team_name           NVARCHAR(200)   NULL,

        -- parent{} flattened — nullable (sub-issues only)
        parent_id           NVARCHAR(50)    NULL,
        parent_identifier   NVARCHAR(50)    NULL,

        -- cycle{} flattened — nullable
        cycle_id            NVARCHAR(50)    NULL,
        cycle_name          NVARCHAR(200)   NULL,
        cycle_starts_at     NVARCHAR(50)    NULL,
        cycle_ends_at       NVARCHAR(50)    NULL,

        -- labels — array of names stored pipe-separated, e.g. 'Bug|OwlMonitor'
        labels              NVARCHAR(1000)  NULL,

        -- Audit / loader metadata
        _snapshot_file      NVARCHAR(260)   NOT NULL,
        _loaded_at          DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_bronze_linear_issues PRIMARY KEY (_row_id)
    );
    PRINT 'Created: bronze.linear_issues';
END
ELSE
    PRINT 'Already exists: bronze.linear_issues';
GO
