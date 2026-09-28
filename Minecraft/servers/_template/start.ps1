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

Push-Location $PSScriptRoot
try {
    if ($UseModpackLauncher) {
        # Forge/NeoForge 1.17+ generate run.bat, which reads memory from user_jvm_args.txt.
        # We pass 'nogui' so the server runs in the console without opening a Swing window.
        # start.bat (raw Fabric) and startserver.bat (ATM-style NeoForge, self-
        # installing) already hardcode nogui themselves, so no extra arg there.
        $launcherScript = Get-ModpackLauncherScript -InstancePath $PSScriptRoot
        if ($launcherScript -eq "run.bat") {
            cmd /c run.bat nogui
        }
        elseif ($launcherScript) {
            cmd /c $launcherScript
        }
        else {
            Write-Error "UseModpackLauncher is true but I couldn't find run.bat/start.bat/startserver.bat in $PSScriptRoot"
        }
    }
    else {
        java "-Xms$MinRam" "-Xmx$MaxRam" -jar $ServerJar nogui
    }
}
finally {
    Pop-Location
}
