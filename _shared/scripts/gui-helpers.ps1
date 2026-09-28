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
        "Home"           { return [PSCustomObject]@{ Width = 640; Height = 860 } }
        "ManageMaps"     { return [PSCustomObject]@{ Width = 480; Height = 640 } }
        "AddServer"      { return [PSCustomObject]@{ Width = 480; Height = 580 } }
        "Console"        { return [PSCustomObject]@{ Width = 640; Height = 720 } }
        "ServerSettings" { return [PSCustomObject]@{ Width = 480; Height = 690 } }
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
        "Home"           { return $null }
        "ManageMaps"     { return "Home" }
        "AddServer"      { return "Home" }
        "Console"        { return "Home" }
        "ServerSettings" { return "Home" }
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
            # UTF-8, not ASCII: player chat/usernames in the log can contain
            # non-ASCII characters (accents, emoji, other scripts), which
            # ASCII would silently mangle into '?'.
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $reader = New-Object System.IO.StreamReader($stream, $utf8NoBom)
            $text = $reader.ReadToEnd()
            return [PSCustomObject]@{ Text = $text; Offset = $stream.Length }
        } finally {
            $stream.Close()
        }
    } catch {
        return [PSCustomObject]@{ Text = ""; Offset = $Offset }
    }
}

# Best-effort read of the repo-root VERSION file for the Home screen label.
# Never throws - a missing/unreadable file just means no label is shown.
function Get-AppVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )
    $versionFile = Join-Path $Root "VERSION"
    if (-not (Test-Path $versionFile)) { return "" }
    try {
        return (Get-Content -Path $versionFile -Raw -ErrorAction Stop).Trim()
    } catch {
        return ""
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

# The jar named by an "invalid dist DEDICATED_SERVER" crash. Forge crash
# reports have one "-- MOD <id> --" section per failing mod, with its
# "Mod File:" line BEFORE the failure text, so the jar is taken from the
# section that contains the failure. Without such a section (a plain log
# line), the first "Mod File:" after the failure is used.
function Get-InvalidDistModFile {
    param([AllowEmptyString()][string]$ConsoleText = "")
    $marker = "invalid dist DEDICATED_SERVER"
    $at = $ConsoleText.IndexOf($marker)
    if ($at -lt 0) { return $null }
    $modFile = 'Mod File: .*[\\/]mods[\\/]([^\\/\r\n]+\.jar)'
    foreach ($section in ($ConsoleText -split '(?m)^(?=-- )')) {
        if ($section.StartsWith("-- MOD ") -and $section.Contains($marker) -and $section -match $modFile) { return $Matches[1] }
    }
    if ($ConsoleText.Substring($at) -match $modFile) { return $Matches[1] }
    return $null
}

# Turns a failed start into one sentence a non-technical user can act on.
# $ConsoleText is logs\firekeep-console.log (everything the server and Java
# printed, captured by start.ps1). Returns $null while nothing says startup
# failed - unless the launcher already exited, which during "Starting"
# always means it did. Some Forge crashes never exit the process (the log
# ends at "Negative index in crash report handler"), so the text is checked
# for a fatal marker rather than waiting for the process.
function Get-StartupFailure {
    param(
        [AllowEmptyString()][string]$ConsoleText = "",
        [bool]$LauncherExited = $false
    )
    $fatal = 'Failed to start the minecraft server|Could not create the Java Virtual Machine|Error occurred during initialization of VM|---- Minecraft Crash Report ----|could not open .*jvm\.cfg|FAILED TO BIND TO PORT'
    if (-not $LauncherExited -and $ConsoleText -notmatch $fatal) { return $null }

    if ($ConsoleText -match 'Firekeep: installing Java (\d+) failed') {
        return "Firekeep couldn't install Java $($Matches[1]) for this server - check the internet connection and try again."
    }
    if ($ConsoleText -match 'Could not reserve enough space|Invalid maximum heap size|insufficient memory for the Java Runtime') {
        return "The server asked for more memory than this PC can give it. Lower Max memory in Server Settings."
    }
    if ($ConsoleText -match 'OutOfMemoryError') {
        return "The server ran out of memory while starting. Raise Max memory in Server Settings."
    }
    if ($ConsoleText -match 'UnsupportedClassVersionError|compiled by a more recent version of the Java') {
        return "This modpack needs a different Java version. Set `$JavaVersion in the server's run.config.ps1 (17 for Minecraft 1.17-1.20.4, 21 for 1.20.5 and newer)."
    }
    if ($ConsoleText -match 'jvm\.cfg|could not find java\.dll') {
        return "This server's Java install is broken. Start it again - Firekeep repairs Java on the next start."
    }
    if ($ConsoleText -match 'invalid dist DEDICATED_SERVER') {
        $jar = Get-InvalidDistModFile -ConsoleText $ConsoleText
        if ($jar) {
            return "A mod that only works in the game client stopped the server: $jar. Move that file out of the server's mods folder and start again."
        }
        return "A mod that only works in the game client stopped the server. The crash report names it - move that mod out of the server's mods folder and start again."
    }
    if ($ConsoleText -match 'Mixin apply for mod ([\w-]+) failed') {
        return "The mod '$($Matches[1])' failed to load on the server - it's probably client-only. Move it out of the server's mods folder and start again."
    }
    if ($ConsoleText -match "Mod ID: '([^']+)', Requested by: '([^']+)'") {
        return "The mod '$($Matches[2])' needs '$($Matches[1])', which isn't in the server's mods folder."
    }
    if ($ConsoleText -match 'FAILED TO BIND TO PORT|Address already in use') {
        return "The server's port is already in use - another server or program is using it. Stop that one first."
    }
    if ($ConsoleText -match 'session\.lock|already locked') {
        return "This world is already open in another server window. Close that one first."
    }
    if ($ConsoleText -match 'agree to the EULA') {
        return "The Minecraft EULA hasn't been accepted for this server (set eula=true in its eula.txt)."
    }
    if (-not $ConsoleText.Trim()) {
        return "The server stopped before Minecraft launched. Try Start again; if it keeps happening, run start-with-tunnel.ps1 from the server's folder to see the error."
    }
    return "The server crashed while starting."
}

# Fingerprint of a script's text that ignores line endings, a BOM and
# trailing whitespace - so a copy that git or an editor re-saved with CRLF
# still counts as the same version.
function Get-ScriptFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").TrimEnd()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally {
        $sha.Dispose()
    }
}

# Fingerprints of every earlier version of Minecraft\servers\_template\start.ps1.
# When you change that file, add the OLD version's fingerprint here
# (Get-ScriptFingerprint) - tests/gui-helpers.tests.ps1 fails until you do.
function Get-PastTemplateStartHashes {
    return @(
        "2eff4f425014e19a63ed7408a6c03ff6a6a7c6b3b4eaf282aa1aa53fe2725f41"  # 3e7b280 initial
        "5705f3e7e68c4241b1c772f2dfb0bcfad37a7dedc1540377a44e888fbc2eae47"  # e1e0fda English
        "cf96b1afc675db2d1fe23ddcf8a7e6860b0f2803255730d25c2ec1723caca19d"  # cb5233b Java detection
        "e22810297173ce2494e006b8a82da2371f6f4a566c82309846fcbe7382a52b55"  # f3e9380 v1.0.0
        "3aed437b13b36b84f95228ec1a156b8b1e73ecb8a9cb19823ef72de2459bfac6"  # b3180ef Java repair
        "9f474def415bd36b3aae96f2c72de1beec7566acabdb76bde58101d975c9f9b5"  # 2130afe RCON defaults
        "df7ee009698997d3f7cbee6492b04a4ad45548a72be9030b57d5845c1de63b1d"  # 58a31e8 GC flags
        "c7fc6ba1cdad735cd0f566fb6468cc3adf4f96ef8a1342566c355d9932635ad6"  # b95fa5d backups
        "8529e1bdb60d5785d879eda53019aa948bf12fdd0bcd61afd6cf8a8949f715f3"  # 955b455 console capture
    )
}

# Each server gets its own copy of start.ps1 when it's created, so fixes to
# the template never reached existing servers. Before a start, replace the
# server's copy with the current template - but only when it's an untouched
# copy of an earlier template (a known fingerprint), never a customized one.
# Returns $true when it updated the file.
function Update-ServerStartScript {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][string]$TemplatePath
    )
    $target = Join-Path $InstancePath "start.ps1"
    if (-not (Test-Path $target) -or -not (Test-Path $TemplatePath)) { return $false }
    $fingerprint = Get-ScriptFingerprint $target
    if ($fingerprint -eq (Get-ScriptFingerprint $TemplatePath)) { return $false }
    if ((Get-PastTemplateStartHashes) -notcontains $fingerprint) { return $false }
    Copy-Item -Path $TemplatePath -Destination $target -Force
    return $true
}

# Who holds a server's .starting.lock (start-with-tunnel.ps1 writes its PID
# there and refuses to launch while that process is alive). Returns $null
# when there's no lock, else Kind:
#   Stale    - the PID is gone or now belongs to some other program; the
#              lock is safe to delete.
#   Leftover - the launcher is alive but only a cmd.exe is left under it, no
#              Java: the server has stopped and run.bat's "pause" is waiting
#              for a key nobody will press (servers on an older or custom
#              start.ps1). Safe to kill - no world is open.
#   Starting - a real launch in progress (still preparing, so no cmd.exe
#              yet, or Java is running). Leave it alone.
function Get-LaunchLockState {
    param([Parameter(Mandatory = $true)][string]$InstancePath)
    $lockPath = Join-Path $InstancePath ".starting.lock"
    if (-not (Test-Path $lockPath)) { return $null }
    $raw = "$(Get-Content -Path $lockPath -Raw -ErrorAction SilentlyContinue)".Trim()
    if ($raw -notmatch '^\d+$') { return [PSCustomObject]@{ Kind = "Stale"; Pid = $null } }
    $launcherPid = [int]$raw

    $processes = @(Get-CimInstance Win32_Process)
    $launcher = $processes | Where-Object { $_.ProcessId -eq $launcherPid }
    $ownScript = Join-Path $InstancePath "start-with-tunnel.ps1"
    if (-not $launcher -or "$($launcher.CommandLine)" -notlike "*$ownScript*") {
        return [PSCustomObject]@{ Kind = "Stale"; Pid = $launcherPid }
    }

    $descendants = @()
    $frontier = @($launcherPid)
    while ($frontier.Count -gt 0) {
        $children = @($processes | Where-Object { $frontier -contains $_.ParentProcessId })
        $descendants += $children
        $frontier = @($children | ForEach-Object { $_.ProcessId })
    }
    $names = @($descendants | ForEach-Object { $_.Name.ToLower() })
    $leftover = ($names -contains "cmd.exe") -and -not ($names -contains "java.exe" -or $names -contains "javaw.exe")
    return [PSCustomObject]@{ Kind = $(if ($leftover) { "Leftover" } else { "Starting" }); Pid = $launcherPid }
}

# The jar a failed start blames for being client-only, so Home can offer to
# move it aside: the "Mod File:" line that follows an "invalid dist
# DEDICATED_SERVER" crash, or - when a Mixin failure names only a mod id -
# the jar in mods\ whose META-INF/mods.toml declares that id. $null when the
# crash isn't about such a mod or the jar isn't in mods\ (never guesses).
function Get-ClientOnlyModJar {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [AllowEmptyString()][string]$ConsoleText = ""
    )
    $modsDir = Join-Path $InstancePath "mods"
    $jar = Get-InvalidDistModFile -ConsoleText $ConsoleText
    if ($jar) {
        if (Test-Path -LiteralPath (Join-Path $modsDir $jar)) { return $jar }
        return $null
    }
    if ($ConsoleText -match 'Mixin apply for mod ([\w-]+) failed') {
        $modId = $Matches[1]
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # Opening every jar takes a second or two on a big pack (this runs on
        # the UI thread), so jars whose name looks like the mod id go first.
        $jars = @(Get-ChildItem -LiteralPath $modsDir -Filter "*.jar" -File -ErrorAction SilentlyContinue)
        $key = ($modId -replace '[-_ ]', '')
        $likely = @($jars | Where-Object { ($_.BaseName -replace '[-_ ]', '') -like "*$key*" })
        $ordered = $likely + @($jars | Where-Object { $likely -notcontains $_ })
        foreach ($file in $ordered) {
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName) } catch { continue }
            try {
                $toml = $zip.GetEntry("META-INF/mods.toml")
                if (-not $toml) { continue }
                $reader = New-Object System.IO.StreamReader($toml.Open())
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($text -match "(?m)^\s*modId\s*=\s*[`"']$([regex]::Escape($modId))[`"']") { return $file.Name }
            } finally {
                $zip.Dispose()
            }
        }
    }
    return $null
}

# The one-click fix: moves a mod the server refused into _excluded\client-only
# (never deletes it). Throws if the move fails, so the caller doesn't restart
# the server as if it had worked.
function Move-ModAside {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][string]$JarName
    )
    $target = Join-Path $InstancePath "_excluded\client-only"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Move-Item -LiteralPath (Join-Path $InstancePath "mods\$JarName") -Destination $target -Force -ErrorAction Stop
}
