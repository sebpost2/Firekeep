. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\gui-helpers.ps1")

Describe "Get-ServerInstances" {

    function New-FakeInstanceTree([string]$Root) {
        # <Root>\Minecraft\servers\Cave Horror Project\  (a real instance)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root "Minecraft\servers\Cave Horror Project") | Out-Null
        # <Root>\Minecraft\servers\_template\  (must be excluded)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root "Minecraft\servers\_template") | Out-Null
        # <Root>\_shared\  (must never be treated as a game)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root "_shared\scripts") | Out-Null
        # <Root>\Valheim\  (a game folder with no servers subfolder yet)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root "Valheim") | Out-Null
    }

    $root = Join-Path $env:TEMP ("gui-helpers-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-FakeInstanceTree -Root $root

    It "finds a server instance nested under Game\servers\Instance" {
        $result = @(Get-ServerInstances -Root $root)
        @($result | Where-Object { $_.Name -eq "Cave Horror Project" }).Count | Should Be 1
    }

    It "tags the found instance with its game name and full path" {
        $result = @(Get-ServerInstances -Root $root)
        $inst = $result | Where-Object { $_.Name -eq "Cave Horror Project" }
        $inst.Game | Should Be "Minecraft"
        $inst.Path | Should Be (Join-Path $root "Minecraft\servers\Cave Horror Project")
    }

    It "excludes the _template instance" {
        $result = @(Get-ServerInstances -Root $root)
        @($result | Where-Object { $_.Name -eq "_template" }).Count | Should Be 0
    }

    It "excludes _shared from being treated as a game" {
        $result = @(Get-ServerInstances -Root $root)
        @($result | Where-Object { $_.Game -eq "_shared" }).Count | Should Be 0
    }

    It "ignores a game folder that has no servers subfolder yet" {
        $result = @(Get-ServerInstances -Root $root)
        @($result | Where-Object { $_.Game -eq "Valheim" }).Count | Should Be 0
    }

    It "returns an empty array when the root has no game folders at all" {
        $emptyRoot = Join-Path $env:TEMP ("gui-helpers-empty-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $emptyRoot | Out-Null
        $result = @(Get-ServerInstances -Root $emptyRoot)
        $result.Count | Should Be 0
        Remove-Item -Recurse -Force $emptyRoot -ErrorAction SilentlyContinue
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-ServerStatusView" {

    It "returns the LIT label and the online color key when running" {
        $view = Get-ServerStatusView -IsRunning $true
        $view.Label | Should Be "LIT"
        $view.ColorKey | Should Be "Online"
    }

    It "returns the OUT label and the offline color key when not running" {
        $view = Get-ServerStatusView -IsRunning $false
        $view.Label | Should Be "OUT"
        $view.ColorKey | Should Be "Offline"
    }
}

Describe "Get-PrimaryActionLabel" {

    It "returns STOP SERVER when the server is running" {
        Get-PrimaryActionLabel -IsRunning $true | Should Be "STOP SERVER"
    }

    It "returns START SERVER when the server is not running" {
        Get-PrimaryActionLabel -IsRunning $false | Should Be "START SERVER"
    }
}
