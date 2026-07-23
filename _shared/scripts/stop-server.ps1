# Stops a server cleanly and without drama:
#   1. Sends 'stop' via RCON (this SAVES the world properly).
#   2. Waits for the Java process to end on its own.
#   3. Closes the playit.gg tunnel if it was left open.
#
# Doesn't need to have been started from any particular window: it finds
# the running server by its port. You can run it by double-clicking
# "Stop Server.bat".
#
# Optional usage:  stop-server.ps1 -ServerPath "D:\...\servers\My Server"

param(
    [string]$ServerPath,   # a specific server's folder (optional)
    [switch]$KeepTunnel    # if passed, does NOT close the playit.gg tunnel
)

$ErrorActionPreference = "Stop"

# Load the shared RCON client.
. (Join-Path $PSScriptRoot "rcon.ps1")

# GameServers root (this script lives in _shared\scripts\).
$gsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# --- Discover all server instances (Game\servers\Instance\) ---
function Get-AllServerInstances {
    $result = @()
    Get-ChildItem -Path $gsRoot -Directory | Where-Object { $_.Name -ne "_shared" } | ForEach-Object {
        $serversDir = Join-Path $_.FullName "servers"
        if (Test-Path $serversDir) {
            Get-ChildItem -Path $serversDir -Directory | Where-Object { $_.Name -ne "_template" } | ForEach-Object {
                if (Test-Path (Join-Path $_.FullName "start-with-tunnel.ps1")) {
                    $result += [PSCustomObject]@{ Name = $_.Name; Path = $_.FullName }
                }
            }
        }
    }
    return $result
}

# Closes the playit.gg tunnel (shared process) if it's still open.
function Stop-Tunnel {
    if ($KeepTunnel) { return }
    $procs = Get-Process -Name "playit" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Closing the playit.gg tunnel..."
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# Stops ONE given server (object with .Name and .Path). Returns $true if it stopped it.
function Stop-OneServer {
    param($server)

    $propsPath = Join-Path $server.Path "server.properties"
    $props = Read-ServerProperties $propsPath

    $serverPort = 25565
    if ($props["server-port"]) { $serverPort = [int]$props["server-port"] }

    $rconOn = ($props["enable-rcon"] -eq "true")
    $rconPort = 25575
    if ($props["rcon.port"]) { $rconPort = [int]$props["rcon.port"] }
    $rconPass = $props["rcon.password"]

    Write-Host ""
    Write-Host "=== Stopping: $($server.Name) ==="

    # Java's PID (the one listening on the server's port) so we can wait for it to close.
    $javaPid = Get-ListenerPid -Port $serverPort

    if ($rconOn -and $rconPass) {
        try {
            Write-Host "Sending 'stop' via RCON (saving the world)..."
            Invoke-RconCommand -Port $rconPort -Password $rconPass -Command "stop" | Out-Null
        } catch {
            Write-Host "  Warning: could not use RCON ($($_.Exception.Message))."
            # Keep going anyway: the server might already be shutting down.
        }
    } else {
        Write-Host "  This server doesn't have RCON enabled, I can't stop it cleanly."
        Write-Host "  Type 'stop' in the server's window to save it properly,"
        Write-Host "  or have RCON enabled on it for next time."
        Stop-Tunnel
        return $false
    }

    # Wait for Java to finish on its own (saving 100+ mods can take a while).
    if ($javaPid) {
        Write-Host "Waiting for the server to finish saving and closing..."
        $waited = 0
        while ($waited -lt 90) {
            $p = Get-Process -Id $javaPid -ErrorAction SilentlyContinue
            if (-not $p) { break }
            Start-Sleep -Seconds 1
            $waited++
        }
        $p = Get-Process -Id $javaPid -ErrorAction SilentlyContinue
        if ($p) {
            Write-Host "  The server didn't close after 90s. Forcing it closed..."
            Stop-Process -Id $javaPid -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "  Server closed correctly."
        }
    } else {
        # We didn't know the PID; give it a moment for the 'stop' to take effect.
        Start-Sleep -Seconds 3
        Write-Host "  'stop' sent."
    }

    Stop-Tunnel
    return $true
}

# ---------------------------------------------------------------------------
# Choose what to stop.
# ---------------------------------------------------------------------------
if ($ServerPath) {
    if (-not (Test-Path $ServerPath)) {
        Write-Host "That folder doesn't exist: $ServerPath"
        exit 1
    }
    $target = [PSCustomObject]@{ Name = (Split-Path $ServerPath -Leaf); Path = $ServerPath }
    Stop-OneServer $target | Out-Null
    Write-Host ""
    exit 0
}

# No -ServerPath: detect which one(s) are running (by their RCON port).
$instances = Get-AllServerInstances
$running = @()
foreach ($inst in $instances) {
    $props = Read-ServerProperties (Join-Path $inst.Path "server.properties")
    if ($props["enable-rcon"] -eq "true") {
        $rp = 25575
        if ($props["rcon.port"]) { $rp = [int]$props["rcon.port"] }
        if (Test-PortOpen -Port $rp) {
            $running += $inst
        }
    }
}

if ($running.Count -eq 0) {
    Write-Host ""
    Write-Host "No server is running (nothing to stop)."
    # Just in case, close the tunnel if it was left hanging.
    Stop-Tunnel
    Write-Host ""
    exit 0
}

foreach ($srv in $running) {
    Stop-OneServer $srv | Out-Null
}
Write-Host ""
Write-Host "Done."
Write-Host ""
