# Pure logic behind the Server Settings screen (Start-Gui.ps1). Reads go
# through Read-ServerProperties (rcon.ps1); writes go through the existing
# Set-ServerProperty (worlds-helpers.ps1) - this file adds no new
# server.properties I/O of its own, only the curated-field/defaults/
# protection logic layered on top. Loaded via dot-source.

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
