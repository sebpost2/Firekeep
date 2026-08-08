# _shared/scripts/verity-helpers.ps1
# Detection, config, and local-AI-sidecar lifecycle for servers running the
# Verity mod. Loaded via dot-source.

# A server is "Verity-enabled" if its mods/ folder has a verity-*.jar -
# same signature-file-scan pattern Get-DetectedJavaVersion already uses.
function Test-VerityModPresent {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $modsDir = Join-Path $InstancePath "mods"
    if (-not (Test-Path $modsDir)) { return $false }
    $jar = Get-ChildItem -Path $modsDir -Filter "verity-*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$jar
}

# Replaces `Key = "..."` with a new value, but only for lines that fall
# under the given `[Section]` header - so e.g. AISettings.aiProvider and a
# hypothetical same-named key elsewhere never collide. Preserves the
# original line's leading whitespace (verity-common.toml indents nested
# keys with a tab). Section headers are matched by exact text inside the
# brackets (e.g. "GeneralSettings.AISettings" for "[GeneralSettings.AISettings]").
function Set-TomlSectionValue {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    # Cast to [string[]] to ensure proper array handling:
    # - Scalar string inputs (e.g., from Get-Content on single line) become one-element array
    # - Arrays with empty strings (valid TOML blank lines) pass through intact
    # This approach works around Pester v4 issue where [string[]] type constraint fails with arrays containing empty strings
    [string[]]$Lines = @($Lines)

    $result = @()
    $inSection = $false
    $sectionHeader = "[$Section]"

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[.+\]$') {
            $inSection = ($trimmed -eq $sectionHeader)
            $result += $line
            continue
        }
        if ($inSection -and $trimmed -match "^$([regex]::Escape($Key))\s*=") {
            $leading = $line.Substring(0, $line.Length - $line.TrimStart().Length)
            $result += "$leading$Key = `"$Value`""
            continue
        }
        $result += $line
    }
    return $result
}
