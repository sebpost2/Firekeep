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

function New-Manifest([string]$Loader = "forge-47.4.20", [string]$FilesJson = '[{"projectID":1,"fileID":10,"required":true}]', [string]$Overrides = "overrides", [string]$McVersion = "1.20.1") {
    return '{"minecraft":{"version":"' + $McVersion + '","modLoaders":[{"id":"' + $Loader + '","primary":true}]},"manifestType":"minecraftModpack","files":' + $FilesJson + ',"overrides":"' + $Overrides + '"}'
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

    It "ignores launcher-like names inside a custom overrides folder too" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -Overrides "files"); "files/config/somemod/run.bat" = "x" }
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

    # Forge installers before 1.17 make no run.bat, so the import would
    # download everything and only then fail with a misleading error.
    It "refuses a Forge pack for Minecraft before 1.17 up front" {
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -Loader "forge-36.2.39" -McVersion "1.16.5") }
        try { { Read-CurseForgeManifest -ZipPath $zip } | Should Throw "1.17 and newer" } finally { Remove-Item $zip }
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

    It "refuses a file name that would leave the mods folder" {
        $fake = Start-FakeCurseForge -Files @{ "8/80" = @{ Name = "..\..\evil.jar"; Body = (Get-Bytes "x") } }
        try { { Resolve-CurseForgeFile -ProjectId 8 -FileId 80 -BaseUrl $fake.BaseUrl } | Should Throw "Unsafe file name" } finally { Stop-FakeCurseForge $fake }
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

    # .NET allows 2 connections per host by default, so without raising it
    # only 2 of the 6 workers download and the rest queue until they time out.
    It "lets every worker connect at once" {
        Invoke-ParallelDownload -Items @(1) -Work { param($i) $i } -Throttle 6 | Out-Null
        [System.Net.ServicePointManager]::DefaultConnectionLimit | Should BeGreaterThan 5
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

    # A name that was never found can't be matched against mods\, so the
    # user needs to be told how to clear it themselves.
    It "tells the user how to clear an entry Firekeep can't check" {
        $dir = New-Instance
        try {
            Write-MissingModsFile -InstancePath $dir -Entries @([pscustomobject]@{ FileName = $null; ProjectId = 9; FileId = 90 })
            Get-Content (Join-Path $dir "MISSING-MODS.txt") -Raw | Should Match "delete this block"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns nothing when there's no list" {
        $dir = New-Instance
        try { @(Get-MissingModDownloads -InstancePath $dir).Count | Should Be 0 } finally { Remove-Item -Recurse -Force $dir }
    }
}

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

    It "copies overrides whatever the folder name's case or trailing slash" {
        $fake = Start-FakeCurseForge -Files @{ "1/10" = $files["1/10"] }
        $zip = New-TestZip @{
            "manifest.json"           = (New-Manifest -FilesJson '[{"projectID":1,"fileID":10,"required":true}]' -Overrides "overrides/")
            "Overrides/config/c.toml" = "cfg"
        }
        $dest = New-Dest
        try {
            Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall | Out-Null
            Test-Path (Join-Path $dest "config\c.toml") | Should Be $true
        } finally { Stop-FakeCurseForge $fake; Remove-Item $zip; Remove-Item -Recurse -Force $dest }
    }

    It "doesn't blame the internet when the pack simply has no mod jars" {
        $fake = Start-FakeCurseForge -Files @{ "3/30" = $files["3/30"] }
        $zip = New-TestZip @{ "manifest.json" = (New-Manifest -FilesJson '[{"projectID":3,"fileID":30,"required":true}]') }
        $dest = New-Dest
        try {
            (Install-CurseForgeClientExport -ZipPath $zip -DestPath $dest -McRoot $env:TEMP -BaseUrl $fake.BaseUrl -SkipServerInstall).MissingCount | Should Be 0
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

Describe "Install-ForgeServer" {
    It "says plainly when Forge's installer can't be downloaded" {
        $fake = Start-FakeCurseForge -Files @{}
        $dest = Join-Path $env:TEMP ("cf-forge-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dest | Out-Null
        try {
            { Install-ForgeServer -McVersion "1.20.1" -ForgeVersion "47.4.20" -DestPath $dest -JavaExe "java.exe" -MavenBase $fake.BaseUrl } |
                Should Throw "Couldn't download Forge 47.4.20's installer"
        } finally { Stop-FakeCurseForge $fake; Remove-Item -Recurse -Force $dest }
    }
}
