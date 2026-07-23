# Muestra la IP de Tailscale de esta laptop para pasarsela a los amigos.
# INERTE hasta que instales Tailscale: si no esta, solo te dice como instalarlo.
# No instala nada ni crea cuentas por su cuenta.

function Get-TailscaleExe {
    $candidates = @(
        (Get-Command tailscale -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        "C:\Program Files\Tailscale\tailscale.exe",
        "C:\Program Files (x86)\Tailscale\tailscale.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

$exe = Get-TailscaleExe
Write-Host ""
if (-not $exe) {
    Write-Host "  Tailscale todavia NO esta instalado en esta laptop."
    Write-Host "  Si decidiste usar Tailscale, instalalo desde https://tailscale.com/download"
    Write-Host "  e inicia sesion. Despues volve a correr este script."
    Write-Host ""
    return
}

# tailscale ip -4 devuelve la IP 100.x.y.z de esta maquina en la red Tailscale.
$ip = $null
try { $ip = (& $exe ip -4 2>$null | Select-Object -First 1).Trim() } catch { }

if ($ip) {
    Write-Host "  Direccion de tu server por Tailscale"
    Write-Host "  (Minecraft -> Multiplayer -> Add Server):"
    Write-Host ""
    Write-Host "      ${ip}:25565"
    Write-Host ""
    Write-Host "  Tu amigo necesita: (1) Tailscale instalado y logueado,"
    Write-Host "  (2) estar en tu misma red Tailscale, (3) el modpack Cave Horror v3.4.1."
    Write-Host "  El HOST (esta casa) sigue entrando por LAN: localhost o 192.168.100.49:25565."
} else {
    Write-Host "  Tailscale esta instalado pero no devolvio IP."
    Write-Host "  Abri la app de Tailscale y asegurate de haber iniciado sesion (Connected)."
}
Write-Host ""
