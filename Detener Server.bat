@echo off
title Detener Server
echo Deteniendo el server de forma segura (guardando el mundo)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_shared\scripts\stop-server.ps1"
echo.
pause
