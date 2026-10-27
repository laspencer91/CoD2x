@echo off
python "%~dp0bake.py" %*
set "smokeExit=%ERRORLEVEL%"
if not "%smokeExit%"=="0" pause
exit /b %smokeExit%
