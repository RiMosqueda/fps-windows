@echo off
echo Direcciones IPv4 de este PC:
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { '   ' + $_.IPAddress + '   (' + $_.InterfaceAlias + ')' }"
echo.
set "DEPOT_IP="
set /p DEPOT_IP=Escribe la IPv4 de este PC en la red local y pulsa Enter: 
if "%DEPOT_IP%"=="" goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\depot.ps1" -Action server -Address %DEPOT_IP%
echo.
echo Los jugadores abren "Cliente.bat" y se conectan a %DEPOT_IP% puerto 7777.
echo Para cerrar el servidor: "Detener partida.bat"
pause
