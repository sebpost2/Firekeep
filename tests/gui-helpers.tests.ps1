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

Describe "Get-ActionButtonView" {

    It "returns START SERVER, enabled, when Stopped" {
        $view = Get-ActionButtonView -State "Stopped"
        $view.Label | Should Be "START SERVER"
        $view.IsEnabled | Should Be $true
    }

    It "returns CANCEL, enabled, when Starting (lets you abort a slow boot)" {
        $view = Get-ActionButtonView -State "Starting"
        $view.Label | Should Be "CANCEL"
        $view.IsEnabled | Should Be $true
    }

    It "returns STOP SERVER, enabled, when Running" {
        $view = Get-ActionButtonView -State "Running"
        $view.Label | Should Be "STOP SERVER"
        $view.IsEnabled | Should Be $true
    }

    It "returns STOPPING..., disabled, when Stopping (graceful stop can't be interrupted)" {
        $view = Get-ActionButtonView -State "Stopping"
        $view.Label | Should Be "STOPPING..."
        $view.IsEnabled | Should Be $false
    }

    It "throws a clear error for an unrecognized state" {
        { Get-ActionButtonView -State "Confused" } | Should Throw
    }
}

Describe "Get-ServerLifecycleState" {

    It "is Starting while a launch is pending and the port isn't up yet" {
        Get-ServerLifecycleState -IsRunning $false -PendingStart $true -PendingStop $false | Should Be "Starting"
    }

    It "settles to Running once a pending launch's port comes up" {
        Get-ServerLifecycleState -IsRunning $true -PendingStart $true -PendingStop $false | Should Be "Running"
    }

    It "is Stopping while a graceful stop is pending and the port is still up" {
        Get-ServerLifecycleState -IsRunning $true -PendingStart $false -PendingStop $true | Should Be "Stopping"
    }

    It "settles to Stopped once a pending stop's port goes down" {
        Get-ServerLifecycleState -IsRunning $false -PendingStart $false -PendingStop $true | Should Be "Stopped"
    }

    It "is Running when the port is up with nothing pending" {
        Get-ServerLifecycleState -IsRunning $true -PendingStart $false -PendingStop $false | Should Be "Running"
    }

    It "is Stopped when the port is down with nothing pending" {
        Get-ServerLifecycleState -IsRunning $false -PendingStart $false -PendingStop $false | Should Be "Stopped"
    }
}
