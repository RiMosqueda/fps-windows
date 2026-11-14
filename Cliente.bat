@echo off
rem Abre un cliente con el formulario de conexion (escribe la IP y el puerto del servidor).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\depot.ps1" -Action client
if errorlevel 1 pause
