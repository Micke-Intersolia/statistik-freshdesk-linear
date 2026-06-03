-- Skapa dimensioner och tabeller, fyll på data

CREATE TABLE Gold.DimFreshdeskStatus (
    StatusID          INT             NOT NULL PRIMARY KEY,
    StatusName        NVARCHAR(200)   NOT NULL,
    StatusDescription NVARCHAR(500)   NULL,
    KPIStatusGroup    NVARCHAR(50)    NULL
);
GO

INSERT INTO Gold.DimFreshdeskStatus (StatusID, StatusName, StatusDescription)
VALUES
(2, 'Open', 'Ticket is in progress'),
(3, 'Pending', 'Awaiting your answer'),
(4, 'Resolved', 'Ticket is resolved'),
(5, 'Closed', 'This ticket is closed'),
(10, 'Information needed (internal)', 'Ticket is waiting for internal info'),
(24, 'Customer responded', 'Customer Responded'),
(17, 'New case', 'Ticket is waiting for technical support'),
(6, 'Available', 'Ticket is waiting for technical support'),
(12, 'Investigate', 'Ticket is waiting for technical support'),
(8, 'In progress', 'Ticket is in progress'),
(9, 'In testing', 'Ticket is in testing'),
(7, 'Escalation', 'Ticket is escalated'),
(25, 'Task in backlog', 'Ticket is under review for future changes'),
(19, 'Need sprint planning', 'Ticket is under review for future changes'),
(14, 'Ready for hotfix', 'Ticket is ready for hotfix'),
(27, 'Product feedback', 'Product feedback'),
(16, 'Task done', 'Ticket is in progress'),
(26, 'Uninstall', 'Ticket is in progress'),
(23, 'Linked ticket awaiting SLS', 'Ticket is waiting for technical support'),
(9000, 'Assigned to AI Agent', 'Assigned to AI Agent');
GO

CREATE TABLE Gold.DimPerson (
    PersonID     UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,   -- AssigneeID från Linear
    PersonName   NVARCHAR(200)    NOT NULL
);
GO

INSERT INTO Gold.DimPerson (PersonID, PersonName)
SELECT DISTINCT
    AssigneeID,
    AssigneeName
FROM Silver.LinearIssues
WHERE AssigneeID IS NOT NULL;
GO


CREATE TABLE Gold.FactFreshdeskTickets (
    TicketID        BIGINT        NOT NULL,
    DateKeyCreated  INT           NOT NULL,
    DateKeyUpdated  INT           NULL,
    StatusID        INT           NOT NULL,
    IsEscalated     BIT           NOT NULL,
    SnapshotTS      DATETIME2     NOT NULL,
    CONSTRAINT PK_FactFreshdeskTickets PRIMARY KEY (TicketID, SnapshotTS),
    CONSTRAINT FK_FactFreshdeskTickets_DateCreated FOREIGN KEY (DateKeyCreated) REFERENCES Gold.DimDate(DateKey),
    CONSTRAINT FK_FactFreshdeskTickets_DateUpdated FOREIGN KEY (DateKeyUpdated) REFERENCES Gold.DimDate(DateKey),
    CONSTRAINT FK_FactFreshdeskTickets_Status FOREIGN KEY (StatusID) REFERENCES Gold.DimFreshdeskStatus(StatusID)
);
GO

INSERT INTO Gold.FactFreshdeskTickets (
    TicketID,
    DateKeyCreated,
    DateKeyUpdated,
    StatusID,
    IsEscalated,
    SnapshotTS
)
SELECT
    TicketID,
    YEAR(CreatedAt)*10000 + MONTH(CreatedAt)*100 + DAY(CreatedAt),
    CASE WHEN UpdatedAt IS NULL THEN NULL
         ELSE YEAR(UpdatedAt)*10000 + MONTH(UpdatedAt)*100 + DAY(UpdatedAt)
    END,
    Status,
    IsEscalated,
    SnapshotTS
FROM Silver.FreshdeskTickets;
GO

-- Skapa tabellen
CREATE TABLE Gold.FactLinearIssues (
    IssueID         UNIQUEIDENTIFIER NOT NULL,
    DateKeyCreated  INT              NOT NULL,
    DateKeyUpdated  INT              NULL,
    StateType       NVARCHAR(50)     NOT NULL,
    StateName       NVARCHAR(200)    NOT NULL,
    AssigneeID      UNIQUEIDENTIFIER NULL,
    SnapshotTS      DATETIME2        NOT NULL,
    CONSTRAINT PK_FactLinearIssues PRIMARY KEY (IssueID, SnapshotTS),
    CONSTRAINT FK_FactLinearIssues_DateCreated FOREIGN KEY (DateKeyCreated) REFERENCES Gold.DimDate(DateKey),
    CONSTRAINT FK_FactLinearIssues_DateUpdated FOREIGN KEY (DateKeyUpdated) REFERENCES Gold.DimDate(DateKey),
    CONSTRAINT FK_FactLinearIssues_Assignee FOREIGN KEY (AssigneeID) REFERENCES Gold.DimPerson(PersonID)
);
GO

-- Fyll tabellen
INSERT INTO Gold.FactLinearIssues (
    IssueID,
    DateKeyCreated,
    DateKeyUpdated,
    StateType,
    StateName,
    AssigneeID,
    SnapshotTS
)
SELECT
    IssueID,
    YEAR(CreatedAt)*10000 + MONTH(CreatedAt)*100 + DAY(CreatedAt),
    CASE WHEN UpdatedAt IS NULL THEN NULL
         ELSE YEAR(UpdatedAt)*10000 + MONTH(UpdatedAt)*100 + DAY(UpdatedAt)
    END,
    StateType,
    StateName,
    AssigneeID,
    SnapshotTS
FROM Silver.LinearIssues;
GO
