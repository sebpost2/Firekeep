# Downloads and installs (portable, no admin) a Temurin/Adoptium Java version
# inside GameServers\Minecraft\tools\java\<version>\
#
# Usage: .\install-java.ps1 -MajorVersion 21

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(8, 11, 17, 21)]
    [int]$MajorVersion
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "_shared\scripts\checksum-helpers.ps1")

$mcRoot = Split-Path -Parent $PSScriptRoot
$javaDir = Join-Path $mcRoot "tools\java\$MajorVersion"

if (Test-Path (Join-Path $javaDir "bin\java.exe")) {
    Write-Host "Java $MajorVersion is already installed at $javaDir"
    exit 0
}

New-Item -ItemType Directory -Force -Path $javaDir | Out-Null

# We ask for the official SHA256 checksum along with the download link, to
# verify the zip before installing it (avoids installing a corrupted or
# tampered file along the way).
$assetsUrl = "https://api.adoptium.net/v3/assets/latest/$MajorVersion/hotspot?os=windows&architecture=x64&image_type=jdk"
$asset = (Invoke-RestMethod -Uri $assetsUrl -UseBasicParsing) | Select-Object -First 1
$url = $asset.binary.package.link
$expectedSha256 = $asset.binary.package.checksum
if (-not $url -or -not $expectedSha256) {
    Write-Error "Could not get the link/checksum for Java $MajorVersion from Adoptium."
    exit 1
}

$zipPath = Join-Path $env:TEMP "jdk$MajorVersion.zip"

Write-Host "Downloading Java $MajorVersion (Temurin/Adoptium)..."
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

if (-not (Test-Sha256Checksum -Path $zipPath -ExpectedSha256 $expectedSha256)) {
    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
    Write-Error "The download's checksum doesn't match the expected one. Installation aborted."
    exit 1
}

$extractTmp = Join-Path $env:TEMP "jdk$MajorVersion-extract"
if (Test-Path $extractTmp) { Remove-Item -Recurse -Force $extractTmp }
Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

# The zip has an inner folder like jdk-21.0.x+y; we move its contents to the final destination.
$inner = Get-ChildItem $extractTmp | Select-Object -First 1
Get-ChildItem $inner.FullName | Move-Item -Destination $javaDir -Force

Remove-Item -Recurse -Force $extractTmp
Remove-Item -Force $zipPath

Write-Host "Java $MajorVersion installed at $javaDir"
