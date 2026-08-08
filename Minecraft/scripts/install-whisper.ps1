# Minecraft/scripts/install-whisper.ps1
# Installs the Whisper STT sidecar: the shared portable Python runtime,
# faster-whisper + fastapi/uvicorn, and the server script. The base.en
# model itself is downloaded lazily by faster-whisper on first request.
#
# Usage: .\install-whisper.ps1

$mcRoot = Split-Path -Parent $PSScriptRoot
$gsRoot = Split-Path -Parent $mcRoot
$whisperDir = Join-Path $mcRoot "tools\ai\whisper"
$pythonExe = Join-Path $mcRoot "tools\ai\python\python.exe"

if (-not (Test-Path $pythonExe)) {
    & (Join-Path $PSScriptRoot "install-ai-python.ps1")
}

New-Item -ItemType Directory -Force -Path $whisperDir | Out-Null

Write-Host "Installing faster-whisper, fastapi, uvicorn..."
& $pythonExe -m pip install --quiet faster-whisper fastapi "uvicorn[standard]" python-multipart

Copy-Item -Path (Join-Path $gsRoot "_shared\scripts\verity-ai-servers\whisper_server.py") -Destination $whisperDir -Force

Write-Host "Whisper STT installed at $whisperDir (base.en model downloads automatically on first use)"
