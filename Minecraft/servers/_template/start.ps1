# Arranca esta instancia de server con la version de Java correcta.
# La instala sola (portable, sin admin) si todavia no esta descargada.

. (Join-Path $PSScriptRoot "run.config.ps1")

$mcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$javaHome = Join-Path $mcRoot "tools\java\$JavaVersion"
$javaBin = Join-Path $javaHome "bin"

if (-not (Test-Path (Join-Path $javaBin "java.exe"))) {
    Write-Host "Java $JavaVersion no esta instalado todavia, instalando..."
    & (Join-Path $mcRoot "scripts\install-java.ps1") -MajorVersion $JavaVersion
}

$env:PATH = "$javaBin;$env:PATH"
$env:JAVA_HOME = $javaHome

$eulaContent = Get-Content (Join-Path $PSScriptRoot "eula.txt") -Raw -ErrorAction SilentlyContinue
if (-not $eulaContent -or $eulaContent -notmatch "eula\s*=\s*true") {
    Write-Error "Falta aceptar la EULA. Lee https://aka.ms/MinecraftEULA y pon eula=true en eula.txt"
    exit 1
}

Push-Location $PSScriptRoot
try {
    if ($UseModpackLauncher) {
        # Forge/NeoForge 1.17+ generan run.bat, que lee la memoria de user_jvm_args.txt.
        # Le pasamos 'nogui' para que el server corra en consola sin abrir ventana Swing.
        if (Test-Path "run.bat") {
            cmd /c run.bat nogui
        }
        elseif (Test-Path "start.bat") {
            cmd /c start.bat
        }
        else {
            Write-Error "UseModpackLauncher esta en true pero no encontre run.bat/start.bat en $PSScriptRoot"
        }
    }
    else {
        java "-Xms$MinRam" "-Xmx$MaxRam" -jar $ServerJar nogui
    }
}
finally {
    Pop-Location
}
