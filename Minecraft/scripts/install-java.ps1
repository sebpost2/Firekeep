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

$ErrorActionPreference = "Stop"

$mcRoot = Split-Path -Parent $PSScriptRoot
$javaDir = Join-Path $mcRoot "tools\java\$MajorVersion"

if (Test-JavaWorks -JavaHome $javaDir) {
    Write-Host "Java $MajorVersion is already installed at $javaDir"
    exit 0
}
if (Test-Path $javaDir) {
    Write-Host "Java $MajorVersion at $javaDir doesn't run (broken or half-installed) - reinstalling it..."
}

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

$guid = [Guid]::NewGuid().ToString("N")
$zipPath = Join-Path $env:TEMP "jdk$MajorVersion-$guid.zip"
# Extracted next to the final folder (same drive), so the swap below is a
# rename: moving folders across drives (TEMP on C:, this on D:) can fail
# partway and leave a half-copied JDK behind.
$javaParent = Split-Path -Parent $javaDir
New-Item -ItemType Directory -Force -Path $javaParent | Out-Null
$extractTmp = Join-Path $javaParent ".extract-$MajorVersion-$guid"

try {
    Write-Host "Downloading Java $MajorVersion (Temurin/Adoptium)..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if (-not (Test-Sha256Checksum -Path $zipPath -ExpectedSha256 $expectedSha256)) {
        Write-Error "The download's checksum doesn't match the expected one. Installation aborted."
        exit 1
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

    # The zip has an inner folder like jdk-21.0.x+y; that folder becomes $javaDir.
    $inner = Get-ChildItem $extractTmp -Directory | Select-Object -First 1
    if (-not $inner -or -not (Test-JavaWorks -JavaHome $inner.FullName)) {
        Write-Error "The downloaded Java $MajorVersion doesn't run. Installation aborted."
        exit 1
    }

    if (Test-Path $javaDir) { Remove-Item -Recurse -Force $javaDir }
    Move-Item -Path $inner.FullName -Destination $javaDir
}
finally {
    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $extractTmp -ErrorAction SilentlyContinue
}

Write-Host "Java $MajorVersion installed at $javaDir"
