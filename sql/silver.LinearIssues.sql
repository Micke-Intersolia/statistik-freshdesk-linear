-- 1. Skapa om tabellen
CREATE TABLE Silver.LinearIssues (
    IssueID        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    CreatedAt      DATETIME2        NOT NULL,
    UpdatedAt      DATETIME2        NULL,
    StateType      NVARCHAR(50)     NOT NULL,
    StateName      NVARCHAR(200)    NULL,
    AssigneeID     UNIQUEIDENTIFIER NULL,
    AssigneeName   NVARCHAR(200)    NULL,
    SnapshotTS     DATETIME2        NOT NULL
);
GO

-- 2. Fyll tabellen från Bronze
INSERT INTO Silver.LinearIssues (
    IssueID,
    CreatedAt,
    UpdatedAt,
    StateType,
    StateName,
    AssigneeID,
    AssigneeName,
    SnapshotTS
)
SELECT
    id,
    createdAt,
    updatedAt,
    state_type,
    state_name,
    assignee_id,
    assignee_name,
    snapshot_ts
FROM Bronze.LinearIssues;
GO
