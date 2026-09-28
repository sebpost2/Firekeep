# Starts this server instance with the correct Java version.
# Installs it on its own (portable, no admin) if it isn't downloaded yet.

. (Join-Path $PSScriptRoot "run.config.ps1")

$mcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gsRoot = Split-Path -Parent $mcRoot

# For servers set up by hand (CurseForge "Server Files" copied in, no
# .mrpack metadata to read $JavaVersion from): try to detect the right Java
# version from whatever got copied in, so run.config.ps1's default/manually
# set value only has to be right when detection can't figure it out itself.
. (Join-Path $gsRoot "_shared\scripts\modloader-helpers.ps1")
. (Join-Path $gsRoot "_shared\scripts\new-server-helpers.ps1")
. (Join-Path $gsRoot "_shared\scripts\server-settings-helpers.ps1")
. (Join-Path $gsRoot "_shared\scripts\backup-helpers.ps1")
$detectedJavaVersion = Get-DetectedJavaVersion -InstancePath $PSScriptRoot
if ($detectedJavaVersion -and $detectedJavaVersion -ne $JavaVersion) {
    Write-Host "Detected Java $detectedJavaVersion from the modpack files (run.config.ps1 says $JavaVersion) - using $detectedJavaVersion for this start."
    $JavaVersion = $detectedJavaVersion
}

$javaHome = Join-Path $mcRoot "tools\java\$JavaVersion"
$javaBin = Join-Path $javaHome "bin"

# Always run the installer: it returns right away when Java works, and
# repairs it when it's missing or broken (e.g. half-extracted).
& (Join-Path $mcRoot "scripts\install-java.ps1") -MajorVersion $JavaVersion

$env:PATH = "$javaBin;$env:PATH"
$env:JAVA_HOME = $javaHome

$eulaContent = Get-Content (Join-Path $PSScriptRoot "eula.txt") -Raw -ErrorAction SilentlyContinue
if (-not $eulaContent -or $eulaContent -notmatch "eula\s*=\s*true") {
    Write-Error "You need to accept the EULA. Read https://aka.ms/MinecraftEULA and set eula=true in eula.txt"
    exit 1
}

# The app tracks and stops servers over RCON; servers built by hand may not
# have it on yet.
Set-RconDefaults -PropsPath (Join-Path $PSScriptRoot "server.properties")

# Once a day, before the world is opened. A failed backup never blocks play.
try {
    $backup = Backup-World -InstancePath $PSScriptRoot
    if ($backup) { Write-Host "Backed up the world to $backup" }
} catch {
    Write-Warning "World backup failed ($($_.Exception.Message)) - starting anyway."
}

# Every launch below reads stdin from NUL and writes all output to
# logs\firekeep-console.log:
#  - NUL: Forge's run.bat ends with "pause", which otherwise leaves a hidden
#    console waiting forever after the server stops, holding this folder open
#    (it blocked deleting the server).
#  - The log: the app launches this window hidden, so without it errors Java
#    prints before Minecraft starts logging (wrong Java, too much memory) are
#    lost. The app reads it to explain a failed start in plain words.
# Paths are relative (we're inside this folder) so nothing needs quoting.
$consoleLog = "logs\firekeep-console.log"
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "logs") | Out-Null

Push-Location $PSScriptRoot
try {
    if ($UseModpackLauncher) {
        # Forge/NeoForge 1.17+ generate run.bat, which reads memory from user_jvm_args.txt.
        # We pass 'nogui' so the server runs in the console without opening a Swing window.
        # start.bat (raw Fabric) and startserver.bat (ATM-style NeoForge, self-
        # installing) already hardcode nogui themselves, so no extra arg there.
        $launcherScript = Get-ModpackLauncherScript -InstancePath $PSScriptRoot
        if ($launcherScript -eq "run.bat") {
            cmd /c ".\run.bat nogui <NUL >$consoleLog 2>&1"
        }
        elseif ($launcherScript) {
            cmd /c ".\$launcherScript <NUL >$consoleLog 2>&1"
        }
        else {
            Write-Error "UseModpackLauncher is true but I couldn't find run.bat/start.bat/startserver.bat in $PSScriptRoot"
        }
    }
    else {
        $javaArgs = @("-Xms$MinRam", "-Xmx$MaxRam") + (Get-AikarFlags) -join " "
        cmd /c "java $javaArgs -jar `"$ServerJar`" nogui <NUL >$consoleLog 2>&1"
    }
}
finally {
    Pop-Location
}
