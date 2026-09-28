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
