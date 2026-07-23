# Crea una nueva instancia de server a partir de la plantilla generica.
# Uso: .\new-server.ps1 -Name "MiModpack"
# Con un modpack de Modrinth (autoinstala todo, RAM/Java quedan configurados solos):
#   .\new-server.ps1 -Name "MiModpack" -MrpackPath "C:\descargas\ElModpack.mrpack"
#   .\new-server.ps1 -Name "MiModpack" -MrpackPath "https://cdn.modrinth.com/.../ElModpack.mrpack"

param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    # Ruta local o URL a un archivo .mrpack (Modrinth). Si se pasa, este script
    # instala el modpack solo (mrpack.exe) y configura Java/RAM automaticamente.
    [string]$MrpackPath
)

$mcRoot = Split-Path -Parent $PSScriptRoot
$gsRoot = Split-Path -Parent $mcRoot
$template = Join-Path $mcRoot "servers\_template"
$dest = Join-Path $mcRoot "servers\$Name"
. (Join-Path $gsRoot "_shared\scripts\console-ui.ps1")

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
Write-UiSuccess "Server '$Name' creado en $dest"
Write-UiHint "RCON quedo activado (para el apagado limpio con 'Detener Server')."

if (-not $MrpackPath) {
    Write-Host ""
    Write-Host "Pasos siguientes:"
    Write-Host "  1. Copia ahi (descomprimidos) los 'Server Files' del modpack de CurseForge."
    Write-Host "  2. Edita run.config.ps1: version de Java que pide el modpack y RAM."
    Write-Host "  3. Lee https://aka.ms/MinecraftEULA y si aceptas, pon eula=true en eula.txt."
    Write-Host "  4. Corre start-with-tunnel.ps1 para levantar el server + el tunel de playit.gg."
    return
}

# --- Instalacion automatica desde un modpack de Modrinth (.mrpack) ---
. (Join-Path $gsRoot "_shared\scripts\mrpack-helpers.ps1")

$mrpackExe = Join-Path $gsRoot "_shared\tools\mrpack.exe"
if (-not (Test-Path $mrpackExe)) {
    Write-Error "No encontre mrpack.exe en $mrpackExe"
    exit 1
}

$localMrpack = $MrpackPath
if ($MrpackPath -match '^https?://') {
    Write-Host ""
    Write-Host "Descargando el modpack..."
    $localMrpack = Join-Path $env:TEMP ("descarga-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    Invoke-WebRequest -Uri $MrpackPath -OutFile $localMrpack -UseBasicParsing
}
elseif (-not (Test-Path $MrpackPath)) {
    Write-Error "No encontre el archivo .mrpack en '$MrpackPath'."
    exit 1
}

$mcVersion = Get-MinecraftVersionFromMrpack -MrpackPath $localMrpack
$javaVersion = Get-JavaVersionForMinecraft -McVersion $mcVersion
$loader = Get-ModpackLoader -MrpackPath $localMrpack
Write-Host "Modpack para Minecraft $mcVersion ($loader) -> Java $javaVersion."

if ($loader -ne "fabric") {
    Remove-Item -Recurse -Force $dest
    Write-UiWarn "Este modpack usa $loader, que todavia no se puede instalar solo."
    Write-UiHint "(La instalacion automatica por ahora solo funciona con Fabric.)"
    Write-Host ""
    Write-Host "Segui la 'Opcion manual' del LEEME.md: crea el server sin -MrpackPath"
    Write-Host "  (.\Minecraft\scripts\new-server.ps1 -Name ""$Name"") y copiale los"
    Write-Host "'Server Files' del modpack (CurseForge, o el .mrpack exportado a mano)."
    exit 1
}

Write-Host ""
Write-Host "Instalando el modpack (mods, server jar, config)..."
& $mrpackExe $localMrpack --server-dir $dest
if ($LASTEXITCODE -ne 0) {
    Write-Error "mrpack.exe fallo instalando el modpack (codigo $LASTEXITCODE)."
    exit 1
}

$maxRam = Read-Host "Memoria maxima para el server, ej. 6G (Enter para 6G)"
if ([string]::IsNullOrWhiteSpace($maxRam)) { $maxRam = "6G" }
Set-RunConfigJavaAndRam -Path (Join-Path $dest "run.config.ps1") -JavaVersion $javaVersion -MaxRam $maxRam

Write-Host ""
Write-Host "==================================================================="
Write-Host " Antes de arrancar el server tenes que aceptar la EULA de Minecraft:"
Write-Host "   https://aka.ms/MinecraftEULA"
Write-Host "==================================================================="
$eulaAns = Read-Host "Escribi 'acepto' si la leiste y estas de acuerdo"
if ($eulaAns -ne "acepto") {
    Write-Host ""
    Write-Host "No se acepto la EULA. El server quedo instalado pero NO puede arrancar"
    Write-Host "hasta que pongas 'eula=true' a mano en:"
    Write-Host "  $(Join-Path $dest 'eula.txt')"
    return
}
Set-Content -Path (Join-Path $dest "eula.txt") -Value "eula=true" -Encoding ascii

Write-Host ""
Write-UiSuccess "Listo! '$Name' quedo instalado y configurado."
Write-UiHint "Arrancalo desde el menu (Start.bat) o con start-with-tunnel.ps1 en esa carpeta."
