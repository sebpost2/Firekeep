# Builds the zip to publish: copies only the framework (menu, scripts,
# _template, tests, docs) and leaves out any installed server (worlds, mods,
# ops/whitelist, playit secrets, portable Java runtimes). Usage:
#   .\package-release.ps1
#   .\package-release.ps1 -OutputZip "C:\path\GameServers-release.zip"

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputZip,
    # Used internally by tests: loads the functions without building any zip.
    [switch]$TestOnlyLoadFunctions
)

if (-not $OutputZip) { $OutputZip = Join-Path $Root "GameServers-release.zip" }

# Explicit allow-list of what DOES go in the public release. Everything else
# (installed servers, secrets, Java runtimes) stays out by default, so adding
# a new file to the repo never publishes it by accident.
function Get-ReleaseFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $include = @(
        "Start.bat", "Start.ps1",
        "Stop Server.bat", "Manage Maps.bat", "My Address.bat", "View Tailscale IP.bat",
        "README.md", ".gitignore",
        "_shared\scripts",
        "_shared\tools\mrpack.exe",
        "_shared\tools\playit\playit.exe",
        "Minecraft\scripts",
        "Minecraft\servers\_template",
        "tests"
    )

    $files = @()
    foreach ($rel in $include) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path $full)) { continue }
        if ((Get-Item $full).PSIsContainer) {
            $files += Get-ChildItem -Path $full -Recurse -File | Select-Object -ExpandProperty FullName
        }
        else {
            $files += $full
        }
    }
    return $files
}

if ($TestOnlyLoadFunctions) { return }

$files = Get-ReleaseFiles -Root $Root
if ($files.Count -eq 0) {
    Write-Error "Could not find any files to package (Root: $Root)."
    exit 1
}

$stageDir = Join-Path $env:TEMP ("gameservers-release-" + [Guid]::NewGuid().ToString("N"))
foreach ($f in $files) {
    $rel = $f.Substring($Root.Length).TrimStart('\')
    $dest = Join-Path $stageDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item -Path $f -Destination $dest -Force
}

if (Test-Path $OutputZip) { Remove-Item -Force $OutputZip }
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $OutputZip -Force
Remove-Item -Recurse -Force $stageDir

Write-Host "Release zip created at $OutputZip ($($files.Count) files)."
