# Manage Maps window (GUI replacement for Minecraft\scripts\worlds.ps1's
# console menu). Launched in-process from Start-Gui.ps1's "Manage Maps"
# button, passing the currently selected server instance.
#
# Same safety rules as the console tool: delete never actually deletes (goes
# to _trash, recoverable), the active world can't be deleted, and nothing
# touches worlds while the server looks like it's running.

param(
    [Parameter(Mandatory = $true)][string]$InstancePath,
    [Parameter(Mandatory = $true)][string]$InstanceName,
    [Parameter(Mandatory = $true)][string]$GsRoot,
    [System.Windows.Window]$Owner
)

. (Join-Path $GsRoot "_shared\scripts\worlds-helpers.ps1")
. (Join-Path $GsRoot "_shared\scripts\gui-dialogs.ps1")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xamlXml = Get-Content -Path (Join-Path $GsRoot "_shared\gui\ManageMapsWindow.xaml") -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))
if ($Owner) { $window.Owner = $Owner }

$titleText        = $window.FindName("TitleText")
$subtitleText     = $window.FindName("SubtitleText")
$worldsList       = $window.FindName("WorldsList")
$hintText         = $window.FindName("HintText")
$switchButton     = $window.FindName("SwitchButton")
$newButton        = $window.FindName("NewButton")
$importButton     = $window.FindName("ImportButton")
$deleteButton     = $window.FindName("DeleteButton")
$trashToggleButton = $window.FindName("TrashToggleButton")

$subtitleText.Text = $InstanceName
$propsPath = Join-Path $InstancePath "server.properties"
$TrashDirName = "_trash"
$script:showingTrash = $false

function Get-ActiveWorldName { return Get-ServerProperty $propsPath "level-name" }

function Test-ServerRunning {
    $active = Get-ActiveWorldName
    if (-not $active) { return $false }
    return Test-FileLocked (Join-Path $InstancePath "$active\session.lock")
}

function Refresh-WorldsView {
    $active = Get-ActiveWorldName
    $worlds = @(Get-Worlds -InstancePath $InstancePath -ActiveName $active | Where-Object { $_.Exists })
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
    $trash = Join-Path $InstancePath $TrashDirName
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

function Refresh-View {
    if (Test-ServerRunning) {
        $hintText.Text = "The server looks like it's running - stop it first to make changes."
    } else {
        $hintText.Text = " "
    }
    if ($script:showingTrash) { Refresh-TrashView } else { Refresh-WorldsView }
}

$trashToggleButton.Add_Click({
    $script:showingTrash = -not $script:showingTrash
    Refresh-View
})

$switchButton.Add_Click({
    $selected = $worldsList.SelectedItem
    if (-not $selected) { $hintText.Text = "Pick a world first."; return }

    if ($script:showingTrash) {
        $orig = ($selected.Name -replace '__\d{8}-\d{6}$', '')
        $newName = Show-InputDialog -GsRoot $GsRoot -Owner $window -Prompt "Restore as (name):" -DefaultValue $orig
        if (-not $newName) { return }
        if (-not (Test-ValidName $newName)) { $hintText.Text = "Invalid name."; return }
        $dest = Join-Path $InstancePath $newName
        if (Test-Path $dest) { $hintText.Text = "'$newName' already exists."; return }
        Move-Item -Path $selected.Path -Destination $dest
        $hintText.Text = "Restored as '$newName'."
        Refresh-View
        return
    }

    if (Test-ServerRunning) { $hintText.Text = "Stop the server before switching worlds."; return }
    if ($selected.IsActive) { $hintText.Text = "That's already the active world."; return }
    Set-ServerProperty $propsPath "level-name" $selected.Name
    $hintText.Text = "'$($selected.Name)' is now active. Takes effect next time you start the server."
    Refresh-View
})

$newButton.Add_Click({
    if (Test-ServerRunning) { $hintText.Text = "Stop the server before creating a world."; return }
    $name = Show-InputDialog -GsRoot $GsRoot -Owner $window -Prompt "Name for the new world:"
    if (-not $name) { return }
    if (-not (Test-ValidName $name)) { $hintText.Text = "Invalid name."; return }
    $dest = Join-Path $InstancePath $name
    if (Test-Path $dest) { $hintText.Text = "A folder named '$name' already exists."; return }
    New-Item -ItemType Directory -Path $dest | Out-Null
    if (Show-ConfirmDialog -Message "Activate '$name' now?") {
        Set-ServerProperty $propsPath "level-name" $name
        $hintText.Text = "'$name' created and activated. Generated on next server start."
    } else {
        $hintText.Text = "'$name' created (not active). Use Switch active to use it later."
    }
    Refresh-View
})

$importButton.Add_Click({
    if (Test-ServerRunning) { $hintText.Text = "Stop the server before importing a world."; return }
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Filter = "World archive (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne $true) { return }

    $name = Show-InputDialog -GsRoot $GsRoot -Owner $window -Prompt "Name for this world:"
    if (-not $name) { return }
    if (-not (Test-ValidName $name)) { $hintText.Text = "Invalid name."; return }
    $dest = Join-Path $InstancePath $name
    if (Test-Path $dest) { $hintText.Text = "A folder named '$name' already exists."; return }

    $tmp = Join-Path $env:TEMP ("mc-import-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $hintText.Text = "Extracting..."
        Expand-Archive -Path $ofd.FileName -DestinationPath $tmp -Force
        $leveldat = Get-ChildItem -Path $tmp -Recurse -File -Filter "level.dat" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $leveldat) { $hintText.Text = "That .zip doesn't look like a Minecraft world (no level.dat)."; return }
        $worldRoot = Split-Path -Parent $leveldat.FullName
        Copy-Item -Path $worldRoot -Destination $dest -Recurse -Force
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Show-ConfirmDialog -Message "Activate '$name' now?") {
        Set-ServerProperty $propsPath "level-name" $name
    }
    $hintText.Text = "'$name' imported."
    Refresh-View
})

$deleteButton.Add_Click({
    $selected = $worldsList.SelectedItem
    if (-not $selected) { $hintText.Text = "Pick a world first."; return }

    if ($script:showingTrash) {
        if (-not (Show-ConfirmDialog -Message "Permanently delete everything in the trash? This cannot be undone." -Title "Empty trash")) { return }
        Remove-Item -Path (Join-Path $InstancePath $TrashDirName) -Recurse -Force -ErrorAction SilentlyContinue
        $hintText.Text = "Trash emptied."
        Refresh-View
        return
    }

    if ($selected.IsActive) { $hintText.Text = "Can't delete the active world. Switch to another first."; return }
    if (Test-FileLocked (Join-Path $selected.Path "session.lock")) { $hintText.Text = "That world is in use."; return }
    if (-not (Show-ConfirmDialog -Message "Send '$($selected.Name)' to the trash? (Recoverable from View trash.)")) { return }

    $trash = Join-Path $InstancePath $TrashDirName
    if (-not (Test-Path $trash)) { New-Item -ItemType Directory -Path $trash | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Move-Item -Path $selected.Path -Destination (Join-Path $trash ("{0}__{1}" -f $selected.Name, $stamp))
    $hintText.Text = "'$($selected.Name)' sent to the trash."
    Refresh-View
})

Refresh-View
$window.ShowDialog() | Out-Null
