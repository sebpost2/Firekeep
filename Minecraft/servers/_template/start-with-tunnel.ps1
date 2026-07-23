# Levanta el tunel de playit.gg en paralelo y despues arranca el server.
# Al cerrar el server (Ctrl+C o STOP), tambien cierra el tunel.

$serverName = Split-Path $PSScriptRoot -Leaf
$mcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gsRoot = Split-Path -Parent $mcRoot
$toolDir = Join-Path $gsRoot "_shared\tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"
$addrFile = Join-Path $toolDir "address.txt"

if (-not (Test-Path $playitExe)) {
    Write-Error "No se encontro playit.exe en $playitExe"
    exit 1
}

$tunnel = $null
$addr = $null
if (Test-Path $secretFile) {
    $secret = (Get-Content $secretFile -Raw).Trim()
    Write-Host "Iniciando tunel playit.gg..."
    $tunnel = Start-Process -FilePath $playitExe -ArgumentList "--secret", $secret -PassThru -WindowStyle Minimized

    # Leer la direccion publica actual desde playit (y cachearla en address.txt).
    try {
        $rd = Invoke-RestMethod -Uri "https://api.playit.gg/agents/rundata" -Method Post -Body "{}" `
            -Headers @{ Authorization = "Agent-Key $secret"; "Content-Type" = "application/json" } -TimeoutSec 15
        $mc = $rd.data.tunnels | Where-Object { $_.tunnel_type -eq "minecraft-java" -and $_.local_port -eq 25565 } | Select-Object -First 1
        if ($mc -and $mc.assigned_domain) {
            $addr = $mc.assigned_domain
            Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ascii
        }
    } catch { }
    if (-not $addr -and (Test-Path $addrFile)) { $addr = (Get-Content $addrFile -Raw).Trim() }
}
else {
    Write-Host "==================================================================="
    Write-Host " playit.gg todavia NO esta configurado (falta secret.key)."
    Write-Host " Para que amigos de otra red entren, corre UNA vez:"
    Write-Host "   powershell -ExecutionPolicy Bypass -File `"$gsRoot\_shared\scripts\setup-playit.ps1`""
    Write-Host " Por ahora arranco solo el server (sirve para la misma red/LAN)."
    Write-Host "==================================================================="
}

if ($addr) {
    Write-Host ""
    Write-Host "==================================================================="
    Write-Host "  DIRECCION PARA TUS AMIGOS  (Minecraft -> Multiplayer -> Add Server)"
    Write-Host ""
    Write-Host "      $addr"
    Write-Host ""
    Write-Host "  (misma WiFi que la laptop pueden usar tambien:  <IP-local>:25565)"
    Write-Host "==================================================================="
    Write-Host ""
    # Dejar la direccion visible en el titulo de la ventana mientras corre el server.
    $host.UI.RawUI.WindowTitle = "$serverName  |  $addr"
}

try {
    & (Join-Path $PSScriptRoot "start.ps1")
}
finally {
    # Cierre gracioso: si el server sigue vivo (apretaron Ctrl+C o cerraron la
    # ventana), mandarle 'stop' por RCON para que GUARDE el mundo antes de bajar
    # todo. Si ya se cerro solo (se escribio 'stop'), esto no hace nada.
    try {
        $rconMod = Join-Path $gsRoot "_shared\scripts\rcon.ps1"
        if (Test-Path $rconMod) {
            . $rconMod
            $props = Read-ServerProperties (Join-Path $PSScriptRoot "server.properties")
            $rp = 25575
            if ($props["rcon.port"]) { $rp = [int]$props["rcon.port"] }
            if ($props["enable-rcon"] -eq "true" -and $props["rcon.password"] -and (Test-PortOpen -Port $rp)) {
                Write-Host ""
                Write-Host "Guardando y deteniendo el server de forma segura..."
                $sp = 25565
                if ($props["server-port"]) { $sp = [int]$props["server-port"] }
                $javaPid = Get-ListenerPid -Port $sp
                try { Invoke-RconCommand -Port $rp -Password $props["rcon.password"] -Command "stop" | Out-Null } catch { }
                if ($javaPid) {
                    $w = 0
                    while ($w -lt 90) {
                        if (-not (Get-Process -Id $javaPid -ErrorAction SilentlyContinue)) { break }
                        Start-Sleep -Seconds 1
                        $w++
                    }
                }
            }
        }
    } catch { }

    if ($tunnel -and -not $tunnel.HasExited) {
        Write-Host "Cerrando tunel playit.gg..."
        Stop-Process -Id $tunnel.Id -Force
    }
}
