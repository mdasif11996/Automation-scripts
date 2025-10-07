@echo off
REM ================================================================
REM PostgreSQL WAL Move Script
REM Author: Asif
REM Purpose: Safely move PostgreSQL WAL folder to a new location
REM Requirements:
REM   - Run as Administrator
REM   - PostgreSQL service must be stopped before moving WAL
REM ================================================================

:: ------------------- USER INPUT -------------------
SET /P PG_SERVICE=Enter the PostgreSQL service name (e.g., postgresql-x64-16): 
SET /P OLD_WAL=Enter the old WAL path (e.g., D:\PostgreSQL\PGDATA\pg_wal): 
SET /P NEW_WAL=Enter the new WAL path (e.g., D:\PostgreSQL\PGWAL): 

ECHO.
ECHO ================================================================
ECHO PostgreSQL WAL Move Process
ECHO ================================================================
ECHO Service Name : %PG_SERVICE%
ECHO Old WAL Path : %OLD_WAL%
ECHO New WAL Path : %NEW_WAL%
ECHO ================================================================
ECHO.

:: ------------------- Step 1: Stop PostgreSQL -------------------
ECHO [Step 1] Stopping PostgreSQL service: %PG_SERVICE% ...
net stop "%PG_SERVICE%"
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: Failed to stop PostgreSQL service. Check the service name and permissions.
    PAUSE
    EXIT /B 1
)
ECHO PostgreSQL service stopped successfully.
ECHO.

:: ------------------- Step 2: Move WAL files -------------------
ECHO [Step 2] Moving WAL data from "%OLD_WAL%" to "%NEW_WAL%" ...

IF NOT EXIST "%OLD_WAL%" (
    ECHO ERROR: Old WAL directory not found: "%OLD_WAL%"
    PAUSE
    EXIT /B 1
)

:: Create new WAL directory if it doesn't exist
IF NOT EXIST "%NEW_WAL%" (
    ECHO Creating new WAL folder at "%NEW_WAL%" ...
    mkdir "%NEW_WAL%"
    IF %ERRORLEVEL% NEQ 0 (
        ECHO ERROR: Failed to create new WAL folder. Check permissions.
        PAUSE
        EXIT /B 1
    )
)

:: Use robocopy to move all files and preserve structure
robocopy "%OLD_WAL%" "%NEW_WAL%" /MOVE /E
IF %ERRORLEVEL% GEQ 8 (
    ECHO ERROR: robocopy encountered a failure while moving files.
    PAUSE
    EXIT /B 1
)
ECHO WAL files moved successfully.
ECHO.

:: ------------------- Step 3: Remove old pg_wal -------------------
ECHO [Step 3] Removing old WAL folder ...

IF EXIST "%OLD_WAL%" (
    :: Remove hidden, system, read-only attributes
    attrib -h -s -r "%OLD_WAL%\*" /S /D

    :: Try to delete the directory
    rmdir /S /Q "%OLD_WAL%"
    
    IF EXIST "%OLD_WAL%" (
        ECHO ERROR: Failed to completely remove old WAL folder.
        ECHO The folder may still contain locked or hidden files.
        ECHO Please close all PostgreSQL processes and try again.
        PAUSE
        EXIT /B 1
    )

    ECHO Old WAL folder removed successfully.
) ELSE (
    ECHO WARNING: Old WAL folder not found. Skipping removal.
)
ECHO.

:: ------------------- Step 4: Create symbolic link -------------------
ECHO [Step 4] Creating symbolic link: "%OLD_WAL%" -> "%NEW_WAL%"

:: Verify old WAL folder does NOT exist before creating symlink
IF EXIST "%OLD_WAL%" (
    ECHO ERROR: Cannot create symbolic link because "%OLD_WAL%" already exists.
    ECHO Please delete it manually and re-run this step.
    PAUSE
    EXIT /B 1
)

:: Create the symbolic link
mklink /D "%OLD_WAL%" "%NEW_WAL%"
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: Failed to create symbolic link.
    ECHO Make sure you are running this script as Administrator.
    PAUSE
    EXIT /B 1
)

ECHO Symbolic link created successfully.
ECHO.

:: ------------------- Step 5: Start PostgreSQL -------------------
ECHO [Step 5] Starting PostgreSQL service: %PG_SERVICE% ...
net start "%PG_SERVICE%"
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: Failed to start PostgreSQL service. Check PostgreSQL logs for details.
    PAUSE
    EXIT /B 1
)

ECHO PostgreSQL service started successfully.
ECHO.

:: ------------------- Final Status -------------------
ECHO ================================================================
ECHO WAL move completed successfully!
ECHO PostgreSQL is now using "%NEW_WAL%" for WAL storage.
ECHO ================================================================
PAUSE
EXIT /B 0
