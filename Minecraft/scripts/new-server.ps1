# Crea una nueva instancia de server a partir de la plantilla generica.
# Uso: .\new-server.ps1 -Name "MiModpack"

param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$mcRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $mcRoot "servers\_template"
$dest = Join-Path $mcRoot "servers\$Name"

if (Test-Path $dest) {
    Write-Error "Ya existe un server llamado '$Name' en $dest"
    exit 1
}

Copy-Item -Recurse -Path $template -Destination $dest

# Pre-sembrar server.properties con RCON activado y una contraseña aleatoria PROPIA
# de este server. Minecraft completa el resto de las claves al primer arranque y
# respeta estas. Asi el "Detener Server" funciona limpio desde el dia uno.
$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$rconPass = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', ''

$propsPath = Join-Path $dest "server.properties"
@(
    "#Minecraft server properties (pre-configurado por new-server.ps1)"
    "enable-rcon=true"
    "rcon.port=25575"
    "rcon.password=$rconPass"
) | Set-Content -Path $propsPath -Encoding ascii

Write-Host ""
Write-Host "Server '$Name' creado en $dest"
Write-Host "RCON quedo activado (para el apagado limpio con 'Detener Server')."
Write-Host ""
Write-Host "Pasos siguientes:"
Write-Host "  1. Copia ahi (descomprimidos) los 'Server Files' del modpack de CurseForge."
Write-Host "  2. Edita run.config.ps1: version de Java que pide el modpack y RAM."
Write-Host "  3. Lee https://aka.ms/MinecraftEULA y si aceptas, pon eula=true en eula.txt."
Write-Host "  4. Corre start-with-tunnel.ps1 para levantar el server + el tunel de playit.gg."
