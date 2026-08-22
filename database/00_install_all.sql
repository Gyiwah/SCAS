/* ============================================================================
   SCAS - MASTER INSTALLER
   Smart Classroom Attendance System
   University of Education, Winneba - MPhil ICT - ICTE825
   ---------------------------------------------------------------------------
   Builds the entire database from nothing.

   HOW TO RUN
     Open a command prompt IN THIS DIRECTORY (D:\SCAS\database) and run:

         C:\xampp\mysql\bin\mysql.exe -u root < 00_install_all.sql

     or simply double-click  ..\tools\install.bat

   WARNING: step 1 executes DROP DATABASE IF EXISTS scas_db. Any existing SCAS
   data is destroyed. No other database on the server is touched.

   The file order is a dependency order, not a preference:
     tables -> indexes -> functions -> views (call functions) ->
     procedures -> triggers -> security -> recovery -> events -> data ->
     measurement -> tests.
   ========================================================================= */

SELECT '==================================================' AS '';
SELECT 'SCAS DATABASE INSTALLATION STARTING' AS '';
SELECT NOW() AS started_at;
SELECT '==================================================' AS '';

SELECT '[1/12] Schema: tables, constraints, partitions, temporal table' AS step;
source 01_schema.sql

SELECT '[2/12] Access paths: indexes and optimiser statistics' AS step;
source 02_indexes_and_optimization.sql

SELECT '[3/12] Stored functions' AS step;
source 03_functions.sql

SELECT '[4/12] Views, including the row-level security views' AS step;
source 04_views.sql

SELECT '[5/12] Stored procedures' AS step;
source 05_stored_procedures.sql

SELECT '[6/12] Triggers' AS step;
source 06_triggers.sql

SELECT '[7/12] Security: roles, accounts, grants, encryption' AS step;
source 07_security_authorization.sql

SELECT '[8/12] Transaction management and recovery infrastructure' AS step;
source 08_transactions_recovery.sql

SELECT '[9/12] Scheduled events' AS step;
source 09_events.sql

SELECT '[10/12] Seed data (this step takes around 15 seconds)' AS step;
source 10_seed_data.sql

SELECT '[11/12] Query processing and evaluation' AS step;
source 11_query_processing_evaluation.sql

SELECT '[12/12] Verification test suite' AS step;
source 12_verification_tests.sql

SELECT '==================================================' AS '';
SELECT 'SCAS DATABASE INSTALLATION COMPLETE' AS '';
SELECT NOW() AS finished_at;
SELECT '==================================================' AS '';

SELECT 'Object inventory' AS summary;
SELECT 'tables'     AS object_type, COUNT(*) AS count FROM information_schema.TABLES
       WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE <> 'VIEW'
UNION ALL SELECT 'views',      COUNT(*) FROM information_schema.VIEWS     WHERE TABLE_SCHEMA   = 'scas_db'
UNION ALL SELECT 'procedures', COUNT(*) FROM information_schema.ROUTINES  WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'PROCEDURE'
UNION ALL SELECT 'functions',  COUNT(*) FROM information_schema.ROUTINES  WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'FUNCTION'
UNION ALL SELECT 'triggers',   COUNT(*) FROM information_schema.TRIGGERS  WHERE TRIGGER_SCHEMA = 'scas_db'
UNION ALL SELECT 'events',     COUNT(*) FROM information_schema.EVENTS    WHERE EVENT_SCHEMA   = 'scas_db'
UNION ALL SELECT 'indexes',    COUNT(DISTINCT TABLE_NAME, INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'scas_db'
UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = 'scas_db' AND CONSTRAINT_TYPE = 'FOREIGN KEY'
UNION ALL SELECT 'check constraints', COUNT(*) FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = 'scas_db';

SELECT 'Next step: point the application at the database and sign in.' AS next_step,
       'http://localhost/scas/' AS url;
