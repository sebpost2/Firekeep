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

# Label + enabled state for the single action button, across the server's
# full lifecycle. Starting exposes Cancel (aborting a slow/stuck boot before
# RCON is even up); Stopping is disabled because a graceful RCON stop is
# already bounded (see stop-server.ps1) and shouldn't be interrupted mid-wait.
function Get-ActionButtonView {
    param(
        [Parameter(Mandatory = $true)][string]$State
    )
    switch ($State) {
        "Stopped" { return [PSCustomObject]@{ Label = "START SERVER"; IsEnabled = $true } }
        "Starting" { return [PSCustomObject]@{ Label = "CANCEL"; IsEnabled = $true } }
        "Running" { return [PSCustomObject]@{ Label = "STOP SERVER"; IsEnabled = $true } }
        "Stopping" { return [PSCustomObject]@{ Label = "STOPPING..."; IsEnabled = $false } }
        default { throw "Unrecognized server state '$State'." }
    }
}
