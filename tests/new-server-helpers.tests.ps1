. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\new-server-helpers.ps1")

Describe "New-ServerFromTemplate" {

    function New-FakeMcRoot {
        $mcRoot = Join-Path $env:TEMP ("new-server-helpers-fixture-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path (Join-Path $mcRoot "servers\_template") | Out-Null
        Set-Content -Path (Join-Path $mcRoot "servers\_template\eula.txt") -Value "eula=false"
        Set-Content -Path (Join-Path $mcRoot "servers\_template\run.config.ps1") -Value '$JavaVersion = 21'
        return $mcRoot
    }

    It "copies the template into a new instance folder named after -Name" {
        $mcRoot = New-FakeMcRoot
        $dest = New-ServerFromTemplate -Name "MyModpack" -McRoot $mcRoot
        Test-Path (Join-Path $dest "eula.txt") | Should Be $true
        Test-Path (Join-Path $dest "run.config.ps1") | Should Be $true
        Remove-Item -Recurse -Force $mcRoot -ErrorAction SilentlyContinue
    }

    It "throws if a server with that name already exists" {
        $mcRoot = New-FakeMcRoot
        New-ServerFromTemplate -Name "Dup" -McRoot $mcRoot | Out-Null
        { New-ServerFromTemplate -Name "Dup" -McRoot $mcRoot } | Should Throw
        Remove-Item -Recurse -Force $mcRoot -ErrorAction SilentlyContinue
    }

    It "pre-seeds server.properties with RCON enabled and a non-empty random password" {
        $mcRoot = New-FakeMcRoot
        $dest = New-ServerFromTemplate -Name "RconCheck" -McRoot $mcRoot
        $props = Get-Content (Join-Path $dest "server.properties") -Raw
        $props | Should Match "enable-rcon=true"
        $props | Should Match "rcon\.port=25575"
        $props | Should Match "rcon\.password=\S+"
        Remove-Item -Recurse -Force $mcRoot -ErrorAction SilentlyContinue
    }

    It "generates a different password for each server" {
        $mcRoot = New-FakeMcRoot
        $destA = New-ServerFromTemplate -Name "A" -McRoot $mcRoot
        $destB = New-ServerFromTemplate -Name "B" -McRoot $mcRoot
        $propsA = Get-Content (Join-Path $destA "server.properties") -Raw
        $propsB = Get-Content (Join-Path $destB "server.properties") -Raw
        $propsA | Should Not Be $propsB
        Remove-Item -Recurse -Force $mcRoot -ErrorAction SilentlyContinue
    }
}
