# Brings up the playit.gg tunnel in parallel and then starts the server.
# When the server closes (Ctrl+C or STOP), it also closes the tunnel.

$serverName = Split-Path $PSScriptRoot -Leaf
$mcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gsRoot = Split-Path -Parent $mcRoot

. (Join-Path $gsRoot "_shared\scripts\verity-helpers.ps1")
if (Test-VerityModPresent -InstancePath $PSScriptRoot) {
    Write-Host "Verity mod detected - making sure the local AI stack (Ollama/Kokoro/Whisper) is up..."
    try {
        Start-VerityLocalAiStack -McRoot $mcRoot
    } catch {
        Write-Warning "Local AI stack didn't come up ($_) - starting the server anyway; Verity will fall back to its configured cloud provider."
    }
}

$toolDir = Join-Path $gsRoot "_shared\tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"
$addrFile = Join-Path $toolDir "address.txt"

if (-not (Test-Path $playitExe)) {
    Write-Error "Could not find playit.exe at $playitExe"
    exit 1
}

$tunnel = $null
$addr = $null
if (Test-Path $secretFile) {
    $secret = (Get-Content $secretFile -Raw).Trim()
    Write-Host "Starting the playit.gg tunnel..."
    $tunnel = Start-Process -FilePath $playitExe -ArgumentList "--secret", $secret -PassThru -WindowStyle Minimized

    # Read the current public address from playit (and cache it in address.txt).
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
    Write-Host " playit.gg is NOT configured yet (missing secret.key)."
    Write-Host " For friends on another network to join, run this ONCE:"
    Write-Host "   powershell -ExecutionPolicy Bypass -File `"$gsRoot\_shared\scripts\setup-playit.ps1`""
    Write-Host " For now, starting just the server (works for the same network/LAN)."
    Write-Host "==================================================================="
}

if ($addr) {
    Write-Host ""
    Write-Host "==================================================================="
    Write-Host "  ADDRESS FOR YOUR FRIENDS  (Minecraft -> Multiplayer -> Add Server)"
    Write-Host ""
    Write-Host "      $addr"
    Write-Host ""
    Write-Host "  (same WiFi as this PC can also use:  <local-IP>:25565)"
    Write-Host "==================================================================="
    Write-Host ""
    # Keep the address visible in the window title while the server is running.
    $host.UI.RawUI.WindowTitle = "$serverName  |  $addr"
}

try {
    & (Join-Path $PSScriptRoot "start.ps1")
}
finally {
    # Graceful shutdown: if the server is still alive (Ctrl+C or the window
    # was closed), send it 'stop' via RCON so it SAVES the world before
    # everything goes down. If it already closed on its own ('stop' was
    # typed), this does nothing.
    try {
        $rconMod = Join-Path $gsRoot "_shared\scripts\rcon.ps1"
        if (Test-Path $rconMod) {
            . $rconMod
            $props = Read-ServerProperties (Join-Path $PSScriptRoot "server.properties")
            $rp = 25575
            if ($props["rcon.port"]) { $rp = [int]$props["rcon.port"] }
            if ($props["enable-rcon"] -eq "true" -and $props["rcon.password"] -and (Test-PortOpen -Port $rp)) {
                Write-Host ""
                Write-Host "Saving and stopping the server safely..."
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
        Write-Host "Closing the playit.gg tunnel..."
        Stop-Process -Id $tunnel.Id -Force
    }
}
