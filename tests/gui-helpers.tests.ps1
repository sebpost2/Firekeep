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

Describe "Get-ScreenSize" {

    It "returns the Home screen size" {
        $s = Get-ScreenSize -Screen "Home"
        $s.Width | Should Be 640
        $s.Height | Should Be 860
    }

    It "returns the Manage Maps screen size" {
        $s = Get-ScreenSize -Screen "ManageMaps"
        $s.Width | Should Be 480
        $s.Height | Should Be 640
    }

    It "returns the Add Server screen size" {
        $s = Get-ScreenSize -Screen "AddServer"
        $s.Width | Should Be 480
        $s.Height | Should Be 580
    }

    It "returns the Console screen size" {
        $s = Get-ScreenSize -Screen "Console"
        $s.Width | Should Be 640
        $s.Height | Should Be 720
    }

    It "returns the ServerSettings size" {
        $s = Get-ScreenSize -Screen "ServerSettings"
        $s.Width | Should Be 480
        $s.Height | Should Be 690
    }

    It "throws a clear error for an unrecognized screen" {
        { Get-ScreenSize -Screen "Confused" } | Should Throw
    }
}

Describe "Get-BackTarget" {

    It "returns null for Home, since it's the root screen with no back arrow" {
        Get-BackTarget -Screen "Home" | Should Be $null
    }

    It "returns Home as the back target from Manage Maps" {
        Get-BackTarget -Screen "ManageMaps" | Should Be "Home"
    }

    It "returns Home as the back target from Add Server" {
        Get-BackTarget -Screen "AddServer" | Should Be "Home"
    }

    It "returns Home as the back target from Console" {
        Get-BackTarget -Screen "Console" | Should Be "Home"
    }

    It "returns Home for ServerSettings" {
        Get-BackTarget -Screen "ServerSettings" | Should Be "Home"
    }

    It "throws a clear error for an unrecognized screen" {
        { Get-BackTarget -Screen "Confused" } | Should Throw
    }
}

Describe "Get-LogTailChunk" {

    $root = Join-Path $env:TEMP ("log-tail-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "returns empty text and offset 0 when the log file doesn't exist yet" {
        $missing = Join-Path $root "does-not-exist.log"
        $chunk = Get-LogTailChunk -Path $missing -Offset 0
        $chunk.Text | Should Be ""
        $chunk.Offset | Should Be 0
    }

    It "reads the whole file on a first read from offset 0" {
        $logPath = Join-Path $root "fresh.log"
        Set-Content -Path $logPath -Value "line one`r`nline two" -NoNewline -Encoding ascii
        $chunk = Get-LogTailChunk -Path $logPath -Offset 0
        $chunk.Text | Should Be "line one`r`nline two"
        $chunk.Offset | Should Be (Get-Item $logPath).Length
    }

    It "returns only the bytes appended since the given offset" {
        $logPath = Join-Path $root "growing.log"
        Set-Content -Path $logPath -Value "first" -NoNewline -Encoding ascii
        $firstChunk = Get-LogTailChunk -Path $logPath -Offset 0
        Add-Content -Path $logPath -Value "second" -NoNewline -Encoding ascii
        $secondChunk = Get-LogTailChunk -Path $logPath -Offset $firstChunk.Offset
        $secondChunk.Text | Should Be "second"
        $secondChunk.Offset | Should Be (Get-Item $logPath).Length
    }

    It "restarts from the beginning when the offset is past the current file length (log was rotated/truncated)" {
        $logPath = Join-Path $root "rotated.log"
        Set-Content -Path $logPath -Value "short" -NoNewline -Encoding ascii
        $chunk = Get-LogTailChunk -Path $logPath -Offset 99999
        $chunk.Text | Should Be "short"
        $chunk.Offset | Should Be (Get-Item $logPath).Length
    }

    It "returns an unchanged chunk when nothing new has been written" {
        $logPath = Join-Path $root "idle.log"
        Set-Content -Path $logPath -Value "steady" -NoNewline -Encoding ascii
        $firstChunk = Get-LogTailChunk -Path $logPath -Offset 0
        $secondChunk = Get-LogTailChunk -Path $logPath -Offset $firstChunk.Offset
        $secondChunk.Text | Should Be ""
        $secondChunk.Offset | Should Be $firstChunk.Offset
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-AppVersion" {

    $root = Join-Path $env:TEMP ("gui-helpers-version-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "reads and trims the VERSION file contents" {
        Set-Content -Path (Join-Path $root "VERSION") -Value "1.0.0`r`n"
        Get-AppVersion -Root $root | Should Be "1.0.0"
    }

    It "returns an empty string when VERSION is missing" {
        $emptyRoot = Join-Path $env:TEMP ("gui-helpers-version-empty-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $emptyRoot | Out-Null
        Get-AppVersion -Root $emptyRoot | Should Be ""
        Remove-Item -Recurse -Force $emptyRoot -ErrorAction SilentlyContinue
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-StartupFailure" {

    It "returns null while the server is still loading normally" {
        Get-StartupFailure -ConsoleText "[main/INFO] Loading 356 mods" | Should Be $null
    }

    It "reports a generic crash when nothing more specific matches" {
        $text = "[Server thread/ERROR] [net.minecraft.server.MinecraftServer/]: Failed to start the minecraft server"
        Get-StartupFailure -ConsoleText $text | Should Match "crashed while starting"
    }

    # The Arcadia case: the process never exits after this, so the log text
    # is the only signal that startup is over.
    It "names the client-only mod behind an 'invalid dist' crash" {
        $text = @(
            "Attempted to load class net/minecraft/client/gui/screens/Screen for invalid dist DEDICATED_SERVER",
            "-- MOD oculus --",
            "Details:",
            "`tMod File: /D:/3_Hobbies/GameServers/Minecraft/servers/Arcadia RPG/mods/oculus-mc1.20.1-1.8.0.jar",
            "Failed to start the minecraft server"
        ) -join "`n"
        $msg = Get-StartupFailure -ConsoleText $text
        $msg | Should Match "only works in the game client"
        $msg | Should Match "oculus-mc1\.20\.1-1\.8\.0\.jar"
    }

    It "names the mod whose mixins failed to apply" {
        $text = "Mixin apply for mod blur failed blur.mixins.json:MixinGameRenderer`nFailed to start the minecraft server"
        Get-StartupFailure -ConsoleText $text | Should Match "'blur'"
    }

    It "explains a missing dependency" {
        $text = "Missing or unsupported mandatory dependencies:`n`tMod ID: 'geckolib', Requested by: 'mowziesmobs', Expected range: '[4.4,)'`nFailed to start the minecraft server"
        $msg = Get-StartupFailure -ConsoleText $text
        $msg | Should Match "'mowziesmobs' needs 'geckolib'"
    }

    It "explains asking for more memory than the PC has" {
        $text = "Error occurred during initialization of VM`nCould not reserve enough space for 20971520KB object heap"
        Get-StartupFailure -ConsoleText $text | Should Match "Lower Max memory"
    }

    It "explains running out of memory" {
        $text = "java.lang.OutOfMemoryError: Java heap space`nFailed to start the minecraft server"
        Get-StartupFailure -ConsoleText $text | Should Match "Raise Max memory"
    }

    It "explains the wrong Java version" {
        $text = "Error: LinkageError occurred while loading main class net.minecraft.server.Main`n`tjava.lang.UnsupportedClassVersionError: has been compiled by a more recent version of the Java Runtime`nError: Could not create the Java Virtual Machine."
        Get-StartupFailure -ConsoleText $text | Should Match "different Java"
    }

    It "explains a broken Java install" {
        $text = "Error: could not open 'D:\...\tools\java\17\lib\jvm.cfg'"
        Get-StartupFailure -ConsoleText $text -LauncherExited $true | Should Match "Java install is broken"
    }

    It "explains a port that's already taken" {
        $text = "**** FAILED TO BIND TO PORT!`nThe exception was: java.net.BindException: Address already in use: bind`nPerhaps a server is already running on that port?"
        Get-StartupFailure -ConsoleText $text -LauncherExited $true | Should Match "already in use"
    }

    It "explains a world that's already open" {
        $text = "Failed to load level`njava.nio.channels.OverlappingFileLockException ... session.lock: already locked (possibly by other Minecraft instance?)`nFailed to start the minecraft server"
        Get-StartupFailure -ConsoleText $text | Should Match "already open"
    }

    It "explains an unaccepted EULA" {
        Get-StartupFailure -ConsoleText "You need to agree to the EULA in order to run the server." -LauncherExited $true | Should Match "EULA"
    }

    It "reports a launcher that died before Minecraft wrote anything" {
        Get-StartupFailure -ConsoleText "" -LauncherExited $true | Should Match "before Minecraft"
    }
}
