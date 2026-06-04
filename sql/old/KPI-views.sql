/* =========================================================
   FRESHdesk – gemensam basvy med triageklassning
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Freshdesk_TriageBase AS
SELECT
    f.TicketID,
    f.SnapshotTS,
    f.DateKeyCreated,
    f.DateKeyUpdated,
    f.StatusID,
    f.IsEscalated,
    s.StatusName,
    s.StatusDescription,
    CASE
        WHEN f.StatusID IN (17, 6, 23)
            THEN 'WaitingForTriage'      -- 17 New case, 6 Available, 23 Linked ticket awaiting SLS
        WHEN f.StatusID IN (12, 7)
            THEN 'PostTriage'            -- 12 Investigate, 7 Escalation
        ELSE 'Unknown'
    END AS TriageStage
FROM Gold.FactFreshdeskTickets f
JOIN Gold.DimFreshdeskStatus s
    ON f.StatusID = s.StatusID;
GO

/* =========================================================
   FRESHdesk – antal ärenden som väntar på triage (per snapshot)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Freshdesk_TicketsWaitingForTriage AS
SELECT
    SnapshotTS,
    COUNT(*) AS TicketsWaitingForTriage
FROM Gold.vw_Freshdesk_TriageBase
WHERE TriageStage = 'WaitingForTriage'
GROUP BY SnapshotTS;
GO

/* =========================================================
   FRESHdesk – antal ärenden som har genomgått triage (per snapshot)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Freshdesk_TicketsPostTriage AS
SELECT
    SnapshotTS,
    COUNT(*) AS TicketsPostTriage
FROM Gold.vw_Freshdesk_TriageBase
WHERE TriageStage = 'PostTriage'
GROUP BY SnapshotTS;
GO

/* =========================================================
   FRESHdesk – antal eskalerade ärenden (per snapshot)
   (enligt antagande: StatusID = 7 = Escalation)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Freshdesk_TicketsEscalated AS
SELECT
    SnapshotTS,
    COUNT(*) AS TicketsEscalated
FROM Gold.vw_Freshdesk_TriageBase
WHERE StatusID = 7
GROUP BY SnapshotTS;
GO

/* =========================================================
   FRESHdesk – inflöde per dag (påverkas inte av triagelogik)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Freshdesk_TicketsPerDay AS
SELECT
    d.DateValue AS Date,
    COUNT(*) AS TicketsCreated
FROM Gold.FactFreshdeskTickets f
JOIN Gold.DimDate d
    ON f.DateKeyCreated = d.DateKey
GROUP BY d.DateValue;
GO

/* =========================================================
   LINEAR – inflöde per dag
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Linear_IssuesPerDay AS
SELECT
    d.DateValue AS Date,
    COUNT(*) AS IssuesCreated
FROM Gold.FactLinearIssues f
JOIN Gold.DimDate d
    ON f.DateKeyCreated = d.DateKey
GROUP BY d.DateValue;
GO

/* =========================================================
   LINEAR – issues per state (snapshot-baserat)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Linear_IssuesPerState AS
SELECT
    f.SnapshotTS,
    f.StateType,
    f.StateName,
    COUNT(*) AS Issues
FROM Gold.FactLinearIssues f
GROUP BY f.SnapshotTS, f.StateType, f.StateName;
GO

/* =========================================================
   LINEAR – ledtid (Created → Done) i dagar
   (justera StateName = 'Done' vid behov)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Linear_LeadTime AS
SELECT
    f.IssueID,
    f.StateName,
    d1.DateValue AS CreatedDate,
    d2.DateValue AS UpdatedDate,
    DATEDIFF(DAY, d1.DateValue, d2.DateValue) AS LeadTimeDays
FROM Gold.FactLinearIssues f
JOIN Gold.DimDate d1
    ON f.DateKeyCreated = d1.DateKey
JOIN Gold.DimDate d2
    ON f.DateKeyUpdated = d2.DateKey
WHERE f.StateName = 'Done';
GO

/* =========================================================
   LINEAR – personbaserade KPI:er (antal Done per person)
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Linear_PersonKPIs AS
SELECT
    p.PersonName,
    COUNT(*) AS IssuesDone
FROM Gold.FactLinearIssues f
JOIN Gold.DimPerson p
    ON f.AssigneeID = p.PersonID
WHERE f.StateName = 'Done'
GROUP BY p.PersonName;
GO

/* =========================================================
   LINEAR – backlog-hälsa (enkel variant, state_type antas)
   Justera listan ('backlog','unstarted', ...) efter verklig logik.
   ========================================================= */
CREATE OR ALTER VIEW Gold.vw_Linear_BacklogHealth AS
SELECT
    f.SnapshotTS,
    COUNT(*) AS IssuesInBacklog
FROM Gold.FactLinearIssues f
WHERE f.StateType IN ('backlog', 'unstarted')
GROUP BY f.SnapshotTS;
GO
