# Depot Tactical Prototype - lanzador para Windows (PowerShell 5.1+).
# Solo cierra los procesos que este script inició (PID + hora de inicio + ruta del ejecutable).
param(
    [ValidateSet('session', 'server', 'client', 'stop', 'status')]
    [string]$Action = 'session',
    [string]$Address = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$Port = 7777,
    # 0 = el límite de FPS guardado en la configuración del juego.
    [ValidateRange(0, 1000)][int]$Fps = 0
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $Root 'Depot\Depot.exe'
$Logs = Join-Path $Root 'Logs'
$RunFile = Join-Path $Logs 'session.json'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

function Read-Record {
    if (Test-Path $RunFile) { return Get-Content $RunFile -Raw | ConvertFrom-Json }
    return $null
}

function Get-Owned($item) {
    $process = Get-Process -Id $item.pid -ErrorAction SilentlyContinue
    if (-not $process) { return $null }
    try {
        if ($process.Path -ne $Exe) { return $null }
        if ($process.StartTime.ToFileTimeUtc() -ne [int64]$item.start) { return $null }
    } catch { return $null }
    return $process
}

function Stop-Record {
    $record = Read-Record
    if (-not $record) { return }
    foreach ($item in $record.processes) {
        $process = Get-Owned $item
        if (-not $process) { continue }
        # Clientes: cierre normal de ventana; servidor (sin ventana) o sin respuesta: forzado.
        [void]$process.CloseMainWindow()
        if (-not $process.WaitForExit(5000)) { $process.Kill() }
        Write-Host "Cerrado $($item.kind) pid=$($item.pid)"
    }
    Remove-Item $RunFile -ErrorAction SilentlyContinue
}

function Save-Record { $script:Record | ConvertTo-Json -Depth 4 | Set-Content -Path $RunFile -Encoding UTF8 }

function Start-Depot([string]$Kind, [string[]]$Arguments, [bool]$Track = $true) {
    $log = Join-Path $Logs "$($script:RunId)-$Kind.log"
    $all = $Arguments + @('-logFile', $log)
    $line = ($all | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $process = Start-Process -FilePath $Exe -ArgumentList $line -WorkingDirectory $Root -PassThru
    if ($Track) {
        $script:Record.processes += [pscustomobject]@{ kind = $Kind; pid = $process.Id; start = $process.StartTime.ToFileTimeUtc(); log = $log }
        Save-Record
    }
    Write-Host "$Kind pid=$($process.Id) log=$log"
    return $log
}

function Wait-Log([string]$Log, [string]$Text, [int]$Seconds = 30) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path $Log) -and (Select-String -Path $Log -Pattern $Text -SimpleMatch -Quiet)) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Tiempo agotado esperando '$Text'. Revisa $Log"
}

switch ($Action) {
    'stop' { Stop-Record; Write-Host 'Procesos propios cerrados.'; exit 0 }
    'status' {
        $record = Read-Record
        if (-not $record) { Write-Host 'Sin sesión registrada.'; exit 0 }
        foreach ($item in $record.processes) { Write-Host "$($item.kind) pid=$($item.pid) activo=$([bool](Get-Owned $item)) log=$($item.log)" }
        exit 0
    }
}

if (-not (Test-Path $Exe)) { Write-Host "ERROR: no se encuentra $Exe" -ForegroundColor Red; exit 1 }
$ip = $null
if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') {
    Write-Host "ERROR: '$Address' no es una dirección IPv4." -ForegroundColor Red; exit 1
}

$script:RunId = [guid]::NewGuid().ToString('N')
$common = @('--address', $Address, '--port', "$Port", '--run-id', $script:RunId)
if ($Fps -ge 15) { $common += @('--fps', "$Fps") }
$window = @('-screen-width', '1280', '-screen-height', '720', '-screen-fullscreen', '0')

if ($Action -eq 'client') {
    # Cliente suelto (por ejemplo, en el segundo PC): abre el formulario para escribir la IP del servidor.
    Start-Depot 'client' ($common + $window) $false | Out-Null
    exit 0
}

$existing = Read-Record
if ($existing -and ($existing.processes | Where-Object { Get-Owned $_ })) {
    Write-Host 'ERROR: ya hay una sesión activa. Ciérrala con "Detener partida.bat".' -ForegroundColor Red; exit 1
}
# Comprueba el puerto UDP antes de lanzar nada.
try {
    $probe = New-Object System.Net.Sockets.UdpClient (New-Object System.Net.IPEndPoint ($ip, $Port))
    $probe.Close()
} catch {
    Write-Host "ERROR: no se puede usar UDP ${Address}:$Port ($($_.Exception.Message))" -ForegroundColor Red; exit 1
}

$script:Record = [pscustomobject]@{ run_id = $script:RunId; processes = @() }
try {
    $serverLog = Start-Depot 'server' (@('-batchmode', '-nographics', '--server') + $common)
    Wait-Log $serverLog '[SERVER] READY'
    Write-Host "Servidor listo en UDP ${Address}:$Port"
    if ($Action -eq 'session') {
        Start-Depot 'client-1' (@('--connect') + $common + $window) | Out-Null
        Start-Depot 'client-2' (@('--connect') + $common + $window) | Out-Null
    }
    Write-Host 'Para cerrar: "Detener partida.bat"'
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Record
    exit 1
}
