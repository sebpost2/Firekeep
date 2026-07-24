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
