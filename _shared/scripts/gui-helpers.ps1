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

# Combines the live port check with the GUI's in-flight intent (a launch or
# stop it kicked off but hasn't confirmed yet) into one lifecycle state.
# "Pending" only holds while the port hasn't caught up yet; once it does, the
# transition settles to Running/Stopped, same as the old inline logic in
# Start-Gui.ps1, now testable on its own.
function Get-ServerLifecycleState {
    param(
        [Parameter(Mandatory = $true)][bool]$IsRunning,
        [Parameter(Mandatory = $true)][bool]$PendingStart,
        [Parameter(Mandatory = $true)][bool]$PendingStop
    )
    if ($PendingStart -and -not $IsRunning) { return "Starting" }
    if ($PendingStop -and $IsRunning) { return "Stopping" }
    if ($IsRunning) { return "Running" }
    return "Stopped"
}

# Window size for each in-window screen, so the shell window can resize
# itself to fit whichever screen is showing (Home/ManageMaps/AddServer share
# one Window now instead of each being its own popup).
function Get-ScreenSize {
    param(
        [Parameter(Mandatory = $true)][string]$Screen
    )
    switch ($Screen) {
        "Home"       { return [PSCustomObject]@{ Width = 420; Height = 660 } }
        "ManageMaps" { return [PSCustomObject]@{ Width = 440; Height = 580 } }
        "AddServer"  { return [PSCustomObject]@{ Width = 440; Height = 500 } }
        "Console"    { return [PSCustomObject]@{ Width = 560; Height = 640 } }
        default { throw "Unrecognized screen '$Screen'." }
    }
}

# Where the back arrow on a screen returns to. Flat two-level navigation -
# Home is the root and has no back target; everything else returns to Home.
function Get-BackTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Screen
    )
    switch ($Screen) {
        "Home"       { return $null }
        "ManageMaps" { return "Home" }
        "AddServer"  { return "Home" }
        "Console"    { return "Home" }
        default { throw "Unrecognized screen '$Screen'." }
    }
}

# Incrementally reads whatever's been appended to a log file since the last
# read, so the Console screen's log tail doesn't re-read (and re-render) the
# whole file every tick as it grows over a long session. If the offset is
# past the current length (file was rotated/truncated) or the file doesn't
# exist yet, it just starts over from the beginning.
function Get-LogTailChunk {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int64]$Offset
    )
    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{ Text = ""; Offset = 0 }
    }
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $startOffset = if ($Offset -gt $stream.Length) { 0 } else { $Offset }
            $stream.Seek($startOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
            $text = $reader.ReadToEnd()
            return [PSCustomObject]@{ Text = $text; Offset = $stream.Length }
        } finally {
            $stream.Close()
        }
    } catch {
        return [PSCustomObject]@{ Text = ""; Offset = $Offset }
    }
}

# Kills a process and everything it spawned (children first, so a hard kill
# of the launcher doesn't orphan the java/playit processes underneath it).
# Used to abort a server that's still starting (before RCON is even up, so
# there's no graceful "stop" command to send yet). I/O boundary, not unit
# tested, same convention as Test-PortOpen/Get-ListenerPid in rcon.ps1.
function Stop-ProcessTree {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId
    )
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId $child.ProcessId
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
