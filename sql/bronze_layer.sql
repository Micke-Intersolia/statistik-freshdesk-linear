-- Import log — tracks which files have been loaded, prevents double imports
CREATE TABLE bronze.import_log (
    import_id       INT             NOT NULL IDENTITY(1,1),
    source          NVARCHAR(20)    NOT NULL,   -- 'freshdesk' or 'linear'
    file_name       NVARCHAR(260)   NOT NULL,
    row_count       INT             NOT NULL,
    imported_at     DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_bronze_import_log  PRIMARY KEY (import_id),
    CONSTRAINT UQ_bronze_import_log_file UNIQUE (file_name)
);

-- Freshdesk tickets — append from nightly snapshots and backfill
CREATE TABLE bronze.freshdesk_tickets (
    _row_id         INT             NOT NULL IDENTITY(1,1),
    id              INT             NOT NULL,
    subject         NVARCHAR(1000)  NULL,
    status          TINYINT         NULL,
    priority        TINYINT         NULL,
    created_at      DATETIMEOFFSET  NULL,
    updated_at      DATETIMEOFFSET  NULL,
    due_by          DATETIMEOFFSET  NULL,
    group_id        BIGINT          NULL,
    product_id      INT             NULL,
    _snapshot_file  NVARCHAR(260)   NOT NULL,
    _loaded_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_bronze_freshdesk_tickets PRIMARY KEY (_row_id)
);

-- Linear issues — append from nightly snapshots and backfill
-- Nested objects flattened; labels stored pipe-separated
CREATE TABLE bronze.linear_issues (
    _row_id             INT             NOT NULL IDENTITY(1,1),
    id                  NVARCHAR(50)    NOT NULL,
    number              INT             NULL,
    identifier          NVARCHAR(50)    NULL,
    title               NVARCHAR(1000)  NULL,
    description         NVARCHAR(MAX)   NULL,
    created_at          DATETIMEOFFSET  NULL,
    updated_at          DATETIMEOFFSET  NULL,
    archived_at         DATETIMEOFFSET  NULL,
    completed_at        DATETIMEOFFSET  NULL,
    canceled_at         DATETIMEOFFSET  NULL,
    started_at          DATETIMEOFFSET  NULL,
    due_date            DATE            NULL,
    priority            TINYINT         NULL,
    estimate            FLOAT           NULL,
    trashed             BIT             NULL,
    state_id            NVARCHAR(50)    NULL,
    state_name          NVARCHAR(200)   NULL,
    state_type          NVARCHAR(50)    NULL,
    assignee_id         NVARCHAR(50)    NULL,
    assignee_name       NVARCHAR(200)   NULL,
    assignee_email      NVARCHAR(200)   NULL,
    project_id          NVARCHAR(50)    NULL,
    project_name        NVARCHAR(200)   NULL,
    team_id             NVARCHAR(50)    NULL,
    team_name           NVARCHAR(200)   NULL,
    parent_id           NVARCHAR(50)    NULL,
    parent_identifier   NVARCHAR(50)    NULL,
    cycle_id            NVARCHAR(50)    NULL,
    cycle_name          NVARCHAR(200)   NULL,
    cycle_starts_at     DATETIMEOFFSET  NULL,
    cycle_ends_at       DATETIMEOFFSET  NULL,
    labels              NVARCHAR(1000)  NULL,
    _snapshot_file      NVARCHAR(260)   NOT NULL,
    _loaded_at          DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_bronze_linear_issues PRIMARY KEY (_row_id)
);