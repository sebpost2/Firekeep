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

# True when the file on disk has exactly the zip entry's bytes.
function Test-ZipEntryMatchesFile {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -ne $Entry.Length) { return $false }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $zipStream = $Entry.Open()
        try { $zipHash = $sha.ComputeHash($zipStream) } finally { $zipStream.Dispose() }
        $fileStream = [System.IO.File]::OpenRead($Path)
        try { $fileHash = $sha.ComputeHash($fileStream) } finally { $fileStream.Dispose() }
        return [BitConverter]::ToString($zipHash) -eq [BitConverter]::ToString($fileHash)
    } finally {
        $sha.Dispose()
    }
}

# Copies every file under $Prefix in the zip into $Destination (keeping
# subfolders, skipping the $ExcludeTop folders), then checks each copied file
# byte for byte against the zip. Lesson from the Arcadia build: a wildcard
# unzip silently dropped every file inside subfolders, so a copy is only
# trusted once verified. Refuses entries that would land outside
# $Destination (the zip comes from the internet). Returns the file count.
function Expand-ZipFolderVerified {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExcludeTop = @()
    )
    $root = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $copied = @()
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if (-not $name.StartsWith($Prefix) -or $name.EndsWith('/')) { continue }
            $relative = $name.Substring($Prefix.Length)
            if (-not $relative) { continue }
            if ($ExcludeTop -contains ($relative -split '/')[0]) { continue }

            $target = [System.IO.Path]::GetFullPath((Join-Path $Destination ($relative -replace '/', '\')))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Unsafe path in the modpack zip: $name"
            }
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target)) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            $copied += [pscustomobject]@{ Entry = $entry; Path = $target }
        }
        foreach ($c in $copied) {
            if (-not (Test-ZipEntryMatchesFile -Entry $c.Entry -Path $c.Path)) {
                throw "Extracted file doesn't match the modpack zip: $($c.Entry.FullName)"
            }
        }
        return $copied.Count
    } finally {
        $zip.Dispose()
    }
}

# Asks CurseForge where a file lives without downloading it: the download
# endpoint answers 307 with the CDN URL, whose last segment is the real file
# name (so non-jar files can be skipped before downloading anything).
# -BaseUrl exists for tests.
function Resolve-CurseForgeFile {
    param(
        [Parameter(Mandatory = $true)][int]$ProjectId,
        [Parameter(Mandatory = $true)][int]$FileId,
        [string]$BaseUrl = "https://www.curseforge.com"
    )
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $request = [System.Net.HttpWebRequest]::Create("$BaseUrl/api/v1/mods/$ProjectId/files/$FileId/download")
    $request.Method = "HEAD"
    $request.AllowAutoRedirect = $false
    $request.Timeout = 30000
    $response = $request.GetResponse()   # 4xx/5xx throw; 3xx don't with redirects off
    try { $location = $response.Headers["Location"] } finally { $response.Close() }
    if (-not $location) { throw "CurseForge gave no download location for project $ProjectId file $FileId" }
    $uri = New-Object System.Uri((New-Object System.Uri($BaseUrl)), $location)
    $fileName = [System.Uri]::UnescapeDataString(($uri.AbsolutePath -split '/')[-1])
    return [pscustomobject]@{ FileName = $fileName; Url = $uri.AbsoluteUri }
}

# Downloads to <Path>.part and renames only when complete, so a failed or
# interrupted download never leaves a truncated jar where the server loads it.
function Save-UrlToFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path
    )
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $part = "$Path.part"
    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Url, $part)
        Move-Item -LiteralPath $part -Destination $Path -Force
    } catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw
    } finally {
        $client.Dispose()
    }
}

# Runs -Work once per item, $Throttle at a time, retrying failures up to
# $Retries attempts. Results come back in input order as
# { Item; Ok; Result; Error }. The work runs in separate runspaces, which
# only see the functions named in -Functions - scriptblocks are passed as
# text, never as live objects (they don't cross runspaces reliably).
function Invoke-ParallelDownload {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][scriptblock]$Work,
        [string[]]$Functions = @(),
        [int]$Throttle = 6,
        [int]$Retries = 3,
        [string]$Activity = "Downloading"
    )
    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($name in $Functions) {
        $definition = (Get-Command $name -CommandType Function).Definition
        $state.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($name, $definition)))
    }
    $pool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $state, $Host)
    $pool.Open()

    $wrapper = {
        param($workText, $item, $retries)
        $work = [scriptblock]::Create($workText)
        $lastError = $null
        for ($attempt = 1; $attempt -le $retries; $attempt++) {
            try {
                $result = & $work $item
                return [pscustomobject]@{ Ok = $true; Result = $result; Error = $null }
            } catch {
                $lastError = $_.Exception.Message
                Start-Sleep -Milliseconds (250 * $attempt)
            }
        }
        return [pscustomobject]@{ Ok = $false; Result = $null; Error = $lastError }
    }

    $jobs = @()
    try {
        foreach ($item in $Items) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            $ps.AddScript($wrapper.ToString()).AddArgument($Work.ToString()).AddArgument($item).AddArgument($Retries) | Out-Null
            $jobs += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); Item = $item; Outcome = $null }
        }
        $total = $jobs.Count
        do {
            $done = 0
            foreach ($job in $jobs) {
                if (-not $job.Outcome -and $job.Handle.IsCompleted) {
                    $job.Outcome = @($job.PS.EndInvoke($job.Handle)) | Select-Object -Last 1
                    if (-not $job.Outcome) { $job.Outcome = [pscustomobject]@{ Ok = $false; Result = $null; Error = "no result" } }
                }
                if ($job.Outcome) { $done++ }
            }
            if ($total -gt 0) { Write-Progress -Activity $Activity -Status "$done of $total" -PercentComplete ([int](100 * $done / $total)) }
            if ($done -lt $total) { Start-Sleep -Milliseconds 200 }
        } while ($done -lt $total)
        Write-Progress -Activity $Activity -Completed
        return @($jobs | ForEach-Object {
            [pscustomobject]@{ Item = $_.Item; Ok = [bool]$_.Outcome.Ok; Result = $_.Outcome.Result; Error = $_.Outcome.Error }
        })
    } finally {
        foreach ($job in $jobs) { $job.PS.Dispose() }
        $pool.Close()
        $pool.Dispose()
    }
}

# MISSING-MODS.txt: mods an import couldn't download, for the user to fetch
# by hand. Human-readable; each block starts with a "mod:" line that code
# reads back ("mod: ? (project P, file F)" when the name was never found).
function Write-MissingModsFile {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )
    $lines = @(
        "These mods couldn't be downloaded automatically.",
        "Download each one from its link and put the .jar file in this server's",
        "'mods' folder, then press Start again. The version must be exactly the",
        "one named here, or players won't be able to join.",
        ""
    )
    foreach ($e in $Entries) {
        $label = if ($e.FileName) { $e.FileName } else { "? (project $($e.ProjectId), file $($e.FileId))" }
        $lines += "mod: $label"
        $lines += "  page:     https://www.curseforge.com/projects/$($e.ProjectId)"
        $lines += "  download: https://www.curseforge.com/api/v1/mods/$($e.ProjectId)/files/$($e.FileId)/download"
        $lines += ""
    }
    [System.IO.File]::WriteAllLines((Join-Path $InstancePath "MISSING-MODS.txt"), [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
}

# The entries of MISSING-MODS.txt whose exact jar isn't in mods\ yet. Once
# none are left the list is deleted, so Start stops being blocked. A
# different version of a mod doesn't count - players must match exactly.
function Get-MissingModDownloads {
    param([Parameter(Mandatory = $true)][string]$InstancePath)
    $listPath = Join-Path $InstancePath "MISSING-MODS.txt"
    if (-not (Test-Path -LiteralPath $listPath)) { return @() }

    $entries = @()
    $current = $null
    foreach ($line in [System.IO.File]::ReadAllLines($listPath)) {
        if ($line -match '^mod: \? \(project (\d+), file (\d+)\)$') {
            $current = [pscustomobject]@{ FileName = $null; ProjectId = [int]$Matches[1]; FileId = [int]$Matches[2] }
            $entries += $current
        } elseif ($line -match '^mod: (.+)$') {
            $current = [pscustomobject]@{ FileName = $Matches[1]; ProjectId = 0; FileId = 0 }
            $entries += $current
        } elseif ($current -and $line -match '/api/v1/mods/(\d+)/files/(\d+)/download') {
            $current.ProjectId = [int]$Matches[1]
            $current.FileId = [int]$Matches[2]
        }
    }

    $modsDir = Join-Path $InstancePath "mods"
    $missing = @($entries | Where-Object { -not $_.FileName -or -not (Test-Path -LiteralPath (Join-Path $modsDir $_.FileName)) })
    if ($missing.Count -eq 0) { Remove-Item -LiteralPath $listPath -Force }
    return $missing
}
