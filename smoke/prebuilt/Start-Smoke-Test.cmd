@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Smoke-Test.ps1" -Action Launch %*
set "smokeExit=%ERRORLEVEL%"
if not "%smokeExit%"=="0" pause
exit /b %smokeExit%
