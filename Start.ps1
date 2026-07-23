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

if ($instances.Count -eq 0) {
    Write-Host ""
    Write-Host "No hay ningun server creado todavia."
    Write-Host ""
    Write-Host "Para crear uno de Minecraft:"
    Write-Host "  .\Minecraft\scripts\new-server.ps1 -Name ""NombreDelModpack"""
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "===================== SERVERS DISPONIBLES ====================="
for ($i = 0; $i -lt $instances.Count; $i++) {
    Write-Host "  [$i] $($instances[$i].Game) - $($instances[$i].Name)"
}
Write-Host "=============================================================="
Write-Host ""
Write-Host "Cuando arranque, te va a mostrar (y copiar al portapapeles) la"
Write-Host "direccion para pasarle a tus amigos."
Write-Host ""

$choice = Read-Host "Elegi un numero y apreta Enter"
if ($choice -notmatch '^\d+$' -or [int]$choice -ge $instances.Count) {
    Write-Host "Opcion invalida."
    exit 1
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
