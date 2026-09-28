# Automatic world backups, taken by start.ps1 before launching (the world
# is closed and consistent then - nothing has it open). Restoring one is
# Manage Maps -> Import, which finds the level.dat inside these zips.
# Loaded via dot-source.

. (Join-Path $PSScriptRoot "worlds-helpers.ps1")   # Get-ServerProperty

# Zips the active world to <server>\backups\<world>-yyyy-MM-dd_HHmm.zip, at
# most once a day, keeping the newest $Keep of that world. Returns the zip's
# path, or $null when there was nothing to do (already backed up today, or
# no world yet on a first start). Throws on failure, leaving no partial zip.
function Backup-World {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [int]$Keep = 5,
        [datetime]$Now = (Get-Date)
    )
    $propsPath = Join-Path $InstancePath "server.properties"
    $levelName = if (Test-Path $propsPath) { Get-ServerProperty $propsPath "level-name" }
    if (-not $levelName) { $levelName = "world" }

    $world = Join-Path $InstancePath $levelName
    if (-not (Test-Path (Join-Path $world "level.dat"))) { return $null }

    $backupDir = Join-Path $InstancePath "backups"
    $pattern = '^' + [regex]::Escape($levelName) + '-\d{4}-\d{2}-\d{2}_\d{4}\.zip$'
    $existing = @(Get-ChildItem -Path $backupDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern })
    if ($existing | Where-Object { $_.Name -like "$levelName-$($Now.ToString('yyyy-MM-dd'))_*" }) { return $null }

    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $zip = Join-Path $backupDir "$levelName-$($Now.ToString('yyyy-MM-dd_HHmm')).zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        # Fastest: a big modded world is mostly already-compressed region files.
        [System.IO.Compression.ZipFile]::CreateFromDirectory($world, $zip, [System.IO.Compression.CompressionLevel]::Fastest, $true)
    } catch {
        Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
        throw
    }

    # Names sort by date, so the oldest go first.
    @(Get-ChildItem -Path $backupDir -File | Where-Object { $_.Name -match $pattern } | Sort-Object Name -Descending) |
        Select-Object -Skip $Keep | Remove-Item -Force
    return $zip
}
