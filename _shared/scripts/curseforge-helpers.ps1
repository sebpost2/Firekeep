# Installs a CurseForge "Server Files" .zip download directly into a new
# server instance, so the user doesn't have to extract it and copy the
# contents in by hand. Loaded via dot-source.

. (Join-Path $PSScriptRoot "modloader-helpers.ps1")

# ServerPackCreator-built packs (anything with a variables.txt) ship their
# own start.ps1/start.bat, which the -Force copy in Install-CurseForgeServerZip
# just overwrote our per-instance start.ps1 with. Their start.ps1 is
# self-sufficient (installs Forge/NeoForge, generates user_jvm_args.txt,
# etc.), so rather than fight that overwrite we let it win - but by default
# its JAVA="java" setting makes it hunt the *system* PATH, and finding
# nothing there it tries to interactively self-install Java via a bundled
# tool ("Jabba"), ignoring the portable Java this project already manages.
# Point it at our portable Java instead, using the override variables.txt's
# own comments document (JAVA=<absolute path>, SKIP_JAVA_CHECK=true), and
# download that Java version now - this pack's start.ps1 has no lazy-install
# step of its own (unlike ours, which it just overwrote).
function Set-PortableJavaForVariablesFile {
    param(
        [Parameter(Mandatory = $true)][string]$DestPath,
        [Parameter(Mandatory = $true)][int]$JavaVersion
    )

    $varsPath = Join-Path $DestPath "variables.txt"
    if (-not (Test-Path $varsPath)) { return }

    $mcRoot = Split-Path -Parent (Split-Path -Parent $DestPath)
    $installJavaScript = Join-Path $mcRoot "scripts\install-java.ps1"
    if (-not (Test-Path $installJavaScript)) { return }

    $javaExe = Join-Path $mcRoot "tools\java\$JavaVersion\bin\java.exe"
    # Installs, or repairs a broken install; returns right away when Java works.
    & $installJavaScript -MajorVersion $JavaVersion
    if (-not (Test-Path $javaExe)) { return }

    # variables.txt escapes \ and : with an extra \ (its own documented format).
    $escapedJavaExe = ($javaExe -replace '\\', '\\') -replace ':', '\:'

    $content = Get-Content -Path $varsPath -Encoding ascii
    $content = $content -replace '^JAVA=.*$', "JAVA=`"$escapedJavaExe`""
    $content = $content -replace '^SKIP_JAVA_CHECK=.*$', "SKIP_JAVA_CHECK=true"
    Set-Content -Path $varsPath -Value $content -Encoding ascii
}

# Extracts a CurseForge "Server Files" .zip into $DestPath and returns the
# detected Java version (or $null if the files are recognizable but the
# version can't be pinned down - same "fail closed, let the caller fall
# back to run.config.ps1" contract as Get-DetectedJavaVersion).
#
# CurseForge zips sometimes wrap the actual server files in an extra
# top-level folder (seen in real downloads, e.g. "Into_the_backrooms"), so
# the real root is found by searching recursively for any of the same
# signature files/filenames Get-DetectedJavaVersion already recognizes,
# rather than assuming the zip root is the server root.
#
# Throws if nothing recognizable as CurseForge Server Files is found at
# all (e.g. a client modpack export with only manifest.json/modlist.html -
# a real mistake a user can make, confirmed with a real sample this
# session: DarkRPG's download was a client pack, not Server Files).
function Install-CurseForgeServerZip {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestPath
    )

    $tmp = Join-Path $env:TEMP ("curseforge-import-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $tmp -Force

        $marker = Get-ChildItem -Path $tmp -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq "variables.txt" -or
            $_.Name -eq "run.bat" -or
            $_.Name -eq "startserver.bat" -or
            $_.Name -match '^fabric-server-mc\.' -or
            $_.Name -match '^forge-.*-installer\.jar$'
        } | Select-Object -First 1

        if (-not $marker) {
            throw "That .zip doesn't look like CurseForge 'Server Files' - no run.bat/variables.txt/start script found inside it. Make sure you downloaded Server Files, not the modpack itself."
        }

        $serverRoot = Split-Path -Parent $marker.FullName
        Copy-Item -Path (Join-Path $serverRoot "*") -Destination $DestPath -Recurse -Force

        $javaVersion = Get-DetectedJavaVersion -InstancePath $DestPath
        if ($javaVersion) {
            Set-PortableJavaForVariablesFile -DestPath $DestPath -JavaVersion $javaVersion
        }
        return $javaVersion
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- CurseForge client exports (manifest.json + overrides/) ----------------
# See docs/superpowers/specs/2026-09-28-curseforge-client-import-design.md.

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Reads a zip entry as UTF-8 text.
function Read-ZipEntryText {
    param([Parameter(Mandatory = $true)]$Entry)
    $reader = New-Object System.IO.StreamReader($Entry.Open(), [System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

# "ServerFiles" when the zip has a server launcher outside overrides/ (the
# same markers Install-CurseForgeServerZip looks for), "ClientExport" when it
# has a root manifest.json of type minecraftModpack and no launcher, $null
# otherwise. Reads the entry list only - nothing is extracted.
function Get-CurseForgeZipKind {
    param([Parameter(Mandatory = $true)][string]$ZipPath)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ($name -like "overrides/*") { continue }
            $leaf = ($name -split '/')[-1]
            if ($leaf -eq "variables.txt" -or $leaf -eq "run.bat" -or $leaf -eq "startserver.bat" -or
                $leaf -match '^fabric-server-mc\.' -or $leaf -match '^forge-.*-installer\.jar$') {
                return "ServerFiles"
            }
        }
        $manifest = $zip.GetEntry("manifest.json")
        if ($manifest) {
            try { $json = Read-ZipEntryText $manifest | ConvertFrom-Json } catch { $json = $null }
            if ($json -and $json.manifestType -eq "minecraftModpack") { return "ClientExport" }
        }
        return $null
    } finally {
        $zip.Dispose()
    }
}

# Reads manifest.json from a client export. Forge only: any other loader
# throws a message meant for the user, before anything is downloaded.
# Optional files ("required": false) are left out - the CurseForge app
# doesn't install them by default, so players won't have them.
function Read-CurseForgeManifest {
    param([Parameter(Mandatory = $true)][string]$ZipPath)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $json = Read-ZipEntryText ($zip.GetEntry("manifest.json")) | ConvertFrom-Json
    } finally {
        $zip.Dispose()
    }

    $loaders = @($json.minecraft.modLoaders)
    $loader = ($loaders | Where-Object { $_.primary } | Select-Object -First 1)
    if (-not $loader) { $loader = $loaders | Select-Object -First 1 }
    $loaderId = "$($loader.id)"
    if ($loaderId -notmatch '^forge-(.+)$') {
        $names = @{ neoforge = "NeoForge"; fabric = "Fabric"; quilt = "Quilt" }
        $kind = ($loaderId -split '-')[0]
        $label = if ($names.ContainsKey($kind)) { $names[$kind] } else { $kind }
        throw "This modpack uses $label, which Firekeep can't import yet (Forge only for now)."
    }
    $forgeVersion = $Matches[1]

    $files = @($json.files | Where-Object { $_.required -ne $false } | ForEach-Object {
        [pscustomobject]@{ ProjectId = [int]$_.projectID; FileId = [int]$_.fileID }
    })
    $overrides = if ($json.overrides) { "$($json.overrides)" } else { "overrides" }
    return [pscustomobject]@{
        McVersion    = "$($json.minecraft.version)"
        ForgeVersion = $forgeVersion
        Files        = $files
        OverridesDir = $overrides
    }
}
