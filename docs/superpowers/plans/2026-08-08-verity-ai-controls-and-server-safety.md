# Verity AI Per-Process Controls & Server-Creation Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the stuck "Horror Ultimate Selection" server, block spaces in new server names at creation time, split the Local AI sidecar stack (Ollama/Kokoro/Whisper) into three independently start/stoppable services instead of one all-or-nothing toggle, and auto-stop those sidecars when the last Verity server using them closes.

**Architecture:** `config/verity-common.toml`'s existing per-subsystem provider fields (`aiProvider`/`ttsProvider`/`sttProvider`) become the single source of truth for which sidecars a server wants running — no new config file. `_shared/scripts/verity-helpers.ps1`'s combined `Set-VerityLocalAI`/`Start-VerityLocalAiStack`/`Stop-VerityLocalAiStack` are split into per-service functions (`Set-VerityAiProvider`, `Start-<X>Sidecar`, `Stop-<X>Sidecar`) plus a `Get-VerityRequiredSidecars` reader. The GUI's single "Local AI" button becomes 3 status rows. `start-with-tunnel.ps1` reads the toml to decide what to boot, and stops sidecars in its existing shutdown `finally` block when no other running Verity server needs them (checked via a new `Test-OtherVerityServerRunning`).

**Tech Stack:** PowerShell 5.1, WPF/XAML, Pester (v4-style `Should Be`).

## Global Constraints

- Pester tests (v4 style: `Describe`/`It`/`Should Be`/`Should Throw`) only for pure logic (TOML editing, config reads, path enumeration) — matches every existing `tests/*.tests.ps1` file. Sidecar process start/stop (real `Start-Process`/network I/O) is verified manually, same convention as the existing `Start-VerityLocalAiStack`/`Stop-VerityLocalAiStack`.
- Default sidecar ports (unchanged, already the mod's convention): Ollama `127.0.0.1:11434`, Kokoro `127.0.0.1:8880`, Whisper `127.0.0.1:9000`.
- Default model/values (unchanged): `aiModel = "timheinrich2011/verity-3b"`, `kokoroModel = "kokoro"`, `sttModel = "base.en"`.
- Non-local revert values (Verity's own vanilla defaults, confirmed in `Minecraft/servers/VerityCraft/config/verity-common.toml`): `aiProvider = "OPENAI"`, `ttsProvider = "NATIVE"`, `sttProvider = "NATIVE"`.
- Server instance folders are gitignored (`Minecraft/servers/*/` except `_template`) — renaming/copying files inside one is not a git operation.
- Windows PowerShell 5.1's `-Encoding utf8` prepends a BOM that Forge's TOML parser rejects — TOML writes must use `[System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding($false)))`, matching the existing `Set-VerityLocalAI`.

---

### Task 1: Rename the stuck Horror Ultimate Selection server

**Files:**
- Rename (filesystem only, not git-tracked): `Minecraft/servers/Horror Ultimate Selection/` -> `Minecraft/servers/HorrorUltimateSelection/`

**Interfaces:** None (operational step, no code).

- [ ] **Step 1: Confirm no Java process is using the server before renaming**

Run: `tasklist //FI "IMAGENAME eq java.exe"`
Expected: `INFO: No tasks are running which match the specified criteria.` (already confirmed stuck at the spaces prompt with nothing running — re-check in case the user answered the prompt since).

- [ ] **Step 2: Rename the folder**

Run:
```
Rename-Item -Path "D:\3_Hobbies\GameServers\Minecraft\servers\Horror Ultimate Selection" -NewName "HorrorUltimateSelection"
```

- [ ] **Step 3: Verify the rename and that nothing else references the old name**

Run:
```
Test-Path "D:\3_Hobbies\GameServers\Minecraft\servers\HorrorUltimateSelection\start-with-tunnel.ps1"
Select-String -Path "D:\3_Hobbies\GameServers\*.ps1","D:\3_Hobbies\GameServers\_shared\**\*.ps1" -Pattern "Horror Ultimate Selection" -ErrorAction SilentlyContinue
```
Expected: first command `True`; second command returns no matches (the GUI discovers server folders at runtime via `Get-ServerInstances`, so no stored path needs updating).

No commit — this folder is gitignored, nothing for git to track.

---

### Task 2: Block spaces in new server names

**Files:**
- Modify: `_shared/scripts/new-server-helpers.ps1`
- Modify: `Start-Gui.ps1:12-18` (add a dot-source), `Start-Gui.ps1:614-617` (validate before creating)
- Test: `tests/new-server-helpers.tests.ps1`

**Interfaces:**
- Produces: `Test-ServerNameValid(-Name <string>) -> bool`

- [ ] **Step 1: Write the failing test**

Add to `tests/new-server-helpers.tests.ps1` (new `Describe` block, after the existing `New-ServerFromTemplate` one):

```powershell
Describe "Test-ServerNameValid" {
    It "rejects a name with a space" {
        Test-ServerNameValid -Name "Horror Ultimate" | Should Be $false
    }

    It "rejects a name with path-unsafe characters" {
        Test-ServerNameValid -Name "My:Server" | Should Be $false
    }

    It "accepts a name with only letters, numbers, dashes and underscores" {
        Test-ServerNameValid -Name "Horror-Ultimate_2" | Should Be $true
    }

    It "rejects an empty name" {
        Test-ServerNameValid -Name "" | Should Be $false
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\new-server-helpers.tests.ps1`
Expected: FAIL — `Test-ServerNameValid` not recognized.

- [ ] **Step 3: Write minimal implementation**

Add to `_shared/scripts/new-server-helpers.ps1` (after the file's header comment, before `New-ServerFromTemplate`):

```powershell
# Server names become a Windows folder name directly (servers\<Name>\), so
# spaces and path-unsafe characters are rejected here rather than letting a
# broken server get created - ServerPackCreator's vendored start.ps1 blocks
# on a "path contains spaces" prompt that silently strands the server if
# nobody's watching the console when it boots.
function Test-ServerNameValid {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -match '[\\/:*?"<>|\s]') { return $false }
    return $true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\new-server-helpers.tests.ps1`
Expected: PASS (8 tests: 4 existing + 4 new).

- [ ] **Step 5: Wire the validation into the Add Server screen**

In `Start-Gui.ps1`, add the dot-source alongside the others (after line 16, `worlds-helpers.ps1`):

```powershell
. (Join-Path $root "_shared\scripts\new-server-helpers.ps1")
```

Then in the `$createButton.Add_Click` handler, insert a check right after the existing empty-name check (currently `Start-Gui.ps1:616`):

```powershell
$createButton.Add_Click({
    $name = $nameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $addHintText.Text = "Enter a server name."; return }
    if (-not (Test-ServerNameValid -Name $name)) {
        $suggestion = $name -replace '[\\/:*?"<>|\s]', ''
        $addHintText.Text = "Server names can't contain spaces or path characters - some modpacks' launch scripts break on spaced paths. Try '$suggestion' instead."
        return
    }
    if (-not $eulaCheck.IsChecked) { $addHintText.Text = "You need to accept the Minecraft EULA to continue."; return }
    ...
```

(Leave everything else in the handler, from the `$mrpack = ...` line onward, unchanged.)

- [ ] **Step 6: Verify Start-Gui.ps1 still parses**

Run:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("D:\3_Hobbies\GameServers\Start-Gui.ps1", [ref]$null, [ref]$null) | Out-Null
```
Expected: no exception thrown.

- [ ] **Step 7: Commit**

```bash
git add _shared/scripts/new-server-helpers.ps1 tests/new-server-helpers.tests.ps1 Start-Gui.ps1
git commit -m "feat: block spaces and path-unsafe characters in new server names"
```

---

### Task 3: Per-service AI provider config (`Set-VerityAiProvider`)

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (replace `Set-VerityLocalAI` with `Set-VerityAiProvider`)
- Test: `tests/verity-helpers.tests.ps1` (replace the `Set-VerityLocalAI` `Describe` block)

**Interfaces:**
- Consumes: `Set-TomlSectionValue(-Lines, -Section, -Key, -Value)` (existing, unchanged)
- Produces: `Set-VerityAiProvider(-InstancePath <string>, -Service <"Ollama"|"Kokoro"|"Whisper">, -UseLocal <bool>)` — edits `config/verity-common.toml`, throws if the file doesn't exist.

- [ ] **Step 1: Write the failing test**

In `tests/verity-helpers.tests.ps1`, replace the entire `Describe "Set-VerityLocalAI" { ... }` block (current lines 64-129) with:

```powershell
Describe "Set-VerityAiProvider" {

    $root = Join-Path $env:TEMP ("verity-provider-" + [Guid]::NewGuid().ToString("N"))

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

    It "points AISettings at the local Ollama sidecar when UseLocal is true" {
        $inst = Join-Path $root "ollama-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OLLAMA"'
        $content | Should Match 'aiEndpoint = "http://127\.0\.0\.1:11434/v1"'
        $content | Should Match 'aiModel = "timheinrich2011/verity-3b"'
    }

    It "reverts aiProvider to OPENAI when UseLocal is false" {
        $inst = Join-Path $root "ollama-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OPENAI"'
    }

    It "points VoiceSettings at the local Kokoro sidecar when UseLocal is true" {
        $inst = Join-Path $root "kokoro-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "KOKORO"'
        $content | Should Match 'ttsEndpoint = "http://127\.0\.0\.1:8880/v1"'
    }

    It "reverts ttsProvider to NATIVE when UseLocal is false" {
        $inst = Join-Path $root "kokoro-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "NATIVE"'
    }

    It "points SpeechSettings at the local Whisper sidecar when UseLocal is true" {
        $inst = Join-Path $root "whisper-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "WHISPER"'
        $content | Should Match 'sttEndpoint = "http://127\.0\.0\.1:9000/v1"'
    }

    It "reverts sttProvider to NATIVE when UseLocal is false" {
        $inst = Join-Path $root "whisper-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "NATIVE"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Set-VerityAiProvider` not recognized (the old `Set-VerityLocalAI` tests are gone, replaced by these).

- [ ] **Step 3: Write minimal implementation**

In `_shared/scripts/verity-helpers.ps1`, replace the entire `Set-VerityLocalAI` function (current lines 61-94) with:

```powershell
# Points one Verity subsystem (LLM/TTS/STT) at its local sidecar, or reverts
# it to Verity's vanilla non-local default. config/verity-common.toml is the
# single source of truth for which sidecars a server wants running - there's
# no separate on/off state to keep in sync.
function Set-VerityAiProvider {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][ValidateSet("Ollama", "Kokoro", "Whisper")][string]$Service,
        [Parameter(Mandatory = $true)][bool]$UseLocal
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8

    switch ($Service) {
        "Ollama" {
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiEndpoint" -Value "http://127.0.0.1:11434/v1"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiModel" -Value "timheinrich2011/verity-3b"
            } else {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OPENAI"
            }
        }
        "Kokoro" {
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsProvider" -Value "KOKORO"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsEndpoint" -Value "http://127.0.0.1:8880/v1"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "kokoroModel" -Value "kokoro"
            } else {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsProvider" -Value "NATIVE"
            }
        }
        "Whisper" {
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttProvider" -Value "WHISPER"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttEndpoint" -Value "http://127.0.0.1:9000/v1"
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttModel" -Value "base.en"
            } else {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttProvider" -Value "NATIVE"
            }
        }
    }

    # Windows PowerShell 5.1's -Encoding utf8 always prepends a BOM, which
    # Forge's TOML parser (NightConfig) doesn't strip - it reads the BOM
    # bytes as the start of a bare key and refuses to load the file at all,
    # crashing every server boot. Write UTF-8 without a BOM instead.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (all tests, including the untouched `Test-VerityModPresent`/`Set-TomlSectionValue`/`Test-SidecarHealthy` blocks).

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "refactor: split Set-VerityLocalAI into per-service Set-VerityAiProvider"
```

---

### Task 4: Read which sidecars a server currently wants (`Get-VerityRequiredSidecars`)

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (add function)
- Test: `tests/verity-helpers.tests.ps1` (add `Describe` block)

**Interfaces:**
- Produces: `Get-VerityRequiredSidecars(-InstancePath <string>) -> string[]` — subset of `@("Ollama","Kokoro","Whisper")`, order-stable, empty array if the config is missing or nothing is set local.

- [ ] **Step 1: Write the failing test**

Add to `tests/verity-helpers.tests.ps1` (after the `Set-VerityAiProvider` block from Task 3):

```powershell
Describe "Get-VerityRequiredSidecars" {

    $root = Join-Path $env:TEMP ("verity-required-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityToml([string]$Path, [string]$AiProvider, [string]$TtsProvider, [string]$SttProvider) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @"
[GeneralSettings.AISettings]
	aiProvider = "$AiProvider"

[GeneralSettings.VoiceSettings]
	ttsProvider = "$TtsProvider"

[GeneralSettings.SpeechSettings]
	sttProvider = "$SttProvider"
"@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "returns all three when all providers are local" {
        $inst = Join-Path $root "all-local"
        New-FakeVerityToml -Path $inst -AiProvider "OLLAMA" -TtsProvider "KOKORO" -SttProvider "WHISPER"
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama", "Kokoro", "Whisper")
    }

    It "returns only the ones set local, e.g. just the core LLM" {
        $inst = Join-Path $root "llm-only"
        New-FakeVerityToml -Path $inst -AiProvider "OLLAMA" -TtsProvider "NATIVE" -SttProvider "NATIVE"
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama")
    }

    It "returns an empty array when nothing is local" {
        $inst = Join-Path $root "cloud-only"
        New-FakeVerityToml -Path $inst -AiProvider "OPENAI" -TtsProvider "NATIVE" -SttProvider "NATIVE"
        (Get-VerityRequiredSidecars -InstancePath $inst).Count | Should Be 0
    }

    It "returns an empty array when the config file doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        (Get-VerityRequiredSidecars -InstancePath $inst).Count | Should Be 0
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Get-VerityRequiredSidecars` not recognized.

- [ ] **Step 3: Write minimal implementation**

Add to `_shared/scripts/verity-helpers.ps1`, right after `Set-VerityAiProvider`:

```powershell
# Reads which of the 3 sidecars this server's config currently points at
# locally - the toml IS the persisted on/off state, so this is the only
# place that needs to know how to read it back out.
function Get-VerityRequiredSidecars {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) { return @() }

    $content = Get-Content -Path $tomlPath -Raw
    $required = @()
    if ($content -match '(?m)^\s*aiProvider\s*=\s*"OLLAMA"') { $required += "Ollama" }
    if ($content -match '(?m)^\s*ttsProvider\s*=\s*"KOKORO"') { $required += "Kokoro" }
    if ($content -match '(?m)^\s*sttProvider\s*=\s*"WHISPER"') { $required += "Whisper" }
    return $required
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add Get-VerityRequiredSidecars to read sidecar state from the toml"
```

---

### Task 5: Split sidecar start into per-service functions

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (replace `Start-VerityLocalAiStack` with 3 functions)

**Interfaces:**
- Consumes: `Test-Path`, `Test-PortOpen` (rcon.ps1, already dot-sourced), `Test-OllamaModelPresent`, `Test-SidecarHealthy` (both already in this file, unchanged).
- Produces: `Start-OllamaSidecar(-McRoot <string>)`, `Start-KokoroSidecar(-McRoot <string>)`, `Start-WhisperSidecar(-McRoot <string>)` — each installs if needed, starts if not already listening, waits up to 30s for health, throws with the same wording as today's combined function if it never comes up.

No new Pester coverage here (matches this file's existing convention: `Start-VerityLocalAiStack` itself has no test today — installing real binaries and spawning real processes needs manual/GPU verification, tracked in Task 11).

- [ ] **Step 1: Replace `Start-VerityLocalAiStack`**

In `_shared/scripts/verity-helpers.ps1`, delete the entire `Start-VerityLocalAiStack` function (current lines 130-199) and replace it with:

```powershell
# Installed once, shared host-wide under Minecraft/tools/ai/ - one Ollama/
# Kokoro/Whisper instance serves every Verity-enabled server on this
# machine. Each Start-<X>Sidecar is independent: a caller starts only the
# ones a given server's config actually needs (see Get-VerityRequiredSidecars).
function Start-OllamaSidecar {
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
    if (-not (Test-PortOpen -Port 11434)) {
        # Must match the OLLAMA_MODELS install-ollama.ps1 set in its own
        # process when it pulled verity-3b - otherwise this server (which
        # doesn't inherit that env var from the installer's process) reads
        # the default %USERPROFILE%\.ollama\models instead, finds nothing,
        # and serves an empty model list while still reporting healthy.
        $env:OLLAMA_MODELS = Join-Path $aiDir "ollama\models"
        Start-Process -FilePath (Join-Path $aiDir "ollama\ollama.exe") -ArgumentList "serve" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "ollama.log") -RedirectStandardError (Join-Path $logDir "ollama.err.log")
    }

    # A 200 from /v1/models isn't enough to know it's OUR Ollama - a
    # pre-existing system-wide install (or any other Ollama already holding
    # port 11434) answers the same way but won't have verity-3b loaded.
    $ollamaReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-OllamaModelPresent) { $ollamaReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ollamaReady) {
        throw "Ollama is listening on port 11434 but the timheinrich2011/verity-3b model isn't loaded - looks like a different Ollama instance is already running on that port. Check $(Join-Path $logDir 'ollama.err.log'), or free port 11434 and try again."
    }
}

function Start-KokoroSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )
    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "kokoro\kokoro_server.py"))) {
        & (Join-Path $scriptsDir "install-kokoro.ps1")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 8880)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'kokoro\kokoro_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "kokoro.log") -RedirectStandardError (Join-Path $logDir "kokoro.err.log")
    }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SidecarHealthy -Url "http://127.0.0.1:8880/health") { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "Kokoro didn't become ready within 30s - check $(Join-Path $logDir 'kokoro.err.log')"
    }
}

function Start-WhisperSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )
    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "whisper\whisper_server.py"))) {
        & (Join-Path $scriptsDir "install-whisper.ps1")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 9000)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'whisper\whisper_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "whisper.log") -RedirectStandardError (Join-Path $logDir "whisper.err.log")
    }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SidecarHealthy -Url "http://127.0.0.1:9000/health") { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "Whisper didn't become ready within 30s - check $(Join-Path $logDir 'whisper.err.log')"
    }
}
```

- [ ] **Step 2: Confirm the file still parses and existing tests still pass**

Run:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("D:\3_Hobbies\GameServers\_shared\scripts\verity-helpers.ps1", [ref]$null, [ref]$null) | Out-Null
```
```
Invoke-Pester -Path tests\verity-helpers.tests.ps1
```
Expected: no parse exception; all existing Pester tests still PASS (this task adds no new tests since the removed function had none either).

- [ ] **Step 3: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1
git commit -m "refactor: split Start-VerityLocalAiStack into per-service Start-<X>Sidecar functions"
```

---

### Task 6: Split sidecar stop into per-service functions

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (replace `Stop-VerityLocalAiStack` with 3 functions + a thin aggregate wrapper)

**Interfaces:**
- Consumes: `Test-OllamaModelPresent`, `Get-ListenerPid` (rcon.ps1), `Stop-ProcessTree` (gui-helpers.ps1, already dot-sourced by this file).
- Produces: `Stop-OllamaSidecar()`, `Stop-KokoroSidecar()`, `Stop-WhisperSidecar()`, and `Stop-VerityLocalAiStack()` (calls all three - kept as the "stop whatever's running" convenience used by the boot-safety net and the GUI's "Stop All").

- [ ] **Step 1: Replace `Stop-VerityLocalAiStack`**

In `_shared/scripts/verity-helpers.ps1`, replace the current `Stop-VerityLocalAiStack` function (the tail of the file) with:

```powershell
# Ollama is only killed if verity-3b is confirmed loaded on port 11434 -
# this doesn't share in-memory state with whatever Start-Process call may
# have launched it, so a plain "whatever owns the port" kill would just as
# happily kill a pre-existing user-installed Ollama that happened to
# already be running when the stack started.
function Stop-OllamaSidecar {
    if (Test-OllamaModelPresent) {
        $ownerPid = Get-ListenerPid -Port 11434
        if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
    }
}

# Kokoro/Whisper have no such collision risk (nothing else on the system
# would be using those ports), so they use a simple by-port kill.
function Stop-KokoroSidecar {
    $ownerPid = Get-ListenerPid -Port 8880
    if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
}

function Stop-WhisperSidecar {
    $ownerPid = Get-ListenerPid -Port 9000
    if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
}

# Stops whichever of the 3 sidecars happen to be running - used by the
# GUI's "Stop All" and by the boot-safety stop-on-close check, neither of
# which needs to track which ones were actually started.
function Stop-VerityLocalAiStack {
    Stop-OllamaSidecar
    Stop-KokoroSidecar
    Stop-WhisperSidecar
}
```

- [ ] **Step 2: Confirm the file still parses and existing tests still pass**

Run:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("D:\3_Hobbies\GameServers\_shared\scripts\verity-helpers.ps1", [ref]$null, [ref]$null) | Out-Null
```
```
Invoke-Pester -Path tests\verity-helpers.tests.ps1
```
Expected: no parse exception; all existing tests PASS.

- [ ] **Step 3: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1
git commit -m "refactor: split Stop-VerityLocalAiStack into per-service Stop-<X>Sidecar functions"
```

---

### Task 7: Detect other running Verity servers (`Test-OtherVerityServerRunning`)

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (add 2 functions)
- Test: `tests/verity-helpers.tests.ps1` (add 2 `Describe` blocks)

**Interfaces:**
- Consumes: `Test-VerityModPresent`, `Read-ServerProperties` and `Test-PortOpen` (rcon.ps1, already dot-sourced by this file).
- Produces: `Get-AllServerInstancePaths(-GsRoot <string>) -> string[]` (every `<Game>\servers\<Instance>` folder, skipping `_shared` and `_template`); `Test-OtherVerityServerRunning(-GsRoot <string>, -ExcludePath <string>) -> bool`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/verity-helpers.tests.ps1` (after the `Get-VerityRequiredSidecars` block from Task 4):

```powershell
Describe "Get-AllServerInstancePaths" {

    $root = Join-Path $env:TEMP ("verity-instances-" + [Guid]::NewGuid().ToString("N"))

    It "finds instance folders under each game, skipping _shared and _template" {
        New-Item -ItemType Directory -Force -Path (Join-Path $root "Minecraft\servers\ServerA") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "Minecraft\servers\_template") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "_shared\servers\NotAGame") | Out-Null

        $paths = Get-AllServerInstancePaths -GsRoot $root
        $paths | Should Contain (Join-Path $root "Minecraft\servers\ServerA")
        ($paths | Where-Object { $_ -like "*_template*" }) | Should Be $null
        ($paths | Where-Object { $_ -like "*_shared*" }) | Should Be $null
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Test-OtherVerityServerRunning" {

    $root = Join-Path $env:TEMP ("verity-other-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeInstance([string]$Path, [bool]$HasVerity, [int]$Port) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "mods") | Out-Null
        if ($HasVerity) {
            Set-Content -Path (Join-Path $Path "mods\verity-6.1.jar") -Value "fake jar" -Encoding ascii
        }
        Set-Content -Path (Join-Path $Path "server.properties") -Value "server-port=$Port" -Encoding ascii
    }

    It "returns false when no other instance has Verity installed" {
        $me = Join-Path $root "Minecraft\servers\Me"
        $other = Join-Path $root "Minecraft\servers\Other"
        New-FakeInstance -Path $me -HasVerity $true -Port 39301
        New-FakeInstance -Path $other -HasVerity $false -Port 39302

        Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $false
    }

    It "returns false when the other Verity instance isn't running" {
        $me = Join-Path $root "Minecraft\servers\Me2"
        $other = Join-Path $root "Minecraft\servers\Other2"
        New-FakeInstance -Path $me -HasVerity $true -Port 39303
        New-FakeInstance -Path $other -HasVerity $true -Port 39304

        Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $false
    }

    It "returns true when another Verity instance is running" {
        $me = Join-Path $root "Minecraft\servers\Me3"
        $other = Join-Path $root "Minecraft\servers\Other3"
        New-FakeInstance -Path $me -HasVerity $true -Port 39305
        New-FakeInstance -Path $other -HasVerity $true -Port 39306

        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 39306)
        $listener.Start()
        try {
            Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $true
        } finally {
            $listener.Stop()
        }
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: FAIL — `Get-AllServerInstancePaths`/`Test-OtherVerityServerRunning` not recognized.

- [ ] **Step 3: Write minimal implementation**

Add to `_shared/scripts/verity-helpers.ps1`, after the `Stop-VerityLocalAiStack` block from Task 6:

```powershell
# Every <Game>\servers\<Instance>\ folder under the GameServers root -
# "_shared" is infrastructure, not a game; "_template" is the generic
# scaffold, not a real instance. Same discovery rule as stop-server.ps1's
# Get-AllServerInstances and gui-helpers.ps1's Get-ServerInstances.
function Get-AllServerInstancePaths {
    param(
        [Parameter(Mandatory = $true)][string]$GsRoot
    )
    $result = @()
    Get-ChildItem -Path $GsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "_shared" } | ForEach-Object {
        $serversDir = Join-Path $_.FullName "servers"
        if (Test-Path $serversDir) {
            Get-ChildItem -Path $serversDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "_template" } | ForEach-Object {
                $result += $_.FullName
            }
        }
    }
    return $result
}

# The sidecars are shared host-wide - stopping them when ONE Verity server
# closes would break AI for another Verity server still running. This
# checks whether any other instance is both Verity-enabled and currently up
# (by its Minecraft port, not RCON - RCON may be disabled) before it's safe
# to stop the sidecars.
function Test-OtherVerityServerRunning {
    param(
        [Parameter(Mandatory = $true)][string]$GsRoot,
        [Parameter(Mandatory = $true)][string]$ExcludePath
    )
    foreach ($path in (Get-AllServerInstancePaths -GsRoot $GsRoot)) {
        if ($path -eq $ExcludePath) { continue }
        if (-not (Test-VerityModPresent -InstancePath $path)) { continue }

        $props = Read-ServerProperties (Join-Path $path "server.properties")
        $port = 25565
        if ($props["server-port"]) { $port = [int]$props["server-port"] }
        if (Test-PortOpen -Port $port) { return $true }
    }
    return $false
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path tests\verity-helpers.tests.ps1`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add Test-OtherVerityServerRunning for safe shared-sidecar shutdown"
```

---

### Task 8: Redesign the Local AI panel into 3 independent rows

**Files:**
- Modify: `_shared/gui/HomeScreen.xaml:357-376` (replace `VerityAiPanel`)

**Interfaces:**
- Produces (new `x:Name`s Task 9 wires up): `VerityAiPanel`, `VerityOllamaStatusText`/`VerityOllamaButton`, `VerityKokoroStatusText`/`VerityKokoroButton`, `VerityWhisperStatusText`/`VerityWhisperButton`, `VerityAiStopAllButton`.

- [ ] **Step 1: Replace the panel markup**

In `_shared/gui/HomeScreen.xaml`, replace the `<Border ... x:Name="VerityAiPanel" ...>...</Border>` block (current lines 357-376) with:

```xml
    <!-- Local AI panel: only shown when the selected server has Verity
         installed (see Sync-StatusDisplay in Start-Gui.ps1). Each of the 3
         sidecars (LLM/TTS/STT) has its own row and can be started/stopped
         independently. -->
    <Border Grid.Row="6" x:Name="VerityAiPanel" Background="{StaticResource PanelBrush}" CornerRadius="10"
            BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="14" Margin="0,12,0,0"
            Visibility="Collapsed">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="LOCAL AI (VERITY)" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI Semibold" FontSize="11" Margin="0,0,0,8"/>

            <Grid Grid.Row="1" Margin="0,0,0,6">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" x:Name="VerityOllamaStatusText" Text="Core LLM (Ollama): OUT"
                           Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityOllamaButton" Content="START" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}"/>
            </Grid>

            <Grid Grid.Row="2" Margin="0,0,0,6">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" x:Name="VerityKokoroStatusText" Text="Voice out (Kokoro): OUT"
                           Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityKokoroButton" Content="START" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}"/>
            </Grid>

            <Grid Grid.Row="3" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" x:Name="VerityWhisperStatusText" Text="Voice in (Whisper): OUT"
                           Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityWhisperButton" Content="START" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}"/>
            </Grid>

            <Button Grid.Row="4" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
        </Grid>
    </Border>
</Grid>
```

- [ ] **Step 2: Verify the XAML parses**

Run:
```powershell
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[xml]$xamlXml = Get-Content -Path "D:\3_Hobbies\GameServers\_shared\gui\HomeScreen.xaml" -Raw
[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml)) | Out-Null
```
Expected: no exception (this is the exact loader `Start-Gui.ps1`'s `Get-ScreenXaml` uses).

- [ ] **Step 3: Commit**

```bash
git add _shared/gui/HomeScreen.xaml
git commit -m "feat: redesign Local AI panel into 3 independent service rows"
```

---

### Task 9: Wire the GUI to per-service start/stop

**Files:**
- Modify: `Start-Gui.ps1:83-86` (control lookup), `Start-Gui.ps1:196-211` (`Sync-StatusDisplay`), `Start-Gui.ps1:263-287` (click handlers), `Start-Gui.ps1:704-723` (`$aiJobTimer`)
- Modify: `_shared/scripts/gui-helpers.ps1` (remove now-unused `Get-VerityAiStatusText`/`Get-VerityAiButtonLabel`)
- Test: `tests/gui-helpers.tests.ps1` (remove their `Describe` blocks)

**Interfaces:**
- Consumes: `Set-VerityAiProvider`, `Start-OllamaSidecar`/`Start-KokoroSidecar`/`Start-WhisperSidecar`, `Stop-OllamaSidecar`/`Stop-KokoroSidecar`/`Stop-WhisperSidecar`, `Stop-VerityLocalAiStack` (Tasks 3, 5, 6), `Get-ServerStatusView` (existing, in `gui-helpers.ps1`), `Test-PortOpen` (rcon.ps1).

- [ ] **Step 1: Remove the now-unused helper functions and their tests**

In `_shared/scripts/gui-helpers.ps1`, delete `Get-VerityAiStatusText` and `Get-VerityAiButtonLabel` (the last two functions in the file - current lines 160-181).

In `tests/gui-helpers.tests.ps1`, delete the `Describe "Get-VerityAiStatusText" { ... }` and `Describe "Get-VerityAiButtonLabel" { ... }` blocks (current lines 234-248).

- [ ] **Step 2: Run the gui-helpers tests to confirm nothing else references them**

Run: `Invoke-Pester -Path tests\gui-helpers.tests.ps1`
Expected: PASS (remaining tests unaffected).

- [ ] **Step 3: Replace the control lookup**

In `Start-Gui.ps1`, replace lines 83-86:

```powershell
$verityAiPanel      = $homeRoot.FindName("VerityAiPanel")
$verityAiStatusText = $homeRoot.FindName("VerityAiStatusText")
$verityAiButton     = $homeRoot.FindName("VerityAiButton")
$script:aiJob       = $null
```

with:

```powershell
$verityAiPanel = $homeRoot.FindName("VerityAiPanel")
$verityServices = @(
    [PSCustomObject]@{ Key = "Ollama";  Port = 11434; Label = "Core LLM (Ollama)";  StatusText = $homeRoot.FindName("VerityOllamaStatusText");  Button = $homeRoot.FindName("VerityOllamaButton") }
    [PSCustomObject]@{ Key = "Kokoro";  Port = 8880;  Label = "Voice out (Kokoro)"; StatusText = $homeRoot.FindName("VerityKokoroStatusText");  Button = $homeRoot.FindName("VerityKokoroButton") }
    [PSCustomObject]@{ Key = "Whisper"; Port = 9000;  Label = "Voice in (Whisper)"; StatusText = $homeRoot.FindName("VerityWhisperStatusText"); Button = $homeRoot.FindName("VerityWhisperButton") }
)
$verityAiStopAllButton = $homeRoot.FindName("VerityAiStopAllButton")
$script:aiJobs = @{ Ollama = $null; Kokoro = $null; Whisper = $null }
```

- [ ] **Step 4: Replace the `Sync-StatusDisplay` Verity block**

Replace lines 196-208 (the `if ($script:selected -and ... Test-VerityModPresent ...) { ... } else { $verityAiPanel.Visibility = "Collapsed" }` block) with:

```powershell
    if ($script:selected -and $script:selected.Game -eq "Minecraft" -and (Test-VerityModPresent -InstancePath $script:selected.Path)) {
        $verityAiPanel.Visibility = "Visible"
        foreach ($svc in $verityServices) {
            if ($script:aiJobs[$svc.Key]) { continue }
            $running = Test-PortOpen -Port $svc.Port
            $svc.StatusText.Text = "$($svc.Label): $((Get-ServerStatusView -IsRunning $running).Label)"
            $svc.Button.Content = if ($running) { "STOP" } else { "START" }
            $svc.Button.IsEnabled = $true
        }
        $verityAiStopAllButton.IsEnabled = -not [bool]($script:aiJobs.Values | Where-Object { $_ })
    } else {
        $verityAiPanel.Visibility = "Collapsed"
    }
```

(This sits inside `Sync-StatusDisplay`, before its final `return $state` - leave that line and everything above line 196 unchanged.)

- [ ] **Step 5: Replace the click handler**

Replace the entire `$verityAiButton.Add_Click({ ... })` block (current lines 263-287) with:

```powershell
function Invoke-VerityServiceToggle {
    param($svc)
    if (-not $script:selected -or $script:aiJobs[$svc.Key]) { return }

    $running = Test-PortOpen -Port $svc.Port
    $svc.Button.IsEnabled = $false
    $svc.StatusText.Text = "$($svc.Label): $(if ($running) { 'Stopping...' } else { 'Starting...' })"
    $script:aiJobs[$svc.Key] = Start-Job -ScriptBlock {
        param($GsRoot, $InstancePath, $McRoot, $Service, $ToLocal)
        . (Join-Path $GsRoot "_shared\scripts\verity-helpers.ps1")
        if ($ToLocal) {
            & "Start-${Service}Sidecar" -McRoot $McRoot
            Set-VerityAiProvider -InstancePath $InstancePath -Service $Service -UseLocal $true
        } else {
            & "Stop-${Service}Sidecar"
            Set-VerityAiProvider -InstancePath $InstancePath -Service $Service -UseLocal $false
        }
    } -ArgumentList $root, $script:selected.Path, (Join-Path $root "Minecraft"), $svc.Key, (-not $running)
}

foreach ($svc in $verityServices) {
    $svc.Button.Add_Click({ Invoke-VerityServiceToggle -svc $svc }.GetNewClosure())
}

$verityAiStopAllButton.Add_Click({
    if (-not $script:selected) { return }
    foreach ($svc in $verityServices) {
        if ((Test-PortOpen -Port $svc.Port) -and -not $script:aiJobs[$svc.Key]) {
            Invoke-VerityServiceToggle -svc $svc
        }
    }
})
```

- [ ] **Step 6: Replace the `$aiJobTimer` tick handler**

Replace the `$aiJobTimer.Add_Tick({ ... })` block (current lines 706-722) with:

```powershell
$aiJobTimer.Add_Tick({
    foreach ($svc in $verityServices) {
        $job = $script:aiJobs[$svc.Key]
        if (-not $job) { continue }
        if ($job.State -eq "Running" -or $job.State -eq "NotStarted") { continue }

        $failed = $job.State -eq "Failed"
        $reason = if ($failed) { $job.ChildJobs[0].JobStateInfo.Reason.Message } else { $null }
        Remove-Job $job -Force
        $script:aiJobs[$svc.Key] = $null
        if ($failed) { $svc.StatusText.Text = "$($svc.Label): Error - $reason" }
    }
    Sync-StatusDisplay | Out-Null
})
```

(Leave `$aiJobTimer = New-Object ...` / `$aiJobTimer.Interval = ...` above it and `$aiJobTimer.Start()` below it unchanged.)

- [ ] **Step 7: Verify Start-Gui.ps1 still parses**

Run:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("D:\3_Hobbies\GameServers\Start-Gui.ps1", [ref]$null, [ref]$null) | Out-Null
```
Expected: no exception.

- [ ] **Step 8: Manual smoke test**

Run `Start-Gui.ps1`, select a Verity-enabled server (e.g. VerityCraft), confirm the Local AI panel shows 3 rows each reading "OUT" with a "START" button (assuming no sidecars are currently running - check with `Get-Process -Name ollama,python -ErrorAction SilentlyContinue` first). Click one row's START button, confirm its text changes to "Starting..." and the button disables; after it completes, confirm it flips to "LIT"/"STOP" and `config/verity-common.toml` for that server now has the matching provider set (e.g. `aiProvider = "OLLAMA"` after starting Ollama). Click STOP on that row, confirm it reverts.

- [ ] **Step 9: Commit**

```bash
git add Start-Gui.ps1 _shared/scripts/gui-helpers.ps1 tests/gui-helpers.tests.ps1
git commit -m "feat: wire GUI to independent per-service Local AI start/stop"
```

---

### Task 10: Boot only required sidecars, stop them on close when safe

**Files:**
- Modify: `Minecraft/servers/_template/start-with-tunnel.ps1:22-30` (boot logic), and its `finally` block (stop-on-close)

**Interfaces:**
- Consumes: `Get-VerityRequiredSidecars`, `Start-OllamaSidecar`/`Start-KokoroSidecar`/`Start-WhisperSidecar`, `Test-OtherVerityServerRunning`, `Stop-VerityLocalAiStack` (Tasks 3-7), `Test-VerityModPresent` (existing).

No new Pester coverage (this file has never had a test - it's real process orchestration, verified manually in Task 11).

- [ ] **Step 1: Replace the boot-time Verity block**

In `Minecraft/servers/_template/start-with-tunnel.ps1`, replace lines 22-30:

```powershell
. (Join-Path $gsRoot "_shared\scripts\verity-helpers.ps1")
if (Test-VerityModPresent -InstancePath $PSScriptRoot) {
    Write-Host "Verity mod detected - making sure the local AI stack (Ollama/Kokoro/Whisper) is up..."
    try {
        Start-VerityLocalAiStack -McRoot $mcRoot
    } catch {
        Write-Warning "Local AI stack didn't come up ($_) - starting the server anyway; Verity will fall back to its configured cloud provider."
    }
}
```

with:

```powershell
. (Join-Path $gsRoot "_shared\scripts\verity-helpers.ps1")
if (Test-VerityModPresent -InstancePath $PSScriptRoot) {
    $requiredSidecars = Get-VerityRequiredSidecars -InstancePath $PSScriptRoot
    if ($requiredSidecars.Count -gt 0) {
        Write-Host "Verity mod detected - making sure the local AI ($($requiredSidecars -join ', ')) is up..."
        foreach ($service in $requiredSidecars) {
            try {
                & "Start-${service}Sidecar" -McRoot $mcRoot
            } catch {
                Write-Warning "$service didn't come up ($_) - starting the server anyway; Verity will fall back to its configured cloud provider for that piece."
            }
        }
    }
}
```

- [ ] **Step 2: Add the stop-on-close block**

In the same file's `finally` block, after the existing `if ($tunnel -and -not $tunnel.HasExited) { ... }` block and before `Remove-Item -Path $startLock -Force -ErrorAction SilentlyContinue`, add:

```powershell
    if (Test-VerityModPresent -InstancePath $PSScriptRoot) {
        if (-not (Test-OtherVerityServerRunning -GsRoot $gsRoot -ExcludePath $PSScriptRoot)) {
            Write-Host "Stopping local AI (no other Verity server needs it)..."
            Stop-VerityLocalAiStack
        }
    }
```

- [ ] **Step 3: Verify the file still parses**

Run:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("D:\3_Hobbies\GameServers\Minecraft\servers\_template\start-with-tunnel.ps1", [ref]$null, [ref]$null) | Out-Null
```
Expected: no exception.

- [ ] **Step 4: Commit**

```bash
git add Minecraft/servers/_template/start-with-tunnel.ps1
git commit -m "feat: boot only configured sidecars, stop them on close when no other Verity server needs them"
```

---

### Task 11: Roll the fix out to Horror Ultimate Selection and verify end-to-end

**Files:**
- Modify: `Minecraft/servers/HorrorUltimateSelection/start-with-tunnel.ps1` (overwrite with the updated template copy)

**Interfaces:** None (deployment + manual verification).

- [ ] **Step 1: Copy the updated template script over the renamed server's copy**

`HorrorUltimateSelection`'s copy was confirmed identical to `_template`'s pre-change version (both created in the same recent batch), so a straight overwrite carries no local customization risk. Other existing servers (VerityCraft, VerityWorld, etc.) already had older, diverged copies before this plan and are intentionally left alone - only newly-created servers and this actively-tested one need the update right now.

Run:
```powershell
Copy-Item -Path "D:\3_Hobbies\GameServers\Minecraft\servers\_template\start-with-tunnel.ps1" `
          -Destination "D:\3_Hobbies\GameServers\Minecraft\servers\HorrorUltimateSelection\start-with-tunnel.ps1" -Force
```

- [ ] **Step 2: Run the full Pester suite**

Run: `Invoke-Pester -Path tests\`
Expected: PASS across every `*.tests.ps1` file (no regressions from Tasks 1-10).

- [ ] **Step 3: Full manual end-to-end check on Horror Ultimate Selection**

1. Launch it via `Start-Gui.ps1` (or `HorrorUltimateSelection\start-with-tunnel.ps1` directly).
2. Confirm the console does **not** hang on the "path contains spaces" prompt (folder no longer has spaces) and the Minecraft server actually reaches "Done" in its log.
3. Confirm `tasklist //FI "IMAGENAME eq java.exe"` now shows a running java process.
4. Confirm you (or a friend) can join via the printed playit.gg address without a `Connection reset`.
5. In the GUI, verify the Local AI panel's 3 rows reflect whatever `config/verity-common.toml` currently has configured for this server.
6. Stop the server (GUI's STOP SERVER button). Confirm any sidecars this server had running (check with `Get-Process -Name ollama,python -ErrorAction SilentlyContinue`) shut down afterward - unless VerityCraft or VerityWorld happens to also be running at the time, in which case they should correctly stay up.

- [ ] **Step 4: Commit** (only if Step 1's copy is the sole remaining change)

```bash
git status
```
(Server folders are gitignored, so this step will likely show nothing to commit - confirm, don't force a commit if there's nothing tracked to add.)

---

## Explicitly out of scope (carried over from the spec)

- Migrating already-created servers with spaces in their names other than Horror Ultimate Selection.
- Syncing the updated `start-with-tunnel.ps1` to VerityCraft/VerityWorld/other pre-existing servers (they were already running an older copy before this plan; not requested).
- A "some services on, some off" indicator anywhere outside the GUI's 3 status rows.
- Changing the shared, host-wide nature of the sidecars.
