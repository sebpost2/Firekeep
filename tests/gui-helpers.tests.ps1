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

Describe "Get-ScreenResizeTarget" {

    It "sizes the first screen shown" {
        $s = Get-ScreenResizeTarget -Screen "Home" -CurrentWidth 640 -CurrentHeight 860 -LastApplied $null
        $s.Width | Should Be 640
        $s.Height | Should Be 860
    }

    It "gives Home its full size back after Add Server shrank the window" {
        $applied = Get-ScreenSize -Screen "AddServer"
        $s = Get-ScreenResizeTarget -Screen "Home" -CurrentWidth 480 -CurrentHeight 580 -LastApplied $applied
        $s.Width | Should Be 640
        $s.Height | Should Be 860
    }

    It "keeps a size the user dragged the window to" {
        $applied = Get-ScreenSize -Screen "Home"
        Get-ScreenResizeTarget -Screen "AddServer" -CurrentWidth 900 -CurrentHeight 1000 -LastApplied $applied | Should BeNullOrEmpty
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
            "-- MOD oculus --",
            "Details:",
            "`tMod File: /D:/3_Hobbies/GameServers/Minecraft/servers/Arcadia RPG/mods/oculus-mc1.20.1-1.8.0.jar",
            "`tFailure message: Oculus (oculus) encountered an error",
            "`t`tjava.lang.RuntimeException: Attempted to load class net/minecraft/client/gui/screens/Screen for invalid dist DEDICATED_SERVER",
            "-- System Details --",
            "Failed to start the minecraft server"
        ) -join "`n"
        $msg = Get-StartupFailure -ConsoleText $text
        $msg | Should Match "only works in the game client"
        $msg | Should Match "oculus-mc1\.20\.1-1\.8\.0\.jar"
    }

    It "blames the mod whose mixin failed, not the mod its crash report names" {
            $text = @(
                "[19:53:16] [main/ERROR] [ne.mi.fm.lo.RuntimeDistCleaner/DISTXFORM]: Attempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER",
                "[19:53:16] [main/WARN] [mixin/]: @Mixin target net.minecraft.client.Minecraft was not found fragmentum.mixins.json:MixinMinecraft from mod fragmentum",
                "[19:53:43] [main/WARN] [ne.mi.ja.se.JarSelector/]: Attempted to select a dependency jar for JarJar which was passed in as source: curios. Using Mod File: D:\srv\mods\curios-forge-5.9.1.jar",
                "[19:53:29] [modloading-worker-0/FATAL] [mixin/]: Mixin apply for mod shouldersurfing failed shouldersurfing.forge.compat.mixins.json:create.ContraptionHandlerClientMixin_6_0_0 from mod shouldersurfing -> com.simibubi.create.content.contraptions.ContraptionHandlerClient",
                "---- Minecraft Crash Report ----",
                "-- MOD create --",
                "Details:",
                "`tMod File: /D:/srv/mods/create-1.20.1-6.0.8.jar",
                "`tFailure message: Create (create) has failed to load correctly",
                "`t`torg.spongepowered.asm.mixin.transformer.throwables.MixinTransformerError: An unexpected critical error was encountered",
                "-- System Details --",
                "Failed to start the minecraft server"
            ) -join "`n"
        $msg = Get-StartupFailure -ConsoleText $text
        $msg | Should Match "'shouldersurfing'"
        $msg | Should Not Match "create-1"
    }

    It "ignores harmless 'invalid dist' warnings when something else failed" {
        $text = @(
            "[19:53:16] [main/ERROR] [ne.mi.fm.lo.RuntimeDistCleaner/DISTXFORM]: Attempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER",
            "Missing or unsupported mandatory dependencies:",
            "`tMod ID: 'create', Requested by: 'create_enchantment_industry', Expected range: '[6.0.8,6.0.9)'",
            "Failed to start the minecraft server"
        ) -join "`n"
        Get-StartupFailure -ConsoleText $text | Should Match "'create_enchantment_industry' needs 'create'"
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

Describe "Update-ServerStartScript" {

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $templatePath = Join-Path $repoRoot "Minecraft\servers\_template\start.ps1"

    function New-Instance([string]$StartContent) {
        $dir = Join-Path $env:TEMP ("start-refresh-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir "start.ps1"), $StartContent)
        return $dir
    }

    # A real past template version (the v1.0.0 one), as git has it.
    $oldVersion = (& git -C $repoRoot show "f3e9380:Minecraft/servers/_template/start.ps1" 2>$null) -join "`n"

    It "replaces an unmodified copy of an older template with the current one" -Skip:(-not $oldVersion) {
        $dir = New-Instance $oldVersion
        Update-ServerStartScript -InstancePath $dir -TemplatePath $templatePath | Should Be $true
        (Get-ScriptFingerprint (Join-Path $dir "start.ps1")) | Should Be (Get-ScriptFingerprint $templatePath)
        Remove-Item -Recurse -Force $dir
    }

    It "recognizes an older template regardless of line endings" -Skip:(-not $oldVersion) {
        $dir = New-Instance ($oldVersion -replace "`n", "`r`n")
        Update-ServerStartScript -InstancePath $dir -TemplatePath $templatePath | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "never touches a start.ps1 someone customized" {
        $dir = New-Instance "# my own start script`nWrite-Host hi"
        Update-ServerStartScript -InstancePath $dir -TemplatePath $templatePath | Should Be $false
        Get-Content (Join-Path $dir "start.ps1") -Raw | Should Match "my own start script"
        Remove-Item -Recurse -Force $dir
    }

    It "leaves an up-to-date copy alone" {
        $dir = New-Instance ([System.IO.File]::ReadAllText($templatePath))
        Update-ServerStartScript -InstancePath $dir -TemplatePath $templatePath | Should Be $false
        Remove-Item -Recurse -Force $dir
    }

    # Guards the list itself: whenever _template\start.ps1 changes, the old
    # version's fingerprint must be added, or servers created from it stop
    # getting fixes.
    $pastVersions = @(& git -C $repoRoot log --format=%h -- "Minecraft/servers/_template/start.ps1" 2>$null)
    It "knows every earlier committed version of the template" -Skip:($pastVersions.Count -eq 0) {
        $current = Get-ScriptFingerprint $templatePath
        $known = Get-PastTemplateStartHashes
        foreach ($commit in $pastVersions) {
            $tmp = Join-Path $env:TEMP ("tpl-" + [Guid]::NewGuid().ToString("N") + ".ps1")
            [System.IO.File]::WriteAllText($tmp, ((& git -C $repoRoot show "${commit}:Minecraft/servers/_template/start.ps1") -join "`n"))
            $fp = Get-ScriptFingerprint $tmp
            Remove-Item $tmp
            if ($fp -ne $current) { "$commit known=$($known -contains $fp)" | Should Be "$commit known=True" }
        }
    }
}

Describe "Get-LaunchLockState" {

    # A fake server whose start-with-tunnel.ps1 runs $Body, launched hidden
    # the way the GUI does; its PID goes into .starting.lock like the real one.
    function Start-FakeLaunch([string]$Body) {
        $dir = Join-Path $env:TEMP ("lock-state-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "start-with-tunnel.ps1") -Value $Body
        $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$dir\start-with-tunnel.ps1`""
        Set-Content -Path (Join-Path $dir ".starting.lock") -Value $p.Id -NoNewline
        return [PSCustomObject]@{ Dir = $dir; Pid = $p.Id }
    }

    function Wait-ForChild([int]$ParentId, [string]$Name) {
        for ($i = 0; $i -lt 50; $i++) {
            if (Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId AND Name = '$Name'") { return }
            Start-Sleep -Milliseconds 100
        }
    }

    function Remove-FakeLaunch($launch) {
        Stop-ProcessTree -ProcessId $launch.Pid
        Start-Sleep -Milliseconds 300
        Remove-Item -Recurse -Force $launch.Dir -ErrorAction SilentlyContinue
    }

    It "returns null when there's no lock" {
        $dir = Join-Path $env:TEMP ("lock-state-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Get-LaunchLockState -InstancePath $dir | Should Be $null
        Remove-Item -Recurse -Force $dir
    }

    It "calls a lock stale when its launcher is gone" {
        $dir = Join-Path $env:TEMP ("lock-state-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $gone = Start-Process cmd.exe -ArgumentList "/c", "exit" -WindowStyle Hidden -PassThru
        $gone.WaitForExit()
        Set-Content -Path (Join-Path $dir ".starting.lock") -Value $gone.Id -NoNewline
        (Get-LaunchLockState -InstancePath $dir).Kind | Should Be "Stale"
        Remove-Item -Recurse -Force $dir
    }

    # Windows reuses PIDs: a live process that isn't this server's launcher
    # must not block the server from starting.
    It "calls a lock stale when its PID now belongs to something else" {
        $dir = Join-Path $env:TEMP ("lock-state-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir ".starting.lock") -Value $PID -NoNewline
        (Get-LaunchLockState -InstancePath $dir).Kind | Should Be "Stale"
        Remove-Item -Recurse -Force $dir
    }

    # Last night's Arcadia launcher: the server had stopped, but run.bat's
    # "pause" kept cmd.exe (and the lock) alive for hours.
    It "spots a launcher left waiting at 'pause' after its server stopped" {
        $launch = Start-FakeLaunch "cmd /c pause"
        try {
            Wait-ForChild $launch.Pid "cmd.exe"
            $state = Get-LaunchLockState -InstancePath $launch.Dir
            $state.Kind | Should Be "Leftover"
            $state.Pid | Should Be $launch.Pid
        } finally { Remove-FakeLaunch $launch }
    }

    It "leaves alone a launcher that's still preparing (no cmd.exe yet)" {
        $launch = Start-FakeLaunch "Start-Sleep -Seconds 60"
        try {
            Start-Sleep -Seconds 1
            (Get-LaunchLockState -InstancePath $launch.Dir).Kind | Should Be "Starting"
        } finally { Remove-FakeLaunch $launch }
    }

    It "leaves alone a launcher whose server (java.exe) is running" {
        $fakeJava = Join-Path $env:TEMP ("fakejava-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $fakeJava | Out-Null
        Copy-Item (Join-Path $env:SystemRoot "System32\PING.EXE") (Join-Path $fakeJava "java.exe")
        $launch = Start-FakeLaunch "cmd /c `"`"$fakeJava\java.exe`" -n 60 127.0.0.1`""
        try {
            Wait-ForChild $launch.Pid "cmd.exe"
            $cmd = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($launch.Pid) AND Name = 'cmd.exe'"
            Wait-ForChild $cmd.ProcessId "java.exe"
            (Get-LaunchLockState -InstancePath $launch.Dir).Kind | Should Be "Starting"
        } finally {
            Remove-FakeLaunch $launch
            Remove-Item -Recurse -Force $fakeJava -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-StartupFailure (before Minecraft launches)" {
    It "says Java couldn't be installed when start.ps1 reports that" {
        $text = "Firekeep: installing Java 17 failed: Could not get the link/checksum for Java 17 from Adoptium."
        Get-StartupFailure -ConsoleText $text -LauncherExited $true | Should Match "couldn't install Java 17"
    }

    # It used to guess "no internet", which sent people looking in the wrong place.
    It "doesn't guess a cause when nothing was captured" {
        Get-StartupFailure -ConsoleText "" -LauncherExited $true | Should Not Match "internet"
    }
}

Describe "Get-ClientOnlyModJar" {

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

    # A fake mod jar: a zip whose META-INF/mods.toml declares $ModId.
    function New-ModJar([string]$Dir, [string]$FileName, [string]$ModId, [string]$Toml = "META-INF/mods.toml", [string]$ModuleName, [hashtable]$Entries = @{}) {
        $path = Join-Path $Dir $FileName
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries.Keys) {
                $out = $zip.CreateEntry($name).Open()
                try { $bytes = [byte[]]$Entries[$name]; $out.Write($bytes, 0, $bytes.Length) } finally { $out.Dispose() }
            }
            $w = New-Object System.IO.StreamWriter($zip.CreateEntry($Toml).Open())
            try { $w.Write("modLoader=`"javafml`"`n[[mods]]`nmodId=`"$ModId`"`nversion=`"1.0`"`n") } finally { $w.Dispose() }
            if ($ModuleName) {
                $w = New-Object System.IO.StreamWriter($zip.CreateEntry("META-INF/MANIFEST.MF").Open())
                try { $w.Write("Manifest-Version: 1.0`r`nFMLModType: LIBRARY`r`nAutomatic-Module-Name: $ModuleName`r`n") } finally { $w.Dispose() }
            }
        } finally { $zip.Dispose(); $stream.Dispose() }
    }

    function New-Instance { $d = Join-Path $env:TEMP ("clientonly-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force -Path (Join-Path $d "mods") | Out-Null; return $d }

    # "invalid dist" log lines are often harmless warnings, and "Mod File:"
    # shows up in ordinary log lines too - so neither is a culprit on its own.
    It "doesn't guess from 'invalid dist' log lines outside a crash report section" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "oculus-mc1.20.1-1.8.0.jar" "oculus"
            $text = "Mod File: /D:/srv/mods/other.jar`nAttempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER`n-- MOD oculus --`n`tMod File: /D:/srv/mods/oculus-mc1.20.1-1.8.0.jar`nFailed to start the minecraft server"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be $null
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "offers the mod whose mixin failed, not the mod its crash report names (real Arcadia crash)" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "create-1.20.1-6.0.8.jar" "create"
            New-ModJar (Join-Path $dir "mods") "ShoulderSurfing-Forge-1.20.1-5.0.10.jar" "shouldersurfing"
            $text = @(
                "[19:53:16] [main/ERROR] [ne.mi.fm.lo.RuntimeDistCleaner/DISTXFORM]: Attempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER",
                "[19:53:16] [main/WARN] [mixin/]: @Mixin target net.minecraft.client.Minecraft was not found fragmentum.mixins.json:MixinMinecraft from mod fragmentum",
                "[19:53:43] [main/WARN] [ne.mi.ja.se.JarSelector/]: Attempted to select a dependency jar for JarJar which was passed in as source: curios. Using Mod File: D:\srv\mods\curios-forge-5.9.1.jar",
                "[19:53:29] [modloading-worker-0/FATAL] [mixin/]: Mixin apply for mod shouldersurfing failed shouldersurfing.forge.compat.mixins.json:create.ContraptionHandlerClientMixin_6_0_0 from mod shouldersurfing -> com.simibubi.create.content.contraptions.ContraptionHandlerClient",
                "---- Minecraft Crash Report ----",
                "-- MOD create --",
                "Details:",
                "`tMod File: /D:/srv/mods/create-1.20.1-6.0.8.jar",
                "`tFailure message: Create (create) has failed to load correctly",
                "`t`torg.spongepowered.asm.mixin.transformer.throwables.MixinTransformerError: An unexpected critical error was encountered",
                "-- System Details --",
                "Failed to start the minecraft server"
            ) -join "`n"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "ShoulderSurfing-Forge-1.20.1-5.0.10.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # NeoForge 1.20.5+ mods declare their id in neoforge.mods.toml instead.
    It "finds a NeoForge mod by the id in its neoforge.mods.toml" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "ShoulderSurfing-NeoForge-1.21.1-4.9.jar" "shouldersurfing" "META-INF/neoforge.mods.toml"
            $text = "[main/FATAL] [mixin/]: Mixin apply for mod shouldersurfing failed shouldersurfing.mixins.json:MixinCamera`nFailed to start the minecraft server"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "ShoulderSurfing-NeoForge-1.21.1-4.9.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # Real ATM10 (NeoForge 21.1) boot: Sodium's early "service" layer needs
    # LWJGL, which servers don't have, and dies before any mod loads. The
    # frame names a module (the jar's Automatic-Module-Name), not a jar.
    It "finds the jar behind a NeoForge service-layer crash on a client class (real ATM10 crash)" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "sodium-neoforge-0.8.13+mc1.21.1.jar" "sodium" "META-INF/neoforge.mods.toml" "sodium_service"
            New-ModJar (Join-Path $dir "mods") "create-1.21.1-6.0.4.jar" "create" "META-INF/neoforge.mods.toml"
            $text = @(
                "[10:17:05.322] [main/WARN] [loading.FMLConfig/]: ****************************************************************************************",
                "Exception in thread `"main`" java.lang.NoClassDefFoundError: org/lwjgl/Version",
                "`tat LAYER SERVICE/sodium_service@0.8.13+mc1.21.1/net.caffeinemc.mods.sodium.client.compatibility.checks.PreLaunchChecks.isUsingKnownCompatibleLwjglVersion(PreLaunchChecks.java:136)",
                "`tat LAYER SERVICE/sodium_service@0.8.13+mc1.21.1/net.caffeinemc.mods.sodium.service.SodiumWorkarounds.bootstrap(SodiumWorkarounds.java:19)",
                "`tat MC-BOOTSTRAP/fml_loader@4.0.44/net.neoforged.fml.loading.ImmediateWindowHandler.lambda`$load`$2(ImmediateWindowHandler.java:47)",
                "`tat java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:499)",
                "`tat cpw.mods.bootstraplauncher@2.0.2/cpw.mods.bootstraplauncher.BootstrapLauncher.main(BootstrapLauncher.java:69)",
                "Caused by: java.lang.ClassNotFoundException: org.lwjgl.Version",
                "`tat java.base/jdk.internal.loader.BuiltinClassLoader.loadClass(BuiltinClassLoader.java:641)",
                "`t... 26 more",
                "Press any key to continue . . . "
            ) -join "`r`n"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "sodium-neoforge-0.8.13+mc1.21.1.jar"
            Get-StartupFailure -ConsoleText $text -LauncherExited $true -InstancePath $dir | Should Match "only works in the game client.*sodium-neoforge-0\.8\.13\+mc1\.21\.1\.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # Real ATM10 boot after Sodium was moved aside: Sodium Extra's mixin
    # plugin needs a Sodium client class. NeoForge prints this stack through
    # log4j, so every line has a timestamp prefix.
    It "finds the mod behind a log4j-printed NeoForge crash on a missing client class (real ATM10 crash)" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "sodium-extra-neoforge-0.9.4+mc1.21.1.jar" "sodium_extra" "META-INF/neoforge.mods.toml"
            $p = "[10:32:24.946] [main/INFO] [STDERR/]: [java.lang.Throwable:printStackTrace:660]: "
            $text = @(
                "[10:32:24.932] [main/WARN] [mixin/]: Reference map 'openloader.refmap.json' for openloader.mixins.json could not be read.",
                "Exception in thread `"main`" [10:32:24.945] [main/INFO] [STDERR/]: [java.lang.ThreadGroup:uncaughtException:698]: java.lang.RuntimeException: java.lang.NoClassDefFoundError: net/caffeinemc/mods/sodium/client/services/PlatformRuntimeInformation ",
                "[10:32:24.945] [main/INFO] [STDERR/]: [java.lang.ThreadGroup:uncaughtException:698]: `tat MC-BOOTSTRAP/cpw.mods.modlauncher@11.0.5/cpw.mods.modlauncher.LaunchServiceHandlerDecorator.launch(LaunchServiceHandlerDecorator.java:32) ",
                "${p}Caused by: java.lang.NoClassDefFoundError: net/caffeinemc/mods/sodium/client/services/PlatformRuntimeInformation ",
                "${p}`tat TRANSFORMER/sodium_extra@0.9.4+mc1.21.1/me.flashyreese.mods.sodiumextra.client.SodiumExtraClientMod.mixinConfig(SodiumExtraClientMod.java:80) ",
                "${p}`tat MC-BOOTSTRAP/org.spongepowered.mixin/org.spongepowered.asm.mixin.transformer.PluginHandle.onLoad(PluginHandle.java:119) ",
                "${p}`tat java.base/java.lang.Class.forName(Class.java:627) ",
                "${p}`t... 8 more ",
                "Press any key to continue . . . "
            ) -join "`r`n"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "sodium-extra-neoforge-0.9.4+mc1.21.1.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # A mod that adds blocks, items or recipes can be part of quests and
    # recipes, and players' games would no longer match the server - so it
    # is never offered for setting aside, whatever the crash says.
    Context "a refused mod that adds content to the game" {
        $mixinCrash = "[main/FATAL] [mixin/]: Mixin apply for mod coolmod failed coolmod.mixins.json:MixinCamera`nFailed to start the minecraft server"

        It "isn't offered for setting aside when it adds blocks" {
            $dir = New-Instance
            try {
                New-ModJar (Join-Path $dir "mods") "coolmod-1.0.jar" "coolmod" -Entries @{ "assets/coolmod/blockstates/cool_block.json" = [byte[]]@(123, 125) }
                Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $mixinCrash | Should Be $null
                Get-StartupFailure -ConsoleText $mixinCrash -InstancePath $dir | Should Match "coolmod-1\.0\.jar adds items to the game but can't run on a server"
            } finally { Remove-Item -Recurse -Force $dir }
        }

        # Sodium's real layout: the mod itself is a jar inside the jar.
        It "isn't offered when its content is in a jar inside the jar" {
            $dir = New-Instance
            try {
                $innerPath = Join-Path $dir "inner.jar"
                $s = [System.IO.File]::Open($innerPath, [System.IO.FileMode]::CreateNew)
                $z = New-Object System.IO.Compression.ZipArchive($s, [System.IO.Compression.ZipArchiveMode]::Create)
                try { $e = $z.CreateEntry("data/coolmod/recipe/cool_block.json").Open(); $e.WriteByte(123); $e.Dispose() } finally { $z.Dispose(); $s.Dispose() }
                New-ModJar (Join-Path $dir "mods") "coolmod-1.0.jar" "coolmod" -Entries @{ "META-INF/jarjar/coolmod-content.jar" = [System.IO.File]::ReadAllBytes($innerPath) }
                Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $mixinCrash | Should Be $null
            } finally { Remove-Item -Recurse -Force $dir }
        }

        # Client mods may restyle vanilla items; that isn't content of their own.
        It "is still offered when it only overrides Minecraft's own item models" {
            $dir = New-Instance
            try {
                New-ModJar (Join-Path $dir "mods") "coolmod-1.0.jar" "coolmod" -Entries @{ "assets/minecraft/models/item/diamond_sword.json" = [byte[]]@(123, 125) }
                Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $mixinCrash | Should Be "coolmod-1.0.jar"
            } finally { Remove-Item -Recurse -Force $dir }
        }
    }

    # Real Forge crash reports list "Mod File:" BEFORE the failure message
    # inside each "-- MOD x --" section, and can have several sections.
    It "takes the jar from the same MOD section as the 'invalid dist' failure" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "blur-5.0.jar" "blur"
            New-ModJar (Join-Path $dir "mods") "oculus-1.8.jar" "oculus"
            $text = @(
                "-- MOD blur --", "Details:", "`tMod File: /D:/srv/mods/blur-5.0.jar", "`tFailure message: Blur (blur) has failed to load correctly",
                "`t`tjava.lang.NullPointerException",
                "-- MOD oculus --", "Details:", "`tMod File: /D:/srv/mods/oculus-1.8.jar", "`tFailure message: Oculus (oculus) encountered an error",
                "`t`tjava.lang.RuntimeException: Attempted to load class net/minecraft/client/Minecraft for invalid dist DEDICATED_SERVER",
                "-- System Details --", "Failed to start the minecraft server"
            ) -join "`n"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "oculus-1.8.jar"
            Get-StartupFailure -ConsoleText $text | Should Match "oculus-1\.8\.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "finds a Mixin failure's mod by the modId inside the jars" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "Blur-5.0.0.jar" "blur"
            New-ModJar (Join-Path $dir "mods") "Other-1.0.jar" "other"
            $text = "Mixin apply for mod blur failed blur.mixins.json:MixinGameRenderer`nFailed to start the minecraft server"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "Blur-5.0.0.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # Review focus 4.
    It "finds a Mixin failure's mod even when the jar name doesn't contain the id" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "Ryoamic-Lights-0.2.jar" "ryoamiclights"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText "Mixin apply for mod ryoamiclights failed x.mixins.json:Y" | Should Be "Ryoamic-Lights-0.2.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "handles jar names with square brackets" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "[1.20.1]ExtraSounds-2.0.jar" "extrasounds"
            $text = "Mixin apply for mod extrasounds failed extrasounds.mixins.json:X"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "[1.20.1]ExtraSounds-2.0.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns null when the named jar isn't in mods" {
        $dir = New-Instance
        try {
            $text = "-- MOD gone --`n`tMod File: /D:/srv/mods/gone.jar`n`t`tjava.lang.RuntimeException: Attempted to load class x for invalid dist DEDICATED_SERVER`n-- System Details --"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be $null
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "returns null for crashes that aren't about a client-only mod" {
        $dir = New-Instance
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText "java.lang.OutOfMemoryError" | Should Be $null } finally { Remove-Item -Recurse -Force $dir }
    }
}

Describe "Move-ModAside" {
    function New-Instance { $d = Join-Path $env:TEMP ("aside-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force -Path (Join-Path $d "mods") | Out-Null; return $d }

    It "moves the jar into _excluded\client-only" {
        $dir = New-Instance
        try {
            Set-Content -Path (Join-Path $dir "mods\a.jar") -Value "x"
            Move-ModAside -InstancePath $dir -JarName "a.jar"
            Test-Path (Join-Path $dir "_excluded\client-only\a.jar") | Should Be $true
            Test-Path (Join-Path $dir "mods\a.jar") | Should Be $false
        } finally { Remove-Item -Recurse -Force $dir }
    }

    # The one-click fix must not restart the server as if it had worked.
    It "throws, leaving the jar in place, when it can't be moved" {
        $dir = New-Instance
        $jar = Join-Path $dir "mods\held.jar"
        Set-Content -Path $jar -Value "x"
        $lock = [System.IO.File]::Open($jar, 'Open', 'Read', 'None')
        try {
            { Move-ModAside -InstancePath $dir -JarName "held.jar" } | Should Throw
            Test-Path $jar | Should Be $true
        } finally { $lock.Close(); Remove-Item -Recurse -Force $dir }
    }
}

# Found booting DeceasedCraft: once ShoulderSurfing was moved aside as
# client-only, the next start failed because tp_shooting requires it. A mod
# that needs a client-only mod can't load on the server either.
Describe "Mods that need a mod already moved aside as client-only" {

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

    function New-ModJar([string]$Dir, [string]$FileName, [string]$ModId) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        $stream = [System.IO.File]::Open((Join-Path $Dir $FileName), [System.IO.FileMode]::CreateNew)
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $w = New-Object System.IO.StreamWriter($zip.CreateEntry("META-INF/mods.toml").Open())
            try { $w.Write("modLoader=`"javafml`"`n[[mods]]`nmodId=`"$ModId`"`n") } finally { $w.Dispose() }
        } finally { $zip.Dispose(); $stream.Dispose() }
    }

    function New-Instance { $d = Join-Path $env:TEMP ("dependents-" + [Guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force -Path (Join-Path $d "mods") | Out-Null; return $d }

    $text = @(
        "Missing or unsupported mandatory dependencies:",
        "`tMod ID: 'shouldersurfing', Requested by: 'tp_shooting', Expected range: '[4.0,)'",
        "Failed to start the minecraft server"
    ) -join "`n"

    It "offers to move aside a mod whose required mod was moved aside as client-only" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "tp_shooting-forge-1.3.jar" "tp_shooting"
            New-ModJar (Join-Path $dir "_excluded\client-only") "ShoulderSurfing-Forge-1.20.1-4.15.0.jar" "shouldersurfing"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "tp_shooting-forge-1.3.jar"
            $msg = Get-StartupFailure -ConsoleText $text -InstancePath $dir
            $msg | Should Match "'tp_shooting'"
            $msg | Should Match "moved aside"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "offers nothing when the required mod is simply missing" {
        $dir = New-Instance
        try {
            New-ModJar (Join-Path $dir "mods") "tp_shooting-forge-1.3.jar" "tp_shooting"
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be $null
            Get-StartupFailure -ConsoleText $text -InstancePath $dir | Should Match "'tp_shooting' needs 'shouldersurfing', which isn't in the server's mods folder"
        } finally { Remove-Item -Recurse -Force $dir }
    }
}

# Found booting DeceasedCraft: Forge collected several "Failed to create mod
# instance. ModID: X" errors in one start and saved the crash report without
# printing its sections. The mod to move aside is the first stack frame's
# jar in mods\ - for framework that's Controllable, whose client config
# Framework was loading, not Framework (a library server mods need).
Describe "Client-only mods named by 'Failed to create mod instance' errors" {

    function New-Instance([string[]]$Jars) {
        $d = Join-Path $env:TEMP ("failedinstance-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path (Join-Path $d "mods") | Out-Null
        foreach ($j in $Jars) { Set-Content -LiteralPath (Join-Path $d "mods\$j") -Value "jar" }
        return $d
    }

    $frameworkCrash = @(
        "[20:11:52] [modloading-worker-0/ERROR] [ne.mi.fm.ja.FMLModContainer/LOADING]: Failed to create mod instance. ModID: framework, class com.mrcrayfish.framework.FrameworkForge",
        "java.lang.BootstrapMethodError: java.lang.RuntimeException: Attempted to load class net/minecraft/client/gui/screens/Screen for invalid dist DEDICATED_SERVER",
        "`tat cpw.mods.cl.ModuleClassLoader.loadClass(ModuleClassLoader.java:135) ~[securejarhandler-2.1.10.jar:?] {}",
        "`tat com.mrcrayfish.controllable.client.settings.InputLibrary.<clinit>(InputLibrary.java:14) ~[controllable-forge-1.20.1-0.21.7.jar%23466!/:1.20.1-0.21.7] {re:classloading}",
        "`tat com.mrcrayfish.framework.FrameworkForge.<init>(FrameworkForge.java:50) ~[framework-forge-1.20.1-0.7.15.jar%23538!/:1.20.1-0.7.15] {re:classloading}",
        "Caused by: java.lang.RuntimeException: Attempted to load class net/minecraft/client/gui/screens/Screen for invalid dist DEDICATED_SERVER",
        "[20:11:56] [main/FATAL] [ne.mi.fm.ModLoader/LOADING]: Failed to complete lifecycle event CONSTRUCT, 5 errors found",
        "[20:11:56] [main/ERROR] [minecraft/Main]: Failed to start the minecraft server"
    ) -join "`n"

    It "blames the mod whose code touched the client class, not the mod being built" {
        $dir = New-Instance @("controllable-forge-1.20.1-0.21.7.jar", "framework-forge-1.20.1-0.7.15.jar")
        try {
            Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $frameworkCrash | Should Be "controllable-forge-1.20.1-0.21.7.jar"
            Get-StartupFailure -ConsoleText $frameworkCrash -InstancePath $dir | Should Match "controllable-forge-1\.20\.1-0\.21\.7\.jar"
        } finally { Remove-Item -Recurse -Force $dir }
    }

    It "takes a mod that refuses to load on a server at its word" {
        $text = @(
            "[20:11:52] [modloading-worker-0/ERROR] [ne.mi.fm.ja.FMLModContainer/LOADING]: Failed to create mod instance. ModID: entity_model_features, class traben.entity_model_features.forge.EMFForge",
            "java.lang.UnsupportedOperationException: Attempting to load a clientside only mod [EMF] on the server, refusing",
            "`tat traben.entity_model_features.forge.EMFForge.<init>(EMFForge.java:39) ~[entity_model_features_forge_1.20.1-2.2.jar%23510!/:?] {re:classloading}",
            "[20:11:56] [main/ERROR] [minecraft/Main]: Failed to start the minecraft server"
        ) -join "`n"
        $dir = New-Instance @("entity_model_features_forge_1.20.1-2.2.jar")
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "entity_model_features_forge_1.20.1-2.2.jar" } finally { Remove-Item -Recurse -Force $dir }
    }

    # Oculus: Forge fails while inspecting the mod's own class, so no stack
    # frame is in a mod jar - the mod being built is then the culprit.
    It "falls back to the mod being built when no stack frame is in a mod jar" {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $dir = New-Instance @()
        $jarPath = Join-Path $dir "mods\oculus-mc1.20.1-1.8.0.jar"
        $stream = [System.IO.File]::Open($jarPath, [System.IO.FileMode]::CreateNew)
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        $w = New-Object System.IO.StreamWriter($zip.CreateEntry("META-INF/mods.toml").Open())
        $w.Write("[[mods]]`nmodId=`"oculus`"`n"); $w.Dispose(); $zip.Dispose(); $stream.Dispose()
        $text = @(
            "[20:11:52] [modloading-worker-0/ERROR] [ne.mi.fm.ja.FMLModContainer/LOADING]: Failed to create mod instance. ModID: oculus, class net.irisshaders.iris.Iris",
            "java.lang.RuntimeException: Attempted to load class net/minecraft/client/gui/screens/Screen for invalid dist DEDICATED_SERVER",
            "`tat cpw.mods.cl.ModuleClassLoader.loadClass(ModuleClassLoader.java:135) ~[securejarhandler-2.1.10.jar:?] {}",
            "`tat java.lang.Class.getDeclaredConstructors0(Native Method) ~[?:?] {re:mixin}",
            "`tat net.minecraftforge.fml.javafmlmod.FMLModContainer.constructMod(FMLModContainer.java:73) ~[javafmllanguage-1.20.1-47.4.0.jar%23716!/:?] {}",
            "[20:11:52] [modloading-worker-0/INFO] [in.in.InsaneLib/]: Found (COMMON) InsaneLib Feature class x"
        ) -join "`n"
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "oculus-mc1.20.1-1.8.0.jar" } finally { Remove-Item -Recurse -Force $dir }
    }

    # Same crash, second wording (DeceasedCraft, a later start): a missing
    # client class shows up as NoClassDefFoundError/ClassNotFoundException.
    It "treats a missing net.minecraft.client class as a client-only cause" {
        $dir = New-Instance @("controllable-forge-1.20.1-0.21.7.jar", "framework-forge-1.20.1-0.7.15.jar")
        $text = @(
            "[20:21:31] [modloading-worker-0/ERROR] [ne.mi.fm.ja.FMLModContainer/LOADING]: Failed to create mod instance. ModID: framework, class com.mrcrayfish.framework.FrameworkForge",
            "java.lang.NoClassDefFoundError: net/minecraft/client/gui/components/toasts/Toast",
            "`tat com.mrcrayfish.controllable.Controllable.<init>(Controllable.java:40) ~[controllable-forge-1.20.1-0.21.7.jar%23466!/:1.20.1-0.21.7] {re:classloading}",
            "`tat com.mrcrayfish.framework.FrameworkForge.<init>(FrameworkForge.java:50) ~[framework-forge-1.20.1-0.7.15.jar%23538!/:1.20.1-0.7.15] {re:classloading}",
            "Caused by: java.lang.ClassNotFoundException: net.minecraft.client.gui.components.toasts.Toast",
            "[20:21:33] [main/ERROR] [minecraft/Main]: Failed to start the minecraft server"
        ) -join "`n"
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be "controllable-forge-1.20.1-0.21.7.jar" } finally { Remove-Item -Recurse -Force $dir }
    }

    It "ignores a failed mod whose error isn't about the client" {
        $text = @(
            "[20:11:52] [modloading-worker-0/ERROR] [ne.mi.fm.ja.FMLModContainer/LOADING]: Failed to create mod instance. ModID: brokenmod, class a.b.C",
            "java.lang.NullPointerException: config was null",
            "`tat a.b.C.<init>(C.java:10) ~[brokenmod-1.0.jar%23100!/:?] {}",
            "[20:11:56] [main/ERROR] [minecraft/Main]: Failed to start the minecraft server"
        ) -join "`n"
        $dir = New-Instance @("brokenmod-1.0.jar")
        try { Get-ClientOnlyModJar -InstancePath $dir -ConsoleText $text | Should Be $null } finally { Remove-Item -Recurse -Force $dir }
    }
}
