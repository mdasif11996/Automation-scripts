@echo off
setlocal enabledelayedexpansion

:: --- Generate timestamp ---
set "ts=%date:~6,4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "ts=!ts: =0!"  :: Remove any space (from hour like ' 9')

:: --- Prompt for connection details ---
set /p HOST=Enter PostgreSQL host (default: localhost): 
if "%HOST%"=="" set "HOST=localhost"

set /p PORT=Enter PostgreSQL port (default: 5432): 
if "%PORT%"=="" set "PORT=5432"

set /p USER=Enter PostgreSQL username (default: postgres): 
if "%USER%"=="" set "USER=postgres"

:: --- Secure password prompt using PowerShell ---
for /f "tokens=* usebackq" %%p in (`powershell -Command "$p = Read-Host 'Enter PostgreSQL password' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"`) do set "PASSWORD=%%p"

set /p DBNAME=Enter database name to restore: 

:: --- Choose file to restore ---
echo.
set /p DUMPFILE=Enter full path of .out or .dump file to restore: 
if not exist "%DUMPFILE%" (
    echo ERROR: File not found: %DUMPFILE%
    echo Restore aborted.
    goto end
)

:: --- Set PostgreSQL bin path (adjust version/path if needed) ---
set "PGBIN=C:\Program Files\PostgreSQL\16\bin"
set "PGPASSWORD=%PASSWORD%"


:: --- Prompt for log directory ---
set /p LOGDIR=Enter directory to store logs: 
if not exist "%LOGDIR%" (
    echo Directory not found: %LOGDIR%
    echo Creating directory...
    mkdir "%LOGDIR%"
    if errorlevel 1 (
        echo ERROR: Failed to create directory. Restore aborted.
        goto end
    )
)

:: --- Set log file paths with timestamp ---
set "LOGFILE=%LOGDIR%\restore_log_%ts%.log"
set "ERRORLOG=%LOGDIR%\restore_error_%ts%.log"

:: --- Check if database exists ---
echo.
echo Checking if database "%DBNAME%" exists...
"%PGBIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='%DBNAME%';" | findstr "1" >nul
if %errorlevel%==0 (
    echo Database "%DBNAME%" exists. 
    echo Terminating active sessions...
    "%PGBIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='%DBNAME%' AND pid <> pg_backend_pid();"

    echo Dropping existing database...
    "%PGBIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d postgres -c "DROP DATABASE IF EXISTS \"%DBNAME%\";"
) else (
    echo Database "%DBNAME%" does not exist, proceeding to create.
)

:: --- Create new database ---
echo Creating new database "%DBNAME%"...
"%PGBIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d postgres -c "CREATE DATABASE \"%DBNAME%\" WITH OWNER=\"%USER%\" ENCODING='UTF8' LC_COLLATE='en_US.utf8' LC_CTYPE='en_US.utf8' TEMPLATE=template0 CONNECTION LIMIT=-1;"
if %errorlevel% NEQ 0 (
    echo Failed to create database "%DBNAME%".
    goto end
)

echo.
echo Starting restore for file: %DUMPFILE%

:: --- Extract file extension safely ---
for %%F in ("%DUMPFILE%") do set "EXT=%%~xF"

:: --- Check extension ---
if /i not "%EXT%"==".out" if /i not "%EXT%"==".dump" (
    echo ERROR: Unsupported file type [%EXT%]. Only .out or .dump files are supported.
    goto end
)

:: --- Run pg_restore ---
echo Running pg_restore...
"%PGBIN%\pg_restore.exe" -h %HOST% -p %PORT% -U %USER% -d %DBNAME% -Fc -j 1 --verbose --no-owner --no-privileges "%DUMPFILE%" 1>"%LOGFILE%" 2>"%ERRORLOG%"

:: --- Check result ---
if %errorlevel% NEQ 0 (
    echo Restore FAILED. Check logs:
    echo     STDOUT: %LOGFILE%
    echo     STDERR: %ERRORLOG%
    goto end
)

echo Restore completed successfully.
echo     Log output saved to: %LOGFILE%
echo     Error log saved to: %ERRORLOG%

:end
endlocal
pause
