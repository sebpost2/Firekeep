# CurseForge Client-Export Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dropping a Forge CurseForge client export (`manifest.json` + `overrides/`) on Add Server builds a server that boots, downloading the mods itself, listing any it couldn't fetch, and offering a confirmed one-click removal for mods the server refuses to load.

**Architecture:** New import functions in `_shared\scripts\curseforge-helpers.ps1` (zip detection, manifest, parallel name resolution + downloads in a runspace pool, byte-verified overrides extraction, Forge installer), a jar lookup in `gui-helpers.ps1`, and GUI wiring in `Start-Gui.ps1`/`HomeScreen.xaml`. The existing Add Server background job calls the new import; its progress records drive the hint text.

**Tech Stack:** Windows PowerShell 5.1, WPF (XAML), .NET `System.IO.Compression`, `System.Net.HttpWebRequest`/`WebClient`, runspace pools, Pester 3.4 (`Should Be`, `Should Throw`, `Should Match`, `It -Skip:`).

**Spec:** `docs/superpowers/specs/2026-09-28-curseforge-client-import-design.md`

## Global Constraints

- Forge only. Any other loader in `manifest.json` → throw `This modpack uses <Loader>, which Firekeep can't import yet (Forge only for now).` before anything is downloaded or created.
- Never remove a mod by name. Only the one-click fix moves a jar, only after a confirmation naming it, and only to `<server>\_excluded\client-only\` (never delete).
- Only `.jar` files from the manifest go into `mods/`. Resource packs, shader packs and other non-jar files are skipped.
- `overrides/resourcepacks/` and `overrides/shaderpacks/` are not extracted; everything else under the overrides folder is, then byte-verified (length + SHA-256) against the zip.
- Downloads: 6 in parallel, 3 attempts each, written to `<name>.part` and renamed only when complete.
- Missing mods are listed in `<server>\MISSING-MODS.txt`; Start is blocked while any listed jar (exact filename) is absent from `mods/`.
- CurseForge download endpoint: `https://www.curseforge.com/api/v1/mods/{projectID}/files/{fileID}/download` (no API key; answers 307 with the CDN `Location`). Forge installer: `https://maven.minecraftforge.net/net/minecraftforge/forge/{mc}-{forge}/forge-{mc}-{forge}-installer.jar`, run with `--installServer`.
- PowerShell 5.1 gotchas already hit in this repo: a `.ps1` without BOM is read as ANSI (build non-ASCII test strings with `[char]0x..`); `$ErrorActionPreference = "Stop"` turns native stderr into exceptions; paths with `[` `]` need `-LiteralPath`; don't rely on scriptblock literals crossing runspaces (pass text and `[scriptblock]::Create` inside, or register functions in the pool's `InitialSessionState`).
- Tests clean up processes, listeners and temp folders in `finally` blocks, so a failing test can't leak them.
- Every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Zip entries that escape the destination** (`overrides/../../evil.ps1`, from an untrusted downloaded zip): the import must refuse the zip, not write outside the server folder. → Task 2 test.
2. **Manifest files marked `"required": false`** (optional mods): the CurseForge app doesn't install them by default, so the server must not either, or players' clients won't match. → Task 1 test.
3. **Two manifest entries resolving to the same filename, or a manifest jar also shipped in `overrides/mods/`**: download each name once (no two workers writing the same `.part`), and the overrides copy wins without errors. → Task 5 tests.
4. **Filenames with spaces, URL-encoding or square brackets** (`Oh The Biomes You'll Go.jar`, `[1.20.1]Mod.jar` are common): saved under the decoded name, found again by the missing-mods check and the one-click fix. → Tasks 2, 3, 4 and 6 tests.
5. **A custom overrides folder name** (`"overrides": "files"` in the manifest): honoured, not assumed to be `overrides`. → Task 5 test.

---

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `_shared/scripts/curseforge-helpers.ps1` | Modify | All import logic: zip kind, manifest, verified extraction, name resolution, parallel downloads, missing-mods list, Forge installer, orchestration. |
| `_shared/scripts/gui-helpers.ps1` | Modify | `Get-ClientOnlyModJar` (pure lookup the GUI uses after a failed start). |
| `_shared/scripts/new-server-helpers.ps1` | Modify | Clearer "already exists" message. |
| `Start-Gui.ps1` | Modify | Add Server branching + progress; Start blocked while mods are missing; the two Home buttons. |
| `_shared/gui/HomeScreen.xaml` | Modify | Two link buttons under the hint text. |
| `tests/curseforge-client-export.tests.ps1` | Create | Tests for the import functions, with fixture zips and a fake CurseForge HTTP server. |
| `tests/gui-helpers.tests.ps1` | Modify | Tests for `Get-ClientOnlyModJar`. |
| `README.md`, `CHANGELOG.md` | Modify | Document the new import. |

---

### Task 1: Recognize client exports and read the manifest

**Files:**
- Modify: `_shared/scripts/curseforge-helpers.ps1` (append)
- Create: `tests/curseforge-client-export.tests.ps1`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Get-CurseForgeZipKind -ZipPath <string>` → `"ServerFiles"` | `"ClientExport"` | `$null`
  - `Read-CurseForgeManifest -ZipPath <string>` → `[pscustomobject]@{ McVersion=<string>; ForgeVersion=<string>; Files=@([pscustomobject]@{ProjectId=<int>; FileId=<int>}); OverridesDir=<string> }`
  - Test helpers `New-TestZip -Entries <hashtable path→string|byte[]>` → zip path, and `New-Manifest [-Loader] [-FilesJson] [-Overrides]` → manifest JSON text (in the test file; later tasks append to the same file and reuse them).

- [ ] **Step 1: Write the failing tests**

Create `tests/curseforge-client-export.tests.ps1`:

```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\curseforge-helpers.ps1")
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Builds a zip from @{ "path/in/zip" = "text" or [byte[]] } and returns its path.
function New-TestZip([hashtable]$Entries) {
    $path = Join-Path $env:TEMP ("cf-test-" + [Guid]::NewGuid().ToString("N") + ".zip")
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $out = $entry.Open()
            try {
                $bytes = if ($Entries[$name] -is [byte[]]) { $Entries[$name] } else { [System.Text.Encoding]::UTF8.GetBytes([string]$Entries[$name]) }
                $out.Write($bytes, 0, $bytes.Length)
            } finally { $out.Dispose() }
        }
    } finally { $zip.Dispose(); $stream.Dispose() }
    return $path
}

function New-Manifest([string]$Loader = "forge-47.4.20", [string]$FilesJson = '[{"projectID":1,"fileID":10,"required":true}]', [string]$Overrides = "overrides") {
    return '{"minecraft":{"version":"1.20.1","modLoaders":[{"id":"' + $Loader + '","primary":true}]},"manifestType":"minecraftModpack","files":' + $FilesJson + ',"overrides":"' + $Overrides + '"}'
}

Describe "Get-CurseForgeZipKind" {
    It "recognizes a client export (manifest + overrides, no launcher)" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest); "overrides/config/a.toml" = "x" }
        try { Get-CurseForgeZipKind -ZipPath $zip | Should Be "ClientExport" } finally { Remove-Item $zip }
    }

    It "recognizes Server Files by their launcher" {
        $zip = New-TestZip @{ "Pack/run.bat" = "java @args"; "Pack/mods/a.jar" = "x" }
        try { Get-CurseForgeZipKind -ZipPath $zip | Should Be "ServerFiles" } finally { Remove-Item $zip }
    }

    It "treats a zip with a manifest AND a server launcher as Server Files" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest); "startserver.bat" = "x" }
        try { Get-CurseForgeZipKind -ZipPath $zip | Should Be "ServerFiles" } finally { Remove-Item $zip }
    }

    # A mod config that happens to be called variables.txt must not turn a
    # client export into "Server Files".
    It "ignores launcher-like names inside the overrides folder" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest); "overrides/config/somemod/variables.txt" = "x" }
        try { Get-CurseForgeZipKind -ZipPath $zip | Should Be "ClientExport" } finally { Remove-Item $zip }
    }

    It "returns null for an unrelated zip" {
        $zip = New-TestZip @{ "photos/cat.png" = "x" }
        try { Get-CurseForgeZipKind -ZipPath $zip | Should Be $null } finally { Remove-Item $zip }
    }
}

Describe "Read-CurseForgeManifest" {
    It "reads the Minecraft and Forge versions and the files" {
        $files = '[{"projectID":336184,"fileID":5600004,"required":true},{"projectID":2,"fileID":20,"required":true}]'
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -FilesJson $files) }
        try {
            $m = Read-CurseForgeManifest -ZipPath $zip
            $m.McVersion | Should Be "1.20.1"
            $m.ForgeVersion | Should Be "47.4.20"
            $m.Files.Count | Should Be 2
            $m.Files[0].ProjectId | Should Be 336184
            $m.Files[0].FileId | Should Be 5600004
            $m.OverridesDir | Should Be "overrides"
        } finally { Remove-Item $zip }
    }

    # Review focus 2: optional files aren't installed by the CurseForge app by
    # default, so the server must not have them either.
    It "skips files marked optional" {
        $files = '[{"projectID":1,"fileID":10,"required":true},{"projectID":2,"fileID":20,"required":false}]'
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -FilesJson $files) }
        try {
            $m = Read-CurseForgeManifest -ZipPath $zip
            $m.Files.Count | Should Be 1
            $m.Files[0].ProjectId | Should Be 1
        } finally { Remove-Item $zip }
    }

    It "refuses NeoForge with a clear message" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -Loader "neoforge-21.1.77") }
        try { { Read-CurseForgeManifest -ZipPath $zip } | Should Throw "uses NeoForge, which Firekeep can't import yet" } finally { Remove-Item $zip }
    }

    It "refuses Fabric with a clear message" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -Loader "fabric-0.15.11") }
        try { { Read-CurseForgeManifest -ZipPath $zip } | Should Throw "uses Fabric" } finally { Remove-Item $zip }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: all 9 FAIL (`The term 'Get-CurseForgeZipKind' is not recognized`).

- [ ] **Step 3: Implement**

Append to `_shared/scripts/curseforge-helpers.ps1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: 9 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/curseforge-helpers.ps1 tests/curseforge-client-export.tests.ps1
git commit -m "feat: recognize CurseForge client exports and read their manifest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Byte-verified overrides extraction

**Files:**
- Modify: `_shared/scripts/curseforge-helpers.ps1` (append)
- Modify: `tests/curseforge-client-export.tests.ps1` (append)

**Interfaces:**
- Consumes: `New-TestZip` (test helper from Task 1).
- Produces:
  - `Expand-ZipFolderVerified -ZipPath <string> -Prefix <string, e.g. "overrides/"> -Destination <string> [-ExcludeTop <string[]>]` → `[int]` number of files copied. Throws `Unsafe path in the modpack zip: <entry>` or `Extracted file doesn't match the modpack zip: <entry>`.
  - `Test-ZipEntryMatchesFile -Entry <ZipArchiveEntry> -Path <string>` → `[bool]`

- [ ] **Step 1: Write the failing tests**

Append to `tests/curseforge-client-export.tests.ps1`:

```powershell
Describe "Expand-ZipFolderVerified" {

    function New-Dest { $d = Join-Path $env:TEMP ("cf-dest-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $d | Out-Null; return $d }

    # Lesson 1 from the Arcadia build: a wildcard unzip silently dropped every
    # file inside subfolders.
    It "copies files in nested folders" {
        $zip = New-TestZip @{
            "overrides/config/a.toml"                             = "a"
            "overrides/config/ftbquests/quests/chapters/one.snbt" = "deep"
            "overrides/kubejs/server_scripts/x.js"                = "js"
            "overrides/paragliderSettings.nbt"                    = "nbt"
        }
        $dest = New-Dest
        try {
            Expand-ZipFolderVerified -ZipPath $zip -Prefix "overrides/" -Destination $dest | Should Be 4
            Get-Content (Join-Path $dest "config\ftbquests\quests\chapters\one.snbt") -Raw | Should Match "deep"
            Test-Path (Join-Path $dest "paragliderSettings.nbt") | Should Be $true
        } finally { Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    It "skips the excluded top-level folders and files outside the prefix" {
        $zip = New-TestZip @{
            "manifest.json"                    = "{}"
            "overrides/resourcepacks/pack.zip" = "rp"
            "overrides/shaderpacks/shader.zip" = "sp"
            "overrides/mods/handadded.jar"     = "jar"
        }
        $dest = New-Dest
        try {
            Expand-ZipFolderVerified -ZipPath $zip -Prefix "overrides/" -Destination $dest -ExcludeTop @("resourcepacks", "shaderpacks") | Should Be 1
            Test-Path (Join-Path $dest "mods\handadded.jar") | Should Be $true
            Test-Path (Join-Path $dest "resourcepacks") | Should Be $false
            Test-Path (Join-Path $dest "manifest.json") | Should Be $false
        } finally { Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    # Review focus 1: the zip is downloaded from the internet.
    It "refuses an entry that would land outside the destination" {
        $zip = New-TestZip @{ "overrides/../../escaped.txt" = "x" }
        $dest = New-Dest
        try {
            { Expand-ZipFolderVerified -ZipPath $zip -Prefix "overrides/" -Destination $dest } | Should Throw "Unsafe path"
            Test-Path (Join-Path (Split-Path $dest) "escaped.txt") | Should Be $false
        } finally { Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    # Review focus 4.
    It "keeps square brackets in file names" {
        $zip = New-TestZip @{ "overrides/mods/[1.20.1]Mod.jar" = "jar" }
        $dest = New-Dest
        try {
            Expand-ZipFolderVerified -ZipPath $zip -Prefix "overrides/" -Destination $dest | Should Be 1
            Test-Path -LiteralPath (Join-Path $dest "mods\[1.20.1]Mod.jar") | Should Be $true
        } finally { Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }
}

Describe "Test-ZipEntryMatchesFile" {
    It "detects a file that differs from its zip entry" {
        $zip = New-TestZip @{ "overrides/a.txt" = "original" }
        $dest = Join-Path $env:TEMP ("cf-dest-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dest | Out-Null
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entry = $archive.GetEntry("overrides/a.txt")
            $file = Join-Path $dest "a.txt"
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $file)
            Test-ZipEntryMatchesFile -Entry $entry -Path $file | Should Be $true
            [System.IO.File]::WriteAllText($file, "changed!")
            Test-ZipEntryMatchesFile -Entry $entry -Path $file | Should Be $false
        } finally { $archive.Dispose(); Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: the 5 new tests FAIL (`Expand-ZipFolderVerified` not recognized); the 9 from Task 1 still pass.

- [ ] **Step 3: Implement**

Append to `_shared/scripts/curseforge-helpers.ps1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: 14 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/curseforge-helpers.ps1 tests/curseforge-client-export.tests.ps1
git commit -m "feat: extract modpack overrides with a byte-for-byte check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Resolve names and download in parallel

**Files:**
- Modify: `_shared/scripts/curseforge-helpers.ps1` (append)
- Modify: `tests/curseforge-client-export.tests.ps1` (append)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `Resolve-CurseForgeFile -ProjectId <int> -FileId <int> [-BaseUrl <string>]` → `[pscustomobject]@{ FileName=<decoded string>; Url=<string> }`; throws on no redirect / HTTP error.
  - `Save-UrlToFile -Url <string> -Path <string>` → nothing; writes `<Path>.part` then renames; on failure deletes the `.part` and throws.
  - `Invoke-ParallelDownload -Items <object[]> -Work <scriptblock> [-Functions <string[]>] [-Throttle 6] [-Retries 3] [-Activity <string>]` → array (input order) of `[pscustomobject]@{ Item; Ok=<bool>; Result; Error=<string> }`. `-Work` receives one item as its only argument and runs in a runspace where only the functions named in `-Functions` exist. Writes `Write-Progress -Activity $Activity -Status "<done> of <total>"`. (Spec §4 listed `-Items -Throttle -Retries`; `-Work`/`-Functions`/`-Activity` let the same function do both the name lookups and the downloads, as the spec describes.)
  - Test helpers `Start-FakeCurseForge -Files <hashtable "projectId/fileId" → @{Name; Body=[byte[]]}> [-FailTimes <hashtable name→int>]` → `@{ BaseUrl; Http; PS; Hits }`, `Stop-FakeCurseForge`, `Get-Bytes <string>` → `[byte[]]`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/curseforge-client-export.tests.ps1`:

```powershell
# Fake CurseForge + CDN on localhost. HEAD/GET /api/v1/mods/<p>/files/<f>/download
# answers 307 to /files/<escaped name>; GET /files/<name> serves the body, or
# 500 for the first FailTimes[name] requests. Single-threaded on purpose.
function Start-FakeCurseForge {
    param([hashtable]$Files, [hashtable]$FailTimes = @{})
    $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    $base = "http://localhost:$port"
    $http = New-Object System.Net.HttpListener
    $http.Prefixes.Add("$base/")
    $http.Start()
    $hits = [hashtable]::Synchronized(@{})
    $ps = [powershell]::Create()
    $ps.AddScript({
        param($http, $files, $failTimes, $hits, $base)
        while ($http.IsListening) {
            try { $ctx = $http.GetContext() } catch { break }
            $path = $ctx.Request.Url.AbsolutePath
            $res = $ctx.Response
            if ($path -match '^/api/v1/mods/(\d+)/files/(\d+)/download$' -and $files.ContainsKey("$($Matches[1])/$($Matches[2])")) {
                $res.StatusCode = 307
                $res.RedirectLocation = "$base/files/" + [Uri]::EscapeDataString($files["$($Matches[1])/$($Matches[2])"].Name) + "?api-key=test"
            } elseif ($path -match '^/files/(.+)$') {
                $name = [Uri]::UnescapeDataString($Matches[1])
                $hits[$name] = 1 + [int]$hits[$name]
                $body = $null
                foreach ($f in $files.Values) { if ($f.Name -eq $name) { $body = $f.Body } }
                if ($null -eq $body -or $hits[$name] -le [int]$failTimes[$name]) {
                    $res.StatusCode = 500
                } else {
                    $res.ContentLength64 = $body.Length
                    $res.OutputStream.Write($body, 0, $body.Length)
                }
            } else {
                $res.StatusCode = 404
            }
            $res.Close()
        }
    }).AddArgument($http).AddArgument($Files).AddArgument($FailTimes).AddArgument($hits).AddArgument($base) | Out-Null
    $null = $ps.BeginInvoke()
    return [pscustomobject]@{ BaseUrl = $base; Http = $http; PS = $ps; Hits = $hits }
}

function Stop-FakeCurseForge($fake) {
    $fake.Http.Stop()
    $fake.Http.Close()
    $fake.PS.Stop()
    $fake.PS.Dispose()
}

function Get-Bytes([string]$Text) { return [System.Text.Encoding]::UTF8.GetBytes($Text) }

Describe "Resolve-CurseForgeFile" {
    # Review focus 4: names with spaces are URL-encoded in the redirect.
    It "reads the decoded file name from the redirect without downloading it" {
        $fake = Start-FakeCurseForge -Files @{ "7/70" = @{ Name = "Oh The Biomes You'll Go-1.0.jar"; Body = (Get-Bytes "jar") } }
        try {
            $r = Resolve-CurseForgeFile -ProjectId 7 -FileId 70 -BaseUrl $fake.BaseUrl
            $r.FileName | Should Be "Oh The Biomes You'll Go-1.0.jar"
            $r.Url | Should Match "^$([regex]::Escape($fake.BaseUrl))/files/"
            $fake.Hits.Count | Should Be 0
        } finally { Stop-FakeCurseForge $fake }
    }

    It "throws for a file CurseForge doesn't know" {
        $fake = Start-FakeCurseForge -Files @{}
        try { { Resolve-CurseForgeFile -ProjectId 1 -FileId 2 -BaseUrl $fake.BaseUrl } | Should Throw } finally { Stop-FakeCurseForge $fake }
    }
}

Describe "Invoke-ParallelDownload + Save-UrlToFile" {

    function New-Dest { $d = Join-Path $env:TEMP ("cf-dl-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $d | Out-Null; return $d }
    $download = { param($i) Save-UrlToFile -Url $i.Url -Path $i.Path }

    It "downloads every file intact, several at a time" {
        $files = @{}
        for ($n = 1; $n -le 10; $n++) { $files["$n/$n"] = @{ Name = "mod$n.jar"; Body = (Get-Bytes ("body-$n" * 100)) } }
        $fake = Start-FakeCurseForge -Files $files
        $dest = New-Dest
        try {
            $items = 1..10 | ForEach-Object { [pscustomobject]@{ Url = "$($fake.BaseUrl)/files/mod$_.jar"; Path = (Join-Path $dest "mod$_.jar") } }
            $results = Invoke-ParallelDownload -Items $items -Work $download -Functions @("Save-UrlToFile") -Activity "Downloading mods"
            @($results | Where-Object { -not $_.Ok }).Count | Should Be 0
            [System.IO.File]::ReadAllText((Join-Path $dest "mod7.jar")) | Should Be ("body-7" * 100)
            $results[3].Item.Path | Should Be (Join-Path $dest "mod4.jar")
        } finally { Stop-FakeCurseForge $fake; Remove-Item -Recurse -Force $dest }
    }

    It "keeps a file that fails twice and then works" {
        $fake = Start-FakeCurseForge -Files @{ "1/1" = @{ Name = "flaky.jar"; Body = (Get-Bytes "ok") } } -FailTimes @{ "flaky.jar" = 2 }
        $dest = New-Dest
        try {
            $items = @([pscustomobject]@{ Url = "$($fake.BaseUrl)/files/flaky.jar"; Path = (Join-Path $dest "flaky.jar") })
            $results = Invoke-ParallelDownload -Items $items -Work $download -Functions @("Save-UrlToFile") -Retries 3
            $results[0].Ok | Should Be $true
            $fake.Hits["flaky.jar"] | Should Be 3
        } finally { Stop-FakeCurseForge $fake; Remove-Item -Recurse -Force $dest }
    }

    It "reports a file that always fails, leaving no jar or .part behind" {
        $fake = Start-FakeCurseForge -Files @{ "1/1" = @{ Name = "blocked.jar"; Body = (Get-Bytes "x") } } -FailTimes @{ "blocked.jar" = 99 }
        $dest = New-Dest
        try {
            $items = @([pscustomobject]@{ Url = "$($fake.BaseUrl)/files/blocked.jar"; Path = (Join-Path $dest "blocked.jar") })
            $results = Invoke-ParallelDownload -Items $items -Work $download -Functions @("Save-UrlToFile") -Retries 3
            $results[0].Ok | Should Be $false
            $results[0].Error | Should Match "500"
            @(Get-ChildItem $dest).Count | Should Be 0
        } finally { Stop-FakeCurseForge $fake; Remove-Item -Recurse -Force $dest }
    }

    # Review focus 4.
    It "saves names with square brackets" {
        $fake = Start-FakeCurseForge -Files @{ "1/1" = @{ Name = "[1.20.1]Mod.jar"; Body = (Get-Bytes "b") } }
        $dest = New-Dest
        try {
            $url = "$($fake.BaseUrl)/files/" + [Uri]::EscapeDataString("[1.20.1]Mod.jar")
            $items = @([pscustomobject]@{ Url = $url; Path = (Join-Path $dest "[1.20.1]Mod.jar") })
            $results = Invoke-ParallelDownload -Items $items -Work $download -Functions @("Save-UrlToFile")
            $results[0].Ok | Should Be $true
            Test-Path -LiteralPath (Join-Path $dest "[1.20.1]Mod.jar") | Should Be $true
        } finally { Stop-FakeCurseForge $fake; Remove-Item -Recurse -Force $dest }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: the 6 new tests FAIL (functions not recognized); earlier 14 pass.

- [ ] **Step 3: Implement**

Append to `_shared/scripts/curseforge-helpers.ps1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: 20 passed, 0 failed. If a test hangs or a runspace returns nothing, check first that no scriptblock *object* is handed to a runspace (see Global Constraints) and that `Save-UrlToFile` is listed in `-Functions`.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/curseforge-helpers.ps1 tests/curseforge-client-export.tests.ps1
git commit -m "feat: resolve CurseForge file names and download mods in parallel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The missing-mods list

**Files:**
- Modify: `_shared/scripts/curseforge-helpers.ps1` (append)
- Modify: `tests/curseforge-client-export.tests.ps1` (append)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `Write-MissingModsFile -InstancePath <string> -Entries <object[] of @{FileName=<string or $null>; ProjectId=<int>; FileId=<int>}>` → writes `<InstancePath>\MISSING-MODS.txt`.
  - `Get-MissingModDownloads -InstancePath <string>` → array of `[pscustomobject]@{ FileName=<string or $null>; ProjectId=<int>; FileId=<int> }` still missing; deletes the file and returns `@()` when none remain; returns `@()` when there's no file.
  - (Spec §8 placed `Get-MissingModDownloads` in `gui-helpers.ps1`. It lives here next to `Write-MissingModsFile` so the file format is defined in one place; Task 7 dot-sources this file from the GUI.)

- [ ] **Step 1: Write the failing tests**

Append to `tests/curseforge-client-export.tests.ps1`:

```powershell
Describe "Write-MissingModsFile / Get-MissingModDownloads" {

    function New-Instance { $d = Join-Path $env:TEMP ("cf-inst-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path (Join-Path $d "mods") -Force | Out-Null; return $d }

    It "lists each mod with its page and download link" {
        $dir = New-Instance
        try {
            Write-MissingModsFile -InstancePath $dir -Entries @([pscustomobject]@{ FileName = "Blocked-1.0.jar"; ProjectId = 336184; FileId = 5600004 })
            $text = Get-Content (Join-Path $dir "MISSING-MODS.txt") -Raw
            $text | Should Match "Blocked-1\.0\.jar"
            $text | Should Match "https://www\.curseforge\.com/projects/336184"
            $text | Should Match "https://www\.curseforge\.com/api/v1/mods/336184/files/5600004/download"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "keeps reporting a mod until its exact jar is in mods" {
        $dir = New-Instance
        try {
            Write-MissingModsFile -InstancePath $dir -Entries @(
                [pscustomobject]@{ FileName = "A-1.0.jar"; ProjectId = 1; FileId = 10 },
                [pscustomobject]@{ FileName = "[1.20.1]B.jar"; ProjectId = 2; FileId = 20 })
            @(Get-MissingModDownloads -InstancePath $dir).Count | Should Be 2
            Set-Content -Path (Join-Path $dir "mods\A-1.1.jar") -Value "other version"
            @(Get-MissingModDownloads -InstancePath $dir).Count | Should Be 2
            Set-Content -Path (Join-Path $dir "mods\A-1.0.jar") -Value "right"
            $left = @(Get-MissingModDownloads -InstancePath $dir)
            $left.Count | Should Be 1
            $left[0].FileName | Should Be "[1.20.1]B.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # Review focus 4.
    It "deletes the list once everything is in place, including bracketed names" {
        $dir = New-Instance
        try {
            Write-MissingModsFile -InstancePath $dir -Entries @([pscustomobject]@{ FileName = "[1.20.1]B.jar"; ProjectId = 2; FileId = 20 })
            [System.IO.File]::WriteAllText((Join-Path $dir "mods\[1.20.1]B.jar"), "jar")
            @(Get-MissingModDownloads -InstancePath $dir).Count | Should Be 0
            Test-Path (Join-Path $dir "MISSING-MODS.txt") | Should Be $false
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "keeps a mod whose name was never found until the list is edited by hand" {
        $dir = New-Instance
        try {
            Write-MissingModsFile -InstancePath $dir -Entries @([pscustomobject]@{ FileName = $null; ProjectId = 9; FileId = 90 })
            $left = @(Get-MissingModDownloads -InstancePath $dir)
            $left.Count | Should Be 1
            $left[0].FileName | Should Be $null
            $left[0].ProjectId | Should Be 9
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns nothing when there's no list" {
        $dir = New-Instance
        try { @(Get-MissingModDownloads -InstancePath $dir).Count | Should Be 0 } finally { Remove-Item -Recurse -Force $dir }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: the 5 new tests FAIL; earlier 20 pass.

- [ ] **Step 3: Implement**

Append to `_shared/scripts/curseforge-helpers.ps1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: 25 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/curseforge-helpers.ps1 tests/curseforge-client-export.tests.ps1
git commit -m "feat: list mods an import couldn't download

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Forge installer and the whole import

**Files:**
- Modify: `_shared/scripts/curseforge-helpers.ps1` (append)
- Modify: `tests/curseforge-client-export.tests.ps1` (append)

**Interfaces:**
- Consumes: `Read-CurseForgeManifest` (Task 1), `Expand-ZipFolderVerified` (Task 2), `Resolve-CurseForgeFile`, `Save-UrlToFile`, `Invoke-ParallelDownload` (Task 3), `Write-MissingModsFile`, `Get-MissingModDownloads` (Task 4), `Get-JavaVersionForMinecraft` (existing, `mrpack-helpers.ps1`, loaded through `modloader-helpers.ps1` at the top of this file); test helpers `New-TestZip`, `New-Manifest`, `Start-FakeCurseForge`, `Stop-FakeCurseForge`, `Get-Bytes`.
- Produces:
  - `Install-ForgeServer -McVersion <string> -ForgeVersion <string> -DestPath <string> -JavaExe <string> [-MavenBase <string>]` → nothing; throws `Forge's installer failed - its log is at <path>` when no `run.bat` appears.
  - `Install-CurseForgeClientExport -ZipPath <string> -DestPath <string> -McRoot <string> [-BaseUrl <string>] [-SkipServerInstall]` → `[pscustomobject]@{ JavaVersion=<int or $null>; MissingCount=<int> }`. `-SkipServerInstall` (tests only) skips Java + Forge and returns `JavaVersion = $null`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/curseforge-client-export.tests.ps1`:

```powershell
Describe "Install-CurseForgeClientExport (offline, no Forge)" {

    function New-Dest { $d = Join-Path $env:TEMP ("cf-srv-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $d | Out-Null; return $d }

    $files = @{
        "1/10" = @{ Name = "GoodMod-1.0.jar"; Body = (Get-Bytes "good") }
        "2/20" = @{ Name = "Blocked-2.0.jar"; Body = (Get-Bytes "blocked") }
        "3/30" = @{ Name = "Faithful-32x.zip"; Body = (Get-Bytes "resourcepack") }
        "4/40" = @{ Name = "GoodMod-1.0.jar"; Body = (Get-Bytes "good") }
    }
    $manifestFiles = '[{"projectID":1,"fileID":10,"required":true},{"projectID":2,"fileID":20,"required":true},{"projectID":3,"fileID":30,"required":true},{"projectID":4,"fileID":40,"required":true},{"projectID":5,"fileID":50,"required":true}]'

    It "downloads the jars, skips non-jars, copies overrides and lists what's missing" {
        $fake = Start-FakeCurseForge -Files $files -FailTimes @{ "Blocked-2.0.jar" = 99 }
        $zip = New-TestZip @{
            "manifest.json"                  = (New-Manifest -FilesJson $manifestFiles)
            "overrides/config/deep/a.toml"   = "cfg"
            "overrides/mods/HandAdded.jar"   = "hand"
            "overrides/resourcepacks/rp.zip" = "rp"
        }
        $dest = New-Dest
        try {
            $result = Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall
            $result.MissingCount | Should Be 2          # Blocked-2.0.jar + project 5 (unknown to CurseForge)
            Test-Path (Join-Path $dest "mods\GoodMod-1.0.jar") | Should Be $true
            Test-Path (Join-Path $dest "mods\HandAdded.jar") | Should Be $true
            Test-Path (Join-Path $dest "mods\Faithful-32x.zip") | Should Be $false
            Test-Path (Join-Path $dest "config\deep\a.toml") | Should Be $true
            Test-Path (Join-Path $dest "resourcepacks") | Should Be $false
            @(Get-ChildItem (Join-Path $dest "mods") -Filter "*.part").Count | Should Be 0
            $missing = @(Get-MissingModDownloads -InstancePath $dest)
            # Name-lookup failures are recorded before download failures.
            ($missing | ForEach-Object { if ($_.FileName) { $_.FileName } else { "project $($_.ProjectId)" } }) -join "," | Should Be "project 5,Blocked-2.0.jar"
            # Review focus 3: two manifest entries with the same file name are downloaded once.
            $fake.Hits["GoodMod-1.0.jar"] | Should Be 1
        } finally { Stop-FakeCurseForge $fake; Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    # Review focus 5.
    It "honours a custom overrides folder name" {
        $fake = Start-FakeCurseForge -Files @{ "1/10" = $files["1/10"] }
        $zip = New-TestZip @{
            "manifest.json"       = (New-Manifest -FilesJson '[{"projectID":1,"fileID":10,"required":true}]' -Overrides "files")
            "files/config/b.toml" = "cfg"
        }
        $dest = New-Dest
        try {
            (Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall).MissingCount | Should Be 0
            Test-Path (Join-Path $dest "config\b.toml") | Should Be $true
            Test-Path (Join-Path $dest "MISSING-MODS.txt") | Should Be $false
        } finally { Stop-FakeCurseForge $fake; Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    # Review focus 3: the overrides copy of a jar wins over the downloaded one.
    It "lets overrides/mods replace a downloaded jar of the same name" {
        $fake = Start-FakeCurseForge -Files @{ "1/10" = $files["1/10"] }
        $zip = New-TestZip @{
            "manifest.json"                  = (New-Manifest -FilesJson '[{"projectID":1,"fileID":10,"required":true}]')
            "overrides/mods/GoodMod-1.0.jar" = "patched by the pack"
        }
        $dest = New-Dest
        try {
            Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall | Out-Null
            [System.IO.File]::ReadAllText((Join-Path $dest "mods\GoodMod-1.0.jar")) | Should Be "patched by the pack"
        } finally { Stop-FakeCurseForge $fake; Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    It "fails with an internet message when nothing could be downloaded" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -FilesJson $manifestFiles) }
        $dest = New-Dest
        try {
            { Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl "http://localhost:1" -SkipServerInstall } |
                Should Throw "Couldn't reach CurseForge"
        } finally { Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    It "refuses a non-Forge pack before downloading anything" {
        $fake = Start-FakeCurseForge -Files $files
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -Loader "neoforge-21.1.77" -FilesJson $manifestFiles) }
        $dest = New-Dest
        try {
            { Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall } | Should Throw "NeoForge"
            $fake.Hits.Count | Should Be 0
            @(Get-ChildItem $dest).Count | Should Be 0
        } finally { Stop-FakeCurseForge $fake; Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: the 5 new tests FAIL (`Install-CurseForgeClientExport` not recognized); earlier 25 pass.

- [ ] **Step 3: Implement**

Append to `_shared/scripts/curseforge-helpers.ps1`:

```powershell
# Downloads Forge's official installer and runs --installServer into
# $DestPath. Success means run.bat exists afterwards (start.ps1 launches it).
# On failure the installer's output is kept in %TEMP% and named in the error.
function Install-ForgeServer {
    param(
        [Parameter(Mandatory = $true)][string]$McVersion,
        [Parameter(Mandatory = $true)][string]$ForgeVersion,
        [Parameter(Mandatory = $true)][string]$DestPath,
        [Parameter(Mandatory = $true)][string]$JavaExe,
        [string]$MavenBase = "https://maven.minecraftforge.net"
    )
    $full = "$McVersion-$ForgeVersion"
    $installer = Join-Path $env:TEMP ("forge-$full-installer-" + [Guid]::NewGuid().ToString("N") + ".jar")
    $logPath = Join-Path $env:TEMP ("forge-$full-install-" + [Guid]::NewGuid().ToString("N") + ".log")
    Save-UrlToFile -Url "$MavenBase/net/minecraftforge/forge/$full/forge-$full-installer.jar" -Path $installer
    try {
        $ErrorActionPreference = "Continue"   # the installer logs to stderr
        $output = & $JavaExe -jar $installer --installServer $DestPath 2>&1 | ForEach-Object { "$_" }
        [System.IO.File]::WriteAllLines($logPath, [string[]]$output)
    } finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$installer.log" -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path (Join-Path $DestPath "run.bat"))) {
        throw "Forge's installer failed - its log is at $logPath"
    }
    $logsDir = Join-Path $DestPath "logs"
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
    Move-Item -LiteralPath $logPath -Destination (Join-Path $logsDir "forge-installer.log") -Force
}

# Builds a server from a CurseForge client export into $DestPath:
# manifest -> resolve every file's name -> download the .jar ones into mods\
# -> copy + verify overrides\ (minus resource/shader packs) -> Java -> Forge.
# Mods that couldn't be fetched go to MISSING-MODS.txt instead of failing
# the import - unless nothing at all could be fetched, which means no
# connection. -BaseUrl and -SkipServerInstall exist for tests.
function Install-CurseForgeClientExport {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestPath,
        [Parameter(Mandatory = $true)][string]$McRoot,
        [string]$BaseUrl = "https://www.curseforge.com",
        [switch]$SkipServerInstall
    )
    $manifest = Read-CurseForgeManifest -ZipPath $ZipPath

    $lookups = @($manifest.Files | ForEach-Object {
        [pscustomobject]@{ ProjectId = $_.ProjectId; FileId = $_.FileId; BaseUrl = $BaseUrl }
    })
    $resolved = @()
    if ($lookups.Count -gt 0) {
        $resolved = Invoke-ParallelDownload -Items $lookups -Functions @("Resolve-CurseForgeFile") -Activity "Looking up mods" -Work {
            param($i) Resolve-CurseForgeFile -ProjectId $i.ProjectId -FileId $i.FileId -BaseUrl $i.BaseUrl
        }
    }

    $missing = @($resolved | Where-Object { -not $_.Ok } | ForEach-Object {
        [pscustomobject]@{ FileName = $null; ProjectId = $_.Item.ProjectId; FileId = $_.Item.FileId }
    })

    # One download per file name, even if the manifest lists it twice.
    $modsDir = Join-Path $DestPath "mods"
    New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
    $seen = @{}
    $downloads = @()
    foreach ($r in ($resolved | Where-Object { $_.Ok -and $_.Result.FileName -like "*.jar" })) {
        if ($seen.ContainsKey($r.Result.FileName)) { continue }
        $seen[$r.Result.FileName] = $true
        $downloads += [pscustomobject]@{
            Url = $r.Result.Url; Path = (Join-Path $modsDir $r.Result.FileName)
            FileName = $r.Result.FileName; ProjectId = $r.Item.ProjectId; FileId = $r.Item.FileId
        }
    }
    $fetched = @()
    if ($downloads.Count -gt 0) {
        $fetched = Invoke-ParallelDownload -Items $downloads -Functions @("Save-UrlToFile") -Activity "Downloading mods" -Work {
            param($i) Save-UrlToFile -Url $i.Url -Path $i.Path
        }
    }
    $missing += @($fetched | Where-Object { -not $_.Ok } | ForEach-Object {
        [pscustomobject]@{ FileName = $_.Item.FileName; ProjectId = $_.Item.ProjectId; FileId = $_.Item.FileId }
    })

    if ($manifest.Files.Count -gt 0 -and @($fetched | Where-Object { $_.Ok }).Count -eq 0) {
        throw "Couldn't reach CurseForge - check the internet connection and try again."
    }

    Write-Progress -Activity "Copying the modpack's settings" -Status " "
    Expand-ZipFolderVerified -ZipPath $ZipPath -Prefix "$($manifest.OverridesDir)/" -Destination $DestPath -ExcludeTop @("resourcepacks", "shaderpacks") | Out-Null

    if ($missing.Count -gt 0) { Write-MissingModsFile -InstancePath $DestPath -Entries $missing }

    $javaVersion = $null
    if (-not $SkipServerInstall) {
        $javaVersion = Get-JavaVersionForMinecraft -McVersion $manifest.McVersion
        Write-Progress -Activity "Installing Java $javaVersion" -Status " "
        $javaOutput = & (Join-Path $McRoot "scripts\install-java.ps1") -MajorVersion $javaVersion 2>&1
        if ($LASTEXITCODE -ne 0) {
            $reason = ($javaOutput | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }) -join " "
            throw "Firekeep couldn't install Java $javaVersion - check the internet connection and try again. ($reason)"
        }
        Write-Progress -Activity "Installing Forge $($manifest.ForgeVersion)" -Status " "
        Install-ForgeServer -McVersion $manifest.McVersion -ForgeVersion $manifest.ForgeVersion -DestPath $DestPath `
            -JavaExe (Join-Path $McRoot "tools\java\$javaVersion\bin\java.exe")
    }

    return [pscustomobject]@{ JavaVersion = $javaVersion; MissingCount = $missing.Count }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/curseforge-client-export.tests.ps1"`
Expected: 30 passed, 0 failed.

- [ ] **Step 5: Run the full suite**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests -Quiet -PassThru | % { 'Passed=' + $_.PassedCount + ' Failed=' + $_.FailedCount }"`
Expected: `Failed=0` (271 earlier + 30 new).

- [ ] **Step 6: Commit**

```bash
git add _shared/scripts/curseforge-helpers.ps1 tests/curseforge-client-export.tests.ps1
git commit -m "feat: build a server from a CurseForge client export

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Find the jar a failed start blames

**Files:**
- Modify: `_shared/scripts/gui-helpers.ps1` (append)
- Modify: `tests/gui-helpers.tests.ps1` (append)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Get-ClientOnlyModJar -InstancePath <string> -ConsoleText <string>` → jar file name (`<string>`, present in `<InstancePath>\mods`) or `$null`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/gui-helpers.tests.ps1`:

```powershell
Describe "Get-ClientOnlyModJar" {

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

    # A fake mod jar: a zip whose META-INF/mods.toml declares $ModId.
    function New-ModJar([string]$Dir, [string]$FileName, [string]$ModId) {
        $path = Join-Path $Dir $FileName
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $w = New-Object System.IO.StreamWriter($zip.CreateEntry("META-INF/mods.toml").Open())
            try { $w.Write("modLoader=`"javafml`"`n[[mods]]`nmodId=`"$ModId`"`nversion=`"1.0`"`n") } finally { $w.Dispose() }
        } finally { $zip.Dispose(); $stream.Dispose() }
    }

    function New-Instance { $d = Join-Path $env:TEMP ("clientonly-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force -Path (Join-Path $d "mods") | Out-Null; return $d }

    It "takes the jar from the Mod File line after an 'invalid dist' crash" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "oculus-mc1.20.1-1.8.0.jar" "oculus"
            $text = "Mod File: /D:/srv/mods/other.jar`nAttempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER`n-- MOD oculus --`n`tMod File: /D:/srv/mods/oculus-mc1.20.1-1.8.0.jar`nFailed to start the minecraft server"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "oculus-mc1.20.1-1.8.0.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "finds a Mixin failure's mod by the modId inside the jars" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "Blur-5.0.0.jar" "blur"
            New-ModJar (Join-Path $dir "mods") "Other-1.0.jar" "other"
            $text = "Mixin apply for mod blur failed blur.mixins.json:MixinGameRenderer`nFailed to start the minecraft server"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "Blur-5.0.0.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # Review focus 4.
    It "handles jar names with square brackets" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "[1.20.1]ExtraSounds-2.0.jar" "extrasounds"
            $text = "Mixin apply for mod extrasounds failed extrasounds.mixins.json:X"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "[1.20.1]ExtraSounds-2.0.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns null when the named jar isn't in mods" {
        $dir = New-Instance
        try {
            $text = "for invalid dist DEDICATED_SERVER`n`tMod File: /D:/srv/mods/gone.jar"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be $null
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns null for crashes that aren't about a client-only mod" {
        $dir = New-Instance
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText "java.lang.OutOfMemoryError" | Should Be $null } finally { Remove-Item -Recurse -Force $dir }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/gui-helpers.tests.ps1"`
Expected: the 5 new tests FAIL (`Get-ClientOnlyModJar` not recognized); the rest pass.

- [ ] **Step 3: Implement**

Append to `_shared/scripts/gui-helpers.ps1`:

```powershell
# The jar a failed start blames for being client-only, so Home can offer to
# move it aside: the "Mod File:" line that follows an "invalid dist
# DEDICATED_SERVER" crash, or - when a Mixin failure names only a mod id -
# the jar in mods\ whose META-INF/mods.toml declares that id. $null when the
# crash isn't about such a mod or the jar isn't in mods\ (never guesses).
function Get-ClientOnlyModJar {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [AllowEmptyString()][string]$ConsoleText = ""
    )
    $modsDir = Join-Path $InstancePath "mods"
    $distAt = $ConsoleText.IndexOf("invalid dist DEDICATED_SERVER")
    if ($distAt -ge 0 -and $ConsoleText.Substring($distAt) -match 'Mod File: .*[\\/]mods[\\/]([^\\/\r\n]+\.jar)') {
        $jar = $Matches[1]
        if (Test-Path -LiteralPath (Join-Path $modsDir $jar)) { return $jar }
        return $null
    }
    if ($ConsoleText -match 'Mixin apply for mod ([\w-]+) failed') {
        $modId = $Matches[1]
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        foreach ($file in (Get-ChildItem -LiteralPath $modsDir -Filter "*.jar" -File -ErrorAction SilentlyContinue)) {
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName) } catch { continue }
            try {
                $toml = $zip.GetEntry("META-INF/mods.toml")
                if (-not $toml) { continue }
                $reader = New-Object System.IO.StreamReader($toml.Open())
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($text -match "(?m)^\s*modId\s*=\s*[`"']$([regex]::Escape($modId))[`"']") { return $file.Name }
            } finally {
                $zip.Dispose()
            }
        }
    }
    return $null
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests/gui-helpers.tests.ps1"`
Expected: all pass (5 new).

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/gui-helpers.ps1 tests/gui-helpers.tests.ps1
git commit -m "feat: find the jar a failed start blames as client-only

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Wire it into the GUI

**Files:**
- Modify: `Start-Gui.ps1` (Add Server job, add-job timer, Start click, `Watch-ServerStartup`, `Sync-StatusDisplay`, server selection, new click handlers)
- Modify: `_shared/gui/HomeScreen.xaml` (hint row)
- Modify: `_shared/scripts/new-server-helpers.ps1` (message in `New-ServerFromTemplate`)

**Interfaces:**
- Consumes: `Get-CurseForgeZipKind`, `Install-CurseForgeClientExport`, `Get-MissingModDownloads` (curseforge-helpers.ps1); `Get-ClientOnlyModJar` (gui-helpers.ps1); existing `Show-ConfirmDialog -Overlay $overlay -Message <string>` → `[bool]`, `$overlay`, `$homeHintText`, `$actionButton`, `$addHintText`, `$script:startupFailureText`, `Watch-ServerStartup`, `Sync-StatusDisplay`.
- Produces: `ExcludeModButton` and `ShowMissingModsButton` on Home; `$script:clientOnlyJar`.

No new unit tests: the logic is in Tasks 1–6. This task is verified by the headless GUI load tests in the suite, and by Task 8.

- [ ] **Step 1: Add the two buttons under the Home hint**

In `_shared/gui/HomeScreen.xaml`, replace the hint `TextBlock` (Grid.Row 4, `x:Name="HintText"`) with:

```xml
    <StackPanel Grid.Row="4" HorizontalAlignment="Center">
        <TextBlock x:Name="HintText" Text=" " Foreground="{StaticResource MutedTextBrush}"
                   FontFamily="Segoe UI" FontSize="12" HorizontalAlignment="Center" Margin="0,12,0,0"
                   TextWrapping="Wrap" TextAlignment="Center" MaxWidth="440"/>
        <WrapPanel HorizontalAlignment="Center" Margin="0,6,0,0">
            <Button x:Name="ExcludeModButton" Content="Move it aside and start again" Style="{StaticResource LinkButtonStyle}"
                    Visibility="Collapsed" Margin="6,0"/>
            <Button x:Name="ShowMissingModsButton" Content="Show missing mods" Style="{StaticResource LinkButtonStyle}"
                    Visibility="Collapsed" Margin="6,0"/>
        </WrapPanel>
    </StackPanel>
```

- [ ] **Step 2: Load the helpers and find the buttons**

In `Start-Gui.ps1`, after `. (Join-Path $root "_shared\scripts\new-server-helpers.ps1")` add:

```powershell
. (Join-Path $root "_shared\scripts\curseforge-helpers.ps1")
```

After `$homeHintText     = $homeRoot.FindName("HintText")` add:

```powershell
$excludeModButton      = $homeRoot.FindName("ExcludeModButton")
$showMissingModsButton = $homeRoot.FindName("ShowMissingModsButton")
```

After the `$script:startupFailureText = $null` state line near the top add:

```powershell
$script:clientOnlyJar   = $null  # jar the last failed start blamed as client-only, offered by ExcludeModButton
```

- [ ] **Step 3: Branch the Add Server job on the zip kind, with progress**

In the Add Server job, replace:

```powershell
                . (Join-Path $GsRoot "_shared\scripts\curseforge-helpers.ps1")
                try {
                    $javaVersion = Install-CurseForgeServerZip -ZipPath $localFile -DestPath $dest
```

with:

```powershell
                . (Join-Path $GsRoot "_shared\scripts\curseforge-helpers.ps1")
                try {
                    if ((Get-CurseForgeZipKind -ZipPath $localFile) -eq "ClientExport") {
                        $javaVersion = (Install-CurseForgeClientExport -ZipPath $localFile -DestPath $dest -McRoot $McRoot).JavaVersion
                    } else {
                        $javaVersion = Install-CurseForgeServerZip -ZipPath $localFile -DestPath $dest
                    }
```

(The existing `Set-RconDefaults` line, the `catch { Remove-Item -Recurse -Force $dest; throw }` and `Set-RunConfigJavaAndRam` stay as they are.)

In `$addJobTimer.Add_Tick`, replace its first line:

```powershell
    if (-not $script:addJob -or $script:addJob.State -eq "Running" -or $script:addJob.State -eq "NotStarted") { return }
```

with:

```powershell
    if (-not $script:addJob) { return }
    if ($script:addJob.State -eq "Running" -or $script:addJob.State -eq "NotStarted") {
        # Imports report their steps with Write-Progress ("Downloading mods: 120 of 363").
        $progress = $script:addJob.ChildJobs[0].Progress | Select-Object -Last 1
        if ($progress -and $progress.RecordType -ne "Completed") {
            $addHintText.Text = "$($progress.Activity): $($progress.StatusDescription)".TrimEnd(': ')
        }
        return
    }
```

In the same timer's `Completed` branch, after `Refresh-ServerList -PreferName $createdName` add:

```powershell
        $missingMods = @(Get-MissingModDownloads -InstancePath $script:selected.Path)
        if ($missingMods.Count -gt 0) {
            $script:startupFailureText = "Created - but $($missingMods.Count) mods couldn't be downloaded automatically. Click Show missing mods."
        }
```

- [ ] **Step 4: Block Start while mods are missing; clear the fix offer on a new start**

In `$actionButton.Add_Click`, inside `if ($state -eq "Stopped") {`, after the `.starting.lock` handling (the line `if ($lock) { Remove-Item ... }`), add:

```powershell
        $missingMods = @(Get-MissingModDownloads -InstancePath $script:selected.Path)
        if ($missingMods.Count -gt 0) {
            $script:startupFailureText = "$($missingMods.Count) mods still need a manual download before this server can start. Click Show missing mods."
            $homeHintText.Text = $script:startupFailureText
            return
        }
```

In the start branch of the same handler, next to `$script:startupFailureText = $null`, add:

```powershell
        $script:clientOnlyJar = $null
```

In `$serverCombo.Add_SelectionChanged`, next to `$script:startupFailureText = $null`, add the same line.

- [ ] **Step 5: Remember the blamed jar when a start fails**

In `Watch-ServerStartup`, after the line that sets `$script:startupFailureText = if ($details) ...`, add:

```powershell
    $script:clientOnlyJar = Get-ClientOnlyModJar -InstancePath $script:selected.Path -ConsoleText $fullText
```

- [ ] **Step 6: Show the buttons from `Sync-StatusDisplay`**

In `Sync-StatusDisplay`, inside `if (-not $script:closingApp) { ... }`, after the hint-text update, add:

```powershell
        $stopped = ($state -eq "Stopped")
        $excludeModButton.Visibility = if ($stopped -and $script:clientOnlyJar) { "Visible" } else { "Collapsed" }
        $showMissingModsButton.Visibility = if ($stopped -and (Test-Path -LiteralPath (Join-Path $script:selected.Path "MISSING-MODS.txt"))) { "Visible" } else { "Collapsed" }
```

- [ ] **Step 7: The two click handlers**

After the `$actionButton.Add_Click({...})` block add:

```powershell
# One-click fix for a mod the server refused to load (client-only). Only
# after a confirmation naming the jar, and only moved, never deleted
# (docs/superpowers/specs/2026-09-28-curseforge-client-import-design.md).
$excludeModButton.Add_Click({
    $jar = $script:clientOnlyJar
    if (-not $jar -or -not $script:selected) { return }
    if (-not (Show-ConfirmDialog -Overlay $overlay -Message "Move $jar out of the mods folder (into _excluded\client-only) and start the server again?")) { return }
    $target = Join-Path $script:selected.Path "_excluded\client-only"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Move-Item -LiteralPath (Join-Path $script:selected.Path "mods\$jar") -Destination $target -Force
    $script:clientOnlyJar = $null
    $script:startupFailureText = $null
    $excludeModButton.Visibility = "Collapsed"
    $actionButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})

$showMissingModsButton.Add_Click({
    if (-not $script:selected) { return }
    $list = Join-Path $script:selected.Path "MISSING-MODS.txt"
    if (Test-Path -LiteralPath $list) { Start-Process notepad.exe -ArgumentList "`"$list`"" }
    Start-Process explorer.exe -ArgumentList "`"$(Join-Path $script:selected.Path 'mods')`""
})
```

- [ ] **Step 8: Clearer "already exists" message**

In `_shared/scripts/new-server-helpers.ps1`, replace:

```powershell
        throw "A server named '$Name' already exists at $dest"
```

with:

```powershell
        throw "A server named '$Name' already exists at $dest (maybe from an import that didn't finish) - delete that folder or pick another name."
```

- [ ] **Step 9: Run the full suite (includes the headless GUI load tests)**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests -Quiet -PassThru | % { 'Passed=' + $_.PassedCount + ' Failed=' + $_.FailedCount }"`
Expected: `Failed=0`.

- [ ] **Step 10: Commit**

```bash
git add Start-Gui.ps1 _shared/gui/HomeScreen.xaml _shared/scripts/new-server-helpers.ps1
git commit -m "feat: import CurseForge client exports from Add Server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Real import of Arcadia, and docs

**Files:**
- Modify: `README.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: everything above; the user's `%USERPROFILE%\Downloads\Arcadia [RPG]-v3.8.2-fixed.zip`.
- Produces: verified feature; docs.

This task needs the user: it downloads about 1 GB and starts a real server. Never modify `Minecraft\servers\Arcadia RPG` (read-only comparisons only).

- [ ] **Step 1: Import through the GUI**

Ask the user to open Firekeep → New Server → name `ArcadiaImportTest` → drop `Arcadia [RPG]-v3.8.2-fixed.zip` → accept the EULA → Create. Expected: the hint shows "Looking up mods: N of 367", then "Downloading mods: N of M", then the Java/Forge steps, and Home shows the new server.

- [ ] **Step 2: Compare with the hand-built server (read-only)**

Run:

```powershell
$new = "D:\3_Hobbies\GameServers\Minecraft\servers\ArcadiaImportTest"
$old = "D:\3_Hobbies\GameServers\Minecraft\servers\Arcadia RPG"
$serverOnly = "Chunky*", "*StructureLayoutOptimizer*", "*structure_layout_optimizer*", "*SmoothChunk*", "*smoothchunk*", "*noisium*", "*ksyxis*"
$a = @(Get-ChildItem -LiteralPath "$new\mods" -Filter *.jar | ForEach-Object Name)
$b = @(Get-ChildItem -LiteralPath "$old\mods" -Filter *.jar | ForEach-Object Name) + @(Get-ChildItem -LiteralPath "$old\_excluded" -Recurse -Filter *.jar -ErrorAction SilentlyContinue | ForEach-Object Name)
"only in import: " + (($a | Where-Object { $b -notcontains $_ }) -join ", ")
"only in hand build: " + (($b | Where-Object { $a -notcontains $_ } | Where-Object { $n = $_; -not ($serverOnly | Where-Object { $n -like $_ }) } | Where-Object { $_ -notlike "forge-*-installer.jar" }) -join ", ")
"missing list present: " + (Test-Path "$new\MISSING-MODS.txt")
```

Expected: both "only in" lines empty (or differences the user can explain), and no missing list. Config equality is already guaranteed by the byte check against the zip.

- [ ] **Step 3: Boot it with the one-click fix**

Ask the user to press Start on `ArcadiaImportTest`, and on each failure read the named jar and click **Move it aside and start again**. Expected: at most 7 prompts, naming only the Oculus, Blur, RyoamicLights, Great Scrollable Tooltips, ExtraSounds, ShoulderSurfing and ItemPhysicLite jars; then the campfire lights. Then STOP SERVER. The user deletes the `ArcadiaImportTest` folder afterwards.

- [ ] **Step 4: Document it**

In `README.md`, replace the two numbered steps under "**From [CurseForge](https://www.curseforge.com):**" with:

```markdown
1. Go to the modpack's page, the **"Files"** tab, and download either the
   **"Server Files"** package or the regular modpack download (the one the
   CurseForge app uses) - Firekeep handles both.
2. Drag that `.zip` onto the Modpack field, or browse for it.

   With the regular modpack download, Firekeep downloads every mod itself
   (a few minutes for big packs). If a mod's author doesn't allow that,
   Home shows **Show missing mods** with a link to each one - put those
   files in the server's `mods` folder and press Start. If the server
   refuses to start because of a mod that only works in the game (not on a
   server), Home names it and offers **Move it aside and start again**.
   Only Forge modpacks can be imported this way for now.
```

In `CHANGELOG.md`, add above `## [1.1.0] - 2026-09-28`:

```markdown
## [Unreleased]

### Added
- Add Server imports regular CurseForge modpack downloads (Forge), not just
  "Server Files": downloads the mods itself, copies the pack's settings
  with a byte-for-byte check, and installs Forge. Mods that can't be
  downloaded are listed with links (Start waits until they're added), and a
  mod the server refuses to load can be moved aside with one click.

```

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: CurseForge modpack downloads can be imported directly

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
