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

Describe "Test-ServerNameValid" {
    It "rejects a name with a space" {
        Test-ServerNameValid -Name "Horror Ultimate" | Should Be $false
    }

    It "rejects a name with path-unsafe characters" {
        Test-ServerNameValid -Name "My:Server" | Should Be $false
    }

    It "accepts a name with only letters, numbers, dashes and underscores" {
        Test-ServerNameValid -Name "Horror-Ultimate_2" | Should Be $true
    }

    It "rejects an empty name" {
        Test-ServerNameValid -Name "" | Should Be $false
    }
}

Describe "Set-RconDefaults" {

    function New-PropsFile([string[]]$Lines) {
        $path = Join-Path $env:TEMP ("rcon-defaults-" + [Guid]::NewGuid().ToString("N") + ".properties")
        if ($null -ne $Lines) { Set-Content -Path $path -Value $Lines -Encoding ascii }
        return $path
    }

    # Servers built by hand (not from the template) had RCON off, so the
    # GUI showed them as stopped forever and Stop Server couldn't reach them.
    It "turns RCON on with a port and a random password when missing" {
        $path = New-PropsFile @("motd=Hi", "enable-rcon=false")
        Set-RconDefaults -PropsPath $path
        $props = Get-Content $path -Raw
        $props | Should Match "(?m)^enable-rcon=true"
        $props | Should Match "(?m)^rcon\.port=25575"
        $props | Should Match "(?m)^rcon\.password=\S{16,}"
        $props | Should Match "(?m)^motd=Hi"
        Remove-Item $path, "$path.bak" -ErrorAction SilentlyContinue
    }

    It "creates server.properties if it doesn't exist yet" {
        $path = New-PropsFile $null
        Set-RconDefaults -PropsPath $path
        Get-Content $path -Raw | Should Match "(?m)^rcon\.password=\S+"
        Remove-Item $path, "$path.bak" -ErrorAction SilentlyContinue
    }

    It "never changes an existing port or password" {
        $path = New-PropsFile @("enable-rcon=true", "rcon.port=25580", "rcon.password=keepme")
        Set-RconDefaults -PropsPath $path
        $props = Get-Content $path -Raw
        $props | Should Match "(?m)^rcon\.port=25580"
        $props | Should Match "(?m)^rcon\.password=keepme"
        Remove-Item $path, "$path.bak" -ErrorAction SilentlyContinue
    }
}
