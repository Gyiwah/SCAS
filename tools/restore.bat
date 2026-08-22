@echo off
REM ===========================================================================
REM  SCAS - restore from a logical backup.
REM
REM  Usage:  restore.bat ..\backups\scas_db_20260819_020000.sql
REM
REM  Before overwriting anything this script takes a PRE-RESTORE SNAPSHOT of
REM  the current database. Restoring the wrong file is a common way to turn a
REM  small incident into a large one; the snapshot makes that reversible.
REM ===========================================================================
setlocal
set MYSQL=C:\xampp\mysql\bin\mysql.exe
set DUMP=C:\xampp\mysql\bin\mysqldump.exe
set OUTDIR=%~dp0..\backups
set FILE=%~1

echo.
echo  SCAS restore
echo  ------------

if "%FILE%"=="" (
    echo  Usage: restore.bat ^<path-to-dump.sql^>
    echo.
    echo  Available backups:
    dir /b "%OUTDIR%\*.sql" 2>nul
    goto :end
)
if not exist "%FILE%" (
    echo  ERROR: %FILE% not found.
    goto :end
)

echo  Restoring from: %FILE%
echo.
echo  This REPLACES the current contents of scas_db.
set /p CONFIRM=  Type RESTORE to continue:
if /i not "%CONFIRM%"=="RESTORE" (
    echo  Cancelled.
    goto :end
)

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%I
set SNAP=%OUTDIR%\pre_restore_%STAMP%.sql

echo.
echo  [1/3] Taking a pre-restore snapshot of the current database...
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
"%DUMP%" -u root --single-transaction --routines --triggers --events ^
         --default-character-set=utf8mb4 scas_db > "%SNAP%" 2>nul
if errorlevel 1 (
    echo        No existing database to snapshot - continuing.
) else (
    echo        Saved to %SNAP%
)

echo  [2/3] Loading the backup...
"%MYSQL%" -u root -e "DROP DATABASE IF EXISTS scas_db; CREATE DATABASE scas_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
"%MYSQL%" -u root scas_db < "%FILE%"
if errorlevel 1 (
    echo        RESTORE FAILED. The snapshot at %SNAP% still holds the previous state.
    goto :end
)

echo  [3/3] Verifying...
"%MYSQL%" -u root -t scas_db -e "CALL sp_run_integrity_check();"
"%MYSQL%" -u root -t scas_db -e "SELECT COUNT(*) AS attendance_rows FROM attendance; SELECT COUNT(*) AS users FROM app_user;"
"%MYSQL%" -u root scas_db -e "INSERT INTO backup_log (backup_type, file_path, status, completed_at, performed_by, notes) VALUES ('RESTORE', '%FILE:\=/%', 'SUCCESS', NOW(), CURRENT_USER(), 'Restored by tools\\restore.bat');" 2>nul

echo.
echo  Restore complete.
echo.
echo  IMPORTANT: the database users and grants live in the mysql system
echo  database, NOT in this dump. If the server itself was rebuilt, re-run
echo  database\07_security_authorization.sql to recreate the roles and the
echo  scas_app account, or the application will not be able to connect.
echo.
echo  Every rule in the integrity check above must report 0 violations.

:end
endlocal
pause
