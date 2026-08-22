@echo off
REM ===========================================================================
REM  SCAS - build the database from nothing.
REM
REM  WARNING: this DROPS and recreates scas_db. Any existing SCAS data is lost.
REM  No other database on the server is touched.
REM ===========================================================================
setlocal
set MYSQL=C:\xampp\mysql\bin\mysql.exe
set DBDIR=%~dp0..\database

echo.
echo  Smart Classroom Attendance System - database installation
echo  ---------------------------------------------------------
echo.

if not exist "%MYSQL%" (
    echo  ERROR: mysql.exe not found at %MYSQL%
    echo  Edit this file and set MYSQL to your XAMPP path.
    goto :end
)

"%MYSQL%" -u root -e "SELECT 1" >nul 2>&1
if errorlevel 1 (
    echo  ERROR: cannot connect to MySQL.
    echo  Start MySQL from the XAMPP Control Panel and try again.
    goto :end
)

echo  This will DROP the existing scas_db and rebuild it.
set /p CONFIRM=  Type YES to continue:
if /i not "%CONFIRM%"=="YES" (
    echo  Cancelled.
    goto :end
)

pushd "%DBDIR%"
echo.
echo  Running the installer, this takes about 20 seconds...
"%MYSQL%" -u root -t < 00_install_all.sql
popd

echo.
echo  Done. Open http://localhost/scas/ to sign in.
echo.

:end
endlocal
pause
