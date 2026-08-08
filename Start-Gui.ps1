# GUI launcher (replaces the console menu). Double-click Start.bat to run this.
# One Window, three screens (Home / Manage Maps / Add Server) that swap in
# and out of it instead of opening as separate popup windows, plus a small
# in-window overlay for prompts (rename/confirm/browse) - so checking on your
# world never means opening-then-closing a whole extra window.
#
# The actual server/tunnel/world logic is unchanged (start-with-tunnel.ps1,
# stop-server.ps1, rcon.ps1, worlds-helpers.ps1, new-server-helpers.ps1):
# this window just wires their existing functions to whichever screen is
# currently showing.

$root = $PSScriptRoot
. (Join-Path $root "_shared\scripts\gui-helpers.ps1")
. (Join-Path $root "_shared\scripts\rcon.ps1")
. (Join-Path $root "_shared\scripts\tunnel-helpers.ps1")
. (Join-Path $root "_shared\scripts\worlds-helpers.ps1")
. (Join-Path $root "_shared\scripts\new-server-helpers.ps1")
. (Join-Path $root "_shared\scripts\gui-dialogs.ps1")
. (Join-Path $root "_shared\scripts\verity-helpers.ps1")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Get-ScreenXaml([string]$FileName) {
    [xml]$xamlXml = Get-Content -Path (Join-Path $root "_shared\gui\$FileName") -Raw
    return [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))
}

$script:instances = @(Get-ServerInstances -Root $root)

# ---- Shell + screens -------------------------------------------------

$window = Get-ScreenXaml "MainWindow.xaml"
$homeHost = $window.FindName("HomeHost")
$mapsHost = $window.FindName("MapsHost")
$addHost = $window.FindName("AddServerHost")
$consoleHost = $window.FindName("ConsoleHost")
$overlayHost = $window.FindName("OverlayHost")

$homeRoot = Get-ScreenXaml "HomeScreen.xaml"
$mapsRoot = Get-ScreenXaml "ManageMapsScreen.xaml"
$addRoot = Get-ScreenXaml "AddServerScreen.xaml"
$consoleRoot = Get-ScreenXaml "ConsoleScreen.xaml"
$overlayRoot = Get-ScreenXaml "PromptOverlay.xaml"

$homeHost.Content = $homeRoot
$mapsHost.Content = $mapsRoot
$addHost.Content = $addRoot
$consoleHost.Content = $consoleRoot
$overlayHost.Content = $overlayRoot

$overlay = @{
    Host         = $overlayHost
    PromptText   = $overlayRoot.FindName("PromptText")
    ValueBox     = $overlayRoot.FindName("ValueBox")
    OkButton     = $overlayRoot.FindName("OkButton")
    CancelButton = $overlayRoot.FindName("CancelButton")
}

$script:currentScreen = "Home"
function Show-Screen([string]$Screen) {
    $homeHost.Visibility = if ($Screen -eq "Home") { "Visible" } else { "Collapsed" }
    $mapsHost.Visibility = if ($Screen -eq "ManageMaps") { "Visible" } else { "Collapsed" }
    $addHost.Visibility = if ($Screen -eq "AddServer") { "Visible" } else { "Collapsed" }
    $consoleHost.Visibility = if ($Screen -eq "Console") { "Visible" } else { "Collapsed" }
    $size = Get-ScreenSize -Screen $Screen
    $window.Width = $size.Width
    $window.Height = $size.Height
    $script:currentScreen = $Screen
}

# ---- Home screen -------------------------------------------------

$serverCombo      = $homeRoot.FindName("ServerCombo")
$fireIcon         = $homeRoot.FindName("FireVisual")
$statusLabel      = $homeRoot.FindName("StatusLabel")
$addressText      = $homeRoot.FindName("AddressText")
$copyButton       = $homeRoot.FindName("CopyButton")
$actionButton     = $homeRoot.FindName("ActionButton")
$homeHintText     = $homeRoot.FindName("HintText")
$mapsButton       = $homeRoot.FindName("MapsButton")
$consoleButton    = $homeRoot.FindName("ConsoleButton")
$newServerButton  = $homeRoot.FindName("NewServerButton")
$setupTunnelButton = $homeRoot.FindName("SetupTunnelButton")
$verityAiPanel = $homeRoot.FindName("VerityAiPanel")
$verityServices = @(
    [PSCustomObject]@{ Key = "Ollama";  Port = 11434; Label = "Core LLM (Ollama)";  StatusText = $homeRoot.FindName("VerityOllamaStatusText");  Button = $homeRoot.FindName("VerityOllamaButton") }
    [PSCustomObject]@{ Key = "Kokoro";  Port = 8880;  Label = "Voice out (Kokoro)"; StatusText = $homeRoot.FindName("VerityKokoroStatusText");  Button = $homeRoot.FindName("VerityKokoroButton") }
    [PSCustomObject]@{ Key = "Whisper"; Port = 9000;  Label = "Voice in (Whisper)"; StatusText = $homeRoot.FindName("VerityWhisperStatusText"); Button = $homeRoot.FindName("VerityWhisperButton") }
)
$verityAiStopAllButton = $homeRoot.FindName("VerityAiStopAllButton")
$script:aiJobs = @{ Ollama = $null; Kokoro = $null; Whisper = $null }

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
        $homeHintText.Text = "No server yet - click New Server to create one."
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
    if (-not $script:selected) { $consoleButton.Visibility = "Collapsed"; return "Stopped" }
    $consoleButton.Visibility = if ($script:selected.Game -eq "Minecraft") { "Visible" } else { "Collapsed" }
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
        if ($state -eq "Running" -or $state -eq "Stopped") { $homeHintText.Text = " " }
    }

    if ($script:selected -and $script:selected.Game -eq "Minecraft" -and (Test-VerityModPresent -InstancePath $script:selected.Path)) {
        $verityAiPanel.Visibility = "Visible"
        foreach ($svc in $verityServices) {
            if ($script:aiJobs[$svc.Key]) { continue }
            $running = Test-PortOpen -Port $svc.Port
            $svc.StatusText.Text = "$($svc.Label): $((Get-ServerStatusView -IsRunning $running).Label)"
            $svc.Button.Content = if ($running) { "STOP" } else { "START" }
            $svc.Button.IsEnabled = $true
        }
        $verityAiStopAllButton.IsEnabled = -not [bool]($script:aiJobs.Values | Where-Object { $_ })
    } else {
        $verityAiPanel.Visibility = "Collapsed"
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
        $homeHintText.Text = "Cancelling..."
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
        $homeHintText.Text = "Saving the world, this can take a minute..."
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            (Join-Path $root "_shared\scripts\stop-server.ps1"),
            "-ServerPath", "`"$($script:selected.Path)`""
        )
    } else {
        $script:pendingStart = $true
        $actionButton.Content = "CANCEL"
        $homeHintText.Text = "Lighting it up..."
        $script:launchedProcess = Start-Process -FilePath "powershell.exe" -PassThru -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            "`"$(Join-Path $script:selected.Path 'start-with-tunnel.ps1')`""
        )
    }
})

function Invoke-VerityServiceToggle {
    param($svc)
    if (-not $script:selected -or $script:aiJobs[$svc.Key]) { return }

    $running = Test-PortOpen -Port $svc.Port
    if ($running -and (Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $script:selected.Path)) {
        $svc.StatusText.Text = "$($svc.Label): In use by another server, not stopping"
        $svc.Button.IsEnabled = $true
        return
    }

    $svc.Button.IsEnabled = $false
    $svc.StatusText.Text = "$($svc.Label): $(if ($running) { 'Stopping...' } else { 'Starting...' })"
    $script:aiJobs[$svc.Key] = Start-Job -ScriptBlock {
        param($GsRoot, $InstancePath, $McRoot, $Service, $ToLocal)
        . (Join-Path $GsRoot "_shared\scripts\verity-helpers.ps1")
        if ($ToLocal) {
            & "Start-${Service}Sidecar" -McRoot $McRoot
            Set-VerityAiProvider -InstancePath $InstancePath -Service $Service -UseLocal $true
        } else {
            & "Stop-${Service}Sidecar"
            Set-VerityAiProvider -InstancePath $InstancePath -Service $Service -UseLocal $false
        }
    } -ArgumentList $root, $script:selected.Path, (Join-Path $root "Minecraft"), $svc.Key, (-not $running)
}

foreach ($svc in $verityServices) {
    $svc.Button.Add_Click({ Invoke-VerityServiceToggle -svc $svc }.GetNewClosure())
}

$verityAiStopAllButton.Add_Click({
    if (-not $script:selected) { return }
    foreach ($svc in $verityServices) {
        if ((Test-PortOpen -Port $svc.Port) -and -not $script:aiJobs[$svc.Key]) {
            Invoke-VerityServiceToggle -svc $svc
        }
    }
})

$copyButton.Add_Click({
    if ($copyButton.IsEnabled) { Set-Clipboard -Value $addressText.Text }
})

$setupTunnelButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        "`"$(Join-Path $root '_shared\scripts\setup-playit.ps1')`""
    )
})

# ---- Manage Maps screen -------------------------------------------------

$mapsBackButton    = $mapsRoot.FindName("BackButton")
$titleText         = $mapsRoot.FindName("TitleText")
$subtitleText      = $mapsRoot.FindName("SubtitleText")
$worldsList        = $mapsRoot.FindName("WorldsList")
$mapsHintText      = $mapsRoot.FindName("HintText")
$switchButton      = $mapsRoot.FindName("SwitchButton")
$newButton         = $mapsRoot.FindName("NewButton")
$importButton      = $mapsRoot.FindName("ImportButton")
$deleteButton      = $mapsRoot.FindName("DeleteButton")
$trashToggleButton = $mapsRoot.FindName("TrashToggleButton")

$TrashDirName = "_trash"
$script:mapsInstancePath = $null
$script:mapsPropsPath = $null
$script:showingTrash = $false

function Get-ActiveWorldName { return Get-ServerProperty $script:mapsPropsPath "level-name" }

function Test-MapsServerRunning {
    $active = Get-ActiveWorldName
    if (-not $active) { return $false }
    return Test-FileLocked (Join-Path $script:mapsInstancePath "$active\session.lock")
}

function Refresh-WorldsView {
    $active = Get-ActiveWorldName
    $worlds = @(Get-Worlds -InstancePath $script:mapsInstancePath -ActiveName $active | Where-Object { $_.Exists })
    $items = $worlds | ForEach-Object {
        [PSCustomObject]@{
            Name      = $_.Name
            SizeLabel = "{0} MB" -f (Get-FolderSizeMB $_.Path)
            BadgeText = if ($_.IsActive) { "ACTIVE" } else { "" }
            Path      = $_.Path
            IsActive  = $_.IsActive
        }
    }
    $worldsList.ItemsSource = @($items)
    $titleText.Text = "MANAGE MAPS"
    $switchButton.Content = "Switch active"
    $newButton.Visibility = "Visible"
    $importButton.Visibility = "Visible"
    $deleteButton.Content = "Send to trash"
    $trashToggleButton.Content = "View trash"
}

function Refresh-TrashView {
    $trash = Join-Path $script:mapsInstancePath $TrashDirName
    $items = @()
    if (Test-Path $trash) {
        $items = Get-ChildItem -Path $trash -Directory | ForEach-Object {
            [PSCustomObject]@{
                Name      = $_.Name
                SizeLabel = "{0} MB" -f (Get-FolderSizeMB $_.FullName)
                BadgeText = ""
                Path      = $_.FullName
                IsActive  = $false
            }
        }
    }
    $worldsList.ItemsSource = @($items)
    $titleText.Text = "TRASH"
    $switchButton.Content = "Restore"
    $newButton.Visibility = "Collapsed"
    $importButton.Visibility = "Collapsed"
    $deleteButton.Content = "Empty trash (permanent)"
    $trashToggleButton.Content = "Back to worlds"
}

function Refresh-MapsView {
    if (Test-MapsServerRunning) {
        $mapsHintText.Text = "The server looks like it's running - stop it first to make changes."
    } else {
        $mapsHintText.Text = " "
    }
    if ($script:showingTrash) { Refresh-TrashView } else { Refresh-WorldsView }
}

# Called from the Home screen's "Manage Maps" click, right before showing
# this screen, so it always reflects whichever server is currently selected.
function Enter-ManageMapsScreen {
    $script:mapsInstancePath = $script:selected.Path
    $script:mapsPropsPath = Join-Path $script:selected.Path "server.properties"
    $script:showingTrash = $false
    $subtitleText.Text = $script:selected.Name
    Refresh-MapsView
}

$mapsBackButton.Add_Click({ Show-Screen "Home" })

$trashToggleButton.Add_Click({
    $script:showingTrash = -not $script:showingTrash
    Refresh-MapsView
})

$switchButton.Add_Click({
    $selectedWorld = $worldsList.SelectedItem
    if (-not $selectedWorld) { $mapsHintText.Text = "Pick a world first."; return }

    if ($script:showingTrash) {
        $orig = ($selectedWorld.Name -replace '__\d{8}-\d{6}$', '')
        $newName = Show-InputDialog -Overlay $overlay -Prompt "Restore as (name):" -DefaultValue $orig
        if (-not $newName) { return }
        if (-not (Test-ValidName $newName)) { $mapsHintText.Text = "Invalid name."; return }
        $dest = Join-Path $script:mapsInstancePath $newName
        if (Test-Path $dest) { $mapsHintText.Text = "'$newName' already exists."; return }
        Move-Item -Path $selectedWorld.Path -Destination $dest
        $mapsHintText.Text = "Restored as '$newName'."
        Refresh-MapsView
        return
    }

    if (Test-MapsServerRunning) { $mapsHintText.Text = "Stop the server before switching worlds."; return }
    if ($selectedWorld.IsActive) { $mapsHintText.Text = "That's already the active world."; return }
    Set-ServerProperty $script:mapsPropsPath "level-name" $selectedWorld.Name
    $mapsHintText.Text = "'$($selectedWorld.Name)' is now active. Takes effect next time you start the server."
    Refresh-MapsView
})

$newButton.Add_Click({
    if (Test-MapsServerRunning) { $mapsHintText.Text = "Stop the server before creating a world."; return }
    $name = Show-InputDialog -Overlay $overlay -Prompt "Name for the new world:"
    if (-not $name) { return }
    if (-not (Test-ValidName $name)) { $mapsHintText.Text = "Invalid name."; return }
    $dest = Join-Path $script:mapsInstancePath $name
    if (Test-Path $dest) { $mapsHintText.Text = "A folder named '$name' already exists."; return }
    New-Item -ItemType Directory -Path $dest | Out-Null
    if (Show-ConfirmDialog -Overlay $overlay -Message "Activate '$name' now?") {
        Set-ServerProperty $script:mapsPropsPath "level-name" $name
        $mapsHintText.Text = "'$name' created and activated. Generated on next server start."
    } else {
        $mapsHintText.Text = "'$name' created (not active). Use Switch active to use it later."
    }
    Refresh-MapsView
})

$importButton.Add_Click({
    if (Test-MapsServerRunning) { $mapsHintText.Text = "Stop the server before importing a world."; return }
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Filter = "World archive (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne $true) { return }

    $name = Show-InputDialog -Overlay $overlay -Prompt "Name for this world:"
    if (-not $name) { return }
    if (-not (Test-ValidName $name)) { $mapsHintText.Text = "Invalid name."; return }
    $dest = Join-Path $script:mapsInstancePath $name
    if (Test-Path $dest) { $mapsHintText.Text = "A folder named '$name' already exists."; return }

    $tmp = Join-Path $env:TEMP ("mc-import-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $mapsHintText.Text = "Extracting..."
        Expand-Archive -Path $ofd.FileName -DestinationPath $tmp -Force
        $leveldat = Get-ChildItem -Path $tmp -Recurse -File -Filter "level.dat" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $leveldat) { $mapsHintText.Text = "That .zip doesn't look like a Minecraft world (no level.dat)."; return }
        $worldRoot = Split-Path -Parent $leveldat.FullName
        Copy-Item -Path $worldRoot -Destination $dest -Recurse -Force
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Show-ConfirmDialog -Overlay $overlay -Message "Activate '$name' now?") {
        Set-ServerProperty $script:mapsPropsPath "level-name" $name
    }
    $mapsHintText.Text = "'$name' imported."
    Refresh-MapsView
})

$deleteButton.Add_Click({
    $selectedWorld = $worldsList.SelectedItem
    if (-not $selectedWorld) { $mapsHintText.Text = "Pick a world first."; return }

    if ($script:showingTrash) {
        if (-not (Show-ConfirmDialog -Overlay $overlay -Message "Permanently delete everything in the trash? This cannot be undone.")) { return }
        Remove-Item -Path (Join-Path $script:mapsInstancePath $TrashDirName) -Recurse -Force -ErrorAction SilentlyContinue
        $mapsHintText.Text = "Trash emptied."
        Refresh-MapsView
        return
    }

    if ($selectedWorld.IsActive) { $mapsHintText.Text = "Can't delete the active world. Switch to another first."; return }
    if (Test-FileLocked (Join-Path $selectedWorld.Path "session.lock")) { $mapsHintText.Text = "That world is in use."; return }
    if (-not (Show-ConfirmDialog -Overlay $overlay -Message "Send '$($selectedWorld.Name)' to the trash? (Recoverable from View trash.)")) { return }

    $trash = Join-Path $script:mapsInstancePath $TrashDirName
    if (-not (Test-Path $trash)) { New-Item -ItemType Directory -Path $trash | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Move-Item -Path $selectedWorld.Path -Destination (Join-Path $trash ("{0}__{1}" -f $selectedWorld.Name, $stamp))
    $mapsHintText.Text = "'$($selectedWorld.Name)' sent to the trash."
    Refresh-MapsView
})

$mapsButton.Add_Click({
    if (-not $script:selected) { return }
    Enter-ManageMapsScreen
    Show-Screen "ManageMaps"
})

$consoleButton.Add_Click({
    if (-not $script:selected) { return }
    Enter-ConsoleScreen
    Show-Screen "Console"
})

# ---- Add Server screen -------------------------------------------------

$addBackButton      = $addRoot.FindName("BackButton")
$nameBox            = $addRoot.FindName("NameBox")
$mrpackBox          = $addRoot.FindName("MrpackBox")
$browseButton       = $addRoot.FindName("BrowseButton")
$modpackDropZone    = $addRoot.FindName("ModpackDropZone")
$dropZoneOutline    = $addRoot.FindName("DropZoneOutline")
$dropZoneIcon       = $addRoot.FindName("DropZoneIcon")
$dropZoneTitle      = $addRoot.FindName("DropZoneTitle")
$dropZoneEmptyState = $addRoot.FindName("DropZoneEmptyState")
$dropZoneFilledState = $addRoot.FindName("DropZoneFilledState")
$dropZoneFileName   = $addRoot.FindName("DropZoneFileName")
$dropZoneFileType   = $addRoot.FindName("DropZoneFileType")
$clearModpackButton = $addRoot.FindName("ClearModpackButton")
$ramBox          = $addRoot.FindName("RamBox")
$eulaCheck    = $addRoot.FindName("EulaCheck")
$addHintText  = $addRoot.FindName("HintText")
$createButton = $addRoot.FindName("CreateButton")

$script:addJob = $null

function Set-AddServerFormEnabled([bool]$Enabled) {
    $nameBox.IsEnabled = $Enabled
    $modpackDropZone.IsEnabled = $Enabled
    $ramBox.IsEnabled = $Enabled
    $eulaCheck.IsEnabled = $Enabled
    $createButton.IsEnabled = $Enabled
    $addBackButton.IsEnabled = $Enabled
}

# Swaps the drop zone between its empty ("drag a modpack here") and filled
# (filename + type + Remove) states, driven entirely by $mrpackBox.Text -
# that stays the single source of truth Browse/drag-drop/Create already read.
function Update-ModpackDropZoneDisplay {
    $path = $mrpackBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        $dropZoneEmptyState.Visibility = "Visible"
        $dropZoneFilledState.Visibility = "Collapsed"
        return
    }
    $dropZoneEmptyState.Visibility = "Collapsed"
    $dropZoneFilledState.Visibility = "Visible"
    $dropZoneFileName.Text = Split-Path -Path $path -Leaf
    $dropZoneFileType.Text = if ($path -match '\.zip(\?.*)?$') { "CurseForge Server Files" }
                              elseif ($path -match '\.mrpack(\?.*)?$') { "Modrinth modpack" }
                              else { "Modpack link" }
}

function Reset-ModpackDropZoneVisual {
    $dropZoneOutline.Stroke = $addRoot.FindResource("BorderSubtleBrush")
    $dropZoneOutline.Fill = $addRoot.FindResource("PanelBrush")
    $dropZoneIcon.Foreground = $addRoot.FindResource("MutedTextBrush")
    $dropZoneTitle.Foreground = $addRoot.FindResource("TextBrush")
}

function Enter-AddServerScreen {
    $nameBox.Text = ""
    $mrpackBox.Text = ""
    $ramBox.Text = "6G"
    $eulaCheck.IsChecked = $false
    $addHintText.Text = " "
    Update-ModpackDropZoneDisplay
    Reset-ModpackDropZoneVisual
    Set-AddServerFormEnabled $true
}

$addBackButton.Add_Click({ Show-Screen "Home" })

$browseButton.Add_Click({
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Filter = "Modpack (*.mrpack;*.zip)|*.mrpack;*.zip"
    if ($ofd.ShowDialog() -eq $true) {
        $mrpackBox.Text = $ofd.FileName
        Update-ModpackDropZoneDisplay
    }
})

$clearModpackButton.Add_Click({
    $mrpackBox.Text = ""
    Update-ModpackDropZoneDisplay
})

$modpackDropZone.Add_DragEnter({
    param($sender, $e)
    $isFileDrop = $e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)
    $e.Effects = if ($isFileDrop) { [Windows.DragDropEffects]::Copy } else { [Windows.DragDropEffects]::None }
    if ($isFileDrop) {
        $dropZoneOutline.Stroke = $addRoot.FindResource("AccentBrush")
        $dropZoneOutline.Fill = "#1AE0813F"
        $dropZoneIcon.Foreground = $addRoot.FindResource("AccentBrush")
        $dropZoneTitle.Foreground = $addRoot.FindResource("AccentBrush")
    }
})

$modpackDropZone.Add_DragLeave({ Reset-ModpackDropZoneVisual })

$modpackDropZone.Add_Drop({
    param($sender, $e)
    Reset-ModpackDropZoneVisual
    if (-not $e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { return }
    $paths = $e.Data.GetData([Windows.DataFormats]::FileDrop)
    $modpack = $paths | Where-Object { $_ -match '\.(mrpack|zip)$' } | Select-Object -First 1
    if ($modpack) {
        $mrpackBox.Text = $modpack
        Update-ModpackDropZoneDisplay
    }
})

$createButton.Add_Click({
    $name = $nameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $addHintText.Text = "Enter a server name."; return }
    if (-not (Test-ServerNameValid -Name $name)) {
        $suggestion = $name -replace '[\\/:*?"<>|\s]', ''
        $addHintText.Text = "Server names can't contain spaces or path characters - some modpacks' launch scripts break on spaced paths. Try '$suggestion' instead."
        return
    }
    if (-not $eulaCheck.IsChecked) { $addHintText.Text = "You need to accept the Minecraft EULA to continue."; return }
    $mrpack = $mrpackBox.Text.Trim()
    $ram = $ramBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($ram)) { $ram = "6G" }

    Set-AddServerFormEnabled $false
    $addHintText.Text = "Creating '$name'..."

    $mcRoot = Join-Path $root "Minecraft"
    $script:addJob = Start-Job -ScriptBlock {
        param($GsRoot, $McRoot, $Name, $MrpackPath, $MaxRam)
        . (Join-Path $GsRoot "_shared\scripts\new-server-helpers.ps1")
        $dest = New-ServerFromTemplate -Name $Name -McRoot $McRoot

        if ($MrpackPath) {
            . (Join-Path $GsRoot "_shared\scripts\mrpack-helpers.ps1")
            $isZip = $MrpackPath -match '\.zip(\?.*)?$'
            $ext = if ($isZip) { "zip" } else { "mrpack" }
            $localFile = $MrpackPath
            if ($MrpackPath -match '^https?://') {
                $localFile = Join-Path $env:TEMP ("download-" + [Guid]::NewGuid().ToString("N") + ".$ext")
                Invoke-WebRequest -Uri $MrpackPath -OutFile $localFile -UseBasicParsing
            } elseif (-not (Test-Path $MrpackPath)) {
                throw "Could not find the modpack file at '$MrpackPath'."
            }

            if ($isZip) {
                . (Join-Path $GsRoot "_shared\scripts\curseforge-helpers.ps1")
                try {
                    $javaVersion = Install-CurseForgeServerZip -ZipPath $localFile -DestPath $dest
                } catch {
                    Remove-Item -Recurse -Force $dest
                    throw
                }
                if ($javaVersion) {
                    Set-RunConfigJavaAndRam -Path (Join-Path $dest "run.config.ps1") -JavaVersion $javaVersion -MaxRam $MaxRam
                }
            } else {
                $mrpackExe = Join-Path $GsRoot "_shared\tools\mrpack.exe"
                $mcVersion = Get-MinecraftVersionFromMrpack -MrpackPath $localFile
                $javaVersion = Get-JavaVersionForMinecraft -McVersion $mcVersion
                $loader = Get-ModpackLoader -MrpackPath $localFile
                if ($loader -ne "fabric") {
                    Remove-Item -Recurse -Force $dest
                    throw "This modpack uses $loader, which can't be installed automatically yet (Fabric only). Create the server without a modpack and copy the 'Server Files' in by hand (see README.md)."
                }

                & $mrpackExe $localFile --server-dir $dest
                if ($LASTEXITCODE -ne 0) {
                    Remove-Item -Recurse -Force $dest
                    throw "mrpack.exe failed installing the modpack (code $LASTEXITCODE)."
                }
                Set-RunConfigJavaAndRam -Path (Join-Path $dest "run.config.ps1") -JavaVersion $javaVersion -MaxRam $MaxRam
            }
        }

        Set-Content -Path (Join-Path $dest "eula.txt") -Value "eula=true" -Encoding ascii
        return $Name
    } -ArgumentList $root, $mcRoot, $name, $mrpack, $ram
})

$addJobTimer = New-Object System.Windows.Threading.DispatcherTimer
$addJobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$addJobTimer.Add_Tick({
    if (-not $script:addJob -or $script:addJob.State -eq "Running" -or $script:addJob.State -eq "NotStarted") { return }

    if ($script:addJob.State -eq "Completed") {
        $createdName = Receive-Job $script:addJob
        Remove-Job $script:addJob
        $script:addJob = $null
        Set-AddServerFormEnabled $true
        $script:instances = @(Get-ServerInstances -Root $root)
        Refresh-ServerList -PreferName $createdName
        Update-AddressDisplay
        Show-Screen "Home"
        return
    }

    # Failed
    $reason = $script:addJob.ChildJobs[0].JobStateInfo.Reason.Message
    Remove-Job $script:addJob -Force
    $script:addJob = $null
    $addHintText.Text = "Error: $reason"
    Set-AddServerFormEnabled $true
})
$addJobTimer.Start()

$aiJobTimer = New-Object System.Windows.Threading.DispatcherTimer
$aiJobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$aiJobTimer.Add_Tick({
    $settled = @()
    foreach ($svc in $verityServices) {
        $job = $script:aiJobs[$svc.Key]
        if (-not $job) { continue }
        if ($job.State -eq "Running" -or $job.State -eq "NotStarted") { continue }

        $failed = $job.State -eq "Failed"
        $reason = if ($failed) { $job.ChildJobs[0].JobStateInfo.Reason.Message } else { $null }
        Remove-Job $job -Force
        $script:aiJobs[$svc.Key] = $null
        if ($failed) { $settled += [PSCustomObject]@{ Svc = $svc; Reason = $reason } }
    }
    # Sync-StatusDisplay overwrites every row's StatusText from live port
    # state, so it must only run (and the error text applied after it) when
    # something actually settled this tick - otherwise it'd both clobber the
    # error text right back to "OUT" and do a full port-check refresh 4x
    # more often than needed for no reason.
    if ($settled.Count -gt 0) {
        Sync-StatusDisplay | Out-Null
        foreach ($s in $settled) { $s.Svc.StatusText.Text = "$($s.Svc.Label): Error - $($s.Reason)" }
    }
})
$aiJobTimer.Start()

$newServerButton.Add_Click({
    Enter-AddServerScreen
    Show-Screen "AddServer"
})

# ---- Console screen -------------------------------------------------
# Logs tail from disk (logs\latest.log) and commands go out over RCON - the
# same client already used by stop-server.ps1, reused here instead of piping
# stdin/stdout to the (hidden) server process. Both the tail timer and the
# RCON send run off the UI thread's blocking path: the tail read is a cheap
# offset-only file read (Get-LogTailChunk), and the RCON call runs in a
# background Job polled by a timer, the same pattern already used for
# server creation ($addJob/$addJobTimer above) - a direct blocking RCON call
# here would freeze the window exactly like the old Test-PortOpen bug did.

$consoleBackButton   = $consoleRoot.FindName("BackButton")
$consoleSubtitleText = $consoleRoot.FindName("SubtitleText")
$logText             = $consoleRoot.FindName("LogText")
$consoleHintText     = $consoleRoot.FindName("HintText")
$commandBox          = $consoleRoot.FindName("CommandBox")
$sendButton          = $consoleRoot.FindName("SendButton")

$script:logOffset = 0
$script:rconJob = $null
$script:rconJobServerPath = $null
$script:consoleServerPath = $null
$MaxConsoleLines = 2000

# Always clears the view and re-seeds the tail offset on entry, rather than
# replaying whatever text accumulated the last time Console was open for
# this server - a long crash-loop can otherwise leave thousands of stale
# lines sitting in the view long after the server's recovered. Seeking to
# a fixed byte window from the end (not offset 0) keeps this cheap even for
# a huge log file - the same class of full-file-read freeze already fixed
# once this session for Test-PortOpen.
$ConsoleTailWindowBytes = 64KB
function Enter-ConsoleScreen {
    $script:consoleServerPath = $script:selected.Path
    $logPath = Join-Path $script:selected.Path "logs\latest.log"
    $fileLen = if (Test-Path $logPath) { (Get-Item $logPath).Length } else { 0 }
    $script:logOffset = [Math]::Max(0, $fileLen - $ConsoleTailWindowBytes)
    $logText.Text = ""
    $consoleSubtitleText.Text = $script:selected.Name
    $commandBox.Text = ""
    $logTailTimer.Start()
}

$consoleBackButton.Add_Click({
    $logTailTimer.Stop()
    Show-Screen "Home"
})

function Send-ConsoleCommand {
    $cmd = $commandBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($cmd) -or $script:rconJob) { return }

    $props = Read-ServerProperties (Join-Path $script:selected.Path "server.properties")
    $port = Get-SelectedRconPort
    $password = $props["rcon.password"]

    $logText.AppendText("`r`n> $cmd`r`n")
    $logText.ScrollToEnd()
    $commandBox.Text = ""
    $commandBox.IsEnabled = $false
    $sendButton.IsEnabled = $false

    $script:rconJobServerPath = $script:selected.Path
    $script:rconJob = Start-Job -ScriptBlock {
        param($GsRoot, $Port, $Password, $Command)
        . (Join-Path $GsRoot "_shared\scripts\rcon.ps1")
        try { Invoke-RconCommand -Port $Port -Password $Password -Command $Command }
        catch { "Error: $($_.Exception.Message)" }
    } -ArgumentList $root, $port, $password, $cmd
}

$sendButton.Add_Click({ Send-ConsoleCommand })
$commandBox.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { Send-ConsoleCommand }
})

# Tails logs\latest.log while the Console screen is showing (started in
# Enter-ConsoleScreen, stopped on back-navigation - no point reading the
# file when nobody's looking at it) and keeps Send's enabled state in sync
# with whether RCON is actually reachable right now.
$logTailTimer = New-Object System.Windows.Threading.DispatcherTimer
$logTailTimer.Interval = [TimeSpan]::FromSeconds(1.5)
$logTailTimer.Add_Tick({
    if (-not $script:selected) { return }
    $logPath = Join-Path $script:selected.Path "logs\latest.log"
    $chunk = Get-LogTailChunk -Path $logPath -Offset $script:logOffset
    if ($chunk.Text) {
        $logText.AppendText($chunk.Text)
        $script:logOffset = $chunk.Offset

        $lines = $logText.Text -split "`r`n"
        if ($lines.Count -gt $MaxConsoleLines) {
            $logText.Text = ($lines[($lines.Count - $MaxConsoleLines)..($lines.Count - 1)] -join "`r`n")
        }
        $logText.CaretIndex = $logText.Text.Length
        $logText.ScrollToEnd()
    }

    $running = Test-PortOpen -Port (Get-SelectedRconPort)
    $props = Read-ServerProperties (Join-Path $script:selected.Path "server.properties")
    $canSend = $running -and ($props["enable-rcon"] -eq "true") -and $props["rcon.password"]
    if (-not $script:rconJob) {
        $commandBox.IsEnabled = $canSend
        $sendButton.IsEnabled = $canSend
    }
    $consoleHintText.Text = if (-not $running) { "Server isn't running - start it to send commands." }
        elseif (-not $canSend) { "RCON isn't enabled for this server." }
        else { " " }
})

# Polls the background RCON job (mirrors $addJobTimer above) instead of
# blocking the UI thread on Invoke-RconCommand's network round-trip.
$rconJobTimer = New-Object System.Windows.Threading.DispatcherTimer
$rconJobTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$rconJobTimer.Add_Tick({
    if (-not $script:rconJob -or $script:rconJob.State -eq "Running" -or $script:rconJob.State -eq "NotStarted") { return }

    # If you sent a command, then navigated to a different server before the
    # response came back, don't let it land in that other server's log view.
    $sameServer = $script:selected -and ($script:selected.Path -eq $script:rconJobServerPath)

    if ($script:rconJob.State -eq "Completed") {
        $response = Receive-Job $script:rconJob
        if ($response -and $sameServer) { $logText.AppendText("$response`r`n") }
    } else {
        $reason = $script:rconJob.ChildJobs[0].JobStateInfo.Reason.Message
        if ($sameServer) { $logText.AppendText("Error: $reason`r`n") }
    }
    Remove-Job $script:rconJob -Force -ErrorAction SilentlyContinue
    $script:rconJob = $null
    if (-not $sameServer) { return }
    $logText.ScrollToEnd()
    $commandBox.Focus() | Out-Null
})
$rconJobTimer.Start()

# ---- Window lifecycle -------------------------------------------------

# Closing the window shouldn't leave the server running invisibly, or an
# add-server job orphaned. First close attempt intercepts and starts a clean
# shutdown (or cancels a launch/creation still in progress); the timer below
# watches for it to settle and then re-triggers Close() for real.
$window.Add_Closing({
    param($sender, $e)
    if ($script:okToClose) { return }

    if ($script:addJob) {
        Stop-Job $script:addJob -ErrorAction SilentlyContinue
        Remove-Job $script:addJob -Force -ErrorAction SilentlyContinue
        $script:addJob = $null
    }

    if ($script:rconJob) {
        Stop-Job $script:rconJob -ErrorAction SilentlyContinue
        Remove-Job $script:rconJob -Force -ErrorAction SilentlyContinue
        $script:rconJob = $null
    }

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
        $homeHintText.Text = "Cancelling before closing..."
        if ($script:launchedProcess -and -not $script:launchedProcess.HasExited) {
            Stop-ProcessTree -ProcessId $script:launchedProcess.Id
        }
        $script:launchedProcess = $null
        $script:pendingStart = $false
        $script:pendingStop = $false
    } elseif (-not $script:pendingStop) {
        $homeHintText.Text = "Closing - saving the world first..."
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
Show-Screen "Home"

$window.ShowDialog() | Out-Null
$timer.Stop()
$addJobTimer.Stop()
$logTailTimer.Stop()
$rconJobTimer.Stop()
$aiJobTimer.Stop()
