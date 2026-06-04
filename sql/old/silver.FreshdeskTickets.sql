CREATE TABLE Silver.FreshdeskTickets (
    TicketID        BIGINT         NOT NULL PRIMARY KEY,
    CreatedAt       DATETIME2      NOT NULL,
    UpdatedAt       DATETIME2      NULL,
    Status          INT            NOT NULL,
    IsEscalated     BIT            NOT NULL,
    SnapshotTS      DATETIME2      NOT NULL
);
GO

INSERT INTO Silver.FreshdeskTickets (
    TicketID,
    CreatedAt,
    UpdatedAt,
    Status,
    IsEscalated,
    SnapshotTS
)
SELECT
    id,
    created_at,
    updated_at,
    status,
    is_escalated,
    snapshot_ts
FROM Bronze.FreshdeskTickets;
