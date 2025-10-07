@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: PostgreSQL Enterprise Installation Script (PRODUCTION READY)
:: ============================================================

:: ---------------------------
:: Check for Administrator
:: ---------------------------
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo This script must be run as Administrator.
    pause
    exit /b 1
)

echo ================================================================
echo PostgreSQL Enterprise Installation Script
echo ================================================================

:: ---------------------------
:: Collect Inputs
:: ---------------------------
set "installer="
set /p "installer=Enter full path of installer (e.g. C:\Installers\postgresql-17.6-1-windows-x64.exe): "
if not exist "!installer!" (
    echo Error: Installer path "!installer!" not found.
    pause
    exit /b 1
)

set "installdir="
set /p "installdir=Enter installation directory (e.g. D:\PostgreSQL\17): "
if "!installdir!"=="" set "installdir=C:\PostgreSQL\17"

set "datadir="
set /p "datadir=Enter DATA directory (e.g. D:\PGDATA): "
if "!datadir!"=="" set "datadir=C:\PGDATA"

set "waldir="
set /p "waldir=Enter WAL directory (e.g. E:\PGWAL): "
if "!waldir!"=="" set "waldir=!datadir!\pg_wal"

set "logdir="
set /p "logdir=Enter LOGS directory (e.g. F:\PGLOGS): "
if "!logdir!"=="" set "logdir=C:\PGLOGS"

set "backupdir="
set /p "backupdir=Enter BACKUP directory (e.g. G:\PGBACKUP): "
if "!backupdir!"=="" set "backupdir=C:\PGBACKUP"

:: Secure password input for postgres superuser
for /f "delims=" %%p in ('powershell -NoProfile -Command "$pword = Read-Host ''Enter postgres superuser password'' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pword))"') do set "pgpassword=%%p"
if "!pgpassword!"=="" (
    echo Error: Password cannot be empty.
    pause
    exit /b 1
)

set "servicename="
set /p "servicename=Enter PostgreSQL service name (e.g. PostgreSQL17): "
if "!servicename!"=="" set "servicename=PostgreSQL"

:: ---------------------------
:: Safe numeric input for port
:: ---------------------------
:PORT_INPUT
set "port="
set /p "port=Enter PostgreSQL port (default 5432): "
if "%port%"=="" (
    set "port=5432"
    set "port_num=5432"
) else (
    set "port_num=0"
    set /a port_num=!port! 2>nul
)
if !port_num! LEQ 0 (
    echo Invalid port. Must be between 1 and 65535.
    goto :PORT_INPUT
)
if !port_num! GTR 65535 (
    echo Invalid port. Must be between 1 and 65535.
    goto :PORT_INPUT
)

:: Database encoding
set "encoding="
set /p "encoding=Enter database encoding (default UTF8): "
if "%encoding%"=="" set "encoding=UTF8"

:: Detect system locale
for /f "delims=" %%L in ('powershell -NoProfile -Command "(Get-Culture).Name"') do set "default_locale=%%L"
set /p "locale=Enter locale / collation (default !default_locale!): "
if "%locale%"=="" set "locale=!default_locale!"
echo Locale set to '!locale!'.

:: ---------------------------
:: Detect CPU cores
:: ---------------------------
set "cores=0"
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfLogicalProcessors /value ^| find "="') do (
    set "cores=%%a"
)
set "cores=!cores: =!"
if "!cores!"=="" set "cores=2"
echo Detected CPU Cores: !cores!

:: ---------------------------
:: Detect RAM in MB
:: ---------------------------
set "mem=0"
for /f "tokens=2 delims==" %%a in ('wmic computersystem get TotalPhysicalMemory /value ^| find "="') do (
    set "mem=%%a"
)
set "mem=!mem: =!"
if "!mem!"=="" set "mem=4294967296"
for /f %%a in ('powershell -NoProfile -Command "[math]::Floor(%mem%/1MB)"') do set "ramMB=%%a"
if "!ramMB!"=="" set "ramMB=4096"
set /a ramGB=!ramMB!/1024
echo Detected RAM: !ramGB! GB (!ramMB! MB)

:: ---------------------------
:: PostgreSQL Tuning via PowerShell
:: ---------------------------
for /f "delims=" %%a in ('powershell -NoProfile -Command "$ramMB=!ramMB!;$ramGB=!ramGB!;$shared=[math]::Floor($ramMB/4);$cache=[math]::Floor($ramMB*3/4);$maxconn=if($ramGB -lt 4){100}else{200};$work=[math]::Min([math]::Floor($ramMB*1024/(2*$maxconn)),65536);$maint=[math]::Min([math]::Floor($ramMB/20),2048);$wal=[math]::Min([math]::Floor($shared/32),16);$maxwal=[math]::Max([math]::Floor($ramMB/4),1024);$minwal=[math]::Floor($maxwal/4);Write-Output ($shared,$cache,$maxconn,$work,$maint,$wal,$maxwal,$minwal -join ',')"') do set "tunings=%%a"

for /f "tokens=1-8 delims=," %%i in ("!tunings!") do (
    set "shared_buffersMB=%%i"
    set "effective_cacheMB=%%j"
    set "max_connections=%%k"
    set "work_memKB=%%l"
    set "maintenanceMB=%%m"
    set "walbufMB=%%n"
    set "maxwalMB=%%o"
    set "minwalMB=%%p"
)

echo.
echo Recommended Tuning Calculated Successfully:
echo shared_buffers       = !shared_buffersMB! MB
echo effective_cache_size = !effective_cacheMB! MB
echo work_mem             = !work_memKB! kB
echo maintenance_work_mem = !maintenanceMB! MB
echo max_connections      = !max_connections!
echo wal_buffers          = !walbufMB! MB
echo max_wal_size         = !maxwalMB! MB
echo min_wal_size         = !minwalMB! MB
echo.

:: ---------------------------
:: Prompt WAL archiving
:: ---------------------------
:WAL_INPUT
set "enable_wal="
set /p "enable_wal=Enable WAL archiving? (yes/no, default yes): "
if "%enable_wal%"=="" set "enable_wal=yes"
set "enable_wal_input=!enable_wal:~0,1!"
if /i "!enable_wal_input!"=="y" (
    set "enable_wal=yes"
) else if /i "!enable_wal_input!"=="n" (
    set "enable_wal=no"
) else (
    echo Invalid input. Please enter yes or no.
    goto :WAL_INPUT
)

:: ---------------------------
:: Prompt Log Retention
:: ---------------------------
:LOG_RETENTION_INPUT
set "log_retention_days="
set /p "log_retention_days=Enter log retention in days (default 30): "
if "%log_retention_days%"=="" (
    set "log_retention_days=30"
    set "is_valid=1"
) else (
    set "is_valid=0"
    set /a testvar=!log_retention_days! 2>nul
    if !testvar! GEQ 0 (
        for /f "tokens=*" %%x in ("!log_retention_days!") do (
            if "%%x"=="!testvar!" set "is_valid=1"
        )
    )
)
if !is_valid! NEQ 1 (
    echo Invalid input. Please enter a valid number.
    goto :LOG_RETENTION_INPUT
)

:: ---------------------------
:: Confirm Inputs
:: ---------------------------
echo.
echo ================================================================
echo Please confirm your inputs:
echo Installer Path  : !installer!
echo Install Dir     : !installdir!
echo Data Dir        : !datadir!
echo WAL Dir         : !waldir!
echo Logs Dir        : !logdir!
echo Backup Dir      : !backupdir!
echo Service Name    : !servicename!
echo Port            : !port!
echo Encoding        : !encoding!
echo Locale          : !locale!
echo Enable WAL Arch : !enable_wal!
echo Log Retention   : !log_retention_days! days
echo ================================================================
set /p "confirm=Proceed with installation? (yes/no): "
if /i not "!confirm!"=="yes" (
    echo Installation cancelled.
    pause
    exit /b 1
)

:: ---------------------------
:: Create Directories
:: ---------------------------
for %%d in ("!installdir!" "!datadir!" "!waldir!" "!logdir!" "!backupdir!") do (
    if not exist "%%~d" mkdir "%%~d"
)

:: ---------------------------
:: Run Installer
:: ---------------------------
echo Running installer...
"!installer!" --mode unattended --unattendedmodeui minimal ^
  --prefix "!installdir!" ^
  --datadir "!datadir!" ^
  --superpassword "!pgpassword!" ^
  --serverport !port! ^
  --servicename "!servicename!" ^
  --locale "!locale!" ^
  --enable-components "server,pgAdmin,commandlinetools"
if !errorlevel! NEQ 0 (
    echo Error: PostgreSQL installation failed.
    pause
    exit /b 1
)

:: ---------------------------
:: Update postgresql.conf
:: ---------------------------
set "pgconf=!datadir!\postgresql.conf"

echo Updating postgresql.conf with tuning parameters...
powershell -Command ^
  "$conf='!pgconf!'; " ^
  "$params=@{ " ^
  "'shared_buffers'='!shared_buffersMB!MB'; " ^
  "'effective_cache_size'='!effective_cacheMB!MB'; " ^
  "'work_mem'='!work_memKB!kB'; " ^
  "'maintenance_work_mem'='!maintenanceMB!MB'; " ^
  "'max_connections'='!max_connections!'; " ^
  "'wal_buffers'='!walbufMB!MB'; " ^
  "'max_wal_size'='!maxwalMB!MB'; " ^
  "'min_wal_size'='!minwalMB!MB'; " ^
  "'logging_collector'='on'; " ^
  "'log_directory'='!logdir!'; " ^
  "'log_filename'='postgresql-%%%%Y-%%%%m-%%%%d_%%%%H%%%%M%%%%S.log'; " ^
  "'log_truncate_on_rotation'='on'; " ^
  "'log_rotation_age'='1d'; " ^
  "}; " ^
  "if ('!enable_wal!' -eq 'yes') { " ^
  "  $params['wal_level']='replica'; " ^
  "  $params['archive_mode']='on'; " ^
  "  $params['archive_command']='copy \"%%p\" \"!waldir!\\%%f\"'; " ^
  "} " ^
  "foreach ($k in $params.Keys) { " ^
  " if ((Select-String -Path $conf -Pattern ('^' + $k)).Count -gt 0) { " ^
  "   (Get-Content $conf) -replace ('^' + $k + '.*'), ($k + ' = ' + $params[$k]) | Set-Content $conf " ^
  " } else { " ^
  "   Add-Content $conf ('`n' + $k + ' = ' + $params[$k]) " ^
  " } " ^
  "}"

:: ---------------------------
:: Restart PostgreSQL Service
:: ---------------------------
sc query "!servicename!" >nul 2>&1
if !errorlevel! NEQ 0 (
    echo Service !servicename! not found. Skipping restart.
) else (
    echo Stopping service...
    net stop "!servicename!"
    echo Starting service...
    net start "!servicename!"
)

:: ---------------------------
:: Optional: Create additional DB user
:: ---------------------------
set /p username=Enter database username to create (leave blank to skip): 
if not "!username!"=="" (
    for /f "delims=" %%p in ('powershell -NoProfile -Command "$pword = Read-Host ''Enter password for user %username%'' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pword))"') do set "userpass=%%p"
    echo Creating PostgreSQL user "!username!"...
    "!installdir!\bin\psql.exe" -U postgres -p !port! -h localhost -d postgres -c "CREATE USER \"!username!\" WITH PASSWORD '!userpass!';"
    if !errorlevel! NEQ 0 (
        echo [WARNING] Failed to create user "!username!".
    ) else (
        echo User "!username!" created successfully.
    )
)

:: ---------------------------
:: Final Display
:: ---------------------------
echo ================================================================
echo PostgreSQL !servicename! Enterprise Installation Complete
echo DataDir           : !datadir!
echo WALDir            : !waldir!
echo Logs              : !logdir!
echo Backup            : !backupdir!
echo Service           : !servicename!
echo Port              : !port!
echo Encoding          : !encoding!
echo Locale            : !locale!
echo Enable WAL Arch   : !enable_wal!
echo Log Retention     : !log_retention_days! days
echo ================================================================
pause
endlocal
