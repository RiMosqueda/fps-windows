@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\depot.ps1" -Action stop
timeout /t 3 >nul
