@echo off
setlocal
cd /d "%~dp0"
title OpenHostLink
set "LAUNCHER=%~dp0OpenHostLinkHost\start-local-wifi.ps1"
if not exist "%LAUNCHER%" set "LAUNCHER=%~dp0start-local-wifi.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
pause
