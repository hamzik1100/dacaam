@echo off
title DACAAM - Imtixaan
color 0A

echo.
echo  ==========================================
echo    DACAAM - server-ka la imtixaanayo
echo  ==========================================
echo.
echo  Waxay qaadan kartaa 1-2 daqiiqo.
echo  Database-ka maxalliga ah ayuu dib u dhisayaa
echo  imtixaan kasta ka hor - kan server-ka MA taabanayo.
echo.

set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=C:\Program Files (x86)\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not exist "%BASH%" (
  echo  Git Bash lama helin.
  echo  Ka soo dejiso: https://git-scm.com/download/win
  echo.
  pause
  exit /b 1
)

rem The folder this file is in, so moving the project cannot break it.
set "HERE=%~dp0"
set "HERE=%HERE:\=/%"

"%BASH%" "%HERE%test_server.sh"

echo.
echo  ==========================================
if errorlevel 1 (
  echo    WAA FASHILMAY - qoraalka kore akhri
  echo    HA DEPLOY GARAYN intaadan saxin.
) else (
  echo    WAA DHAMMAADAY - wax walba way shaqaynayaan
  echo    Hadda DEPLOY.bat ordi kartaa.
)
echo  ==========================================
echo.
pause
