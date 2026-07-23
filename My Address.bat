@echo off
title My Server Address
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_shared\scripts\show-address.ps1"
echo.
pause
