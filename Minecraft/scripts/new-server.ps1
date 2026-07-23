# Creates a new server instance from the generic template.
# Usage: .\new-server.ps1 -Name "MyModpack"
# With a Modrinth modpack (auto-installs everything, RAM/Java get configured on their own):
#   .\new-server.ps1 -Name "MyModpack" -MrpackPath "C:\downloads\TheModpack.mrpack"
#   .\new-server.ps1 -Name "MyModpack" -MrpackPath "https://cdn.modrinth.com/.../TheModpack.mrpack"

param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    # Local path or URL to a .mrpack file (Modrinth). If passed, this script
    # installs the modpack on its own (mrpack.exe) and configures Java/RAM automatically.
    [string]$MrpackPath
)

$mcRoot = Split-Path -Parent $PSScriptRoot
$gsRoot = Split-Path -Parent $mcRoot
$template = Join-Path $mcRoot "servers\_template"
$dest = Join-Path $mcRoot "servers\$Name"
. (Join-Path $gsRoot "_shared\scripts\console-ui.ps1")

if (Test-Path $dest) {
    Write-Error "A server named '$Name' already exists at $dest"
    exit 1
}

Copy-Item -Recurse -Path $template -Destination $dest

# Pre-seed server.properties with RCON enabled and a random password OF ITS
# OWN for this server. Minecraft fills in the rest of the keys on first
# start and respects these. This way "Stop Server" works cleanly from day one.
$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$rconPass = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', ''

$propsPath = Join-Path $dest "server.properties"
@(
    "#Minecraft server properties (pre-configured by new-server.ps1)"
    "enable-rcon=true"
    "rcon.port=25575"
    "rcon.password=$rconPass"
) | Set-Content -Path $propsPath -Encoding ascii

Write-Host ""
Write-UiSuccess "Server '$Name' created at $dest"
Write-UiHint "RCON is enabled (for clean shutdowns via 'Stop Server')."

if (-not $MrpackPath) {
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Copy the modpack's (unzipped) 'Server Files' in there."
    Write-Host "  2. Edit run.config.ps1: the Java version the modpack needs, and RAM."
    Write-Host "  3. Read https://aka.ms/MinecraftEULA and, if you agree, set eula=true in eula.txt."
    Write-Host "  4. Run start-with-tunnel.ps1 to bring up the server + the playit.gg tunnel."
    return
}

# --- Automatic installation from a Modrinth modpack (.mrpack) ---
. (Join-Path $gsRoot "_shared\scripts\mrpack-helpers.ps1")

$mrpackExe = Join-Path $gsRoot "_shared\tools\mrpack.exe"
if (-not (Test-Path $mrpackExe)) {
    Write-Error "Could not find mrpack.exe at $mrpackExe"
    exit 1
}

$localMrpack = $MrpackPath
if ($MrpackPath -match '^https?://') {
    Write-Host ""
    Write-Host "Downloading the modpack..."
    $localMrpack = Join-Path $env:TEMP ("download-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    Invoke-WebRequest -Uri $MrpackPath -OutFile $localMrpack -UseBasicParsing
}
elseif (-not (Test-Path $MrpackPath)) {
    Write-Error "Could not find the .mrpack file at '$MrpackPath'."
    exit 1
}

$mcVersion = Get-MinecraftVersionFromMrpack -MrpackPath $localMrpack
$javaVersion = Get-JavaVersionForMinecraft -McVersion $mcVersion
$loader = Get-ModpackLoader -MrpackPath $localMrpack
Write-Host "Modpack for Minecraft $mcVersion ($loader) -> Java $javaVersion."

if ($loader -ne "fabric") {
    Remove-Item -Recurse -Force $dest
    Write-UiWarn "This modpack uses $loader, which can't be installed automatically yet."
    Write-UiHint "(Automatic installation currently only works with Fabric.)"
    Write-Host ""
    Write-Host "Follow the 'Manual option' in README.md: create the server without -MrpackPath"
    Write-Host "  (.\Minecraft\scripts\new-server.ps1 -Name ""$Name"") and copy in the"
    Write-Host "modpack's 'Server Files' (CurseForge, or the .mrpack exported by hand)."
    exit 1
}

Write-Host ""
Write-Host "Installing the modpack (mods, server jar, config)..."
& $mrpackExe $localMrpack --server-dir $dest
if ($LASTEXITCODE -ne 0) {
    Write-Error "mrpack.exe failed installing the modpack (code $LASTEXITCODE)."
    exit 1
}

$maxRam = Read-Host "Maximum memory for the server, e.g. 6G (Enter for 6G)"
if ([string]::IsNullOrWhiteSpace($maxRam)) { $maxRam = "6G" }
Set-RunConfigJavaAndRam -Path (Join-Path $dest "run.config.ps1") -JavaVersion $javaVersion -MaxRam $maxRam

Write-Host ""
Write-Host "==================================================================="
Write-Host " Before starting the server you need to accept the Minecraft EULA:"
Write-Host "   https://aka.ms/MinecraftEULA"
Write-Host "==================================================================="
$eulaAns = Read-Host "Type 'accept' if you've read it and agree"
if ($eulaAns -ne "accept") {
    Write-Host ""
    Write-Host "EULA not accepted. The server is installed but CANNOT start"
    Write-Host "until you manually set 'eula=true' in:"
    Write-Host "  $(Join-Path $dest 'eula.txt')"
    return
}
Set-Content -Path (Join-Path $dest "eula.txt") -Value "eula=true" -Encoding ascii

Write-Host ""
Write-UiSuccess "Done! '$Name' is installed and configured."
Write-UiHint "Start it from the menu (Start.bat) or with start-with-tunnel.ps1 in that folder."
