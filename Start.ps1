# Single menu to start any server (Minecraft and whatever gets added later).
# Auto-detects any <Game>\servers\<Instance>\ folder that has a
# start-with-tunnel.ps1, so adding a new game doesn't require touching this script.

$root = $PSScriptRoot
. (Join-Path $root "_shared\scripts\console-ui.ps1")

Write-UiBanner -Title "GAME SERVERS" -Subtitle "A tunnel to your PC so your friends can play with you"
Write-UiHint "Full guide (step by step, with fixes for common problems): README.md"

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
    Write-UiHint "No server created yet. Start with the option below."
}

Write-UiSection "Available servers"
for ($i = 0; $i -lt $instances.Count; $i++) {
    Write-UiMenuItem -Index $i -Label "$($instances[$i].Game) - $($instances[$i].Name)"
}
Write-UiMenuItem -Index $newServerChoice -Label "Create a new server (Modrinth modpack)" -Action
Write-Host ("  " + ("-" * 62)) -ForegroundColor DarkGray
Write-Host ""
Write-UiHint "When it starts, it'll show you (and copy to your clipboard) the"
Write-UiHint "address to send your friends."
Write-Host ""

$choice = Read-Host "Pick a number and press Enter"
if ($choice -notmatch '^\d+$' -or [int]$choice -gt $newServerChoice) {
    Write-Host "  Invalid choice." -ForegroundColor Red
    exit 1
}

if ([int]$choice -eq $newServerChoice) {
    $name = Read-Host "Name for the new server (e.g. MyModpack)"
    $mrpack = Read-Host "Path or URL to the .mrpack file (Enter to install it manually later)"
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
    Write-Host "  Could not find start-with-tunnel.ps1 at $($selected.Path)" -ForegroundColor Red
    exit 1
}

Write-UiSuccess "Starting $($selected.Game) - $($selected.Name)..."
Write-UiHint "(to stop it: double-click 'Stop Server.bat', or type 'stop' here)"
Write-Host ""
& $launcher
