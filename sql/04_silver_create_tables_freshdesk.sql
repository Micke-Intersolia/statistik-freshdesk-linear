-- ============================================================
-- 04_silver_create_tables_freshdesk.sql
-- Skapar silver.freshdesk_tickets i InternalStatistics.
--
-- Kör en gång vid setup. Säker att köra om — IF NOT EXISTS-
-- skyddet gör att befintlig tabell inte påverkas.
--
-- Silverlagret innehåller EN rad per ticket (senaste status).
-- Skillnader mot bronslagret:
--   • Filtrerat      — tickets med group_id slutande på 1939/8846 är borta
--   • Deduplicerat   — bara senaste versionen per ticket-id
--   • Datum          — ISO 8601-strängar konverterade till DATE (tid skrubbad)
--   • Rensat         — subject, priority, due_by, group_id ingår inte
--   • Berikat        — fyra härledda kolumner beräknade från bronshistoriken
--
-- Härledda kolumner (beräknade ur bronze append-historiken):
--   denied_triage    — flagga: ticketen HAR haft status 6/7/12 och sedan 17
--   first_waiting_at — datum då ticketen FÖRSTA GÅNGEN fick status 17
--   first_passed_at  — datum då ticketen FÖRSTA GÅNGEN fick status 6, 7 eller 12
--   denied_triage_at — datum då ticketen SENAST återfick status 17 (efter godkänd triage)
--
-- Status-mappning:
--   17         = Waiting for triage  (supporten sätter)
--   6, 7, 12   = Passed triage        (beslutat av OPEX-mötet)
--   2, 3, 4, 5 = Open, Pending, Resolved, Closed
-- ============================================================

USE InternalStatistics;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'silver' AND t.name = 'freshdesk_tickets'
)
BEGIN
    CREATE TABLE silver.freshdesk_tickets (

        -- Primärnyckel — ett ticket, en rad
        id                  INT         NOT NULL,

        -- Aktuell status som Freshdeskens statuskod (siffra).
        -- 17 = Waiting for triage | 6,7,12 = Passed triage | övriga = andra tillstånd
        status              TINYINT     NOT NULL,

        -- Datum då ticket skapades — volymstatistik per vecka/månad
        created_at          DATE        NULL,

        -- Datum för senaste uppdatering i Freshdesk
        updated_at          DATE        NULL,

        -- Produkt/portal-ID — med tills vidare för produktanalys
        product_id          BIGINT      NULL,

        -- ── Härledda statusdatum ─────────────────────────────────────────
        -- Dessa beräknas ur bronslagrets append-historik.
        -- Möjliggör tidsbaserad rapportering per fas, t.ex.
        -- "hur många tickets passerades i OPEX-mötet den här veckan?"
        --
        -- Notera: datumen är approximationer baserade på updated_at i de
        -- bronze-rader där statusen observerades — inte exakta tidsstämplar
        -- för Freshdesk-händelsen, men tillräckligt precisa för daglig/veckovis
        -- rapportering med nattliga snapshots.

        -- Datum då ticketen FÖRSTA GÅNGEN observerades med status 17.
        -- NULL om ingen rad med status 17 finns i bronshistoriken.
        first_waiting_at    DATE        NULL,

        -- Datum då ticketen FÖRSTA GÅNGEN observerades med status 6, 7 eller 12.
        -- NULL om ticketen aldrig passerat triage.
        first_passed_at     DATE        NULL,

        -- Denied triage-flagga (snabbfilter).
        -- 1 om ticketen NÅGON GÅNG haft status 6/7/12 och sedan återfått 17.
        -- Permanent — nollställs inte om ticketen ändrar status igen.
        denied_triage       BIT         NOT NULL DEFAULT 0,

        -- Datum då ticketen FÖRSTA GÅNGEN återfick status 17 efter en 6/7/12.
        -- NULL om denied_triage = 0.
        denied_triage_at    DATE        NULL,

        -- Audit — när raden senast laddades in i silverlagret
        _loaded_at          DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_silver_freshdesk_tickets PRIMARY KEY (id)
    );
    PRINT 'Skapade: silver.freshdesk_tickets';
END
ELSE
    PRINT 'Finns redan: silver.freshdesk_tickets';
GO
