# Minecraft/scripts/install-ollama.ps1
# Downloads and installs (portable, no admin) Ollama inside
# GameServers\Minecraft\tools\ai\ollama\, then pulls the default local
# model Verity is configured to use (timheinrich2011/verity-3b, a
# Qwen2.5-3B fine-tune for Verity's prompt format).
#
# Usage: .\install-ollama.ps1

$mcRoot = Split-Path -Parent $PSScriptRoot
$ollamaDir = Join-Path $mcRoot "tools\ai\ollama"

if (-not (Test-Path (Join-Path $ollamaDir "ollama.exe"))) {
    New-Item -ItemType Directory -Force -Path $ollamaDir | Out-Null

    Write-Host "Looking up the latest Ollama release..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ollama/ollama/releases/latest" -UseBasicParsing
    $asset = $release.assets | Where-Object { $_.name -eq "ollama-windows-amd64.zip" } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find ollama-windows-amd64.zip in the latest Ollama release ($($release.tag_name))."
    }

    $zipPath = Join-Path $env:TEMP "ollama-windows-amd64.zip"
    Write-Host "Downloading Ollama $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $ollamaDir -Force
    Remove-Item -Force $zipPath
} else {
    Write-Host "Ollama already installed at $ollamaDir"
}

$ollamaExe = Join-Path $ollamaDir "ollama.exe"
$env:OLLAMA_MODELS = Join-Path $ollamaDir "models"

Write-Host "Starting Ollama to pull the verity-3b model (downloads a few GB, this can take a while)..."
$proc = Start-Process -FilePath $ollamaExe -ArgumentList "serve" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
try {
    & $ollamaExe pull "timheinrich2011/verity-3b"
    if ($LASTEXITCODE -ne 0) {
        throw "ollama pull exited with code $LASTEXITCODE - verity-3b was not downloaded successfully."
    }
    Write-Host "Ollama installed and verity-3b model pulled."
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
