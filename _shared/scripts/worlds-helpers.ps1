# Pure-ish logic behind world (map) management, shared by the console menu
# (Minecraft\scripts\worlds.ps1) and the Manage Maps GUI window. Loaded via
# dot-source.

$Script:TrashDir = "_trash"

# True if the file is open exclusively by another process (server alive).
function Test-FileLocked {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $fs.Close(); $fs.Dispose()
        return $false
    } catch {
        return $true
    }
}

function Get-ServerProperty {
    param($PropsPath, $Key)
    foreach ($l in (Get-Content -Path $PropsPath -Encoding ascii)) {
        if ($l -match "^\s*$([regex]::Escape($Key))\s*=(.*)$") { return $matches[1].Trim() }
    }
    return $null
}

function Set-ServerProperty {
    param($PropsPath, $Key, $Value)
    # Changes (or adds) a key without touching the rest of the file. Backs up once.
    Copy-Item -Path $PropsPath -Destination "$PropsPath.bak" -Force
    $lines = @(Get-Content -Path $PropsPath -Encoding ascii)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines[$i] = "$Key=$Value"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "$Key=$Value" }
    Set-Content -Path $PropsPath -Value $lines -Encoding ascii
}

function Get-FolderSizeMB {
    param($Path)
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return 0 }
        return [math]::Round($bytes / 1MB, 1)
    } catch { return 0 }
}

function Test-ValidName {
    param($Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -eq "." -or $Name -eq "..") { return $false }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { if ($Name.Contains($c)) { return $false } }
    if ($Name -eq $Script:TrashDir) { return $false }
    return $true
}

# Returns the list of worlds for an instance (folders with level.dat + the active one).
function Get-Worlds {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [string]$ActiveName
    )
    $result = @()
    $seen = @{}
    Get-ChildItem -Path $InstancePath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $Script:TrashDir } |
        ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "level.dat")) {
                $result += [PSCustomObject]@{
                    Name     = $_.Name
                    Path     = $_.FullName
                    IsActive = ($_.Name -eq $ActiveName)
                    Exists   = $true
                }
                $seen[$_.Name] = $true
            }
        }
    # The active world might not be generated yet (no level.dat yet).
    if ($ActiveName -and -not $seen.ContainsKey($ActiveName)) {
        $p = Join-Path $InstancePath $ActiveName
        $result += [PSCustomObject]@{
            Name     = $ActiveName
            Path     = $p
            IsActive = $true
            Exists   = (Test-Path $p)
        }
    }
    return @($result | Sort-Object -Property @{Expression = "IsActive"; Descending = $true}, "Name")
}
