-- ============================================================
-- 08_gold_dim_date.sql
-- Creates and populates gold.DimDate in InternalStatistics.
--
-- Safe to re-run — TRUNCATE + full rebuild.
-- Date range: 2025-01-01 to 2035-12-31 (4,018 days).
--
-- !! IMPORTANT — EXTENDING THE DATE RANGE !!
-- If this table needs to cover dates beyond 2035-12-31:
--   1. Change '2035-12-31' to the new end date (two places below)
--   2. Add Easter dates for the new years to the easter CTE
--   3. Re-run this script
-- Easter dates for 2036+:
--   2036-04-13, 2037-04-05, 2038-04-25, 2039-04-10, 2040-04-01
-- ============================================================

USE InternalStatistics;
GO

-- ── Create table if not exists ────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'gold' AND t.name = 'dim_date'
)
BEGIN
    CREATE TABLE gold.DimDate (

        -- Primary key — one row per calendar day
        date_key             DATE          NOT NULL,

        -- Year / quarter / month
        year                 SMALLINT      NOT NULL,
        quarter_num          TINYINT       NOT NULL,   -- 1–4
        quarter_name         NVARCHAR(2)   NOT NULL,   -- 'Q1'–'Q4'
        month_num            TINYINT       NOT NULL,   -- 1–12
        month_name           NVARCHAR(10)  NOT NULL,   -- 'January' etc.
        month_short          NVARCHAR(3)   NOT NULL,   -- 'Jan' etc.
        month_sort           INT           NOT NULL,   -- YYYYMM — use as sort key in Power BI
                                                       -- so month names sort Jan→Dec, not A→Z

        -- ISO week
        iso_week             TINYINT       NOT NULL,   -- 1–53
        year_week            NVARCHAR(8)   NOT NULL,   -- 'YYYY-WNN' e.g. '2026-W05'
                                                       -- Uses ISO week-year, not calendar year
                                                       -- (late-Dec/early-Jan weeks handled correctly)
                                                       -- Sorts correctly as a plain string in Power BI

        -- Weekday
        day_of_week_num      TINYINT       NOT NULL,   -- ISO: 1=Monday … 7=Sunday
        day_name             NVARCHAR(10)  NOT NULL,   -- 'Monday' etc.
        day_short            NVARCHAR(3)   NOT NULL,   -- 'Mon' etc.

        -- Working day flags
        is_weekend           BIT           NOT NULL,
        is_public_holiday    BIT           NOT NULL,   -- Swedish public holidays (röda dagar) only
                                                       -- Christmas Eve, Midsummer Eve and New Year's
                                                       -- Eve are NOT included (not official red days)
        is_working_day       BIT           NOT NULL,   -- 1 = NOT weekend AND NOT public holiday
        working_days_in_week TINYINT       NOT NULL,   -- Working days in this ISO week (0–5)
                                                       -- Weeks with a holiday show 4 (or less)

        CONSTRAINT PK_gold_DimDate PRIMARY KEY (date_key)
    );
    PRINT 'Created: gold.DimDate';
END
ELSE
    PRINT 'Table exists: gold.DimDate — truncating for rebuild';
GO

TRUNCATE TABLE gold.DimDate;
GO

-- ── Populate ──────────────────────────────────────────────────
;WITH

-- ── Date series ──────────────────────────────────────────────
-- Recursive CTE. OPTION (MAXRECURSION 5000) at end of INSERT.
dates AS (
    SELECT CAST('2025-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < '2035-12-31'
),

-- ── Easter dates 2025–2035 (hard-coded) ──────────────────────
-- These are verified values from the Gregorian algorithm.
-- Add more years here if the date range above is extended.
easter AS (
    SELECT CAST(e AS DATE) AS easter_date
    FROM (VALUES
        ('2025-04-20'), ('2026-04-05'), ('2027-03-28'), ('2028-04-16'),
        ('2029-04-01'), ('2030-04-21'), ('2031-04-13'), ('2032-03-28'),
        ('2033-04-17'), ('2034-04-09'), ('2035-03-25')
    ) AS t(e)
),

-- ── Easter-based public holidays ─────────────────────────────
easter_holidays AS (
    SELECT easter_date                   AS h FROM easter   -- Easter Sunday   (Påskdagen)
    UNION ALL SELECT DATEADD(DAY, -2, easter_date) FROM easter   -- Good Friday     (Långfredag)
    UNION ALL SELECT DATEADD(DAY,  1, easter_date) FROM easter   -- Easter Monday   (Annandag påsk)
    UNION ALL SELECT DATEADD(DAY, 39, easter_date) FROM easter   -- Ascension Day   (Kristi himmelsfärdsdag)
    UNION ALL SELECT DATEADD(DAY, 49, easter_date) FROM easter   -- Whit Sunday     (Pingstdagen)
),

-- ── Fixed public holidays (same date every year) ─────────────
fixed_holidays AS (
    SELECT CAST(CAST(y.yr AS NVARCHAR(4)) + '-' + h.md AS DATE) AS h
    FROM (VALUES
        (2025),(2026),(2027),(2028),(2029),
        (2030),(2031),(2032),(2033),(2034),(2035)
    ) AS y(yr)
    CROSS JOIN (VALUES
        ('01-01'),   -- New Year's Day       (Nyårsdagen)
        ('01-06'),   -- Epiphany             (Trettondag jul)
        ('05-01'),   -- Labour Day           (Första maj)
        ('06-06'),   -- National Day         (Nationaldagen)
        ('12-25'),   -- Christmas Day        (Juldagen)
        ('12-26')    -- Boxing Day           (Annandag jul)
    ) AS h(md)
),

-- ── Midsummer Day: first Saturday on or after June 20 ────────
-- iso_dow formula: ((DATEDIFF from a known Monday) % 7 + 7) % 7 + 1
-- 2024-12-30 was a Monday → reference date for the formula.
-- Saturday = iso_dow 6.
midsummer AS (
    SELECT d AS h
    FROM dates
    WHERE MONTH(d) = 6
      AND DAY(d) BETWEEN 20 AND 26
      AND ((DATEDIFF(DAY, '2024-12-30', d) % 7 + 7) % 7) + 1 = 6
),

-- ── All Saints' Day: first Saturday on or after October 31 ───
all_saints AS (
    SELECT d AS h
    FROM dates
    WHERE (
        (MONTH(d) = 10 AND DAY(d) = 31) OR
        (MONTH(d) = 11 AND DAY(d) BETWEEN 1 AND 6)
    )
    AND ((DATEDIFF(DAY, '2024-12-30', d) % 7 + 7) % 7) + 1 = 6
),

-- ── All holidays combined ────────────────────────────────────
-- UNION (not UNION ALL) deduplicates in case a fixed holiday
-- falls on the same day as a calculated one.
all_holidays AS (
    SELECT h FROM easter_holidays
    UNION SELECT h FROM fixed_holidays
    UNION SELECT h FROM midsummer
    UNION SELECT h FROM all_saints
),

-- ── Base: compute ISO weekday and holiday flag ────────────────
-- iso_dow is independent of DATEFIRST and server language settings.
-- Formula anchored to 2024-12-30 (verified Monday).
base AS (
    SELECT
        dates.d,
        ((DATEDIFF(DAY, '2024-12-30', dates.d) % 7 + 7) % 7) + 1  AS iso_dow,
        CASE WHEN ah.h IS NOT NULL THEN 1 ELSE 0 END                AS is_holiday
    FROM dates
    LEFT JOIN all_holidays ah ON ah.h = dates.d
),

-- ── Enrich: add is_working_day and ISO-week identifier ───────
-- week_thursday = the Thursday of this ISO week.
-- Used as PARTITION key for working_days_in_week — handles
-- year-boundary weeks correctly (no calendar-year ambiguity).
enriched AS (
    SELECT
        d,
        iso_dow,
        is_holiday,
        CASE WHEN iso_dow >= 6 OR is_holiday = 1 THEN 0 ELSE 1 END  AS is_wd,
        DATEADD(DAY, 4 - iso_dow, d)                                 AS week_thursday
    FROM base
)

INSERT INTO gold.DimDate (
    date_key, year, quarter_num, quarter_name,
    month_num, month_name, month_short, month_sort,
    iso_week, year_week,
    day_of_week_num, day_name, day_short,
    is_weekend, is_public_holiday, is_working_day, working_days_in_week
)
SELECT
    d                                                          AS date_key,
    YEAR(d)                                                    AS year,
    DATEPART(QUARTER, d)                                       AS quarter_num,
    'Q' + CAST(DATEPART(QUARTER, d) AS NVARCHAR(1))           AS quarter_name,
    MONTH(d)                                                   AS month_num,

    -- Explicit mapping avoids language-dependent DATENAME results
    CASE MONTH(d)
        WHEN 1  THEN 'January'   WHEN 2  THEN 'February'  WHEN 3  THEN 'March'
        WHEN 4  THEN 'April'     WHEN 5  THEN 'May'        WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'      WHEN 8  THEN 'August'     WHEN 9  THEN 'September'
        WHEN 10 THEN 'October'   WHEN 11 THEN 'November'   WHEN 12 THEN 'December'
    END                                                        AS month_name,
    CASE MONTH(d)
        WHEN 1  THEN 'Jan'  WHEN 2  THEN 'Feb'  WHEN 3  THEN 'Mar'
        WHEN 4  THEN 'Apr'  WHEN 5  THEN 'May'  WHEN 6  THEN 'Jun'
        WHEN 7  THEN 'Jul'  WHEN 8  THEN 'Aug'  WHEN 9  THEN 'Sep'
        WHEN 10 THEN 'Oct'  WHEN 11 THEN 'Nov'  WHEN 12 THEN 'Dec'
    END                                                        AS month_short,

    YEAR(d) * 100 + MONTH(d)                                  AS month_sort,
    DATEPART(ISO_WEEK, d)                                      AS iso_week,

    -- year_week uses ISO week-year (= year of the Thursday in that week)
    -- so '2036-W01' is correctly assigned to 2035-12-29 through 2036-01-04
    CAST(YEAR(week_thursday) AS NVARCHAR(4))
        + '-W'
        + RIGHT('0' + CAST(DATEPART(ISO_WEEK, d) AS NVARCHAR(2)), 2)
                                                               AS year_week,

    iso_dow                                                    AS day_of_week_num,
    CASE iso_dow
        WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'   WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'  WHEN 5 THEN 'Friday'    WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
    END                                                        AS day_name,
    CASE iso_dow
        WHEN 1 THEN 'Mon'  WHEN 2 THEN 'Tue'  WHEN 3 THEN 'Wed'
        WHEN 4 THEN 'Thu'  WHEN 5 THEN 'Fri'  WHEN 6 THEN 'Sat'
        WHEN 7 THEN 'Sun'
    END                                                        AS day_short,

    CASE WHEN iso_dow >= 6 THEN 1 ELSE 0 END                  AS is_weekend,
    is_holiday                                                 AS is_public_holiday,
    is_wd                                                      AS is_working_day,

    -- Sum working days across the ISO week (partitioned by Thursday = unique week ID)
    SUM(is_wd) OVER (PARTITION BY week_thursday)               AS working_days_in_week

FROM enriched
OPTION (MAXRECURSION 5000);
GO

-- ── Verify ────────────────────────────────────────────────────
PRINT 'Summary:';
SELECT
    COUNT(*)                              AS total_days,
    SUM(CAST(is_weekend        AS INT))   AS weekend_days,
    SUM(CAST(is_public_holiday AS INT))   AS public_holidays,
    SUM(CAST(is_working_day    AS INT))   AS working_days
FROM gold.DimDate;

PRINT 'Public holidays:';
SELECT date_key, day_name, is_weekend
FROM gold.DimDate
WHERE is_public_holiday = 1
ORDER BY date_key;
GO
