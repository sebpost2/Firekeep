# GUI launcher (replaces the console menu). Double-click Start.bat to run this.
# Shows one window: pick a server, see if it's lit (running) or out (stopped),
# start/stop/cancel it with one button, copy the address for friends.
# Closing the window also stops the server, so it never keeps running
# invisibly in the background after you've closed the app.
#
# The actual server/tunnel logic is unchanged (start-with-tunnel.ps1,
# stop-server.ps1, rcon.ps1): this window launches them in the background and
# polls the RCON port to reflect real state, instead of blocking on them.

$root = $PSScriptRoot
. (Join-Path $root "_shared\scripts\gui-helpers.ps1")
. (Join-Path $root "_shared\scripts\rcon.ps1")
. (Join-Path $root "_shared\scripts\tunnel-helpers.ps1")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:instances = @(Get-ServerInstances -Root $root)

[xml]$xamlXml = Get-Content -Path (Join-Path $root "_shared\gui\MainWindow.xaml") -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))

$serverCombo      = $window.FindName("ServerCombo")
$fireIcon         = $window.FindName("FireIcon")
$statusLabel      = $window.FindName("StatusLabel")
$addressText      = $window.FindName("AddressText")
$copyButton       = $window.FindName("CopyButton")
$actionButton     = $window.FindName("ActionButton")
$hintText         = $window.FindName("HintText")
$mapsButton       = $window.FindName("MapsButton")
$newServerButton  = $window.FindName("NewServerButton")
$setupTunnelButton = $window.FindName("SetupTunnelButton")

$script:selected        = $null
$script:pendingStart    = $false
$script:pendingStop     = $false
$script:launchedProcess = $null  # the start-with-tunnel.ps1 wrapper process, for Cancel
$script:closingApp      = $false # true once Window.Closing has taken over to stop the server
$script:okToClose       = $false # set right before we let the real close happen

# (Re)builds the server picker from $script:instances. Used at startup and
# after "New Server" creates one, so the new server shows up without a
# restart. Keeps the previously selected instance selected when possible.
function Refresh-ServerList {
    param([string]$PreferName)

    $serverCombo.Items.Clear()
    foreach ($i in $script:instances) { $serverCombo.Items.Add("$($i.Game) - $($i.Name)") | Out-Null }

    $hasServers = $script:instances.Count -gt 0
    $mapsButton.IsEnabled = $hasServers
    $serverCombo.IsEnabled = $hasServers
    $actionButton.IsEnabled = $hasServers

    if (-not $hasServers) {
        $script:selected = $null
        $statusLabel.Text = "---"
        $fireIcon.Opacity = 0.25
        $addressText.Text = "-"
        $copyButton.IsEnabled = $false
        $actionButton.Content = "START SERVER"
        $hintText.Text = "No server yet - click New Server to create one."
        return
    }

    $index = 0
    if ($PreferName) {
        $found = 0..($script:instances.Count - 1) | Where-Object { $script:instances[$_].Name -eq $PreferName } | Select-Object -First 1
        if ($null -ne $found) { $index = $found }
    }
    $serverCombo.SelectedIndex = $index
    $script:selected = $script:instances[$index]
}

Refresh-ServerList

function Get-SelectedRconPort {
    if (-not $script:selected) { return $null }
    $props = Read-ServerProperties (Join-Path $script:selected.Path "server.properties")
    if ($props["rcon.port"]) { return [int]$props["rcon.port"] }
    return 25575
}

# Reads the shareable address the same way show-address.ps1 does: ask
# playit.gg once, fall back to the cached address.txt if that fails.
function Update-AddressDisplay {
    $toolDir = Join-Path $root "_shared\tools\playit"
    $secretFile = Join-Path $toolDir "secret.key"
    $addrFile = Join-Path $toolDir "address.txt"
    $addr = $null

    if (Test-Path $secretFile) {
        try {
            $secret = (Get-Content $secretFile -Raw).Trim()
            $rd = Invoke-RestMethod -Uri "https://api.playit.gg/agents/rundata" -Method Post -Body "{}" `
                -Headers @{ Authorization = "Agent-Key $secret"; "Content-Type" = "application/json" } -TimeoutSec 8
            $mc = Select-MinecraftTunnel -Tunnels $rd.data.tunnels
            if ($mc -and $mc.assigned_domain) {
                $addr = $mc.assigned_domain
                Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ascii
            }
        } catch { }
        if (-not $addr -and (Test-Path $addrFile)) { $addr = (Get-Content $addrFile -Raw).Trim() }
    }

    if ($addr) {
        $addressText.Text = $addr
        $copyButton.IsEnabled = $true
        $setupTunnelButton.Visibility = "Collapsed"
    } else {
        $addressText.Text = "Same WiFi only (no sharing set up yet)"
        $copyButton.IsEnabled = $false
        $setupTunnelButton.Visibility = "Visible"
    }
}

# Refreshes the campfire/status/button display from real port state, and
# reports the settled lifecycle state so callers (click handler, closing
# handler, timer) can react to transitions completing.
function Sync-StatusDisplay {
    if (-not $script:selected) { return "Stopped" }
    $running = Test-PortOpen -Port (Get-SelectedRconPort)
    $view = Get-ServerStatusView -IsRunning $running
    $statusLabel.Text = $view.Label
    $fireIcon.Opacity = if ($running) { 1.0 } else { 0.25 }

    $state = Get-ServerLifecycleState -IsRunning $running -PendingStart $script:pendingStart -PendingStop $script:pendingStop
    if ($state -eq "Running" -or $state -eq "Stopped") {
        $script:pendingStart = $false
        $script:pendingStop = $false
    }

    if (-not $script:closingApp) {
        $btn = Get-ActionButtonView -State $state
        $serverCombo.IsEnabled = ($state -eq "Running" -or $state -eq "Stopped")
        $actionButton.IsEnabled = $btn.IsEnabled
        $actionButton.Content = $btn.Label
        if ($state -eq "Running" -or $state -eq "Stopped") { $hintText.Text = " " }
    }

    return $state
}

$serverCombo.Add_SelectionChanged({
    if ($serverCombo.SelectedIndex -lt 0) { return }
    $script:selected = $script:instances[$serverCombo.SelectedIndex]
    $script:pendingStart = $false
    $script:pendingStop = $false
    Sync-StatusDisplay | Out-Null
    Update-AddressDisplay
})

$actionButton.Add_Click({
    if (-not $script:selected) { return }
    $state = Get-ServerLifecycleState -IsRunning (Test-PortOpen -Port (Get-SelectedRconPort)) -PendingStart $script:pendingStart -PendingStop $script:pendingStop

    if ($state -eq "Starting") {
        # Cancel: nothing graceful to send yet (RCON isn't up), so kill the
        # launcher and everything it spawned (java, playit).
        $hintText.Text = "Cancelling..."
        $actionButton.IsEnabled = $false
        if ($script:launchedProcess -and -not $script:launchedProcess.HasExited) {
            Stop-ProcessTree -ProcessId $script:launchedProcess.Id
        }
        $script:launchedProcess = $null
        $script:pendingStart = $false
        return
    }
    if ($state -ne "Stopped" -and $state -ne "Running") { return }

    $serverCombo.IsEnabled = $false
    $actionButton.IsEnabled = $false

    if ($state -eq "Running") {
        $script:pendingStop = $true
        $actionButton.Content = "STOPPING..."
        $hintText.Text = "Saving the world, this can take a minute..."
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            (Join-Path $root "_shared\scripts\stop-server.ps1"),
            "-ServerPath", "`"$($script:selected.Path)`""
        )
    } else {
        $script:pendingStart = $true
        $actionButton.Content = "CANCEL"
        $hintText.Text = "Lighting it up..."
        $script:launchedProcess = Start-Process -FilePath "powershell.exe" -PassThru -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            "`"$(Join-Path $script:selected.Path 'start-with-tunnel.ps1')`""
        )
    }
})

$copyButton.Add_Click({
    if ($copyButton.IsEnabled) { Set-Clipboard -Value $addressText.Text }
})

$mapsButton.Add_Click({
    if (-not $script:selected) { return }
    & (Join-Path $root "Start-ManageMapsGui.ps1") -InstancePath $script:selected.Path -InstanceName $script:selected.Name -GsRoot $root -Owner $window
})

$newServerButton.Add_Click({
    $mcRoot = Join-Path $root "Minecraft"
    $createdName = & (Join-Path $root "Start-AddModpackGui.ps1") -McRoot $mcRoot -GsRoot $root -Owner $window
    if ($createdName) {
        $script:instances = @(Get-ServerInstances -Root $root)
        Refresh-ServerList -PreferName $createdName
        Update-AddressDisplay
    }
})

$setupTunnelButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        "`"$(Join-Path $root '_shared\scripts\setup-playit.ps1')`""
    )
})

# Closing the window shouldn't leave the server running invisibly. First
# close attempt intercepts and starts a clean shutdown (or cancels a launch
# still in progress); the timer below watches for it to settle and then
# re-triggers Close() for real.
$window.Add_Closing({
    param($sender, $e)
    if ($script:okToClose) { return }
    if (-not $script:selected) { $script:okToClose = $true; return }

    $running = Test-PortOpen -Port (Get-SelectedRconPort)
    $state = Get-ServerLifecycleState -IsRunning $running -PendingStart $script:pendingStart -PendingStop $script:pendingStop

    if ($state -eq "Stopped") {
        $script:okToClose = $true
        return
    }

    $e.Cancel = $true
    $script:closingApp = $true
    $actionButton.IsEnabled = $false
    $serverCombo.IsEnabled = $false

    if ($state -eq "Starting") {
        $hintText.Text = "Cancelling before closing..."
        if ($script:launchedProcess -and -not $script:launchedProcess.HasExited) {
            Stop-ProcessTree -ProcessId $script:launchedProcess.Id
        }
        $script:launchedProcess = $null
        $script:pendingStart = $false
        $script:pendingStop = $false
    } elseif (-not $script:pendingStop) {
        $hintText.Text = "Closing - saving the world first..."
        $script:pendingStop = $true
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            (Join-Path $root "_shared\scripts\stop-server.ps1"),
            "-ServerPath", "`"$($script:selected.Path)`""
        )
    }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    $state = Sync-StatusDisplay
    if ($state -eq "Running" -and $addressText.Text -eq "Checking...") { Update-AddressDisplay }

    if ($script:closingApp -and $state -eq "Stopped") {
        $script:okToClose = $true
        $window.Close()
    }
})
$timer.Start()

Sync-StatusDisplay | Out-Null
Update-AddressDisplay

$window.ShowDialog() | Out-Null
$timer.Stop()
