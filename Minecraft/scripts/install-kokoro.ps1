# Installs the Kokoro TTS sidecar: the shared portable Python runtime,
# kokoro-onnx + fastapi/uvicorn, the model weights, and the server script.
#
# Usage: .\install-kokoro.ps1

$mcRoot = Split-Path -Parent $PSScriptRoot
$gsRoot = Split-Path -Parent $mcRoot
$kokoroDir = Join-Path $mcRoot "tools\ai\kokoro"
$pythonExe = Join-Path $mcRoot "tools\ai\python\python.exe"

if (-not (Test-Path $pythonExe)) {
    & (Join-Path $PSScriptRoot "install-ai-python.ps1")
}

New-Item -ItemType Directory -Force -Path $kokoroDir | Out-Null

Write-Host "Installing kokoro-onnx, fastapi, uvicorn..."
& $pythonExe -m pip install --quiet kokoro-onnx fastapi "uvicorn[standard]"

$modelPath = Join-Path $kokoroDir "kokoro-v1.0.onnx"
$voicesPath = Join-Path $kokoroDir "voices-v1.0.bin"

if (-not (Test-Path $modelPath) -or -not (Test-Path $voicesPath)) {
    Write-Host "Looking up the kokoro-onnx release that ships the model weights..."
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/thewh1teagle/kokoro-onnx/releases" -UseBasicParsing
    $release = $releases | Where-Object { ($_.assets | Where-Object { $_.name -eq "kokoro-v1.0.onnx" }) } | Select-Object -First 1
    if (-not $release) {
        throw "Could not find a kokoro-onnx release with model weights. Check https://github.com/thewh1teagle/kokoro-onnx/releases manually."
    }
    $modelAsset = $release.assets | Where-Object { $_.name -eq "kokoro-v1.0.onnx" } | Select-Object -First 1
    $voicesAsset = $release.assets | Where-Object { $_.name -eq "voices-v1.0.bin" } | Select-Object -First 1

    Write-Host "Downloading Kokoro model weights (~300MB)..."
    if (-not (Test-Path $modelPath)) {
        Invoke-WebRequest -Uri $modelAsset.browser_download_url -OutFile "$modelPath.tmp" -UseBasicParsing
        Move-Item -Path "$modelPath.tmp" -Destination $modelPath
    }
    if (-not (Test-Path $voicesPath)) {
        Invoke-WebRequest -Uri $voicesAsset.browser_download_url -OutFile "$voicesPath.tmp" -UseBasicParsing
        Move-Item -Path "$voicesPath.tmp" -Destination $voicesPath
    }
}

Copy-Item -Path (Join-Path $gsRoot "_shared\scripts\verity-ai-servers\kokoro_server.py") -Destination $kokoroDir -Force

Write-Host "Kokoro TTS installed at $kokoroDir"
