@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Smoke-Test.ps1" -Action Uninstall %*
set "smokeExit=%ERRORLEVEL%"
echo.
pause
exit /b %smokeExit%
