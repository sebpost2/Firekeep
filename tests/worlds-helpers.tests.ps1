. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\worlds-helpers.ps1")

Describe "Test-ValidName" {
    It "accepts a normal name" { Test-ValidName "world-2" | Should Be $true }
    It "rejects empty/whitespace" { Test-ValidName "   " | Should Be $false }
    It "rejects ." { Test-ValidName "." | Should Be $false }
    It "rejects .." { Test-ValidName ".." | Should Be $false }
    It "rejects names with invalid filename characters" { Test-ValidName "bad:name" | Should Be $false }
    It "rejects the reserved trash folder name" { Test-ValidName "_trash" | Should Be $false }
}

Describe "Get-ServerProperty / Set-ServerProperty" {
    $propsPath = Join-Path $env:TEMP ("worlds-helpers-props-" + [Guid]::NewGuid().ToString("N") + ".properties")

    BeforeEach {
        @("level-name=world", "enable-rcon=true") | Set-Content -Path $propsPath -Encoding ascii
    }

    It "reads an existing key" {
        Get-ServerProperty $propsPath "level-name" | Should Be "world"
    }

    It "returns null for a missing key" {
        Get-ServerProperty $propsPath "no-such-key" | Should Be $null
    }

    It "updates an existing key without touching other lines" {
        Set-ServerProperty $propsPath "level-name" "world-2"
        Get-ServerProperty $propsPath "level-name" | Should Be "world-2"
        Get-ServerProperty $propsPath "enable-rcon" | Should Be "true"
    }

    It "adds a new key when it doesn't exist yet" {
        Set-ServerProperty $propsPath "level-seed" "12345"
        Get-ServerProperty $propsPath "level-seed" | Should Be "12345"
    }

    It "backs up the file before writing" {
        Set-ServerProperty $propsPath "level-name" "world-3"
        Test-Path "$propsPath.bak" | Should Be $true
    }

    Remove-Item -Path $propsPath, "$propsPath.bak" -Force -ErrorAction SilentlyContinue
}

Describe "Get-FolderSizeMB" {
    $dir = Join-Path $env:TEMP ("worlds-helpers-size-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # 2 files of 1MB each -> 2MB total
    $bytes = New-Object byte[] (1MB)
    [System.IO.File]::WriteAllBytes((Join-Path $dir "a.bin"), $bytes)
    [System.IO.File]::WriteAllBytes((Join-Path $dir "b.bin"), $bytes)

    It "sums file sizes recursively in MB" {
        Get-FolderSizeMB $dir | Should Be 2
    }

    It "returns 0 for a folder that doesn't exist" {
        Get-FolderSizeMB (Join-Path $env:TEMP "does-not-exist-folder") | Should Be 0
    }

    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
}

Describe "Get-Worlds" {
    $instancePath = Join-Path $env:TEMP ("worlds-helpers-worlds-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $instancePath "world") | Out-Null
    Set-Content -Path (Join-Path $instancePath "world\level.dat") -Value "x"
    New-Item -ItemType Directory -Force -Path (Join-Path $instancePath "world_nether") | Out-Null
    Set-Content -Path (Join-Path $instancePath "world_nether\level.dat") -Value "x"
    New-Item -ItemType Directory -Force -Path (Join-Path $instancePath "mods") | Out-Null  # no level.dat: not a world
    New-Item -ItemType Directory -Force -Path (Join-Path $instancePath "_trash\old-world") | Out-Null

    It "finds folders with level.dat and marks the active one" {
        $worlds = @(Get-Worlds -InstancePath $instancePath -ActiveName "world")
        $active = $worlds | Where-Object { $_.Name -eq "world" }
        $active.IsActive | Should Be $true
        $active.Exists | Should Be $true
    }

    It "does not confuse a non-world folder (no level.dat) for a world" {
        $worlds = @(Get-Worlds -InstancePath $instancePath -ActiveName "world")
        @($worlds | Where-Object { $_.Name -eq "mods" }).Count | Should Be 0
    }

    It "never lists the trash folder as a world" {
        $worlds = @(Get-Worlds -InstancePath $instancePath -ActiveName "world")
        @($worlds | Where-Object { $_.Name -eq "_trash" }).Count | Should Be 0
    }

    It "includes the active world even if it hasn't generated yet (no level.dat)" {
        $worlds = @(Get-Worlds -InstancePath $instancePath -ActiveName "world-not-yet-generated")
        $pending = $worlds | Where-Object { $_.Name -eq "world-not-yet-generated" }
        $pending.IsActive | Should Be $true
        $pending.Exists | Should Be $false
    }

    Remove-Item -Recurse -Force $instancePath -ErrorAction SilentlyContinue
}
