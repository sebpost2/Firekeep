@echo off
title Mi Direccion de Server
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_shared\scripts\show-address.ps1"
echo.
pause
