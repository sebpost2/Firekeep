. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\backup-helpers.ps1")

Describe "Backup-World" {

    function New-Instance([string]$LevelName = "world") {
        $dir = Join-Path $env:TEMP ("backup-world-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path (Join-Path $dir "$LevelName\region") | Out-Null
        Set-Content -Path (Join-Path $dir "$LevelName\level.dat") -Value "level"
        Set-Content -Path (Join-Path $dir "$LevelName\region\r.0.0.mca") -Value "chunks"
        Set-Content -Path (Join-Path $dir "server.properties") -Value "level-name=$LevelName"
        return $dir
    }

    $day1 = [datetime]"2026-09-28 10:00"

    It "zips the active world into backups\, in a form Manage Maps can import" {
        $dir = New-Instance "MyWorld"
        $zip = Backup-World -InstancePath $dir -Now $day1
        $zip | Should Be (Join-Path $dir "backups\MyWorld-2026-09-28_1000.zip")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        $names = @($archive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        $archive.Dispose()
        ($names -contains "MyWorld/level.dat") | Should Be $true
        ($names -contains "MyWorld/region/r.0.0.mca") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "backs up at most once a day" {
        $dir = New-Instance
        Backup-World -InstancePath $dir -Now $day1 | Out-Null
        Backup-World -InstancePath $dir -Now $day1.AddHours(5) | Should Be $null
        @(Get-ChildItem (Join-Path $dir "backups")).Count | Should Be 1
        Remove-Item -Recurse -Force $dir
    }

    It "keeps only the newest backups of that world" {
        $dir = New-Instance
        for ($i = 0; $i -lt 7; $i++) { Backup-World -InstancePath $dir -Now $day1.AddDays($i) -Keep 5 | Out-Null }
        $left = @(Get-ChildItem (Join-Path $dir "backups") | ForEach-Object Name | Sort-Object)
        $left.Count | Should Be 5
        $left[0] | Should Be "world-2026-09-30_1000.zip"
        Remove-Item -Recurse -Force $dir
    }

    It "never prunes another world's backups" {
        $dir = New-Instance "world"
        New-Item -ItemType Directory -Force -Path (Join-Path $dir "backups") | Out-Null
        Set-Content -Path (Join-Path $dir "backups\world-old-2020-01-01_0000.zip") -Value "other world"
        for ($i = 0; $i -lt 6; $i++) { Backup-World -InstancePath $dir -Now $day1.AddDays($i) -Keep 5 | Out-Null }
        Test-Path (Join-Path $dir "backups\world-old-2020-01-01_0000.zip") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "does nothing before the world exists (first start)" {
        $dir = Join-Path $env:TEMP ("backup-world-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Backup-World -InstancePath $dir -Now $day1 | Should Be $null
        Test-Path (Join-Path $dir "backups") | Should Be $false
        Remove-Item -Recurse -Force $dir
    }

    # A half-written zip must not count as "today's backup".
    It "leaves no zip behind when the backup fails" {
        $dir = New-Instance
        $locked = [System.IO.File]::Open((Join-Path $dir "world\level.dat"), 'Open', 'ReadWrite', 'None')
        try {
            { Backup-World -InstancePath $dir -Now $day1 } | Should Throw
        } finally {
            $locked.Close()
        }
        @(Get-ChildItem (Join-Path $dir "backups") -ErrorAction SilentlyContinue).Count | Should Be 0
        Remove-Item -Recurse -Force $dir
    }
}
