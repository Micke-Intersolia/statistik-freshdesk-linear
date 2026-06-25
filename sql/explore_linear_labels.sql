-- ============================================================
-- Explore Linear labels
-- Underlag för att designa Power BI-sida med label-statistik
-- Kör mot: InternalStatistics på INTSQLSERVER01
-- ============================================================

USE InternalStatistics;
GO

-- ------------------------------------------------------------
-- 1. Alla distinkta labels med antal issues
--    (gold.FactLinear är redan filtrerad: DEV-issues exkluderade)
-- ------------------------------------------------------------
SELECT
    TRIM(s.value)       AS label,
    COUNT(*)            AS issue_count,
    SUM(CASE WHEN f.closed_at IS NOT NULL THEN 1 ELSE 0 END) AS closed_count,
    SUM(CASE WHEN f.closed_at IS NULL     THEN 1 ELSE 0 END) AS open_count
FROM gold.FactLinear f
CROSS APPLY STRING_SPLIT(f.labels, '|') s
WHERE TRIM(s.value) <> ''
GROUP BY TRIM(s.value)
ORDER BY issue_count DESC;

GO

-- ------------------------------------------------------------
-- 2. Issues utan label (för att bedöma täckningsgraden)
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                    AS total_issues,
    SUM(CASE WHEN labels IS NULL
              OR labels = '' THEN 1 ELSE 0 END) AS issues_without_label,
    SUM(CASE WHEN labels IS NOT NULL
             AND labels <> '' THEN 1 ELSE 0 END) AS issues_with_label
FROM gold.FactLinear;

GO

-- ------------------------------------------------------------
-- 3. Issues med flera labels (för att förstå överlapp)
-- ------------------------------------------------------------
SELECT
    label_count,
    COUNT(*) AS issue_count
FROM (
    SELECT
        f.identifier,
        COUNT(s.value) AS label_count
    FROM gold.FactLinear f
    CROSS APPLY STRING_SPLIT(f.labels, '|') s
    WHERE TRIM(s.value) <> ''
    GROUP BY f.identifier
) sub
GROUP BY label_count
ORDER BY label_count;

GO

-- ------------------------------------------------------------
-- 4. Prioritetsfördelning (open vs closed)
-- ------------------------------------------------------------
SELECT
    f.priority_label,
    f.priority,
    COUNT(*)                                                   AS issue_count,
    SUM(CASE WHEN f.closed_at IS NOT NULL THEN 1 ELSE 0 END)  AS closed_count,
    SUM(CASE WHEN f.closed_at IS NULL     THEN 1 ELSE 0 END)  AS open_count
FROM gold.FactLinear f
GROUP BY f.priority_label, f.priority
ORDER BY f.priority;

GO

-- ------------------------------------------------------------
-- 5. Label × Prioritet (för att se mönster)
-- ------------------------------------------------------------
SELECT
    TRIM(s.value)   AS label,
    f.priority_label,
    COUNT(*)        AS issue_count
FROM gold.FactLinear f
CROSS APPLY STRING_SPLIT(f.labels, '|') s
WHERE TRIM(s.value) <> ''
GROUP BY TRIM(s.value), f.priority_label, f.priority
ORDER BY label, f.priority;

GO
