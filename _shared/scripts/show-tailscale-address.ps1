# Shows this PC's Tailscale IP to share with friends.
# INERT until you install Tailscale: if it's not there, it just tells you how to install it.
# Doesn't install anything or create accounts on its own.

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
    Write-Host "  Tailscale is NOT installed on this PC yet."
    Write-Host "  If you decided to use Tailscale, install it from https://tailscale.com/download"
    Write-Host "  and sign in. Then run this script again."
    Write-Host ""
    return
}

# tailscale ip -4 returns this machine's 100.x.y.z IP on the Tailscale network.
$ip = $null
try { $ip = (& $exe ip -4 2>$null | Select-Object -First 1).Trim() } catch { }

if ($ip) {
    Write-Host "  Your server's address over Tailscale"
    Write-Host "  (Minecraft -> Multiplayer -> Add Server):"
    Write-Host ""
    Write-Host "      ${ip}:25565"
    Write-Host ""
    Write-Host "  Your friend needs: (1) Tailscale installed and signed in,"
    Write-Host "  (2) to be on your same Tailscale network, (3) the same modpack you're hosting."
    Write-Host "  The HOST (this PC) still connects over LAN: localhost or its local IP:25565."
} else {
    Write-Host "  Tailscale is installed but didn't return an IP."
    Write-Host "  Open the Tailscale app and make sure you're signed in (Connected)."
}
Write-Host ""
