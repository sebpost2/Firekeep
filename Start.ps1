# Menu unico para arrancar cualquier server (Minecraft y los que se vayan agregando).
# Detecta automaticamente cualquier carpeta <Juego>\servers\<Instancia>\ que tenga
# un start-with-tunnel.ps1, asi que agregar un juego nuevo no requiere tocar este script.

$root = $PSScriptRoot
. (Join-Path $root "_shared\scripts\console-ui.ps1")

Write-UiBanner -Title "GAME SERVERS" -Subtitle "Tunel a tu PC para que tus amigos jueguen con vos"
Write-UiHint "Guia completa (paso a paso, con soluciones a problemas comunes): LEEME.md"

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
    Write-UiHint "No hay ningun server creado todavia. Empeza por la opcion de abajo."
}

Write-UiSection "Servers disponibles"
for ($i = 0; $i -lt $instances.Count; $i++) {
    Write-UiMenuItem -Index $i -Label "$($instances[$i].Game) - $($instances[$i].Name)"
}
Write-UiMenuItem -Index $newServerChoice -Label "Crear un server nuevo (modpack de Modrinth)" -Action
Write-Host ("  " + ("-" * 62)) -ForegroundColor DarkGray
Write-Host ""
Write-UiHint "Cuando arranque, te va a mostrar (y copiar al portapapeles) la"
Write-UiHint "direccion para pasarle a tus amigos."
Write-Host ""

$choice = Read-Host "Elegi un numero y apreta Enter"
if ($choice -notmatch '^\d+$' -or [int]$choice -gt $newServerChoice) {
    Write-Host "  Opcion invalida." -ForegroundColor Red
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
    Write-Host "  No encontre start-with-tunnel.ps1 en $($selected.Path)" -ForegroundColor Red
    exit 1
}

Write-UiSuccess "Arrancando $($selected.Game) - $($selected.Name)..."
Write-UiHint "(para apagarlo: doble click en 'Detener Server.bat', o escribi 'stop' aca)"
Write-Host ""
& $launcher
