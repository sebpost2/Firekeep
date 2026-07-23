# Arma el zip para publicar: copia solo el framework (menu, scripts, _template,
# tests, docs) y deja afuera cualquier server instalado (mundos, mods, ops/whitelist,
# secretos de playit, runtimes de Java portables). Uso:
#   .\package-release.ps1
#   .\package-release.ps1 -OutputZip "C:\ruta\GameServers-release.zip"

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputZip,
    # Uso interno de los tests: carga las funciones sin armar ningun zip.
    [switch]$TestOnlyLoadFunctions
)

if (-not $OutputZip) { $OutputZip = Join-Path $Root "GameServers-release.zip" }

# Lista explicita de lo que SI va en el release publico. Todo lo demas
# (servers instalados, secretos, runtimes de Java) queda afuera por default,
# asi agregar un archivo nuevo al repo no lo publica sin querer.
function Get-ReleaseFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $include = @(
        "Start.bat", "Start.ps1",
        "Detener Server.bat", "Administrar Mapas.bat", "Mi Direccion.bat", "Ver IP Tailscale.bat",
        "LEEME.md", "CONEXION - Opciones y Plan.md", ".gitignore",
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
    Write-Error "No encontre ningun archivo para empaquetar (Root: $Root)."
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

Write-Host "Release zip creado en $OutputZip ($($files.Count) archivos)."
