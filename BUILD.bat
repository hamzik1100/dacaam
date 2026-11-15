@echo off
title DACAAM - APK
color 0B

echo.
echo  ==========================================
echo    DACAAM - APK-ga la dhisayo
echo  ==========================================
echo.
echo  Waxay qaadan kartaa 3-5 daqiiqo.
echo  Server-ka ayuu marka hore hubinayaa, kaddib
echo  imtixaanada, kaddibna APK-ga.
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

"%BASH%" "%HERE%build_apk.sh"

echo.
echo  ==========================================
if errorlevel 1 (
  echo    WAA FASHILMAY - qoraalka kore akhri
  echo    APK-gii hore HA QAYBIN.
) else (
  echo    WAA DHAMMAADAY
  echo    Faylka: %~dp0DACAAM.apk
)
echo  ==========================================
echo.
pause
