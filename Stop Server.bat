@echo off
title Stop Server
echo Stopping the server safely (saving the world)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_shared\scripts\stop-server.ps1"
echo.
pause
