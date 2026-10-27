@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Smoke-Test.ps1" -Action Install %*
set "smokeExit=%ERRORLEVEL%"
echo.
pause
exit /b %smokeExit%
