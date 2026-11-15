@echo off
title DACAAM - Deploy
color 0E

echo.
echo  ==========================================
echo    DACAAM - server-ka wax loo dirayo
echo  ==========================================
echo.
echo  Password-ka server-ka ayuu ku weydiin doonaa.
echo  Markaad qorayso, waxba ma soo bixi doonaan - waa caadi.
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

"%BASH%" "%HERE%deploy.sh"

echo.
echo  ==========================================
if errorlevel 1 (
  echo    WAA FASHILMAY - qoraalka kore akhri
) else (
  echo    WAA DHAMMAADAY
  echo    App-ka ka bax oo dib u gal.
)
echo  ==========================================
echo.
pause
