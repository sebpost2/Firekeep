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
