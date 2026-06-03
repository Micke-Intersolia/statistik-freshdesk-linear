TRUNCATE TABLE Bronze.LinearIssues;

INSERT INTO Bronze.LinearIssues (
    id,
    number,
    identifier,
    title,
    description,
    createdAt,
    updatedAt,
    archivedAt,
    priority,
    estimate,
    trashed,
    state_id,
    state_name,
    state_type,
    assignee_id,
    assignee_name,
    assignee_email,
    project_id,
    project_name,
    team_id,
    team_name,
    labels
)
SELECT
    JSON_VALUE(value, '$.id'),
    JSON_VALUE(value, '$.number'),
    JSON_VALUE(value, '$.identifier'),
    JSON_VALUE(value, '$.title'),
    JSON_VALUE(value, '$.description'),
    JSON_VALUE(value, '$.createdAt'),
    JSON_VALUE(value, '$.updatedAt'),
    JSON_VALUE(value, '$.archivedAt'),
    JSON_VALUE(value, '$.priority'),
    JSON_VALUE(value, '$.estimate'),
    JSON_VALUE(value, '$.trashed'),
    JSON_VALUE(value, '$.state_id'),
    JSON_VALUE(value, '$.state_name'),
    JSON_VALUE(value, '$.state_type'),
    JSON_VALUE(value, '$.assignee_id'),
    JSON_VALUE(value, '$.assignee_name'),
    JSON_VALUE(value, '$.assignee_email'),
    JSON_VALUE(value, '$.project_id'),
    JSON_VALUE(value, '$.project_name'),
    JSON_VALUE(value, '$.team_id'),
    JSON_VALUE(value, '$.team_name'),
    JSON_QUERY(value, '$.labels')
FROM OPENROWSET(
    BULK 'C:\Users\michael.brostrom\Documents\GitHub\statistik-freshdesk-linear\raw\linear_2025-01-01-2026-06-01.json',
    SINGLE_CLOB
) AS raw
CROSS APPLY OPENJSON(raw.BulkColumn);
