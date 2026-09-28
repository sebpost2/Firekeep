# Pure logic behind the Server Settings screen (Start-Gui.ps1). Reads go
# through Read-ServerProperties (rcon.ps1); writes go through the existing
# Set-ServerProperty (worlds-helpers.ps1) for server.properties, and the
# Get/Set-RunConfigMaxRam functions below for run.config.ps1's $MaxRam.
# Loaded via dot-source.

# Minecraft's own hard-coded defaults for the curated fields, used to
# pre-fill the form when a brand-new server's server.properties doesn't
# have these keys yet (only the RCON lines exist until Minecraft's first
# boot populates the rest).
function Get-ServerPropertyDefaults {
    return @{
        "difficulty"       = "easy"
        "pvp"              = "true"
        "white-list"       = "false"
        "max-players"      = "20"
        "motd"             = "A Minecraft Server"
        "spawn-protection" = "16"
    }
}

# Keys the Server Settings screen must never show or let a user edit -
# auto-generated at server creation (New-ServerFromTemplate) and required
# by the existing Stop Server flow. Clearing/editing them would silently
# break Stop Server.
function Get-ProtectedPropertyKeys {
    return @("enable-rcon", "rcon.port", "rcon.password")
}

# Merges a server.properties hashtable (from Read-ServerProperties) with
# the curated defaults - file value wins when present, default fills gaps.
function Get-CuratedPropertyValues {
    param([Parameter(Mandatory = $true)][hashtable]$Props)
    $defaults = Get-ServerPropertyDefaults
    $result = @{}
    foreach ($key in $defaults.Keys) {
        $result[$key] = if ($Props.ContainsKey($key)) { $Props[$key] } else { $defaults[$key] }
    }
    return $result
}

# Validates a numeric field (max players, spawn protection) without
# blocking Save - invalid input just reverts to the last known-good value.
function ConvertTo-ClampedInt {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$FallbackValue
    )
    $parsed = 0
    if ([int]::TryParse($Value.Trim(), [ref]$parsed) -and $parsed -ge 0) {
        return [string]$parsed
    }
    return $FallbackValue
}

# Raw server.properties content for the advanced/escape-hatch text box,
# with protected (RCON) and curated (already editable via the form) key
# lines stripped out - comments and every other key pass through as-is.
# Excluding curated keys too (not just protected ones) avoids the same
# key being editable in two places at once with no defined winner.
function Get-AdvancedPropertiesText {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    $skip = @(Get-ProtectedPropertyKeys) + @((Get-ServerPropertyDefaults).Keys)
    $lines = Get-Content -Path $Path -Encoding ascii | Where-Object {
        if ($_ -match '^\s*#') { return $true }
        $idx = $_.IndexOf('=')
        if ($idx -lt 1) { return $true }
        $key = $_.Substring(0, $idx).Trim()
        return -not ($skip -contains $key)
    }
    return ($lines -join "`r`n")
}

# Writes back whatever key=value lines the user left in the advanced text
# box, via the existing Set-ServerProperty (worlds-helpers.ps1) - one call
# per key, preserving the rest of the file untouched. Protected and
# curated keys are refused even if present in the text (defense in depth;
# Get-AdvancedPropertiesText already keeps them out of that text in normal
# use).
function Save-AdvancedPropertiesLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $skip = @(Get-ProtectedPropertyKeys) + @((Get-ServerPropertyDefaults).Keys)
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*#') { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1)
        if ($skip -contains $key) { continue }
        Set-ServerProperty $Path $key $val
    }
}

# Reads $MaxRam out of a server's run.config.ps1 via regex rather than
# dot-sourcing it, since that file also sets $ServerJar/$UseModpackLauncher
# and executing it just to read one value would be needless (and risky if
# the file ever grows side effects).
function Get-RunConfigMaxRam {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return "6G" }
    $content = Get-Content -Path $Path -Raw
    if ($content -match '\$MaxRam\s*=\s*"([^"]*)"') { return $Matches[1] }
    return "6G"
}

# Writes $MaxRam back into run.config.ps1 in place, same approach
# AddServerScreen's Set-RunConfigJavaAndRam (mrpack-helpers.ps1) uses for
# the creation flow - a straight regex substitution, everything else in
# the file untouched.
function Set-RunConfigMaxRam {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$MaxRam
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $content = [System.IO.File]::ReadAllText($Path, $utf8NoBom)
    $content = $content -replace '\$MaxRam\s*=\s*"[^"]*"', "`$MaxRam = `"$MaxRam`""
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

# Aikar's widely used G1 garbage-collector flags for Minecraft servers
# (https://docs.papermc.io/paper/aikars-flags) - fewer, shorter lag spikes
# than the JVM defaults. Only added when a pack doesn't pick its own GC.
function Get-AikarFlags {
    return @(
        "-XX:+UseG1GC", "-XX:+ParallelRefProcEnabled", "-XX:MaxGCPauseMillis=200",
        "-XX:+UnlockExperimentalVMOptions", "-XX:+DisableExplicitGC", "-XX:+AlwaysPreTouch",
        "-XX:G1NewSizePercent=30", "-XX:G1MaxNewSizePercent=40", "-XX:G1HeapRegionSize=8M",
        "-XX:G1ReservePercent=20", "-XX:G1HeapWastePercent=5", "-XX:G1MixedGCCountTarget=4",
        "-XX:InitiatingHeapOccupancyPercent=15", "-XX:G1MixedGCLiveThresholdPercent=90",
        "-XX:G1RSetUpdatingPauseTimePercent=5", "-XX:SurvivorRatio=32", "-XX:+PerfDisableSharedMem",
        "-XX:MaxTenuringThreshold=1", "-Dusing.aikars.flags=https://mcflags.emc.gs", "-Daikars.new.flags=true"
    )
}

$RamValuePattern = '[0-9]+[KkMmGg]?'

# The max memory a server really starts with. Modpack launchers ignore
# run.config.ps1's $MaxRam: Forge/NeoForge's run.bat reads user_jvm_args.txt,
# ServerPackCreator packs read JAVA_ARGS in variables.txt. So those win when
# present, and $MaxRam only applies to servers start.ps1 launches directly.
function Get-ServerMaxRam {
    param([Parameter(Mandatory = $true)][string]$InstancePath)
    $jvmArgsPath = Join-Path $InstancePath "user_jvm_args.txt"
    if (Test-Path $jvmArgsPath) {
        $m = Select-String -Path $jvmArgsPath -Pattern "^\s*-Xmx($RamValuePattern)\s*$" | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    $varsPath = Join-Path $InstancePath "variables.txt"
    if (Test-Path $varsPath) {
        $m = Select-String -Path $varsPath -Pattern "^JAVA_ARGS=.*-Xmx($RamValuePattern)" | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return Get-RunConfigMaxRam -Path (Join-Path $InstancePath "run.config.ps1")
}

# Writes max memory everywhere a launcher might read it (see Get-ServerMaxRam).
# In user_jvm_args.txt, -Xms is set equal to -Xmx (Aikar's advice) and
# Aikar's flags are added if the pack chose no garbage collector itself.
function Set-ServerMaxRam {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][string]$MaxRam
    )
    # No BOM: java reads user_jvm_args.txt as an @argfile and a BOM breaks it.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $configPath = Join-Path $InstancePath "run.config.ps1"
    if (Test-Path $configPath) { Set-RunConfigMaxRam -Path $configPath -MaxRam $MaxRam }

    $jvmArgsPath = Join-Path $InstancePath "user_jvm_args.txt"
    if (Test-Path $jvmArgsPath) {
        $lines = @([System.IO.File]::ReadAllLines($jvmArgsPath) | Where-Object { $_ -notmatch '^\s*-Xm[sx]' })
        $lines += "-Xms$MaxRam", "-Xmx$MaxRam"
        if (-not ($lines -match '^\s*-XX:\+Use\w+GC')) { $lines += Get-AikarFlags }
        [System.IO.File]::WriteAllLines($jvmArgsPath, [string[]]$lines, $utf8NoBom)
    }

    $varsPath = Join-Path $InstancePath "variables.txt"
    if (Test-Path $varsPath) {
        $vars = [System.IO.File]::ReadAllLines($varsPath) | ForEach-Object {
            if ($_ -match '^JAVA_ARGS=') {
                $_ -replace "-Xmx$RamValuePattern", "-Xmx$MaxRam" -replace "-Xms$RamValuePattern", "-Xms$MaxRam"
            } else { $_ }
        }
        [System.IO.File]::WriteAllLines($varsPath, [string[]]$vars, $utf8NoBom)
    }
}

# Memory to suggest for a server: more mods need more, but never so much
# that Windows is left with under 4 GB (the PC swapping lags worse than a
# small heap does), and never under 2 GB.
function Get-SuggestedMaxRam {
    param(
        [Parameter(Mandatory = $true)][int]$TotalRamGB,
        [Parameter(Mandatory = $true)][int]$ModCount
    )
    $byMods = if ($ModCount -le 0) { 3 } elseif ($ModCount -le 50) { 4 } elseif ($ModCount -le 150) { 6 } elseif ($ModCount -le 250) { 8 } else { 10 }
    $gb = [Math]::Max(2, [Math]::Min($byMods, $TotalRamGB - 4))
    return "${gb}G"
}

# "10G" -> 10, "4096M" -> 4; $null for anything it can't read.
function ConvertTo-RamGB {
    param([string]$Value)
    if ($Value -match '^\s*(\d+)\s*[Gg]\s*$') { return [int]$Matches[1] }
    if ($Value -match '^\s*(\d+)\s*[Mm]\s*$') { return [int][Math]::Floor([int]$Matches[1] / 1024) }
    return $null
}

function Get-TotalRamGB {
    return [int][Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
}
