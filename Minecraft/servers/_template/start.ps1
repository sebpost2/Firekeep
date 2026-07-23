# Starts this server instance with the correct Java version.
# Installs it on its own (portable, no admin) if it isn't downloaded yet.

. (Join-Path $PSScriptRoot "run.config.ps1")

$mcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$javaHome = Join-Path $mcRoot "tools\java\$JavaVersion"
$javaBin = Join-Path $javaHome "bin"

if (-not (Test-Path (Join-Path $javaBin "java.exe"))) {
    Write-Host "Java $JavaVersion isn't installed yet, installing..."
    & (Join-Path $mcRoot "scripts\install-java.ps1") -MajorVersion $JavaVersion
}

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
        if (Test-Path "run.bat") {
            cmd /c run.bat nogui
        }
        elseif (Test-Path "start.bat") {
            cmd /c start.bat
        }
        else {
            Write-Error "UseModpackLauncher is true but I couldn't find run.bat/start.bat in $PSScriptRoot"
        }
    }
    else {
        java "-Xms$MinRam" "-Xmx$MaxRam" -jar $ServerJar nogui
    }
}
finally {
    Pop-Location
}
