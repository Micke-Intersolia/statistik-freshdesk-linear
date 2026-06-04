-- ============================================================
-- 02_bronze_load_freshdesk.sql
-- Loads one Freshdesk JSON file into bronze.freshdesk_tickets.
--
-- HOW TO USE:
--   1. Edit the two variables in Step 1 to point at the file
--      you want to load.
--   2. Select All and run (F5).
--   3. The script checks import_log first — if the file has
--      already been loaded it stops without inserting anything.
--
-- Run order for initial load:
--   First:  the backfill file  (freshdesk_backfill_*.json)
--   Second: the latest snapshot (freshdesk_snapshot_*.json)
--   Future: each new nightly snapshot as it arrives
--
-- HOW IT WORKS:
--   OPENROWSET reads the entire JSON file into memory as a
--   single text string (SINGLE_CLOB). OPENJSON then splits that
--   string into one row per element of the top-level JSON array.
--   JSON_VALUE extracts a single scalar value from each element.
--   Because OPENROWSET requires a literal file path (not a
--   variable), we build the INSERT as a dynamic SQL string and
--   execute it with sp_executesql.
-- ============================================================

USE OPEX_statistics;
GO

-- ── Step 1: Set these two values before running ──────────────
--   @file_name : filename only — used as the unique key in import_log
--   @file_path : full absolute path that SQL Server can read
--                (SQL Server runs as a Windows service and reads
--                 from the local file system — local paths work fine)

DECLARE @file_name  NVARCHAR(260) = 'freshdesk_snapshot_20260604T112101Z.json';
DECLARE @file_path  NVARCHAR(260) = 'C:\Users\michael.brostrom\Documents\GitHub\statistik-freshdesk-linear\raw\freshdesk\freshdesk_backfill_20250501_20260604.json';

-- ── Step 2: Idempotency check ────────────────────────────────
-- Stop immediately if this file is already recorded in import_log.
-- This means the script is safe to run multiple times — it will
-- never insert the same file's rows twice.
IF EXISTS (SELECT 1 FROM bronze.import_log WHERE file_name = @file_name)
BEGIN
    PRINT 'SKIPPED — already loaded: ' + @file_name;
    RETURN;
END

PRINT 'Loading: ' + @file_name;

-- ── Step 3: Insert rows from the JSON file ───────────────────
-- Dynamic SQL is needed because OPENROWSET requires a string
-- literal for the file path, not a variable.
-- The file_name is embedded as a literal string in the query
-- so every inserted row knows which file it came from.
DECLARE @sql NVARCHAR(MAX) = N'
INSERT INTO bronze.freshdesk_tickets
    (id, subject, status, priority,
     created_at, updated_at, due_by,
     group_id, product_id,
     _snapshot_file)
SELECT
    -- CAST ensures the value lands in the correct SQL type.
    -- JSON_VALUE always returns NVARCHAR, so numeric columns need explicit casting.
    CAST(JSON_VALUE(value, ''$.id'')         AS INT)     AS id,
         JSON_VALUE(value, ''$.subject'')               AS subject,
    CAST(JSON_VALUE(value, ''$.status'')     AS TINYINT) AS status,
    CAST(JSON_VALUE(value, ''$.priority'')   AS TINYINT) AS priority,
         JSON_VALUE(value, ''$.created_at'')            AS created_at,
         JSON_VALUE(value, ''$.updated_at'')            AS updated_at,
         JSON_VALUE(value, ''$.due_by'')                AS due_by,
    CAST(JSON_VALUE(value, ''$.group_id'')   AS BIGINT)  AS group_id,
    CAST(JSON_VALUE(value, ''$.product_id'') AS BIGINT)  AS product_id,
    ''' + @file_name + N'''                             AS _snapshot_file
FROM OPENROWSET(
    BULK ''' + @file_path + N''',
    SINGLE_CLOB             -- read the whole file as one text blob
) AS raw_file
CROSS APPLY OPENJSON(raw_file.BulkColumn);
                             -- split the JSON array into one row per ticket
';

EXEC sp_executesql @sql;

-- ── Step 4: Count inserted rows and log the import ───────────
-- We count from the table rather than using @@ROWCOUNT after EXEC
-- to be certain we are reading the correct figure.
DECLARE @rows INT = (
    SELECT COUNT(*)
    FROM bronze.freshdesk_tickets
    WHERE _snapshot_file = @file_name
);

INSERT INTO bronze.import_log (source, file_name, row_count)
VALUES ('freshdesk', @file_name, @rows);

PRINT 'Done — inserted ' + CAST(@rows AS NVARCHAR(10)) + ' rows from ' + @file_name;
GO
