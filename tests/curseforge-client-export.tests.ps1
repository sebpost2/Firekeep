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
        try { { Resolve-CurseForgeFile -ProjectId 1 -FileId 2 -BaseUrl $fake.BaseUrl } | Should Throw "404" } finally { Stop-FakeCurseForge $fake }
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
