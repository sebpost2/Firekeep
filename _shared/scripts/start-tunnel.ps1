# Lanza SOLO el agente de playit.gg (sin arrancar ningun server), compartido
# entre todos los game servers. Normalmente no hace falta correr esto a mano:
# el menu (Start.bat) ya levanta el tunel junto con el server.
#
# Requiere haber corrido antes UNA vez:  setup-playit.ps1  (vincula la cuenta).

$toolDir = Join-Path $PSScriptRoot "..\tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"

if (-not (Test-Path $playitExe)) {
    Write-Error "No se encontro playit.exe en $playitExe"
    exit 1
}

if (-not (Test-Path $secretFile)) {
    Write-Error "playit.gg no esta configurado. Corre primero: setup-playit.ps1"
    exit 1
}

$secret = (Get-Content $secretFile -Raw).Trim()
& $playitExe --secret $secret
