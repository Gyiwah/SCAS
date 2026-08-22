@echo off
REM ===========================================================================
REM  SCAS - logical backup.
REM
REM  Uses mysqldump with:
REM    --single-transaction  take the dump inside one consistent InnoDB
REM                          snapshot, so the school is NOT locked out of the
REM                          system while the backup runs. Without it,
REM                          mysqldump locks every table and check-ins fail
REM                          for the duration.
REM    --routines --triggers --events
REM                          a schema without its procedures, triggers and
REM                          scheduled jobs is not a restorable system: the
REM                          business rules live in those objects.
REM    --master-data=2       writes the binary-log coordinates into the dump as
REM                          a comment. Those coordinates are the starting
REM                          point for a point-in-time recovery. It is skipped
REM                          automatically when binary logging is off.
REM
REM  The backup is registered in backup_log so the DBA console can report how
REM  far back the system could be recovered.
REM ===========================================================================
setlocal enabledelayedexpansion
set MYSQL=C:\xampp\mysql\bin\mysql.exe
set DUMP=C:\xampp\mysql\bin\mysqldump.exe
set OUTDIR=%~dp0..\backups

REM Timestamp via PowerShell rather than wmic: wmic has been removed from
REM recent Windows 11 builds, and %DATE%/%TIME% parsing depends on the
REM machine's locale.
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%I
set FILE=%OUTDIR%\scas_db_%STAMP%.sql

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo.
echo  SCAS backup
echo  -----------
echo  Target: %FILE%
echo.

REM Is binary logging on? It decides whether point-in-time recovery is possible.
for /f "tokens=2" %%A in ('""%MYSQL%" -u root -N -B -e "SELECT @@log_bin" 2>nul"') do set LOGBIN=%%A
"%MYSQL%" -u root -N -B -e "SELECT @@log_bin" > "%TEMP%\scas_logbin.txt" 2>nul
set /p LOGBIN=<"%TEMP%\scas_logbin.txt"

set MASTERDATA=
if "%LOGBIN%"=="1" (
    set MASTERDATA=--master-data=2
    echo  Binary logging is ON - recording the log position for point-in-time recovery.
) else (
    echo  Binary logging is OFF - this backup can only be restored as a whole.
    echo  See docs\RECOVERY.md to enable it.
)

REM Register the attempt before it starts, so a crash mid-backup is visible.
"%MYSQL%" -u root scas_db -e "CALL sp_backup_start('LOGICAL', '%FILE:\=/%', 'tools\\backup.bat', @bid); SELECT @bid INTO @x;" >nul 2>&1
"%MYSQL%" -u root -N -B scas_db -e "SELECT backup_id FROM backup_log ORDER BY backup_id DESC LIMIT 1" > "%TEMP%\scas_bid.txt"
set /p BID=<"%TEMP%\scas_bid.txt"

echo  Dumping...
"%DUMP%" -u root --single-transaction --routines --triggers --events %MASTERDATA% ^
         --default-character-set=utf8mb4 --hex-blob scas_db > "%FILE%"

REM Redirection hides mysqldump's exit code, so verify the artefact itself.
REM A dump that exists but is tiny is a failed dump, not a small database.
set SIZE=0
if exist "%FILE%" for %%S in ("%FILE%") do set SIZE=%%~zS

if %SIZE% LSS 10000 (
    echo  BACKUP FAILED - the dump is %SIZE% bytes, which cannot be a real database.
    "%MYSQL%" -u root scas_db -e "CALL sp_backup_finish(%BID%, 'FAILED', %SIZE%, NULL, NULL)" >nul 2>&1
    goto :end
)

findstr /C:"CREATE TABLE `attendance`" "%FILE%" >nul
if errorlevel 1 (
    echo  BACKUP FAILED - the dump does not contain the attendance table.
    "%MYSQL%" -u root scas_db -e "CALL sp_backup_finish(%BID%, 'FAILED', %SIZE%, NULL, NULL)" >nul 2>&1
    goto :end
)
"%MYSQL%" -u root scas_db -e "CALL sp_backup_finish(%BID%, 'SUCCESS', %SIZE%, NULL, NULL)" >nul 2>&1

echo.
echo  SUCCESS. %SIZE% bytes written.
echo  Registered as backup #%BID% - see the DBA console, Recovery tab.
echo.
echo  A backup that has never been restored is only a hope. Practise the
echo  restore with tools\restore.bat, following docs\RECOVERY.md.

:end
del "%TEMP%\scas_logbin.txt" 2>nul
del "%TEMP%\scas_bid.txt" 2>nul
endlocal
pause
