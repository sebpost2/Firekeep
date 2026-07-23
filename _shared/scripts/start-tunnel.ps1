# Launches ONLY the playit.gg agent (without starting any server), shared
# between all the game servers. You normally don't need to run this by hand:
# the menu (Start.bat) already brings up the tunnel together with the server.
#
# Requires having run once before:  setup-playit.ps1  (links the account).

$toolDir = Join-Path $PSScriptRoot "..\tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"

if (-not (Test-Path $playitExe)) {
    Write-Error "Could not find playit.exe at $playitExe"
    exit 1
}

if (-not (Test-Path $secretFile)) {
    Write-Error "playit.gg is not configured. Run setup-playit.ps1 first."
    exit 1
}

$secret = (Get-Content $secretFile -Raw).Trim()
& $playitExe --secret $secret
