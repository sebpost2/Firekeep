# Helpers para instalar modpacks de Modrinth (.mrpack) via mrpack.exe.
# Se carga con dot-source.

# Traduce la version de Minecraft del modpack a la version mayor de Java que
# necesita, segun la misma guia que ya vive como comentario en run.config.ps1:
#   Minecraft 1.16 y anteriores -> 8
#   Minecraft 1.17 - 1.20.4     -> 17
#   Minecraft 1.20.5+           -> 21
function Get-JavaVersionForMinecraft {
    param(
        [Parameter(Mandatory = $true)][string]$McVersion
    )

    if ($McVersion -notmatch '^\d+(\.\d+){0,2}$') {
        throw "No pude interpretar la version de Minecraft '$McVersion'."
    }

    $parts = $McVersion.Split('.') | ForEach-Object { [int]$_ }
    while ($parts.Count -lt 3) { $parts += 0 }
    $major, $minor, $patch = $parts[0], $parts[1], $parts[2]

    if ($major -gt 1 -or $minor -gt 20 -or ($minor -eq 20 -and $patch -ge 5)) {
        return 21
    }
    if ($minor -ge 17) {
        return 17
    }
    return 8
}

# Lee la version de Minecraft del modpack directamente del .mrpack (es un zip
# que trae modrinth.index.json con los metadatos), sin depender de la salida
# de mrpack.exe.
function Get-MinecraftVersionFromMrpack {
    param(
        [Parameter(Mandatory = $true)][string]$MrpackPath
    )

    if (-not (Test-Path $MrpackPath)) {
        throw "No encontre el archivo .mrpack en '$MrpackPath'."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $MrpackPath))
    try {
        $entry = $zip.GetEntry("modrinth.index.json")
        if (-not $entry) {
            throw "El .mrpack '$MrpackPath' no tiene modrinth.index.json."
        }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try {
            $json = $reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }

    if (-not $json.dependencies -or -not $json.dependencies.minecraft) {
        throw "modrinth.index.json en '$MrpackPath' no tiene dependencies.minecraft."
    }
    return $json.dependencies.minecraft
}

# Actualiza JavaVersion y MaxRam en un run.config.ps1 existente sin tocar el
# resto del archivo (comentarios, MinRam, UseModpackLauncher, etc.).
function Set-RunConfigJavaAndRam {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$JavaVersion,
        [Parameter(Mandatory = $true)][string]$MaxRam
    )

    $content = Get-Content -Path $Path -Raw
    $content = $content -replace '\$JavaVersion\s*=\s*\d+', "`$JavaVersion = $JavaVersion"
    $content = $content -replace '\$MaxRam\s*=\s*"[^"]*"', "`$MaxRam = `"$MaxRam`""
    Set-Content -Path $Path -Value $content -NoNewline -Encoding utf8
}
