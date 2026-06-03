CREATE TABLE Gold.DimDate (
    DateKey            INT PRIMARY KEY,      -- YYYYMMDD
    DateValue          DATE NOT NULL,
    Year               INT NOT NULL,
    Quarter            INT NOT NULL,
    QuarterName        NVARCHAR(10) NOT NULL,
    Month              INT NOT NULL,
    MonthName          NVARCHAR(20) NOT NULL,
    MonthShortName     NVARCHAR(10) NOT NULL,
    ISOWeek            INT NOT NULL,
    Day                INT NOT NULL,
    DayName            NVARCHAR(20) NOT NULL,
    DayShortName       NVARCHAR(10) NOT NULL,
    IsWeekend          BIT NOT NULL,
    IsHoliday          BIT NOT NULL,
    HolidayName        NVARCHAR(100) NULL,
    IsWorkingDay       BIT NOT NULL
);
GO

CREATE OR ALTER FUNCTION Gold.IsSwedishHoliday (@d DATE)
RETURNS TABLE
AS
RETURN
(
    WITH Calc AS (
        SELECT
            @d AS d,
            YEAR(@d) AS y,
            (19 * (YEAR(@d) % 19) + 24) % 30 AS a,
            (YEAR(@d) + YEAR(@d)/4 + ((19 * (YEAR(@d) % 19) + 24) % 30) + 5) % 7 AS b
    ),
    Easter AS (
        SELECT
            d,
            y,
            DATEADD(DAY, (a + b), DATEFROMPARTS(y, 3, 22)) AS EasterSunday
        FROM Calc
    ),
    Holidays AS (
        SELECT 
            d,
            CASE 
                WHEN d = DATEFROMPARTS(y,1,1) THEN 'Nyårsdagen'
                WHEN d = DATEFROMPARTS(y,1,6) THEN 'Trettondagen'
                WHEN d = DATEADD(DAY,-2,EasterSunday) THEN 'Långfredagen'
                WHEN d = EasterSunday THEN 'Påskdagen'
                WHEN d = DATEADD(DAY,1,EasterSunday) THEN 'Annandag påsk'
                WHEN d = DATEADD(DAY,39,EasterSunday) THEN 'Kristi himmelsfärd'
                WHEN d = DATEADD(DAY,49,EasterSunday) THEN 'Pingstdagen'
                WHEN d = DATEFROMPARTS(y,6,6) THEN 'Nationaldagen'
                WHEN d = (
                    DATEADD(
                        DAY,
                        (6 - DATEPART(WEEKDAY, DATEFROMPARTS(y,6,20)) + 7) % 7,
                        DATEFROMPARTS(y,6,20)
                    )
                ) THEN 'Midsommardagen'
                WHEN d = (
                    DATEADD(
                        DAY,
                        (6 - DATEPART(WEEKDAY, DATEFROMPARTS(y,10,31)) + 7) % 7,
                        DATEFROMPARTS(y,10,31)
                    )
                ) THEN 'Alla helgons dag'
                WHEN d = DATEFROMPARTS(y,12,25) THEN 'Juldagen'
                WHEN d = DATEFROMPARTS(y,12,26) THEN 'Annandag jul'
            END AS HolidayName
        FROM Easter
    )
    SELECT
        CASE WHEN HolidayName IS NULL THEN 0 ELSE 1 END AS IsHoliday,
        HolidayName
    FROM Holidays
);
GO



-- Fyll tabellen med data för svenska förhållanden
WITH DateRange AS (
    SELECT CAST('2020-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d)
    FROM DateRange
    WHERE d < '2035-12-31'
)
INSERT INTO Gold.DimDate (
    DateKey, DateValue, Year, Quarter, QuarterName,
    Month, MonthName, MonthShortName,
    ISOWeek, Day, DayName, DayShortName,
    IsWeekend, IsHoliday, HolidayName, IsWorkingDay
)
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')) AS DateKey,
    d AS DateValue,
    YEAR(d) AS Year,
    DATEPART(QUARTER, d) AS Quarter,
    CONCAT('Q', DATEPART(QUARTER, d)) AS QuarterName,

    MONTH(d) AS Month,
    CASE MONTH(d)
        WHEN 1 THEN 'Januari' WHEN 2 THEN 'Februari' WHEN 3 THEN 'Mars'
        WHEN 4 THEN 'April'   WHEN 5 THEN 'Maj'      WHEN 6 THEN 'Juni'
        WHEN 7 THEN 'Juli'    WHEN 8 THEN 'Augusti'  WHEN 9 THEN 'September'
        WHEN 10 THEN 'Oktober' WHEN 11 THEN 'November' WHEN 12 THEN 'December'
    END AS MonthName,

    CASE MONTH(d)
        WHEN 1 THEN 'Jan' WHEN 2 THEN 'Feb' WHEN 3 THEN 'Mar'
        WHEN 4 THEN 'Apr' WHEN 5 THEN 'Maj' WHEN 6 THEN 'Jun'
        WHEN 7 THEN 'Jul' WHEN 8 THEN 'Aug' WHEN 9 THEN 'Sep'
        WHEN 10 THEN 'Okt' WHEN 11 THEN 'Nov' WHEN 12 THEN 'Dec'
    END AS MonthShortName,

    DATEPART(ISO_WEEK, d) AS ISOWeek,
    DAY(d) AS Day,

    CASE DATEPART(WEEKDAY, d)
        WHEN 1 THEN 'Måndag' WHEN 2 THEN 'Tisdag' WHEN 3 THEN 'Onsdag'
        WHEN 4 THEN 'Torsdag' WHEN 5 THEN 'Fredag'
        WHEN 6 THEN 'Lördag' WHEN 7 THEN 'Söndag'
    END AS DayName,

    CASE DATEPART(WEEKDAY, d)
        WHEN 1 THEN 'Mån' WHEN 2 THEN 'Tis' WHEN 3 THEN 'Ons'
        WHEN 4 THEN 'Tor' WHEN 5 THEN 'Fre'
        WHEN 6 THEN 'Lör' WHEN 7 THEN 'Sön'
    END AS DayShortName,

    CASE WHEN DATEPART(WEEKDAY, d) IN (6,7) THEN 1 ELSE 0 END AS IsWeekend,

    h.IsHoliday,
    h.HolidayName,

    CASE 
        WHEN h.IsHoliday = 1 THEN 0
        WHEN DATEPART(WEEKDAY, d) IN (6,7) THEN 0
        ELSE 1
    END AS IsWorkingDay

FROM DateRange
CROSS APPLY Gold.IsSwedishHoliday(d) AS h
OPTION (MAXRECURSION 0);

