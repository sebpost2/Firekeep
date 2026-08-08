# Downloads and sets up a portable (no-admin) embeddable Python inside
# GameServers\Minecraft\tools\ai\python\ - shared by the Kokoro and Whisper
# local-AI sidecars (install-kokoro.ps1 / install-whisper.ps1), so there's
# only one Python runtime to maintain instead of two.
#
# Usage: .\install-ai-python.ps1

$mcRoot = Split-Path -Parent $PSScriptRoot
$pythonDir = Join-Path $mcRoot "tools\ai\python"

if (Test-Path (Join-Path $pythonDir "python.exe")) {
    Write-Host "AI Python runtime already installed at $pythonDir"
    exit 0
}

New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null

$pyVersion = "3.11.9"
$zipUrl = "https://www.python.org/ftp/python/$pyVersion/python-$pyVersion-embed-amd64.zip"
$zipPath = Join-Path $env:TEMP "ai-python-embed.zip"

Write-Host "Downloading portable Python $pyVersion..."
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
Expand-Archive -Path $zipPath -DestinationPath $pythonDir -Force
Remove-Item -Force $zipPath

# The embeddable distribution ships with site-packages imports disabled (its
# own ._pth file comments out "import site"); pip-installed packages need
# that re-enabled to be importable at all.
$pthFile = Get-ChildItem -Path $pythonDir -Filter "python*._pth" | Select-Object -First 1
(Get-Content $pthFile.FullName) -replace '^#\s*import site$', 'import site' | Set-Content $pthFile.FullName -Encoding ascii

Write-Host "Bootstrapping pip..."
$getPipPath = Join-Path $env:TEMP "get-pip.py"
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPipPath -UseBasicParsing
& (Join-Path $pythonDir "python.exe") $getPipPath --no-warn-script-location
Remove-Item -Force $getPipPath

Write-Host "AI Python runtime installed at $pythonDir"
