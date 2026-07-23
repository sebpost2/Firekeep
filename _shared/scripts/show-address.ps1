# Muestra la direccion publica actual del tunel de playit.gg (sin arrancar nada).
. (Join-Path $PSScriptRoot "tunnel-helpers.ps1")

$toolDir = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\playit"
$secretFile = Join-Path $toolDir "secret.key"
$addrFile = Join-Path $toolDir "address.txt"

$addr = $null
if (Test-Path $secretFile) {
    $secret = (Get-Content $secretFile -Raw).Trim()
    try {
        $rd = Invoke-RestMethod -Uri "https://api.playit.gg/agents/rundata" -Method Post -Body "{}" `
            -Headers @{ Authorization = "Agent-Key $secret"; "Content-Type" = "application/json" } -TimeoutSec 15
        $mc = Select-MinecraftTunnel -Tunnels $rd.data.tunnels
        if ($mc -and $mc.assigned_domain) {
            $addr = $mc.assigned_domain
            Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ascii
        }
    } catch { }
}
if (-not $addr -and (Test-Path $addrFile)) { $addr = (Get-Content $addrFile -Raw).Trim() }

Write-Host ""
if ($addr) {
    # Copiar la direccion al portapapeles para pegarla directo en WhatsApp.
    $copied = $false
    try { Set-Clipboard -Value $addr -ErrorAction Stop; $copied = $true } catch { }

    Write-Host "  Direccion del server (Minecraft -> Multiplayer -> Add Server):"
    Write-Host ""
    Write-Host "      $addr" -ForegroundColor Yellow
    Write-Host ""
    if ($copied) {
        Write-Host "  Ya la copie al portapapeles: pegala en WhatsApp con Ctrl+V." -ForegroundColor Cyan
    }
    Write-Host "  (Tu amigo necesita el modpack Cave Horror Project 1 v3.4.1)"
} else {
    Write-Host "  Todavia no hay direccion. Corre setup-playit.ps1 y crea el tunel"
    Write-Host "  Minecraft Java en https://playit.gg/account/tunnels"
}
Write-Host ""
