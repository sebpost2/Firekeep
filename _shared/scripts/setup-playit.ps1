# Configuracion de playit.gg (se corre UNA sola vez).
#
# Vincula este agente a tu cuenta de playit.gg y guarda el "secret key" para que
# el tunel arranque solo de aca en adelante. El binario que usamos es el daemon,
# que no muestra el link de reclamo por si mismo, asi que este script lo hace por vos:
# genera un codigo, te da el link, espera a que lo apruebes, y guarda el secret.

$ErrorActionPreference = "Stop"
$toolDir = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"
$api = "https://api.playit.gg"

if (-not (Test-Path $playitExe)) { Write-Error "No encontre playit.exe en $playitExe"; exit 1 }

if (Test-Path $secretFile) {
    Write-Host "Ya existe un secret guardado ($secretFile)."
    $ans = Read-Host "Queres re-configurar desde cero? (s/N)"
    if ($ans -ne "s") { Write-Host "Ok, no cambio nada."; exit 0 }
}

# Cerrar cualquier playit corriendo para no chocar.
Get-Process playit -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 1) Generar codigo de reclamo (5 bytes aleatorios en hex, igual que el CLI oficial).
$bytes = New-Object byte[] 5
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$code = -join ($bytes | ForEach-Object { $_.ToString("x2") })
$claimUrl = "https://playit.gg/claim/$code"

Write-Host ""
Write-Host "==================================================================="
Write-Host " ABRI ESTE LINK EN TU NAVEGADOR PARA VINCULAR playit.gg:"
Write-Host ""
Write-Host "   $claimUrl"
Write-Host ""
Write-Host " Inicia sesion (o crea una cuenta gratis) y apreta 'Allow / Claim'."
Write-Host "==================================================================="
Write-Host ""
Start-Process $claimUrl   # intenta abrirlo solo
Write-Host "Esperando a que lo apruebes en el navegador..." -NoNewline

$headers = @{ "Content-Type" = "application/json" }
$version = "playit 1.0.10"
$accepted = $false

# 2) Poll a /claim/setup hasta que aceptes.
for ($i = 0; $i -lt 300 -and -not $accepted; $i++) {
    Start-Sleep -Seconds 3
    try {
        $body = @{ code = $code; agent_type = "assignable"; version = $version } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Uri "$api/claim/setup" -Method Post -Body $body -Headers $headers
        switch ($resp.data) {
            "UserAccepted"     { $accepted = $true }
            "UserRejected"     { Write-Host ""; Write-Error "Rechazaste el reclamo. Volve a correr el script."; exit 1 }
            default            { Write-Host "." -NoNewline }
        }
    } catch {
        Write-Host "x" -NoNewline
    }
}
Write-Host ""
if (-not $accepted) { Write-Error "Se agoto el tiempo esperando la aprobacion. Volve a correr el script."; exit 1 }

# 3) Intercambiar el codigo por el secret key.
$secret = $null
for ($i = 0; $i -lt 20 -and -not $secret; $i++) {
    try {
        $body = @{ code = $code } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Uri "$api/claim/exchange" -Method Post -Body $body -Headers $headers
        if ($resp.status -eq "success" -and $resp.data.secret_key) { $secret = $resp.data.secret_key }
        else { Start-Sleep -Seconds 2 }
    } catch { Start-Sleep -Seconds 2 }
}
if (-not $secret) { Write-Error "No pude obtener el secret. Volve a correr el script."; exit 1 }

# 4) Guardar el secret (tratalo como una contrasena).
Set-Content -Path $secretFile -Value $secret -NoNewline -Encoding ascii
# Restringir el archivo a solo este usuario (evita que otras cuentas de la
# misma laptop puedan leer el secret y controlar el tunel).
icacls $secretFile /inheritance:r /grant:r "${env:USERDOMAIN}\${env:USERNAME}:(R,W)" | Out-Null
Write-Host ""
Write-Host "OK! playit.gg quedo vinculado. Secret guardado en:"
Write-Host "   $secretFile"
Write-Host ""
Write-Host "PASO FINAL (una vez): crea el tunel de Minecraft en tu cuenta:"
Write-Host "   1. Entra a  https://playit.gg/account/tunnels"
Write-Host "   2. 'Add Tunnel' -> elegi 'Minecraft Java'."
Write-Host "   3. Que apunte al puerto local 25565 (viene por defecto)."
Write-Host "   4. Copia la direccion que te da (algo.playit.gg) -> esa se la pasas a tus amigos."
Write-Host ""
Write-Host "Listo. La proxima vez que arranques un server desde el menu, el tunel"
Write-Host "se conecta solo con este secret."
