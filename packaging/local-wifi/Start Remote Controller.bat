@echo off
setlocal
cd /d "%~dp0"
title Remote Controller - Local Wi-Fi
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-local-wifi.ps1"
pause
