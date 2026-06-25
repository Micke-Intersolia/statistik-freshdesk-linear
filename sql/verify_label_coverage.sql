-- ============================================================
-- verify_label_coverage.sql
-- Verifierar att label-täckning (58% utan label) stämmer
-- genom hela kedjan: bronze → silver → gold
-- ============================================================

USE InternalStatistics;
GO

-- ------------------------------------------------------------
-- 1. Silver vs Gold — ska vara identiska (gold är en ren vy)
-- ------------------------------------------------------------
SELECT 'silver.linear_issues' AS source, COUNT(*) AS total_rows FROM silver.linear_issues
UNION ALL
SELECT 'gold.FactLinear',               COUNT(*) FROM gold.FactLinear;

GO

-- ------------------------------------------------------------
-- 2. Silver — label-täckning uppdelat på trashed-flaggan
--    (trashade issues kan ha tomma labels och påverka siffran)
-- ------------------------------------------------------------
SELECT
    trashed,
    COUNT(*)                                                        AS issue_count,
    SUM(CASE WHEN labels IS NULL OR labels = '' THEN 1 ELSE 0 END) AS no_label,
    SUM(CASE WHEN labels IS NOT NULL AND labels <> '' THEN 1 ELSE 0 END) AS has_label
FROM silver.linear_issues
GROUP BY trashed
ORDER BY trashed;

GO

-- ------------------------------------------------------------
-- 3. Silver — label-täckning exklusive trashade issues
--    (närmaste jämförelsen mot vad Power BI borde visa
--     om trashed filtreras på rapportnivå)
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                        AS total_active,
    SUM(CASE WHEN labels IS NULL OR labels = '' THEN 1 ELSE 0 END) AS no_label,
    SUM(CASE WHEN labels IS NOT NULL AND labels <> '' THEN 1 ELSE 0 END) AS has_label
FROM silver.linear_issues
WHERE trashed = 0;

GO

-- ------------------------------------------------------------
-- 4. Bronze — label-täckning i senaste snapshot per issue
--    (kontrollerar att silver inte tappat labels vid inläsning)
-- ------------------------------------------------------------
WITH latest AS (
    SELECT
        id,
        labels,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY _loaded_at DESC) AS rn
    FROM bronze.linear_issues
)
SELECT
    COUNT(*)                                                        AS total_issues,
    SUM(CASE WHEN labels IS NULL OR labels = '' THEN 1 ELSE 0 END) AS no_label,
    SUM(CASE WHEN labels IS NOT NULL AND labels <> '' THEN 1 ELSE 0 END) AS has_label
FROM latest
WHERE rn = 1;

GO

-- ------------------------------------------------------------
-- 5. Jämförelse: issues som har label i bronze men INTE i silver
--    (avslöjar om silver-laddningen tappat labels)
-- ------------------------------------------------------------
WITH latest_bronze AS (
    SELECT
        id,
        labels AS bronze_labels,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY _loaded_at DESC) AS rn
    FROM bronze.linear_issues
)
SELECT COUNT(*) AS lost_in_silver
FROM latest_bronze b
JOIN silver.linear_issues s ON b.id = s.id
WHERE b.rn = 1
  AND (b.bronze_labels IS NOT NULL AND b.bronze_labels <> '')
  AND (s.labels IS NULL OR s.labels = '');

GO
