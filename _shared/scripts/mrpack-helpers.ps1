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
