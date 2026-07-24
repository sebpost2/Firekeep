# Detects what a manually-copied-in CurseForge "Server Files" download needs
# to run, without a CurseForge API or a Modrinth-style manifest to read.
# Loaded via dot-source.

. (Join-Path $PSScriptRoot "mrpack-helpers.ps1")

# Detects the Java version an instance needs, by inspecting whatever the user
# copied into its folder. Tries, in order:
#   1. variables.txt (ServerPackCreator's format - loader-agnostic: Forge,
#      NeoForge, Fabric, and Quilt packs built with that tool all produce
#      this same file, with the Minecraft version and/or a recommended Java
#      version spelled out directly).
#   2. run.bat's Forge library path (modern Forge 1.17+, e.g.
#      "libraries/net/minecraftforge/forge/1.20.1-47.4.20/win_args.txt").
#   3. startserver.bat's "requires Java N" line (All-the-Mods-style NeoForge
#      packs, which self-install NeoForge on first run and haven't produced
#      a run.bat/variables.txt yet).
#   4. A fabric-server-mc.<mcVersion>-loader...jar filename (the official
#      Fabric installer's server jar - raw Fabric packs with no
#      variables.txt).
#   5. A forge-<mcVersion>-<forgeVersion>-installer.jar filename (raw Forge
#      packs before the installer has ever been run, so there's no run.bat
#      yet either).
# Returns $null (never throws) when nothing recognizable is found, so the
# caller can fall back to today's fully-manual run.config.ps1 behavior.
function Get-DetectedJavaVersion {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )

    $varsPath = Join-Path $InstancePath "variables.txt"
    if (Test-Path $varsPath) {
        $detected = Get-JavaVersionFromVariablesFile -Path $varsPath
        if ($detected) { return $detected }
    }

    $runBatPath = Join-Path $InstancePath "run.bat"
    if (Test-Path $runBatPath) {
        $detected = Get-JavaVersionFromForgeRunBat -Path $runBatPath
        if ($detected) { return $detected }
    }

    $startServerBatPath = Join-Path $InstancePath "startserver.bat"
    if (Test-Path $startServerBatPath) {
        $detected = Get-JavaVersionFromNeoForgeStartServerBat -Path $startServerBatPath
        if ($detected) { return $detected }
    }

    $fabricJar = Get-ChildItem -Path $InstancePath -Filter "fabric-server-mc.*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fabricJar) {
        $detected = Get-JavaVersionFromFabricServerJar -FileName $fabricJar.Name
        if ($detected) { return $detected }
    }

    $forgeInstallerJar = Get-ChildItem -Path $InstancePath -Filter "forge-*-installer.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($forgeInstallerJar) {
        $detected = Get-JavaVersionFromForgeInstallerJar -FileName $forgeInstallerJar.Name
        if ($detected) { return $detected }
    }

    return $null
}

# Reads a ServerPackCreator variables.txt (simple KEY=VALUE lines, '#'
# comments). Prefers RECOMMENDED_JAVA_VERSION when present (the packer
# already worked it out); falls back to translating MINECRAFT_VERSION via
# the same table the Modrinth/.mrpack path uses.
function Get-JavaVersionFromVariablesFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $vars = @{}
    foreach ($line in (Get-Content -Path $Path -Encoding ascii)) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $idx = $line.IndexOf('=')
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        $vars[$key] = $val
    }

    if ($vars["RECOMMENDED_JAVA_VERSION"] -match '^\d+$') {
        return [int]$vars["RECOMMENDED_JAVA_VERSION"]
    }
    if ($vars["MINECRAFT_VERSION"]) {
        try { return Get-JavaVersionForMinecraft -McVersion $vars["MINECRAFT_VERSION"] }
        catch { return $null }
    }
    return $null
}

# Modern Forge (1.17+) server installs generate a run.bat that references
# "libraries/net/minecraftforge/forge/<mcVersion>-<forgeVersion>/...", which
# is enough to recover the Minecraft version without anything else.
function Get-JavaVersionFromForgeRunBat {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $content = Get-Content -Path $Path -Raw -Encoding ascii
    if ($content -match 'libraries[/\\]net[/\\]minecraftforge[/\\]forge[/\\](\d+(?:\.\d+){1,2})-') {
        try { return Get-JavaVersionForMinecraft -McVersion $matches[1] }
        catch { return $null }
    }
    return $null
}

# All-the-Mods-style NeoForge packs ship a startserver.bat that downloads
# and runs the NeoForge installer on first launch, so there's no run.bat or
# variables.txt to read yet. The script itself already states the Java
# requirement in plain text (e.g. "Minecraft 1.21 requires Java 21"), so
# that's read directly instead of re-deriving it from a version table.
function Get-JavaVersionFromNeoForgeStartServerBat {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $content = Get-Content -Path $Path -Raw -Encoding ascii
    if ($content -match 'requires Java\s+(\d+)') {
        return [int]$matches[1]
    }
    return $null
}

# The official Fabric installer names its server jar
# "fabric-server-mc.<mcVersion>-loader.<loaderVersion>-launcher.<launcherVersion>.jar",
# so raw Fabric packs (no ServerPackCreator variables.txt) reveal their
# Minecraft version through the filename alone.
function Get-JavaVersionFromFabricServerJar {
    param(
        [Parameter(Mandatory = $true)][string]$FileName
    )

    if ($FileName -match '^fabric-server-mc\.(\d+(?:\.\d+){1,2})-loader\.') {
        try { return Get-JavaVersionForMinecraft -McVersion $matches[1] }
        catch { return $null }
    }
    return $null
}

# Raw Forge packs ship their installer jar as
# "forge-<mcVersion>-<forgeVersion>-installer.jar" and, before it's ever
# been run, there's no run.bat yet to read the version from instead.
function Get-JavaVersionFromForgeInstallerJar {
    param(
        [Parameter(Mandatory = $true)][string]$FileName
    )

    if ($FileName -match '^forge-(\d+(?:\.\d+){1,2})-[\d.]+-installer\.jar$') {
        try { return Get-JavaVersionForMinecraft -McVersion $matches[1] }
        catch { return $null }
    }
    return $null
}

# Picks which launcher script start.ps1 should invoke for a manually-copied-
# in (or auto-extracted) modpack instance, in the same priority order
# Get-DetectedJavaVersion checks its signals: run.bat (modern Forge/
# NeoForge), then start.bat (raw Fabric), then startserver.bat (ATM-style
# NeoForge packs that self-install). Returns $null when none exist, so the
# caller can report a clear "nothing to launch" error instead of guessing.
function Get-ModpackLauncherScript {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )

    foreach ($candidate in @("run.bat", "start.bat", "startserver.bat")) {
        if (Test-Path (Join-Path $InstancePath $candidate)) { return $candidate }
    }
    return $null
}
