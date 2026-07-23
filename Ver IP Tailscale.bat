@echo off
title Mi IP de Tailscale
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_shared\scripts\show-tailscale-address.ps1"
echo.
pause
