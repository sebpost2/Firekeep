# Shows the current public address of the playit.gg tunnel (without starting anything).
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
    # Copy the address to the clipboard so it's ready to paste in a chat.
    $copied = $false
    try { Set-Clipboard -Value $addr -ErrorAction Stop; $copied = $true } catch { }

    Write-Host "  Server address (Minecraft -> Multiplayer -> Add Server):"
    Write-Host ""
    Write-Host "      $addr" -ForegroundColor Yellow
    Write-Host ""
    if ($copied) {
        Write-Host "  Copied to your clipboard: paste it wherever you're sending it." -ForegroundColor Cyan
    }
    Write-Host "  (Your friend needs the same modpack installed to join.)"
} else {
    Write-Host "  No address yet. Run setup-playit.ps1 and create the Minecraft"
    Write-Host "  Java tunnel at https://playit.gg/account/tunnels"
}
Write-Host ""
