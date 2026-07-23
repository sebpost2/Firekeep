# Apaga un server de forma limpia y sin drama:
#   1. Le manda 'stop' por RCON (esto GUARDA el mundo correctamente).
#   2. Espera a que el proceso de Java termine solo.
#   3. Cierra el tunel de playit.gg si quedo abierto.
#
# No necesita que lo hayas arrancado desde una ventana en particular: encuentra
# el server que esta corriendo por su puerto. Podes correrlo con doble click
# desde "Detener Server.bat".
#
# Uso opcional:  stop-server.ps1 -ServerPath "D:\...\servers\Mi Server"

param(
    [string]$ServerPath,   # carpeta de un server puntual (opcional)
    [switch]$KeepTunnel    # si se pasa, NO cierra el tunel de playit.gg
)

$ErrorActionPreference = "Stop"

# Cargar el cliente RCON compartido.
. (Join-Path $PSScriptRoot "rcon.ps1")

# Raiz de GameServers (este script vive en _shared\scripts\).
$gsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# --- Descubrir todas las instancias de server (Juego\servers\Instancia\) ---
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

# Cierra el tunel de playit.gg (proceso compartido) si sigue abierto.
function Stop-Tunnel {
    if ($KeepTunnel) { return }
    $procs = Get-Process -Name "playit" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Cerrando el tunel de playit.gg..."
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# Detiene UN server dado (objeto con .Name y .Path). Devuelve $true si lo detuvo.
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
    Write-Host "=== Deteniendo: $($server.Name) ==="

    # PID de Java (el que escucha el puerto del server) para poder esperar a que cierre.
    $javaPid = Get-ListenerPid -Port $serverPort

    if ($rconOn -and $rconPass) {
        try {
            Write-Host "Enviando 'stop' por RCON (guardando el mundo)..."
            Invoke-RconCommand -Port $rconPort -Password $rconPass -Command "stop" | Out-Null
        } catch {
            Write-Host "  Aviso: no pude usar RCON ($($_.Exception.Message))."
            # Igual seguimos: puede que el server ya este cerrando.
        }
    } else {
        Write-Host "  Este server no tiene RCON activado, no puedo apagarlo de forma limpia."
        Write-Host "  Escribi 'stop' en la ventana del server para guardarlo bien,"
        Write-Host "  o pedime que le active RCON para la proxima."
        Stop-Tunnel
        return $false
    }

    # Esperar a que Java termine solo (guardar 130+ mods puede tardar).
    if ($javaPid) {
        Write-Host "Esperando a que el server termine de guardar y cerrar..."
        $waited = 0
        while ($waited -lt 90) {
            $p = Get-Process -Id $javaPid -ErrorAction SilentlyContinue
            if (-not $p) { break }
            Start-Sleep -Seconds 1
            $waited++
        }
        $p = Get-Process -Id $javaPid -ErrorAction SilentlyContinue
        if ($p) {
            Write-Host "  El server no cerro tras 90s. Forzando el cierre..."
            Stop-Process -Id $javaPid -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "  Server cerrado correctamente."
        }
    } else {
        # No sabiamos el PID; damos un margen para que el 'stop' haga efecto.
        Start-Sleep -Seconds 3
        Write-Host "  'stop' enviado."
    }

    Stop-Tunnel
    return $true
}

# ---------------------------------------------------------------------------
# Elegir que detener.
# ---------------------------------------------------------------------------
if ($ServerPath) {
    if (-not (Test-Path $ServerPath)) {
        Write-Host "No existe la carpeta: $ServerPath"
        exit 1
    }
    $target = [PSCustomObject]@{ Name = (Split-Path $ServerPath -Leaf); Path = $ServerPath }
    Stop-OneServer $target | Out-Null
    Write-Host ""
    exit 0
}

# Sin -ServerPath: detectar cual(es) estan corriendo (por su puerto RCON).
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
    Write-Host "No hay ningun server corriendo (nada que detener)."
    # Por las dudas, cerrar el tunel si quedo colgado.
    Stop-Tunnel
    Write-Host ""
    exit 0
}

foreach ($srv in $running) {
    Stop-OneServer $srv | Out-Null
}
Write-Host ""
Write-Host "Listo."
Write-Host ""
