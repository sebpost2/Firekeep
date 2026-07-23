# playit.gg setup (run ONCE).
#
# Links this agent to your playit.gg account and saves the "secret key" so the
# tunnel starts on its own from here on. The binary we use is the daemon,
# which doesn't show the claim link by itself, so this script does it for you:
# it generates a code, gives you the link, waits for you to approve it, and
# saves the secret.

$ErrorActionPreference = "Stop"
$toolDir = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\playit"
$playitExe = Join-Path $toolDir "playit.exe"
$secretFile = Join-Path $toolDir "secret.key"
$api = "https://api.playit.gg"

if (-not (Test-Path $playitExe)) { Write-Error "Could not find playit.exe at $playitExe"; exit 1 }

if (Test-Path $secretFile) {
    Write-Host "A secret is already saved ($secretFile)."
    $ans = Read-Host "Reconfigure from scratch? (y/N)"
    if ($ans -ne "y") { Write-Host "Ok, nothing changed."; exit 0 }
}

# Close any running playit to avoid clashing.
Get-Process playit -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 1) Generate a claim code (5 random hex bytes, same as the official CLI).
$bytes = New-Object byte[] 5
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$code = -join ($bytes | ForEach-Object { $_.ToString("x2") })
$claimUrl = "https://playit.gg/claim/$code"

Write-Host ""
Write-Host "==================================================================="
Write-Host " OPEN THIS LINK IN YOUR BROWSER TO LINK playit.gg:"
Write-Host ""
Write-Host "   $claimUrl"
Write-Host ""
Write-Host " Sign in (or create a free account) and click 'Allow / Claim'."
Write-Host "==================================================================="
Write-Host ""
Start-Process $claimUrl   # tries to open it on its own
Write-Host "Waiting for you to approve it in the browser..." -NoNewline

$headers = @{ "Content-Type" = "application/json" }
$version = "playit 1.0.10"
$accepted = $false

# 2) Poll /claim/setup until you accept.
for ($i = 0; $i -lt 300 -and -not $accepted; $i++) {
    Start-Sleep -Seconds 3
    try {
        $body = @{ code = $code; agent_type = "assignable"; version = $version } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Uri "$api/claim/setup" -Method Post -Body $body -Headers $headers
        switch ($resp.data) {
            "UserAccepted"     { $accepted = $true }
            "UserRejected"     { Write-Host ""; Write-Error "You rejected the claim. Run the script again."; exit 1 }
            default            { Write-Host "." -NoNewline }
        }
    } catch {
        Write-Host "x" -NoNewline
    }
}
Write-Host ""
if (-not $accepted) { Write-Error "Timed out waiting for approval. Run the script again."; exit 1 }

# 3) Exchange the code for the secret key.
$secret = $null
for ($i = 0; $i -lt 20 -and -not $secret; $i++) {
    try {
        $body = @{ code = $code } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Uri "$api/claim/exchange" -Method Post -Body $body -Headers $headers
        if ($resp.status -eq "success" -and $resp.data.secret_key) { $secret = $resp.data.secret_key }
        else { Start-Sleep -Seconds 2 }
    } catch { Start-Sleep -Seconds 2 }
}
if (-not $secret) { Write-Error "Could not get the secret. Run the script again."; exit 1 }

# 4) Save the secret (treat it like a password). Restricts access to the
# current user BEFORE writing the content, so it's never on disk for even a
# moment with the folder's default (inherited) permissions.
. (Join-Path $PSScriptRoot "secret-helpers.ps1")
Set-RestrictedSecretFile -Path $secretFile -Content $secret
Write-Host ""
Write-Host "OK! playit.gg is linked. Secret saved at:"
Write-Host "   $secretFile"
Write-Host ""
Write-Host "LAST STEP (once): create the Minecraft tunnel in your account:"
Write-Host "   1. Go to  https://playit.gg/account/tunnels"
Write-Host "   2. 'Add Tunnel' -> pick 'Minecraft Java'."
Write-Host "   3. Point it to local port 25565 (default)."
Write-Host "   4. Copy the address it gives you (something.playit.gg) -> that's what you share with friends."
Write-Host ""
Write-Host "Done. Next time you start a server from the menu, the tunnel"
Write-Host "connects on its own with this secret."
