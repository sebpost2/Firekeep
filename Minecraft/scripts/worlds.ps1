# World (map) manager for the Minecraft servers.
# Safe CRUD: view / create / switch / import / delete worlds.
#
# Safety rules (by design, can't be skipped from the menu):
#   - "Delete" NEVER actually deletes: it sends the world to the _trash
#     folder inside the same server. It can always be recovered.
#   - You can't delete the ACTIVE world (you have to switch to another first).
#   - If it detects the server is RUNNING, it won't let you touch the world in use.
#   - Before changing server.properties it always makes a backup (.bak).
#   - Worlds are detected by their 'level.dat' file, so it NEVER confuses
#     a mods/config folder with a world.
#
# Note: designed for Forge modpacks (a single world with DIM-1/DIM1 inside).

$ErrorActionPreference = "Stop"
$mcRoot = Split-Path -Parent $PSScriptRoot
$serversRoot = Join-Path $mcRoot "servers"
$gsRoot = Split-Path -Parent $mcRoot
. (Join-Path $gsRoot "_shared\scripts\worlds-helpers.ps1")

# Folders that are NEVER a world (even if they mistakenly had a level.dat).
$TrashDir = "_trash"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to go back to the menu" | Out-Null
}

function Show-WorldsTable($worlds, $activeName) {
    Write-Host ""
    Write-Host ("  {0}  {1,-28} {2,10}   {3}" -f " ", "WORLD", "SIZE", "STATUS")
    Write-Host "  ---------------------------------------------------------------------"
    for ($i = 0; $i -lt $worlds.Count; $i++) {
        $w = $worlds[$i]
        $size = if ($w.Exists) { "{0} MB" -f (Get-FolderSizeMB $w.Path) } else { "-" }
        $status = if ($w.IsActive) { "<== ACTIVE" } elseif (-not $w.Exists) { "(generated on start)" } else { "" }
        $color = if ($w.IsActive) { "Green" } else { "Gray" }
        Write-Host ("  [{0}] {1,-28} {2,10}   {3}" -f $i, $w.Name, $size, $status) -ForegroundColor $color
    }
    Write-Host "  ---------------------------------------------------------------------"
}

# ---------------------------------------------------------------------------
# Server (instance) selection
# ---------------------------------------------------------------------------

function Select-Instance {
    $instances = @(
        Get-ChildItem -Path $serversRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "_template" -and (Test-Path (Join-Path $_.FullName "server.properties")) }
    )
    if ($instances.Count -eq 0) {
        Write-Host "No Minecraft server created yet." -ForegroundColor Yellow
        exit 0
    }
    if ($instances.Count -eq 1) { return $instances[0] }

    Write-Host ""
    Write-Host "Which server do you want to manage?"
    for ($i = 0; $i -lt $instances.Count; $i++) {
        Write-Host "  [$i] $($instances[$i].Name)"
    }
    while ($true) {
        $c = Read-Host "Number"
        if ($c -match '^\d+$' -and [int]$c -lt $instances.Count) { return $instances[[int]$c] }
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# Asks you to pick a world from an already-shown list. Returns the object or $null.
function Pick-World($worlds, $prompt, [switch]$ExcludeActive) {
    $c = Read-Host $prompt
    if ($c -notmatch '^\d+$' -or [int]$c -ge $worlds.Count) {
        Write-Host "Invalid choice." -ForegroundColor Yellow
        return $null
    }
    $w = $worlds[[int]$c]
    if ($ExcludeActive -and $w.IsActive) {
        Write-Host "That's the ACTIVE world. Switch to another one first." -ForegroundColor Yellow
        return $null
    }
    return $w
}

# ---------------------------------------------------------------------------
# CRUD actions
# ---------------------------------------------------------------------------

function Action-View($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = Get-Worlds $instance.FullName $active
    Show-WorldsTable $worlds $active
    Write-Host ""
    Write-Host "  Active world: $active" -ForegroundColor Cyan
    Pause-Menu
}

function Action-Switch($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = @(Get-Worlds $instance.FullName $active | Where-Object { $_.Exists })
    if ($worlds.Count -lt 2) {
        Write-Host ""
        Write-Host "There's only one world. Create or import another before you can switch." -ForegroundColor Yellow
        Pause-Menu; return
    }
    Show-WorldsTable $worlds $active
    Write-Host ""
    $w = Pick-World $worlds "Number of the world to ACTIVATE"
    if (-not $w) { Pause-Menu; return }
    if ($w.IsActive) { Write-Host "That's already the active one." -ForegroundColor Yellow; Pause-Menu; return }

    Set-ServerProperty $propsPath "level-name" $w.Name
    Write-Host ""
    Write-Host "Done. The server now uses the world: $($w.Name)" -ForegroundColor Green
    Write-Host "(The previous world '$active' is untouched; you can go back to it anytime.)"
    Write-Host "The change takes effect next time you start the server."
    Pause-Menu
}

function Action-Create($instance, $propsPath) {
    Write-Host ""
    Write-Host "Creates a NEW, empty world. Minecraft generates it when the server starts."
    $name = Read-Host "Name for the new world (e.g: world-2)"
    if (-not (Test-ValidName $name)) { Write-Host "Invalid name." -ForegroundColor Yellow; Pause-Menu; return }
    $dest = Join-Path $instance.FullName $name
    if (Test-Path $dest) { Write-Host "A folder named '$name' already exists." -ForegroundColor Yellow; Pause-Menu; return }

    New-Item -ItemType Directory -Path $dest | Out-Null

    $seed = Read-Host "Seed (optional, Enter for random)"
    Write-Host ""
    $activate = Read-Host "Activate this world now? (y/N)"
    if ($activate -match '^(s|si|y|yes)$') {
        if ($seed) { Set-ServerProperty $propsPath "level-seed" $seed }
        Set-ServerProperty $propsPath "level-name" $name
        Write-Host ""
        Write-Host "World '$name' created and ACTIVATED." -ForegroundColor Green
        Write-Host "It's generated the next time you start the server."
        if ($seed) { Write-Host "It'll use the seed: $seed" }
    } else {
        Write-Host ""
        Write-Host "World '$name' created (not active yet)." -ForegroundColor Green
        Write-Host "When you want to use it, go to 'Switch active world'."
        if ($seed) { Write-Host "Note: the seed is applied when you activate it and start the server." }
    }
    Pause-Menu
}

function Action-Import($instance, $propsPath) {
    Write-Host ""
    Write-Host "Imports a downloaded map (.zip). You can drag the .zip into this window."
    $zip = (Read-Host "Path to the .zip").Trim().Trim('"')
    if (-not (Test-Path $zip)) { Write-Host "Couldn't find that file." -ForegroundColor Yellow; Pause-Menu; return }
    if ([System.IO.Path]::GetExtension($zip) -ne ".zip") { Write-Host "It has to be a .zip." -ForegroundColor Yellow; Pause-Menu; return }

    $name = Read-Host "Name for this world inside the server"
    if (-not (Test-ValidName $name)) { Write-Host "Invalid name." -ForegroundColor Yellow; Pause-Menu; return }
    $dest = Join-Path $instance.FullName $name
    if (Test-Path $dest) { Write-Host "A folder named '$name' already exists." -ForegroundColor Yellow; Pause-Menu; return }

    $tmp = Join-Path $env:TEMP ("mc-import-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Extracting..."
        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        # Find the folder that contains level.dat (the world's real root).
        $leveldat = Get-ChildItem -Path $tmp -Recurse -File -Filter "level.dat" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $leveldat) {
            Write-Host "That .zip doesn't look like a Minecraft world (no level.dat)." -ForegroundColor Yellow
            Pause-Menu; return
        }
        $worldRoot = Split-Path -Parent $leveldat.FullName
        Write-Host "Copying the world to '$name'..."
        Copy-Item -Path $worldRoot -Destination $dest -Recurse -Force
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    $activate = Read-Host "Activate this world now? (y/N)"
    if ($activate -match '^(s|si|y|yes)$') {
        Set-ServerProperty $propsPath "level-name" $name
        Write-Host "World '$name' imported and ACTIVATED." -ForegroundColor Green
        Write-Host "The change takes effect next time you start the server."
    } else {
        Write-Host "World '$name' imported (not active). Activate it from 'Switch active world'." -ForegroundColor Green
    }
    Pause-Menu
}

function Action-Delete($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = @(Get-Worlds $instance.FullName $active | Where-Object { $_.Exists })
    $deletable = @($worlds | Where-Object { -not $_.IsActive })
    if ($deletable.Count -eq 0) {
        Write-Host ""
        Write-Host "There are no worlds to delete (the only one is the ACTIVE one," -ForegroundColor Yellow
        Write-Host "and the active one is protected). Switch worlds first if you want to delete it."
        Pause-Menu; return
    }

    Write-Host ""
    Write-Host "  Worlds that can be sent to the trash (the ACTIVE one doesn't show up):" -ForegroundColor Cyan
    Show-WorldsTable $worlds $active
    Write-Host ""
    Write-Host "  (You can't pick the ACTIVE world.)" -ForegroundColor DarkGray
    $w = Pick-World $worlds "Number of the world to send to the trash" -ExcludeActive
    if (-not $w) { Pause-Menu; return }

    # Extra safety: if that folder is in use (server running), abort.
    if (Test-FileLocked (Join-Path $w.Path "session.lock")) {
        Write-Host "That world is IN USE (server running). Not touching it." -ForegroundColor Red
        Pause-Menu; return
    }

    Write-Host ""
    Write-Host "You're about to send '$($w.Name)' to the trash (it can be recovered later)." -ForegroundColor Yellow
    $confirm = Read-Host "To confirm, type the EXACT name of the world"
    if ($confirm -ne $w.Name) { Write-Host "Doesn't match. Cancelled." -ForegroundColor Yellow; Pause-Menu; return }

    $trash = Join-Path $instance.FullName $TrashDir
    if (-not (Test-Path $trash)) { New-Item -ItemType Directory -Path $trash | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $target = Join-Path $trash ("{0}__{1}" -f $w.Name, $stamp)
    Move-Item -Path $w.Path -Destination $target
    Write-Host ""
    Write-Host "Done. '$($w.Name)' went to the trash." -ForegroundColor Green
    Write-Host "If you change your mind, it's at: $target"
    Pause-Menu
}

function Action-Trash($instance, $propsPath) {
    $trash = Join-Path $instance.FullName $TrashDir
    $items = @()
    if (Test-Path $trash) { $items = @(Get-ChildItem -Path $trash -Directory) }
    if ($items.Count -eq 0) {
        Write-Host ""
        Write-Host "The trash is empty." -ForegroundColor Cyan
        Pause-Menu; return
    }

    Write-Host ""
    Write-Host "  TRASH:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("  [{0}] {1}   ({2} MB)" -f $i, $items[$i].Name, (Get-FolderSizeMB $items[$i].FullName))
    }
    Write-Host ""
    Write-Host "  [r] Restore a world    [x] Empty the trash (permanent)    [Enter] Go back"
    $op = Read-Host "What do you want to do"

    if ($op -eq 'r') {
        $c = Read-Host "Number to restore"
        if ($c -notmatch '^\d+$' -or [int]$c -ge $items.Count) { Write-Host "Invalid." -ForegroundColor Yellow; Pause-Menu; return }
        $it = $items[[int]$c]
        # The original name is what's before the "__timestamp".
        $orig = ($it.Name -replace '__\d{8}-\d{6}$', '')
        $newName = Read-Host "Name to restore it as (Enter = '$orig')"
        if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $orig }
        if (-not (Test-ValidName $newName)) { Write-Host "Invalid name." -ForegroundColor Yellow; Pause-Menu; return }
        $dest = Join-Path $instance.FullName $newName
        if (Test-Path $dest) { Write-Host "'$newName' already exists. Pick another name." -ForegroundColor Yellow; Pause-Menu; return }
        Move-Item -Path $it.FullName -Destination $dest
        Write-Host "Restored as '$newName'." -ForegroundColor Green
        Write-Host "To use it, activate it from 'Switch active world'."
        Pause-Menu; return
    }

    if ($op -eq 'x') {
        Write-Host ""
        Write-Host "This PERMANENTLY deletes everything in the trash. It CANNOT be recovered." -ForegroundColor Red
        $confirm = Read-Host "To confirm, type:  DELETE ALL"
        if ($confirm -ne "DELETE ALL") { Write-Host "Cancelled." -ForegroundColor Yellow; Pause-Menu; return }
        Remove-Item -Path $trash -Recurse -Force
        Write-Host "Trash emptied." -ForegroundColor Green
        Pause-Menu; return
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$instance = Select-Instance
$propsPath = Join-Path $instance.FullName "server.properties"

while ($true) {
    Clear-Host
    $active = Get-ServerProperty $propsPath "level-name"
    $activeLock = Join-Path (Join-Path $instance.FullName $active) "session.lock"
    $running = Test-FileLocked $activeLock

    Write-Host ""
    Write-Host "==================== WORLD MANAGER ====================" -ForegroundColor Cyan
    Write-Host "  Server: $($instance.Name)"
    Write-Host "  Active world: $active"
    if ($running) {
        Write-Host "  !! The server looks RUNNING. Stop it before touching worlds." -ForegroundColor Yellow
    }
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] View worlds"
    Write-Host "  [2] Switch active world"
    Write-Host "  [3] Create new world"
    Write-Host "  [4] Import world from .zip"
    Write-Host "  [5] Delete world  (goes to trash, recoverable)"
    Write-Host "  [6] Trash  (restore / empty)"
    Write-Host "  [0] Exit"
    Write-Host ""
    $opt = Read-Host "Option"

    switch ($opt) {
        "1" { Action-View $instance $propsPath }
        "2" { Action-Switch $instance $propsPath }
        "3" { Action-Create $instance $propsPath }
        "4" { Action-Import $instance $propsPath }
        "5" { Action-Delete $instance $propsPath }
        "6" { Action-Trash $instance $propsPath }
        "0" { break }
        default { }
    }
}
