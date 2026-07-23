# Descarga e instala (portable, sin admin) una version de Java Temurin/Adoptium
# dentro de GameServers\Minecraft\tools\java\<version>\
#
# Uso: .\install-java.ps1 -MajorVersion 21

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(8, 11, 17, 21)]
    [int]$MajorVersion
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "_shared\scripts\checksum-helpers.ps1")

$mcRoot = Split-Path -Parent $PSScriptRoot
$javaDir = Join-Path $mcRoot "tools\java\$MajorVersion"

if (Test-Path (Join-Path $javaDir "bin\java.exe")) {
    Write-Host "Java $MajorVersion ya esta instalado en $javaDir"
    exit 0
}

New-Item -ItemType Directory -Force -Path $javaDir | Out-Null

# Pedimos el checksum SHA256 oficial junto con el link de descarga, para
# verificar el zip antes de instalarlo (evita instalar un archivo corrupto o
# alterado en el camino).
$assetsUrl = "https://api.adoptium.net/v3/assets/latest/$MajorVersion/hotspot?os=windows&architecture=x64&image_type=jdk"
$asset = (Invoke-RestMethod -Uri $assetsUrl -UseBasicParsing) | Select-Object -First 1
$url = $asset.binary.package.link
$expectedSha256 = $asset.binary.package.checksum
if (-not $url -or -not $expectedSha256) {
    Write-Error "No pude obtener el link/checksum de Java $MajorVersion desde Adoptium."
    exit 1
}

$zipPath = Join-Path $env:TEMP "jdk$MajorVersion.zip"

Write-Host "Descargando Java $MajorVersion (Temurin/Adoptium)..."
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

if (-not (Test-Sha256Checksum -Path $zipPath -ExpectedSha256 $expectedSha256)) {
    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
    Write-Error "El checksum de la descarga no coincide con el esperado. Se aborto la instalacion."
    exit 1
}

$extractTmp = Join-Path $env:TEMP "jdk$MajorVersion-extract"
if (Test-Path $extractTmp) { Remove-Item -Recurse -Force $extractTmp }
Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

# El zip trae una carpeta interna tipo jdk-21.0.x+y; movemos su contenido al destino final.
$inner = Get-ChildItem $extractTmp | Select-Object -First 1
Get-ChildItem $inner.FullName | Move-Item -Destination $javaDir -Force

Remove-Item -Recurse -Force $extractTmp
Remove-Item -Force $zipPath

Write-Host "Java $MajorVersion instalado en $javaDir"
