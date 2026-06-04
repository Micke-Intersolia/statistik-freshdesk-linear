-- ============================================================
-- 05_silver_load_freshdesk.sql
-- Bygger om silver.freshdesk_tickets från bronze.freshdesk_tickets.
--
-- Kör manuellt efter varje bronsladdning, eller schemalagt via
-- ett framtida automatiseringsjobb.
-- Säker att köra om — TRUNCATE + full rebuild är idempotent.
--
-- Vad scriptet gör:
--   1. Trunkerar silver-tabellen
--   2. Filtrerar bort tickets med group_id slutande på 1939 eller 8846
--   3. Deduplicerar — en rad per ticket_id (senaste updated_at vinner)
--   4. Konverterar datum-strängar (ISO 8601) till DATE (tid skrubbas)
--   5. Beräknar fyra härledda kolumner ur bronshistoriken:
--        first_waiting_at  — första gången ticketen hade status 17
--        first_passed_at   — första gången ticketen hade status 6/7/12
--        denied_triage     — flagga: haft 6/7/12 och sedan 17 igen
--        denied_triage_at  — datum för den regressionen
--
-- Status-mappning:
--   17         = Waiting for triage  (supporten sätter)
--   6, 7, 12   = Passed triage        (beslutat av OPEX-mötet)
--   2, 3, 4, 5 = Open, Pending, Resolved, Closed
-- ============================================================

USE OPEX_statistics;
GO

BEGIN TRANSACTION;
BEGIN TRY

    -- ── Steg 1: Rensa silverlagret ───────────────────────────
    --
    -- TRUNCATE är snabbare än DELETE och nollställer identity-räknare.
    -- Hela tabellen byggs om från brons vid varje körning — idempotent.
    TRUNCATE TABLE silver.freshdesk_tickets;

    -- ── Steg 2–5: Bygg upp från bronslagret ─────────────────
    ;WITH ranked AS (
        -- Rangordnar varje version (rad) av en ticket:
        --   rn = 1  →  senaste versionen (den som hamnar i silver)
        --
        -- Primär sortering:  updated_at DESC (ISO 8601-sträng,
        --   lexikografisk ordning = kronologisk för UTC-stämplar)
        -- Sekundär sortering: _row_id DESC — tiebreaker om updated_at är identisk
        --
        -- Filter: tickets med group_id vars fyra sista siffror är 1939
        -- eller 8846 exkluderas. NULL group_id inkluderas.
        SELECT
            id,
            status,
            created_at,
            updated_at,
            product_id,
            ROW_NUMBER() OVER (
                PARTITION BY id
                ORDER BY updated_at DESC, _row_id DESC
            ) AS rn
        FROM bronze.freshdesk_tickets
        WHERE
            group_id IS NULL
            OR RIGHT(CAST(group_id AS VARCHAR(20)), 4) NOT IN ('1939', '8846')
    ),

    first_waiting AS (
        -- Datum då ticketen FÖRSTA GÅNGEN observerades med status 17.
        -- MIN(updated_at) är den äldsta bronspunkten med status 17 —
        -- en tillräckligt bra approximation av när ticketen kom in i triagekön.
        SELECT id, MIN(updated_at) AS first_waiting_at
        FROM bronze.freshdesk_tickets
        WHERE status = 17
        GROUP BY id
    ),

    first_passed AS (
        -- Datum då ticketen FÖRSTA GÅNGEN observerades med status 6, 7 eller 12.
        -- Approximation av när OPEX-mötet beslutade att godkänna ticketen.
        SELECT id, MIN(updated_at) AS first_passed_at
        FROM bronze.freshdesk_tickets
        WHERE status IN (6, 7, 12)
        GROUP BY id
    ),

    denied AS (
        -- Hittar tickets som kvalificerar som "denied triage" och beräknar
        -- datumet för regressionen.
        --
        -- En ticket är denied_triage om:
        --   • Den HAR haft status 17 (waiting) vid tidpunkt T2
        --   • OCH det finns en rad med status 6, 7 eller 12 vid T1 < T2
        --     (dvs. ticketen hade PASSAT triage INNAN den återvände till waiting)
        --
        -- MIN(b_wait.updated_at) ger det FÖRSTA tillfälle regressionen inträffade.
        -- Jämförelse av ISO 8601 UTC-strängar är lexikografiskt korrekt.
        SELECT b_wait.id, MIN(b_wait.updated_at) AS denied_triage_at
        FROM bronze.freshdesk_tickets b_wait
        WHERE
            b_wait.status = 17
            AND EXISTS (
                SELECT 1
                FROM bronze.freshdesk_tickets b_pass
                WHERE b_pass.id         = b_wait.id
                  AND b_pass.status     IN (6, 7, 12)
                  AND b_pass.updated_at < b_wait.updated_at
            )
        GROUP BY b_wait.id
    )

    INSERT INTO silver.freshdesk_tickets
        (id, status, created_at, updated_at, product_id,
         first_waiting_at, first_passed_at,
         denied_triage, denied_triage_at)
    SELECT
        r.id,

        r.status,

        -- ISO 8601-sträng → DATE.
        -- LEFT(..., 10) extraherar "YYYY-MM-DD" ur t.ex. "2026-06-04T11:14:51.968Z".
        -- TRY_CAST returnerar NULL vid ogiltigt värde i stället för att krascha.
        TRY_CAST(LEFT(r.created_at,        10) AS DATE) AS created_at,
        TRY_CAST(LEFT(r.updated_at,        10) AS DATE) AS updated_at,

        r.product_id,

        TRY_CAST(LEFT(fw.first_waiting_at, 10) AS DATE) AS first_waiting_at,
        TRY_CAST(LEFT(fp.first_passed_at,  10) AS DATE) AS first_passed_at,

        -- Snabbflagga för enkel filtrering i Power BI
        CASE WHEN d.id IS NOT NULL THEN 1 ELSE 0 END     AS denied_triage,

        TRY_CAST(LEFT(d.denied_triage_at,  10) AS DATE)  AS denied_triage_at

    FROM ranked r
    LEFT JOIN first_waiting fw ON fw.id = r.id
    LEFT JOIN first_passed  fp ON fp.id = r.id
    LEFT JOIN denied         d ON  d.id = r.id
    WHERE r.rn = 1;   -- bara senaste versionen per ticket

    -- ── Steg 6: Bekräftelse ──────────────────────────────────
    DECLARE @rows          INT = @@ROWCOUNT;
    DECLARE @denied_count  INT = (SELECT COUNT(*) FROM silver.freshdesk_tickets WHERE denied_triage = 1);
    DECLARE @waiting_count INT = (SELECT COUNT(*) FROM silver.freshdesk_tickets WHERE status = 17);
    DECLARE @passed_count  INT = (SELECT COUNT(*) FROM silver.freshdesk_tickets WHERE status IN (6, 7, 12));

    COMMIT TRANSACTION;

    PRINT 'Klart.';
    PRINT '  Totalt laddade rader     : ' + CAST(@rows          AS NVARCHAR(10));
    PRINT '  Aktuellt waiting (17)    : ' + CAST(@waiting_count AS NVARCHAR(10));
    PRINT '  Aktuellt passed (6/7/12) : ' + CAST(@passed_count  AS NVARCHAR(10));
    PRINT '  Varav denied_triage      : ' + CAST(@denied_count  AS NVARCHAR(10));

END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    PRINT 'FEL — transaktionen återrullades.';
    PRINT ERROR_MESSAGE();
    THROW;
END CATCH;
GO
