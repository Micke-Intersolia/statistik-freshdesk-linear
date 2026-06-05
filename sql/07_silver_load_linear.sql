-- ============================================================
-- 07_silver_load_linear.sql
-- Bygger om silver.linear_issues från bronze.linear_issues.
--
-- Kör manuellt efter varje bronsladdning, eller schemalagt via
-- ett framtida automatiseringsjobb.
-- Säker att köra om — TRUNCATE + full rebuild är idempotent.
--
-- Vad scriptet gör:
--   1. Trunkerar silver-tabellen
--   2. Filtrerar bort issues där identifier LIKE 'DEV%'
--      OCH team_name = 'Development' (båda villkor krävs)
--   3. Deduplicerar — en rad per issue-id (senaste updated_at vinner)
--   4. Konverterar datum-strängar (ISO 8601) till DATE
--   5. Beräknar closed_at = COALESCE(completed_at, canceled_at)
--   6. Beräknar is_incident från labels-strängen
-- ============================================================

USE InternalStatistics;
GO

BEGIN TRANSACTION;
BEGIN TRY

    -- ── Steg 1: Rensa silverlagret ───────────────────────────
    TRUNCATE TABLE silver.linear_issues;

    -- ── Steg 2–6: Bygg upp från bronslagret ─────────────────
    ;WITH ranked AS (
        -- Rangordnar varje version av ett issue:
        --   rn = 1  →  senaste versionen (den som hamnar i silver)
        --
        -- Primär sortering:  updated_at DESC (ISO 8601 UTC-sträng,
        --   lexikografisk = kronologisk ordning)
        -- Sekundär sortering: _row_id DESC — tiebreaker vid lika updated_at
        --
        -- Filter: exkluderar issues där BÅDE identifier börjar på 'DEV'
        --   OCH team_name är 'Development'.
        --   Issues med DEV-prefix i andra team, eller Development-issues
        --   utan DEV-prefix, inkluderas.
        SELECT
            id,
            state_name,
            state_type,
            priority,
            created_at,
            started_at,
            completed_at,
            canceled_at,
            project_name,
            assignee_name,
            labels,
            trashed,
            ROW_NUMBER() OVER (
                PARTITION BY id
                ORDER BY updated_at DESC, _row_id DESC
            ) AS rn
        FROM bronze.linear_issues
        WHERE NOT (
            identifier  LIKE 'DEV%'
            AND team_name = 'Development'
        )
    )

    INSERT INTO silver.linear_issues
        (id, state_name, state_type, priority,
         created_at, started_at, completed_at, closed_at,
         project_name, assignee_name, labels, trashed, is_incident)
    SELECT
        id,
        state_name,
        state_type,
        priority,

        -- ISO 8601-strängar → DATE.
        -- LEFT(..., 10) extraherar "YYYY-MM-DD".
        -- TRY_CAST returnerar NULL vid ogiltigt värde.
        TRY_CAST(LEFT(created_at,   10) AS DATE) AS created_at,
        TRY_CAST(LEFT(started_at,   10) AS DATE) AS started_at,
        TRY_CAST(LEFT(completed_at, 10) AS DATE) AS completed_at,

        -- closed_at täcker alla "klara" issues:
        --   completed_at sätts av Linear för completed-states
        --   canceled_at  sätts av Linear för cancelled/duplicate-states
        --   COALESCE returnerar det första icke-NULL-värdet
        COALESCE(
            TRY_CAST(LEFT(completed_at, 10) AS DATE),
            TRY_CAST(LEFT(canceled_at,  10) AS DATE)
        ) AS closed_at,

        project_name,
        assignee_name,
        labels,
        trashed,

        -- is_incident: 1 om labels-strängen innehåller "incident".
        -- Databasens CI-kollation (SQL_Latin1_General_CP1_CI_AS) gör
        -- sökningen skiftlägesokänslig — "Incident", "incident" och
        -- "INCIDENT" ger alla träff.
        -- NULL labels ger 0 (CASE WHEN NULL LIKE ... → ELSE-grenen).
        CASE WHEN labels LIKE '%incident%' THEN 1 ELSE 0 END AS is_incident

    FROM ranked
    WHERE rn = 1;   -- bara senaste versionen per issue

    -- ── Steg 7: Bekräftelse ──────────────────────────────────
    DECLARE @rows             INT = @@ROWCOUNT;
    DECLARE @started_count    INT = (SELECT COUNT(*) FROM silver.linear_issues WHERE state_type = 'started');
    DECLARE @completed_count  INT = (SELECT COUNT(*) FROM silver.linear_issues WHERE state_type = 'completed');
    DECLARE @cancelled_count  INT = (SELECT COUNT(*) FROM silver.linear_issues WHERE state_type = 'cancelled');
    DECLARE @incident_count   INT = (SELECT COUNT(*) FROM silver.linear_issues WHERE is_incident = 1);

    COMMIT TRANSACTION;

    PRINT 'Klart.';
    PRINT '  Totalt laddade rader  : ' + CAST(@rows            AS NVARCHAR(10));
    PRINT '  Aktuellt started      : ' + CAST(@started_count   AS NVARCHAR(10));
    PRINT '  Aktuellt completed    : ' + CAST(@completed_count AS NVARCHAR(10));
    PRINT '  Aktuellt cancelled    : ' + CAST(@cancelled_count AS NVARCHAR(10));
    PRINT '  Varav is_incident     : ' + CAST(@incident_count  AS NVARCHAR(10));

END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    PRINT 'FEL — transaktionen återrullades.';
    PRINT ERROR_MESSAGE();
    THROW;
END CATCH;
GO
