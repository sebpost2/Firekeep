# Pure logic behind the WPF launcher window (Start-Gui.ps1). Kept separate
# from the XAML/event-wiring so it can be unit tested without a UI.
# Loaded via dot-source.

# Scans <Root>\<Game>\servers\<Instance>\ for configured server instances,
# same discovery rule the console menu (Start.ps1) used. "_shared" is
# infrastructure, not a game; "_template" is the generic scaffold, not a
# real instance.
function Get-ServerInstances {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $result = @()
    Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "_shared" } |
        ForEach-Object {
            $game = $_.Name
            $serversDir = Join-Path $_.FullName "servers"
            if (Test-Path $serversDir) {
                Get-ChildItem -Path $serversDir -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne "_template" } |
                    ForEach-Object {
                        $result += [PSCustomObject]@{
                            Game = $game
                            Name = $_.Name
                            Path = $_.FullName
                        }
                    }
            }
        }
    return $result
}

# Maps running state to the campfire status display (the app's signature element).
function Get-ServerStatusView {
    param(
        [Parameter(Mandatory = $true)][bool]$IsRunning
    )
    if ($IsRunning) {
        return [PSCustomObject]@{ Label = "LIT"; ColorKey = "Online" }
    }
    return [PSCustomObject]@{ Label = "OUT"; ColorKey = "Offline" }
}

# Label for the single start/stop toggle button.
function Get-PrimaryActionLabel {
    param(
        [Parameter(Mandatory = $true)][bool]$IsRunning
    )
    if ($IsRunning) { return "STOP SERVER" }
    return "START SERVER"
}
