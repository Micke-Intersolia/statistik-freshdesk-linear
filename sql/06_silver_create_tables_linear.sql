-- ============================================================
-- 06_silver_create_tables_linear.sql
-- Skapar silver.linear_issues i OPEX_statistics.
--
-- Kör en gång vid setup. Säker att köra om — IF NOT EXISTS-
-- skyddet gör att befintlig tabell inte påverkas.
--
-- Silverlagret innehåller EN rad per issue (senaste status).
-- Skillnader mot bronslagret:
--   • Filtrerat    — issues med identifier LIKE 'DEV%' OCH
--                   team_name = 'Development' är borta
--   • Deduplicerat — bara senaste versionen per issue-id
--   • Datum        — ISO 8601-strängar konverterade till DATE
--   • Rensat       — identifier, team, assignee-id m.fl. ingår inte
--   • Berikat      — closed_at och is_incident härledda
--
-- Tre nyckeldat för flödesanalys:
--   created_at   — issue skapad (unstarted)
--   started_at   — issue påbörjad/tilldelad
--   closed_at    — issue klar (completed ELLER cancelled/duplicate)
--
-- closed_at vs completed_at:
--   completed_at = Linears egna fält, sätts bara vid "completed"-states
--   closed_at    = COALESCE(completed_at, canceled_at) — täcker alla klara
--   Båda finns i silver för verifiering; gold väljer vilken som exponeras.
--
-- state_type-värden från Linear:
--   backlog | unstarted | started | completed | cancelled
--   (backlog och unstarted är sannolikt ekvivalenta — utreds i gold)
-- ============================================================

USE OPEX_statistics;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'silver' AND t.name = 'linear_issues'
)
BEGIN
    CREATE TABLE silver.linear_issues (

        -- Primärnyckel — ett issue, en rad (Linear-ID är GUID-sträng)
        id              NVARCHAR(50)    NOT NULL,

        -- Aktuell status som fritext och kategori
        state_name      NVARCHAR(100)   NULL,
        state_type      NVARCHAR(50)    NULL,   -- backlog/unstarted/started/completed/cancelled

        -- Prioritet som Linears sifferkod
        -- 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low
        priority        TINYINT         NULL,

        -- ── Tre nyckeldat för flödesanalys ──────────────────────────────
        -- created_at: när issuen skapades
        created_at      DATE            NULL,

        -- started_at: när arbetet påbörjades (Linears startedAt-fält)
        -- NULL om issuen aldrig startats
        started_at      DATE            NULL,

        -- completed_at: Linears egna fält — sätts bara för "completed"-states.
        -- Finns för verifiering mot closed_at.
        completed_at    DATE            NULL,

        -- closed_at: COALESCE(completed_at, canceled_at).
        -- Täcker completed + cancelled + duplicate (alla "klara" typer).
        closed_at       DATE            NULL,

        -- ── Dimensioner ─────────────────────────────────────────────────
        project_name    NVARCHAR(200)   NULL,
        assignee_name   NVARCHAR(200)   NULL,

        -- Labels pipe-separerade, t.ex. "Bug|Incident|Feature"
        -- Används bl.a. för is_incident-flaggan nedan
        labels          NVARCHAR(500)   NULL,

        -- Trashed-flagga (raderade issues) — behålls för analys
        trashed         BIT             NULL,

        -- ── Härledda flaggor ─────────────────────────────────────────────
        -- is_incident: 1 om labels innehåller strängen "incident"
        -- Skiftlägesokänsligt tack vare databasens CI-kollation.
        -- Hanterar varianter som "Incident", "incident", "INCIDENT".
        is_incident     BIT             NOT NULL DEFAULT 0,

        -- Audit — när raden senast laddades in i silverlagret
        _loaded_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_silver_linear_issues PRIMARY KEY (id)
    );
    PRINT 'Skapade: silver.linear_issues';
END
ELSE
    PRINT 'Finns redan: silver.linear_issues';
GO
