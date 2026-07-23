# Menu unico para arrancar cualquier server (Minecraft y los que se vayan agregando).
# Detecta automaticamente cualquier carpeta <Juego>\servers\<Instancia>\ que tenga
# un start-with-tunnel.ps1, asi que agregar un juego nuevo no requiere tocar este script.

$root = $PSScriptRoot

$instances = @(
    Get-ChildItem -Path $root -Directory |
        Where-Object { $_.Name -ne "_shared" } |
        ForEach-Object {
            $game = $_.Name
            $serversDir = Join-Path $_.FullName "servers"
            if (Test-Path $serversDir) {
                Get-ChildItem -Path $serversDir -Directory |
                    Where-Object { $_.Name -ne "_template" } |
                    ForEach-Object {
                        [PSCustomObject]@{
                            Game = $game
                            Name = $_.Name
                            Path = $_.FullName
                        }
                    }
            }
        }
)

$newServerChoice = $instances.Count

if ($instances.Count -eq 0) {
    Write-Host ""
    Write-Host "No hay ningun server creado todavia."
}

Write-Host ""
Write-Host "===================== SERVERS DISPONIBLES ====================="
for ($i = 0; $i -lt $instances.Count; $i++) {
    Write-Host "  [$i] $($instances[$i].Game) - $($instances[$i].Name)"
}
Write-Host "  [$newServerChoice] Crear un server nuevo (Minecraft, desde un modpack de Modrinth)"
Write-Host "=============================================================="
Write-Host ""
Write-Host "Cuando arranque, te va a mostrar (y copiar al portapapeles) la"
Write-Host "direccion para pasarle a tus amigos."
Write-Host ""

$choice = Read-Host "Elegi un numero y apreta Enter"
if ($choice -notmatch '^\d+$' -or [int]$choice -gt $newServerChoice) {
    Write-Host "Opcion invalida."
    exit 1
}

if ([int]$choice -eq $newServerChoice) {
    $name = Read-Host "Nombre para el nuevo server (ej. MiModpack)"
    $mrpack = Read-Host "Ruta o URL del archivo .mrpack (Enter para instalarlo a mano despues)"
    $newServerScript = Join-Path $root "Minecraft\scripts\new-server.ps1"
    if ([string]::IsNullOrWhiteSpace($mrpack)) {
        & $newServerScript -Name $name
    }
    else {
        & $newServerScript -Name $name -MrpackPath $mrpack
    }
    exit 0
}

$selected = $instances[[int]$choice]
$launcher = Join-Path $selected.Path "start-with-tunnel.ps1"

if (-not (Test-Path $launcher)) {
    Write-Host "No encontre start-with-tunnel.ps1 en $($selected.Path)"
    exit 1
}

Write-Host ""
Write-Host "Arrancando $($selected.Game) - $($selected.Name)..."
Write-Host "(para apagarlo: doble click en 'Detener Server.bat', o escribi 'stop' aca)"
Write-Host ""
& $launcher
