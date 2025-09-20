@echo off
:: 📡 DCS - Windows Device Check-in
:: Runs in loop every 5 minutes and sends heartbeat to NocoDB

:: === CONFIGURATION ===
set "NC_URL=https://<your-nocodb-domain>/api/v1/db/data/v1/DCS/device_checkins"
set "NC_API_KEY=<your_api_key>"

:loop
:: Hostname
for /f "tokens=*" %%i in ('hostname') do set DEVICE_HOSTNAME=%%i

:: Public IP (requires curl on Windows 10+)
for /f "delims=" %%i in ('curl -s https://ifconfig.me') do set PUBIP=%%i
if "%PUBIP%"=="" (
  set PUBIP=unknown
)

:: Date/Time in GMT+8
for /f "tokens=2 delims==" %%i in ('"wmic os get localdatetime /value"') do set ldt=%%i
set YYYY=%ldt:~0,4%
set MM=%ldt:~4,2%
set DD=%ldt:~6,2%
set HH=%ldt:~8,2%
set MIN=%ldt:~10,2%
set TS=%DD%-%MM%-%YYYY% %HH%:%MIN%

:: Send JSON
echo [%date% %time%] Sending check-in: %DEVICE_HOSTNAME% at %TS% (%PUBIP%)
curl -s -X POST "%NC_URL%" ^
  -H "xc-token: %NC_API_KEY%" ^
  -H "Content-Type: application/json" ^
  -d "{\"hostname\":\"%DEVICE_HOSTNAME%\",\"last_seen\":\"%TS%\",\"ip\":\"%PUBIP%\"}" > %TEMP%\dcs_last_response.log

:: Wait 5 minutes
timeout /t 300 /nobreak >nul
goto loop

