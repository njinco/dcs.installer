@echo off
:: 📡 DCS - Windows Device Check-in
:: Runs in loop every 5 minutes and sends heartbeat to NocoDB

setlocal EnableExtensions EnableDelayedExpansion

:: === CONFIGURATION ===
set "NC_URL=https://<your-nocodb-domain>/api/v1/db/data/v1/DCS/device_checkins"
set "NC_API_KEY=<your_api_key>"

:loop
:: Hostname
for /f "tokens=*" %%i in ('hostname') do set "DEVICE_HOSTNAME=%%i"

:: Public IP (requires curl on Windows 10+)
set "PUBIP="
for %%S in (https://ifconfig.me https://api.ipify.org https://ipinfo.io/ip https://checkip.amazonaws.com https://icanhazip.com) do (
  if not defined PUBIP (
    for /f "delims=" %%i in ('curl -s --max-time 5 %%S 2^>nul') do set "PUBIP=%%i"
  )
)
if "%PUBIP%"=="" set "PUBIP=unknown"

:: Date/Time in GMT+8 (Asia/Manila)
set "TS="
set "TS_SOURCE="
for /f "delims=" %%i in ('powershell -NoProfile -Command "$tz = [TimeZoneInfo]::FindSystemTimeZoneById(''Singapore Standard Time''); [TimeZoneInfo]::ConvertTime((Get-Date), $tz).ToString(''dd-MM-yyyy HH:mm'')" 2^>nul') do set "TS=%%i"
if not "%TS%"=="" set "TS_SOURCE=PowerShell"
if "%TS%"=="" (
  set "ldt="
  where wmic >nul 2>&1 && for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value 2^>nul') do set "ldt=%%i"
  if not "%ldt%"=="" (
    set YYYY=%ldt:~0,4%
    set MM=%ldt:~4,2%
    set DD=%ldt:~6,2%
    set HH=%ldt:~8,2%
    set MIN=%ldt:~10,2%
    set TS=%DD%-%MM%-%YYYY% %HH%:%MIN%
    set "TS_SOURCE=WMIC"
  ) else (
    call :format_local_ts
  )
)

:: Send JSON
if /I "%TS_SOURCE%"=="LocalParse" echo [fallback] Using local date parser: %TS%
echo [%date% %time%] Sending check-in: %DEVICE_HOSTNAME% at %TS% (%PUBIP%)
curl -s -X POST "%NC_URL%" ^
  -H "xc-token: %NC_API_KEY%" ^
  -H "Content-Type: application/json" ^
  -d "{\"hostname\":\"%DEVICE_HOSTNAME%\",\"last_seen\":\"%TS%\",\"ip\":\"%PUBIP%\"}" > %TEMP%\dcs_last_response.log

:: Wait 5 minutes
timeout /t 300 /nobreak >nul
goto loop

:format_local_ts
set "date_str=%date%"
set "date_str=%date_str:,=%"
set "time_str=%time%"
set "time_str=%time_str: =0%"
set "HH=%time_str:~0,2%"
set "MIN=%time_str:~3,2%"
set "DD="
set "MM="
set "YYYY="
set "has_alpha="
set "TS_SOURCE=LocalParse"

echo !date_str!| findstr /r "[A-Za-z]" >nul && set "has_alpha=1"
if defined has_alpha (
  for /f "tokens=1-4 delims= " %%a in ("%date_str%") do (
    set "t1=%%a"
    set "t2=%%b"
    set "t3=%%c"
    set "t4=%%d"
  )
  call :month_to_num "!t3!" MM
  if defined MM (
    set "DD=!t2!"
    set "YYYY=!t4!"
  ) else (
    call :month_to_num "!t2!" MM
    if defined MM (
      set "DD=!t1!"
      set "YYYY=!t3!"
    )
  )
) else (
  for /f "tokens=1-3 delims=/.- " %%a in ("%date_str%") do (
    set "n1=%%a"
    set "n2=%%b"
    set "n3=%%c"
  )
  set /a n1v=1!n1! - 100
  set /a n2v=1!n2! - 100
  if !n1v! GTR 31 (
    set "YYYY=!n1!"
    set "MM=!n2!"
    set "DD=!n3!"
  ) else if !n1v! GTR 12 (
    set "DD=!n1!"
    set "MM=!n2!"
    set "YYYY=!n3!"
  ) else if !n2v! GTR 12 (
    set "DD=!n2!"
    set "MM=!n1!"
    set "YYYY=!n3!"
  ) else (
    set "DD=!n1!"
    set "MM=!n2!"
    set "YYYY=!n3!"
  )
)

if defined DD if defined MM if defined YYYY (
  set "DD=0!DD!"
  set "DD=!DD:~-2!"
  set "MM=0!MM!"
  set "MM=!MM:~-2!"
  set "HH=0!HH!"
  set "HH=!HH:~-2!"
  set "MIN=0!MIN!"
  set "MIN=!MIN:~-2!"
  set "TS=!DD!-!MM!-!YYYY! !HH!:!MIN!"
) else (
  set "TS=%date% %time%"
)
set "has_alpha="
goto :eof

:month_to_num
set "mon=%~1"
set "mon=!mon:~0,3!"
set "mon_num="
if /I "!mon!"=="Jan" set "mon_num=01"
if /I "!mon!"=="Feb" set "mon_num=02"
if /I "!mon!"=="Mar" set "mon_num=03"
if /I "!mon!"=="Apr" set "mon_num=04"
if /I "!mon!"=="May" set "mon_num=05"
if /I "!mon!"=="Jun" set "mon_num=06"
if /I "!mon!"=="Jul" set "mon_num=07"
if /I "!mon!"=="Aug" set "mon_num=08"
if /I "!mon!"=="Sep" set "mon_num=09"
if /I "!mon!"=="Oct" set "mon_num=10"
if /I "!mon!"=="Nov" set "mon_num=11"
if /I "!mon!"=="Dec" set "mon_num=12"
set "%~2=%mon_num%"
goto :eof
