# Helpers for installing Modrinth modpacks (.mrpack) via mrpack.exe.
# Loaded via dot-source.

# Translates the modpack's Minecraft version to the Java major version it
# needs, following the same guide that lives as a comment in run.config.ps1:
#   Minecraft 1.16 and earlier -> 8
#   Minecraft 1.17 - 1.20.4     -> 17
#   Minecraft 1.20.5+           -> 21
function Get-JavaVersionForMinecraft {
    param(
        [Parameter(Mandatory = $true)][string]$McVersion
    )

    if ($McVersion -notmatch '^\d+(\.\d+){0,2}$') {
        throw "Could not parse Minecraft version '$McVersion'."
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

# Reads the modpack's Minecraft version directly from the .mrpack (it's a zip
# that carries modrinth.index.json with the metadata), without depending on
# mrpack.exe's output.
function Get-MinecraftVersionFromMrpack {
    param(
        [Parameter(Mandatory = $true)][string]$MrpackPath
    )

    if (-not (Test-Path $MrpackPath)) {
        throw "Could not find the .mrpack file at '$MrpackPath'."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $MrpackPath))
    try {
        $entry = $zip.GetEntry("modrinth.index.json")
        if (-not $entry) {
            throw "The .mrpack '$MrpackPath' has no modrinth.index.json."
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
        throw "modrinth.index.json in '$MrpackPath' has no dependencies.minecraft."
    }
    return $json.dependencies.minecraft
}

# Detects the modpack's mod loader (fabric/forge/quilt/neoforge) by reading
# the same dependencies from modrinth.index.json. mrpack.exe (mrpack-install)
# only auto-installs the server jar for Fabric today: for Forge it fails with
# "forge provider not implemented" and asks you to install the server by
# hand. This lets new-server.ps1 warn BEFORE attempting it, instead of
# leaving the user with a raw Go error mid-install.
function Get-ModpackLoader {
    param(
        [Parameter(Mandatory = $true)][string]$MrpackPath
    )

    if (-not (Test-Path $MrpackPath)) {
        throw "Could not find the .mrpack file at '$MrpackPath'."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $MrpackPath))
    try {
        $entry = $zip.GetEntry("modrinth.index.json")
        if (-not $entry) {
            throw "The .mrpack '$MrpackPath' has no modrinth.index.json."
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

    $deps = $json.dependencies
    if (-not $deps) {
        throw "modrinth.index.json in '$MrpackPath' has no dependencies."
    }
    if ($deps.'fabric-loader') { return "fabric" }
    if ($deps.forge) { return "forge" }
    if ($deps.'quilt-loader') { return "quilt" }
    if ($deps.neoforge) { return "neoforge" }
    throw "Could not detect the modpack's mod loader in '$MrpackPath'."
}

# Updates JavaVersion and MaxRam in an existing run.config.ps1 without
# touching the rest of the file (comments, MinRam, UseModpackLauncher, etc.).
function Set-RunConfigJavaAndRam {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$JavaVersion,
        [Parameter(Mandatory = $true)][string]$MaxRam
    )

    # Explicitly read/write UTF-8 without BOM: Get-Content/Set-Content without
    # -Encoding assume ANSI on files without a BOM (like this one), which
    # breaks accented comments (see _template's run.config.ps1... though this
    # version of the template is plain ASCII English now).
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $content = [System.IO.File]::ReadAllText($Path, $utf8NoBom)
    $content = $content -replace '\$JavaVersion\s*=\s*\d+', "`$JavaVersion = $JavaVersion"
    $content = $content -replace '\$MaxRam\s*=\s*"[^"]*"', "`$MaxRam = `"$MaxRam`""
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}
