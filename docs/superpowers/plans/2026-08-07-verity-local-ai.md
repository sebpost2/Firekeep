# Verity Local AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Verity's LLM/TTS/STT backends locally (Ollama + a Kokoro TTS sidecar + a Whisper STT sidecar) instead of cloud providers, managed as a first-class GUI feature of the GameServers toolkit.

**Architecture:** Three host-wide background services under `Minecraft/tools/ai/` (Ollama native; Kokoro and Whisper as small FastAPI wrappers run by a shared portable Python runtime), installed via `install-*.ps1` scripts matching the existing `install-java.ps1` pattern. A new `_shared/scripts/verity-helpers.ps1` detects the Verity mod, writes `config/verity-common.toml` to point at the sidecars, and starts/stops them. The GUI (`Start-Gui.ps1` + `HomeScreen.xaml`) gets a "Local AI" panel, visible only when Verity is detected on the selected server, following the existing campfire-status/action-button idiom.

**Tech Stack:** PowerShell 5.1, WPF/XAML, Pester (v4-style `Should Be`), Python 3.11 (embeddable, portable) + FastAPI/uvicorn for the two sidecars this project doesn't have a native binary for, Ollama (native).

## Global Constraints

- No admin rights, no system-wide installs — everything lives under `Minecraft/tools/`, matching `install-java.ps1`.
- Never hardcode a downloadable asset's version/URL — resolve it dynamically via the upstream's release API at install time, same as `install-java.ps1` does against Adoptium.
- Pester tests (v4 style: `Describe`/`It`/`Should Be`/`Should Throw`) only for pure logic (no real process/network I/O) — matches every existing `tests/*.tests.ps1` file. Install scripts and the FastAPI server scripts are verified manually, same as `install-java.ps1` (which has no test file).
- Default sidecar ports/URLs (already the mod's own convention, seen in `verity-client.toml`): Ollama `127.0.0.1:11434`, Kokoro `127.0.0.1:8880`, Whisper `127.0.0.1:9000`, all under `/v1`.
- Default model: `timheinrich2011/verity-3b` (Ollama), Kokoro's stock `kokoro-v1.0.onnx` weights, Whisper's `base.en` (auto-downloaded by `faster-whisper` on first use — no separate download step needed).
- CPU inference for Kokoro and Whisper (both are lightweight enough to run comfortably on CPU); the RTX 5050's 8GB VRAM is reserved entirely for Ollama's LLM. Don't add GPU wiring for the two sidecars — it's unnecessary complexity for models this small.

---

### Task 1: Verity mod detection

**Files:**
- Create: `_shared/scripts/verity-helpers.ps1`
- Test: `tests/verity-helpers.tests.ps1`

**Interfaces:**
- Produces: `Test-VerityModPresent(-InstancePath <string>) -> bool`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/verity-helpers.tests.ps1
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\verity-helpers.ps1")

Describe "Test-VerityModPresent" {

    $root = Join-Path $env:TEMP ("verity-detect-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "returns true when a verity-*.jar exists in mods/" {
        $inst = Join-Path $root "with-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\verity-6.1.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $true
    }

    It "returns false when mods/ has no verity jar" {
        $inst = Join-Path $root "without-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\somemod.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    It "returns false when there's no mods/ folder at all" {
        $inst = Join-Path $root "no-mods-dir"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `verity-helpers.ps1` doesn't exist yet / `Test-VerityModPresent` not recognized.

- [ ] **Step 3: Write minimal implementation**

```powershell
# _shared/scripts/verity-helpers.ps1
# Detection, config, and local-AI-sidecar lifecycle for servers running the
# Verity mod. Loaded via dot-source.

# A server is "Verity-enabled" if its mods/ folder has a verity-*.jar -
# same signature-file-scan pattern Get-DetectedJavaVersion already uses.
function Test-VerityModPresent {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $modsDir = Join-Path $InstancePath "mods"
    if (-not (Test-Path $modsDir)) { return $false }
    $jar = Get-ChildItem -Path $modsDir -Filter "verity-*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$jar
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: detect Verity mod in a server's mods folder"
```

---

### Task 2: TOML section-value editor

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1`
- Test: `tests/verity-helpers.tests.ps1`

**Interfaces:**
- Consumes: nothing new
- Produces: `Set-TomlSectionValue(-Lines <string[]> -Section <string> -Key <string> -Value <string>) -> string[]`

- [ ] **Step 1: Write the failing test**

```powershell
Describe "Set-TomlSectionValue" {

    $sampleToml = @(
        '[GeneralSettings.AISettings]',
        '`tapiKey = ""',
        '`taiEndpoint = ""',
        '`taiProvider = "OPENAI"',
        '',
        '[GeneralSettings.VoiceSettings]',
        '`tttsProvider = "NATIVE"'
    ) -replace '`t', "`t"   # literal tab characters in the fixture lines

    It "replaces a key's value only within the matching section" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
        ($result | Where-Object { $_ -match '^\s*aiProvider\s*=' }) | Should Be "`taiProvider = `"OLLAMA`""
    }

    It "leaves a same-named key in a different section untouched" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "ttsProvider" -Value "KOKORO"
        ($result | Where-Object { $_ -match '^\s*ttsProvider\s*=' }) | Should Be "`tttsProvider = `"NATIVE`""
    }

    It "preserves every other line unchanged" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
        $result.Count | Should Be $sampleToml.Count
        $result[0] | Should Be '[GeneralSettings.AISettings]'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Set-TomlSectionValue` not recognized.

- [ ] **Step 3: Write minimal implementation**

```powershell
# Replaces `Key = "..."` with a new value, but only for lines that fall
# under the given `[Section]` header - so e.g. AISettings.aiProvider and a
# hypothetical same-named key elsewhere never collide. Preserves the
# original line's leading whitespace (verity-common.toml indents nested
# keys with a tab). Section headers are matched by exact text inside the
# brackets (e.g. "GeneralSettings.AISettings" for "[GeneralSettings.AISettings]").
function Set-TomlSectionValue {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $result = @()
    $inSection = $false
    $sectionHeader = "[$Section]"

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[.+\]$') {
            $inSection = ($trimmed -eq $sectionHeader)
            $result += $line
            continue
        }
        if ($inSection -and $trimmed -match "^$([regex]::Escape($Key))\s*=") {
            $leading = $line.Substring(0, $line.Length - $line.TrimStart().Length)
            $result += "$leading$Key = `"$Value`""
            continue
        }
        $result += $line
    }
    return $result
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (6 tests total)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add section-aware TOML value editor for verity-common.toml"
```

---

### Task 3: Write the local-AI config into verity-common.toml

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1`
- Test: `tests/verity-helpers.tests.ps1`

**Interfaces:**
- Consumes: `Set-TomlSectionValue` (Task 2)
- Produces: `Set-VerityLocalAI(-InstancePath <string>) -> void`. Throws if `config/verity-common.toml` doesn't exist.

- [ ] **Step 1: Write the failing test**

```powershell
Describe "Set-VerityLocalAI" {

    $root = Join-Path $env:TEMP ("verity-config-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[GeneralSettings.AISettings]
	apiKey = ""
	aiEndpoint = ""
	aiModel = ""
	aiProvider = "OPENAI"
	aiThink = true

[GeneralSettings.VoiceSettings]
	useTTS = true
	ttsProvider = "NATIVE"
	ttsEndpoint = ""
	voice = "Daniel"
	kokoroVoice = "am_fenrir"
	kokoroModel = ""

[GeneralSettings.SpeechSettings]
	sttProvider = "NATIVE"
	groqKey = ""
	sttEndpoint = ""
	sttModel = ""
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "points AISettings at the local Ollama sidecar" {
        $inst = Join-Path $root "server1"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OLLAMA"'
        $content | Should Match 'aiEndpoint = "http://127\.0\.0\.1:11434/v1"'
        $content | Should Match 'aiModel = "timheinrich2011/verity-3b"'
    }

    It "points VoiceSettings at the local Kokoro sidecar" {
        $inst = Join-Path $root "server2"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "KOKORO"'
        $content | Should Match 'ttsEndpoint = "http://127\.0\.0\.1:8880/v1"'
    }

    It "points SpeechSettings at the local Whisper sidecar" {
        $inst = Join-Path $root "server3"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "WHISPER"'
        $content | Should Match 'sttEndpoint = "http://127\.0\.0\.1:9000/v1"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityLocalAI -InstancePath $inst } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Set-VerityLocalAI` not recognized.

- [ ] **Step 3: Write minimal implementation**

```powershell
# Points a Verity-enabled server's config/verity-common.toml at the local
# AI sidecars (Ollama/Kokoro/Whisper) instead of a cloud provider. Run once
# when Local AI is enabled for that server from the GUI.
function Set-VerityLocalAI {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiEndpoint" -Value "http://127.0.0.1:11434/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiModel" -Value "timheinrich2011/verity-3b"

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsProvider" -Value "KOKORO"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsEndpoint" -Value "http://127.0.0.1:8880/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "kokoroModel" -Value "kokoro"

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttProvider" -Value "WHISPER"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttEndpoint" -Value "http://127.0.0.1:9000/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttModel" -Value "base.en"

    Set-Content -Path $tomlPath -Value $lines -Encoding utf8
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (10 tests total)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: write local AI sidecar config into verity-common.toml"
```

---

### Task 4: Sidecar health check

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1`
- Test: `tests/verity-helpers.tests.ps1`

**Interfaces:**
- Produces: `Test-SidecarHealthy(-Url <string> [-TimeoutMs <int>]) -> bool`

- [ ] **Step 1: Write the failing test**

```powershell
Describe "Test-SidecarHealthy" {

    It "returns false when nothing is listening" {
        Test-SidecarHealthy -Url "http://127.0.0.1:39281/health" -TimeoutMs 300 | Should Be $false
    }

    It "returns true when the endpoint responds with 2xx" {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:39282/")
        $listener.Start()
        try {
            $job = Start-Job -ScriptBlock {
                param($listener)
                $ctx = $listener.GetContext()
                $ctx.Response.StatusCode = 200
                $ctx.Response.Close()
            } -ArgumentList $listener

            Test-SidecarHealthy -Url "http://127.0.0.1:39282/health" -TimeoutMs 3000 | Should Be $true
            Wait-Job $job -Timeout 5 | Out-Null
            Remove-Job $job -Force
        } finally {
            $listener.Stop()
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Test-SidecarHealthy` not recognized.

- [ ] **Step 3: Write minimal implementation**

```powershell
# A quick, non-throwing health check for a sidecar's HTTP endpoint.
function Test-SidecarHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 1500
    )
    try {
        $resp = Invoke-WebRequest -Uri $Url -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($TimeoutMs / 1000))) -UseBasicParsing
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
    } catch {
        return $false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (12 tests total)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add sidecar HTTP health check"
```

---

### Task 5: Local AI panel labels (pure GUI logic)

**Files:**
- Modify: `_shared/scripts/gui-helpers.ps1`
- Test: `tests/gui-helpers.tests.ps1`

**Interfaces:**
- Produces:
  - `Get-VerityAiStatusText(-OllamaRunning <bool> -KokoroRunning <bool> -WhisperRunning <bool>) -> string`
  - `Get-VerityAiButtonLabel(-AllRunning <bool>) -> string`

- [ ] **Step 1: Write the failing test**

```powershell
Describe "Get-VerityAiStatusText" {
    It "shows LIT for a running sidecar and OUT for a stopped one" {
        $text = Get-VerityAiStatusText -OllamaRunning $true -KokoroRunning $false -WhisperRunning $true
        $text | Should Be "Ollama: LIT  |  Kokoro: OUT  |  Whisper: LIT"
    }
}

Describe "Get-VerityAiButtonLabel" {
    It "reads START LOCAL AI when not all sidecars are running" {
        Get-VerityAiButtonLabel -AllRunning $false | Should Be "START LOCAL AI"
    }
    It "reads STOP LOCAL AI when all sidecars are running" {
        Get-VerityAiButtonLabel -AllRunning $true | Should Be "STOP LOCAL AI"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\gui-helpers.tests.ps1`
Expected: FAIL — functions not recognized.

- [ ] **Step 3: Write minimal implementation**

Append to `_shared/scripts/gui-helpers.ps1`:

```powershell
# Compact status line for the Home screen's "Local AI" panel.
function Get-VerityAiStatusText {
    param(
        [Parameter(Mandatory = $true)][bool]$OllamaRunning,
        [Parameter(Mandatory = $true)][bool]$KokoroRunning,
        [Parameter(Mandatory = $true)][bool]$WhisperRunning
    )
    $label = { param($running) if ($running) { "LIT" } else { "OUT" } }
    return "Ollama: $(& $label $OllamaRunning)  |  Kokoro: $(& $label $KokoroRunning)  |  Whisper: $(& $label $WhisperRunning)"
}

# Label for the Local AI start/stop button. Simpler than
# Get-ActionButtonView's state machine - starting is a single bounded,
# synchronous-from-the-user's-view action (tracked via a background job,
# see Start-Gui.ps1), not an interruptible one like the server boot is.
function Get-VerityAiButtonLabel {
    param(
        [Parameter(Mandatory = $true)][bool]$AllRunning
    )
    if ($AllRunning) { return "STOP LOCAL AI" }
    return "START LOCAL AI"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\gui-helpers.tests.ps1`
Expected: PASS (all existing + 3 new tests)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/gui-helpers.ps1 tests/gui-helpers.tests.ps1
git commit -m "feat: add pure-logic labels for the Local AI GUI panel"
```

---

### Task 6: Portable Python runtime installer (shared by Kokoro + Whisper)

**Files:**
- Create: `Minecraft/scripts/install-ai-python.ps1`

**Interfaces:**
- Produces: after running, `Minecraft/tools/ai/python/python.exe` exists and can `pip install`.
- No test file (I/O-heavy installer script, same convention as `install-java.ps1` — verified manually in Task 14).

- [ ] **Step 1: Write the script**

```powershell
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
```

- [ ] **Step 2: Commit**

```bash
git add Minecraft/scripts/install-ai-python.ps1
git commit -m "feat: add portable Python runtime installer for local AI sidecars"
```

---

### Task 7: Kokoro TTS sidecar server + installer

**Files:**
- Create: `_shared/scripts/verity-ai-servers/kokoro_server.py`
- Create: `Minecraft/scripts/install-kokoro.ps1`

**Interfaces:**
- Produces: an HTTP server on `127.0.0.1:8880` exposing `GET /health` and `POST /v1/audio/speech` (matches the endpoint Task 3 wrote into `verity-common.toml`).
- No test file (needs a real Python process + audio model — manual verification in Task 14).

- [ ] **Step 1: Write the server script**

```python
# _shared/scripts/verity-ai-servers/kokoro_server.py
# Minimal OpenAI-style TTS server wrapping kokoro-onnx, for Verity's
# ttsProvider = "KOKORO" / ttsEndpoint = "http://127.0.0.1:8880/v1".
import io
import os
import wave

from fastapi import FastAPI, Response
from pydantic import BaseModel
from kokoro_onnx import Kokoro

MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
kokoro = Kokoro(
    os.path.join(MODEL_DIR, "kokoro-v1.0.onnx"),
    os.path.join(MODEL_DIR, "voices-v1.0.bin"),
)

app = FastAPI()


class SpeechRequest(BaseModel):
    input: str
    voice: str = "am_fenrir"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/audio/speech")
def speech(req: SpeechRequest):
    samples, sample_rate = kokoro.create(req.input, voice=req.voice)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        pcm16 = (samples * 32767).astype("int16")
        wf.writeframes(pcm16.tobytes())
    return Response(content=buf.getvalue(), media_type="audio/wav")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8880)
```

- [ ] **Step 2: Write the installer**

```powershell
# Minecraft/scripts/install-kokoro.ps1
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
    if (-not (Test-Path $modelPath)) { Invoke-WebRequest -Uri $modelAsset.browser_download_url -OutFile $modelPath -UseBasicParsing }
    if (-not (Test-Path $voicesPath)) { Invoke-WebRequest -Uri $voicesAsset.browser_download_url -OutFile $voicesPath -UseBasicParsing }
}

Copy-Item -Path (Join-Path $gsRoot "_shared\scripts\verity-ai-servers\kokoro_server.py") -Destination $kokoroDir -Force

Write-Host "Kokoro TTS installed at $kokoroDir"
```

- [ ] **Step 3: Commit**

```bash
git add _shared/scripts/verity-ai-servers/kokoro_server.py Minecraft/scripts/install-kokoro.ps1
git commit -m "feat: add Kokoro TTS sidecar server and installer"
```

---

### Task 8: Whisper STT sidecar server + installer

**Files:**
- Create: `_shared/scripts/verity-ai-servers/whisper_server.py`
- Create: `Minecraft/scripts/install-whisper.ps1`

**Interfaces:**
- Produces: an HTTP server on `127.0.0.1:9000` exposing `GET /health` and `POST /v1/audio/transcriptions` (matches the endpoint Task 3 wrote into `verity-common.toml`).
- No test file (needs a real Python process + audio model — manual verification in Task 14).

- [ ] **Step 1: Write the server script**

```python
# _shared/scripts/verity-ai-servers/whisper_server.py
# Minimal OpenAI-style STT server wrapping faster-whisper, for Verity's
# sttProvider = "WHISPER" / sttEndpoint = "http://127.0.0.1:9000/v1".
import tempfile

from fastapi import FastAPI, File, UploadFile
from faster_whisper import WhisperModel

# int8 quantization keeps this fast and light on CPU - plenty for short
# in-game voice clips; base.en downloads automatically on first use.
model = WhisperModel("base.en", device="cpu", compute_type="int8")

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    segments, _ = model.transcribe(tmp_path)
    text = "".join(segment.text for segment in segments)
    return {"text": text.strip()}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=9000)
```

- [ ] **Step 2: Write the installer**

```powershell
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
```

- [ ] **Step 3: Commit**

```bash
git add _shared/scripts/verity-ai-servers/whisper_server.py Minecraft/scripts/install-whisper.ps1
git commit -m "feat: add Whisper STT sidecar server and installer"
```

---

### Task 9: Ollama installer + model pull

**Files:**
- Create: `Minecraft/scripts/install-ollama.ps1`

**Interfaces:**
- Produces: `Minecraft/tools/ai/ollama/ollama.exe`, with `timheinrich2011/verity-3b` already pulled into `Minecraft/tools/ai/ollama/models`.
- No test file (real download + multi-GB model pull — manual verification in Task 14).

- [ ] **Step 1: Write the script**

```powershell
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
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "Ollama installed and verity-3b model pulled."
```

- [ ] **Step 2: Commit**

```bash
git add Minecraft/scripts/install-ollama.ps1
git commit -m "feat: add Ollama installer with verity-3b model pull"
```

---

### Task 10: Sidecar stack start/stop

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1`

**Interfaces:**
- Consumes: `Test-SidecarHealthy` (Task 4)
- Produces:
  - `Start-VerityLocalAiStack(-McRoot <string>) -> void`. Installs anything missing, starts anything not running, throws if a sidecar doesn't become healthy within its timeout.
  - `Stop-VerityLocalAiStack() -> void`
- No test file (spawns real processes — this is the same I/O-boundary convention `Stop-ProcessTree` in `gui-helpers.ps1` already follows, with no test of its own).

- [ ] **Step 1: Write the implementation**

Append to `_shared/scripts/verity-helpers.ps1` (needs `Test-PortOpen`/`Get-ListenerPid` from `rcon.ps1` and `Stop-ProcessTree` from `gui-helpers.ps1`, so dot-source both at the top of the file):

```powershell
. (Join-Path $PSScriptRoot "rcon.ps1")
. (Join-Path $PSScriptRoot "gui-helpers.ps1")

# Installs (if needed) and starts the 3 local-AI sidecars, waiting for each
# to answer a health check before returning. Shared host-wide - one set of
# sidecars serves every Verity-enabled server on this machine.
function Start-VerityLocalAiStack {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )

    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "ollama\ollama.exe"))) {
        & (Join-Path $scriptsDir "install-ollama.ps1")
    }
    if (-not (Test-Path (Join-Path $aiDir "kokoro\kokoro_server.py"))) {
        & (Join-Path $scriptsDir "install-kokoro.ps1")
    }
    if (-not (Test-Path (Join-Path $aiDir "whisper\whisper_server.py"))) {
        & (Join-Path $scriptsDir "install-whisper.ps1")
    }

    if (-not (Test-PortOpen -Port 11434)) {
        Start-Process -FilePath (Join-Path $aiDir "ollama\ollama.exe") -ArgumentList "serve" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "ollama.log") -RedirectStandardError (Join-Path $logDir "ollama.err.log")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 8880)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'kokoro\kokoro_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "kokoro.log") -RedirectStandardError (Join-Path $logDir "kokoro.err.log")
    }
    if (-not (Test-PortOpen -Port 9000)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'whisper\whisper_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "whisper.log") -RedirectStandardError (Join-Path $logDir "whisper.err.log")
    }

    $checks = @(
        @{ Url = "http://127.0.0.1:11434/v1/models"; Name = "Ollama"; LogFile = "ollama.err.log" },
        @{ Url = "http://127.0.0.1:8880/health"; Name = "Kokoro"; LogFile = "kokoro.err.log" },
        @{ Url = "http://127.0.0.1:9000/health"; Name = "Whisper"; LogFile = "whisper.err.log" }
    )
    foreach ($check in $checks) {
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            if (Test-SidecarHealthy -Url $check.Url) { $ready = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw "$($check.Name) didn't become ready within 30s - check $(Join-Path $logDir $check.LogFile)"
        }
    }
}

# Stops all 3 sidecars by whatever's listening on their ports.
function Stop-VerityLocalAiStack {
    foreach ($port in @(11434, 8880, 9000)) {
        $ownerPid = Get-ListenerPid -Port $port
        if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1
git commit -m "feat: add Verity local AI sidecar stack start/stop"
```

---

### Task 11: HomeScreen "Local AI" panel (XAML)

**Files:**
- Modify: `_shared/gui/HomeScreen.xaml`

**Interfaces:**
- Produces new named elements: `VerityAiPanel` (Border, starts `Visibility="Collapsed"`), `VerityAiStatusText` (TextBlock), `VerityAiButton` (Button).

- [ ] **Step 1: Add a 7th row and the panel**

In `_shared/gui/HomeScreen.xaml`, change the `Grid.RowDefinitions` (currently 6 rows, indices 0-5) to add a 7th:

```xml
    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
```

Then, right after the closing `</WrapPanel>` (the current last element, secondary actions row, `Grid.Row="5"`), add:

```xml
    <!-- Local AI panel: only shown when the selected server has Verity
         installed (see Sync-StatusDisplay in Start-Gui.ps1). -->
    <Border Grid.Row="6" x:Name="VerityAiPanel" Background="{StaticResource PanelBrush}" CornerRadius="10"
            BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="12" Margin="0,12,0,0"
            Visibility="Collapsed">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="LOCAL AI (VERITY)" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI Semibold" FontSize="11" Margin="0,0,0,8"/>
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" x:Name="VerityAiStatusText" Text="Ollama: OUT  |  Kokoro: OUT  |  Whisper: OUT"
                           Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityAiButton" Content="START LOCAL AI" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}"/>
            </Grid>
        </Grid>
    </Border>
```

- [ ] **Step 2: Commit**

```bash
git add _shared/gui/HomeScreen.xaml
git commit -m "feat: add Local AI panel to the Home screen"
```

---

### Task 12: Wire the Local AI panel into Start-Gui.ps1

**Files:**
- Modify: `Start-Gui.ps1`

**Interfaces:**
- Consumes: `Test-VerityModPresent`, `Set-VerityLocalAI`, `Start-VerityLocalAiStack`, `Stop-VerityLocalAiStack` (verity-helpers.ps1); `Get-VerityAiStatusText`, `Get-VerityAiButtonLabel` (gui-helpers.ps1); `Test-PortOpen` (rcon.ps1, already dot-sourced elsewhere in this file).

- [ ] **Step 1: Dot-source verity-helpers.ps1 and find the new elements**

Near the top of `Start-Gui.ps1`, alongside the other dot-sourced helpers, add:

```powershell
. (Join-Path $root "_shared\scripts\verity-helpers.ps1")
```

In the Home screen element block (around line 71-81), add:

```powershell
$verityAiPanel      = $homeRoot.FindName("VerityAiPanel")
$verityAiStatusText = $homeRoot.FindName("VerityAiStatusText")
$verityAiButton     = $homeRoot.FindName("VerityAiButton")
$script:aiJob       = $null
```

- [ ] **Step 2: Show/hide and refresh the panel from `Sync-StatusDisplay`**

Inside `Sync-StatusDisplay` (around line 169-192), right before its `return $state` line, add:

```powershell
    if ($script:selected -and $script:selected.Game -eq "Minecraft" -and (Test-VerityModPresent -InstancePath $script:selected.Path)) {
        $verityAiPanel.Visibility = "Visible"
        if (-not $script:aiJob) {
            $ollamaUp = Test-PortOpen -Port 11434
            $kokoroUp = Test-PortOpen -Port 8880
            $whisperUp = Test-PortOpen -Port 9000
            $verityAiStatusText.Text = Get-VerityAiStatusText -OllamaRunning $ollamaUp -KokoroRunning $kokoroUp -WhisperRunning $whisperUp
            $verityAiButton.Content = Get-VerityAiButtonLabel -AllRunning ($ollamaUp -and $kokoroUp -and $whisperUp)
            $verityAiButton.IsEnabled = $true
        }
    } else {
        $verityAiPanel.Visibility = "Collapsed"
    }
```

- [ ] **Step 3: Wire the button click, following the existing Start-Job + DispatcherTimer pattern used for server creation**

Add this near the other Home-screen click handlers (after `$actionButton.Add_Click` around line 242):

```powershell
$verityAiButton.Add_Click({
    if (-not $script:selected -or $script:aiJob) { return }

    $allRunning = (Test-PortOpen -Port 11434) -and (Test-PortOpen -Port 8880) -and (Test-PortOpen -Port 9000)
    $verityAiButton.IsEnabled = $false

    if ($allRunning) {
        $verityAiStatusText.Text = "Stopping..."
        $script:aiJob = Start-Job -ScriptBlock {
            param($GsRoot)
            . (Join-Path $GsRoot "_shared\scripts\verity-helpers.ps1")
            Stop-VerityLocalAiStack
        } -ArgumentList $root
    } else {
        $verityAiStatusText.Text = "Starting local AI (first run can take a few minutes to install)..."
        $script:aiJob = Start-Job -ScriptBlock {
            param($GsRoot, $InstancePath, $McRoot)
            . (Join-Path $GsRoot "_shared\scripts\verity-helpers.ps1")
            Set-VerityLocalAI -InstancePath $InstancePath
            Start-VerityLocalAiStack -McRoot $McRoot
        } -ArgumentList $root, $script:selected.Path, (Join-Path $root "Minecraft")
    }
})
```

- [ ] **Step 4: Poll the job to completion, mirroring `$addJobTimer`**

Add near `$addJobTimer` (around line 633-657):

```powershell
$aiJobTimer = New-Object System.Windows.Threading.DispatcherTimer
$aiJobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$aiJobTimer.Add_Tick({
    if (-not $script:aiJob -or $script:aiJob.State -eq "Running" -or $script:aiJob.State -eq "NotStarted") { return }

    if ($script:aiJob.State -eq "Failed") {
        $reason = $script:aiJob.ChildJobs[0].JobStateInfo.Reason.Message
        $verityAiStatusText.Text = "Error: $reason"
    }
    Remove-Job $script:aiJob -Force
    $script:aiJob = $null
    Sync-StatusDisplay | Out-Null
})
$aiJobTimer.Start()
```

- [ ] **Step 5: Commit**

```bash
git add Start-Gui.ps1
git commit -m "feat: wire the Local AI panel into the Home screen"
```

---

### Task 13: Auto-start sidecars before a Verity server boots

**Files:**
- Modify: `Minecraft/servers/_template/start-with-tunnel.ps1`

Note: this goes in `start-with-tunnel.ps1`, not `start.ps1` — `Install-CurseForgeServerZip` overwrites a server's own `start.ps1` with ServerPackCreator's generated one (this is exactly what `Set-PortableJavaForVariablesFile` already works around for Java), but `start-with-tunnel.ps1` isn't a file ServerPackCreator generates, so it always survives and is what the GUI (and `stop-server.ps1`) actually invoke. This makes it the one integration point that reliably fires regardless of how the pack was installed.

**Interfaces:**
- Consumes: `Test-VerityModPresent`, `Start-VerityLocalAiStack` (verity-helpers.ps1).

- [ ] **Step 1: Add the sidecar check before launching the server**

In `Minecraft/servers/_template/start-with-tunnel.ps1`, right after the existing header block that computes `$gsRoot` (around line 6) and before the "Brings up the playit.gg tunnel" logic starts, add:

```powershell
. (Join-Path $gsRoot "_shared\scripts\verity-helpers.ps1")
if (Test-VerityModPresent -InstancePath $PSScriptRoot) {
    Write-Host "Verity mod detected - making sure the local AI stack (Ollama/Kokoro/Whisper) is up..."
    Start-VerityLocalAiStack -McRoot $mcRoot
}
```

- [ ] **Step 2: Commit**

```bash
git add Minecraft/servers/_template/start-with-tunnel.ps1
git commit -m "feat: auto-start Verity local AI sidecars before server boot"
```

---

### Task 14: Full manual verification

Not a code task — this is the end-to-end check, mirroring how the rest of this session's server-boot testing was done (real GPU/network I/O that Pester can't cover).

- [ ] **Step 1: Run the full automated test suite**

Run: `Invoke-Pester -Path tests\ -CI` (or however this repo's test runner is normally invoked — check `README.md`/CI config if one exists)
Expected: All tests pass, including every `verity-helpers.tests.ps1` and `gui-helpers.tests.ps1` test from Tasks 1-5.

- [ ] **Step 2: Launch the GUI and confirm detection**

Run `Start-Gui.ps1`, select the VerityWorld server. Confirm the "Local AI" panel appears (VerityWorld has `verity-6.1.jar`) and reads `Ollama: OUT | Kokoro: OUT | Whisper: OUT`.

- [ ] **Step 3: Start the local AI stack from the GUI**

Click "START LOCAL AI". First run installs Ollama, the shared Python runtime, Kokoro, and Whisper (several GB downloaded — expect this to take minutes). Confirm the panel eventually reads `Ollama: LIT | Kokoro: LIT | Whisper: LIT` and the button flips to "STOP LOCAL AI".

- [ ] **Step 4: Confirm verity-common.toml was rewritten correctly**

Check `Minecraft/servers/VerityWorld/config/verity-common.toml` — `aiProvider = "OLLAMA"`, `ttsProvider = "KOKORO"`, `sttProvider = "WHISPER"`, and all three endpoints pointing at `127.0.0.1`.

- [ ] **Step 5: Boot the server and talk to Verity**

Start VerityWorld from the GUI. Confirm in the server log it doesn't crash on Verity's AI-backend connectivity check. Join in-game, get near Verity, and confirm it responds via the local model (check `Minecraft/tools/ai/logs/ollama.log` for inbound requests if there's no visible in-game response).

- [ ] **Step 6: Confirm sidecars survive a server stop**

Stop the VerityWorld server from the GUI (or `stop-server.ps1`). Confirm the Local AI panel still reads all `LIT` afterward (per the design, sidecars are only stopped by the explicit "STOP LOCAL AI" button, not by the server stopping).

- [ ] **Step 7: Stop the local AI stack**

Click "STOP LOCAL AI". Confirm the panel returns to all `OUT` and the 3 processes (`ollama.exe`, and the two `python.exe` sidecars) are actually gone from Task Manager.
