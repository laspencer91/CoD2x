@echo off
title ProSmoke
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1" -Action Undo %*
echo.
pause
