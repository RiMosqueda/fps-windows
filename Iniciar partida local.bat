@echo off
rem Servidor local + dos clientes en este PC (127.0.0.1:7777).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\depot.ps1" -Action session %*
if errorlevel 1 pause
