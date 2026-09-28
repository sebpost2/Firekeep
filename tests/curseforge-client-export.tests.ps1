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
