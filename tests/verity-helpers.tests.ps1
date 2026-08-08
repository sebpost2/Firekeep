# tests/verity-helpers.tests.ps1
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\verity-helpers.ps1")

Describe "Test-VerityModPresent" {

    $root = Join-Path $env:TEMP ("verity-detect-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "returns true when a verity-*.jar exists in mods/" {
        $inst = Join-Path $root "with-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\verity-6.1.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $true
    }

    It "returns false when mods/ has no verity jar" {
        $inst = Join-Path $root "without-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\somemod.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    It "returns false when there's no mods/ folder at all" {
        $inst = Join-Path $root "no-mods-dir"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
