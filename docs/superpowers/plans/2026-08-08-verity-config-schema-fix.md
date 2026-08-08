# Verity Config Schema Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the GUI's "Local AI" toggles for Verity (Ollama/Kokoro/Whisper) actually write config keys the installed Verity 5.7.1 mod reads, and add a GUI field to set the Groq cloud API key, so a Verity-enabled server can be made to work (local or cloud) entirely from the GUI.

**Architecture:** All logic lives in `_shared/scripts/verity-helpers.ps1` (dot-sourced by both `Start-Gui.ps1` and its Pester tests). Five small, independently-testable functions read/write `config/verity-common.toml`'s flat `[AISettings]` section. `Start-Gui.ps1` only wires UI events (button clicks, selection change) to those functions - it contains no TOML-parsing logic itself.

**Tech Stack:** PowerShell 5.1, Pester v4 (`Should Be` / `Should Match` / `Should Throw` syntax - not v5's `Should -Be`), WPF/XAML.

## Global Constraints

- All three local-AI toggles (Ollama, Kokoro, Whisper) share one flat `[AISettings]` TOML section - not three separate sections.
- Enable flags (`use_ollama`, `use_kokoro`, `use_local_whisper`) are TOML booleans: written unquoted (`true`/`false`), never as quoted strings.
- Ollama's URL/model, when enabled, are fixed to `http://127.0.0.1:11434/v1/` and `timheinrich2011/verity-3b` (the raw Ollama sidecar this repo already installs - no LiteLLM proxy).
- Kokoro's URL/model, when enabled, are fixed to `http://127.0.0.1:8880/v1/` and `kokoro`.
- Whisper's URL/model, when enabled, are fixed to `http://127.0.0.1:9000/v1/` and `base.en`.
- Disabling a service only clears its boolean flag - URL/model keys are left as-is (Verity ignores them once the flag is off).
- `apiKey` is independent of the three toggles - never touched by `Set-VerityAiProvider`.
- Config files are written UTF-8 **without BOM** (`New-Object System.Text.UTF8Encoding($false)`) - Forge's TOML parser crashes on a BOM. Every function that writes `verity-common.toml` must use this, matching the existing pattern.
- Pester tests in this repo use v4 syntax: `Should Be`, `Should Match`, `Should Throw` (not `Should -Be`).

---

### Task 1: `Set-TomlSectionBoolValue` helper

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (add function after `Set-TomlSectionValue`, which currently ends at line 59)
- Test: `tests/verity-helpers.tests.ps1` (add new `Describe` block after the existing `Describe "Set-TomlSectionValue"` block, which currently ends at line 62)

**Interfaces:**
- Produces: `Set-TomlSectionBoolValue -Lines <string[]> -Section <string> -Key <string> -Value <bool>` → returns `string[]`. Same section/key-matching behavior as `Set-TomlSectionValue`, but writes `$Key = true` / `$Key = false` (unquoted) instead of `$Key = "value"`.

- [ ] **Step 1: Write the failing tests**

Add this `Describe` block to `tests/verity-helpers.tests.ps1`, right after the closing `}` of `Describe "Set-TomlSectionValue"` (line 62):

```powershell
Describe "Set-TomlSectionBoolValue" {

    $sampleToml = @(
        '[AISettings]',
        "`tuse_ollama = false",
        "`tuse_kokoro = false",
        '',
        '[Custom]',
        "`tsomeOtherFlag = true"
    )

    It "replaces a key's value only within the matching section" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_ollama" -Value $true
        ($result | Where-Object { $_ -match '^\s*use_ollama\s*=' }) | Should Be "`tuse_ollama = true"
    }

    It "leaves a key in a different section untouched" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_kokoro" -Value $true
        ($result | Where-Object { $_ -match '^\s*someOtherFlag\s*=' }) | Should Be "`tsomeOtherFlag = true"
    }

    It "preserves every other line unchanged" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_ollama" -Value $true
        $result.Count | Should Be $sampleToml.Count
        $result[0] | Should Be '[AISettings]'
    }

    It "writes false unquoted" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_kokoro" -Value $false
        ($result | Where-Object { $_ -match '^\s*use_kokoro\s*=' }) | Should Be "`tuse_kokoro = false"
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Set-TomlSectionBoolValue"`
Expected: FAIL - `Set-TomlSectionBoolValue` is not recognized as the name of a cmdlet/function.

- [ ] **Step 3: Implement the function**

In `_shared/scripts/verity-helpers.ps1`, add this immediately after `Set-TomlSectionValue`'s closing `}` (line 59), before the comment block that currently precedes `Set-VerityAiProvider`:

```powershell
# Same section/key matching as Set-TomlSectionValue, but for TOML booleans
# (use_ollama/use_kokoro/use_local_whisper) - these must be written unquoted
# (`true`/`false`), not as strings, or NightConfig reads them as the wrong type.
function Set-TomlSectionBoolValue {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][bool]$Value
    )

    [string[]]$Lines = @($Lines)
    $valueText = if ($Value) { "true" } else { "false" }

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
            $result += "$leading$Key = $valueText"
            continue
        }
        $result += $line
    }
    return $result
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Set-TomlSectionBoolValue"`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add Set-TomlSectionBoolValue for unquoted TOML booleans"
```

---

### Task 2: Rewrite `Set-VerityAiProvider` for the real config schema

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1:65-121` (the whole `Set-VerityAiProvider` function)
- Test: `tests/verity-helpers.tests.ps1:64-162` (the whole `Describe "Set-VerityAiProvider"` block)

**Interfaces:**
- Consumes: `Set-TomlSectionBoolValue` (Task 1), existing `Set-TomlSectionValue`.
- Produces: `Set-VerityAiProvider -InstancePath <string> -Service <"Ollama"|"Kokoro"|"Whisper"> -UseLocal <bool>` - same signature as before, callers (`Start-Gui.ps1`) need no changes.

- [ ] **Step 1: Replace the test fixture and assertions with the real schema**

Replace the entire `Describe "Set-VerityAiProvider" { ... }` block (`tests/verity-helpers.tests.ps1:64-162`) with:

```powershell
Describe "Set-VerityAiProvider" {

    $root = Join-Path $env:TEMP ("verity-provider-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	voice = "Daniel"
	useLocalTts = true
	useLocalStt = false
	apiKey = ""
	aiModel = "FAST"
	aiProvider = "GROQ"
	use_ollama = false
	ollama_url = "http://127.0.0.1:4000/v1/"
	ollama_ai_model = "ollama/qwen2.5:1.5b"
	thinking_mode = false
	use_kokoro = false
	ollama_tts_url = "http://127.0.0.1:8880/v1/"
	ollama_tts_model = "kokoro"
	ollama_tts_voice = "am_fenrir"
	use_local_whisper = false
	ollama_stt_url = "http://127.0.0.1:9000/v1/"
	ollama_stt_model = "models/ggml-large-v3-turbo.bin"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "points AISettings at the local Ollama sidecar when UseLocal is true" {
        $inst = Join-Path $root "ollama-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_ollama = true'
        $content | Should Match 'ollama_url = "http://127\.0\.0\.1:11434/v1/"'
        $content | Should Match 'ollama_ai_model = "timheinrich2011/verity-3b"'
    }

    It "clears use_ollama when UseLocal is false, without touching url/model" {
        $inst = Join-Path $root "ollama-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_ollama = false'
        $content | Should Match 'ollama_url = "http://127\.0\.0\.1:11434/v1/"'
    }

    It "points AISettings at the local Kokoro sidecar when UseLocal is true" {
        $inst = Join-Path $root "kokoro-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_kokoro = true'
        $content | Should Match 'ollama_tts_url = "http://127\.0\.0\.1:8880/v1/"'
        $content | Should Match 'ollama_tts_model = "kokoro"'
    }

    It "clears use_kokoro when UseLocal is false" {
        $inst = Join-Path $root "kokoro-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_kokoro = false'
    }

    It "points AISettings at the local Whisper sidecar when UseLocal is true" {
        $inst = Join-Path $root "whisper-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_local_whisper = true'
        $content | Should Match 'ollama_stt_url = "http://127\.0\.0\.1:9000/v1/"'
        $content | Should Match 'ollama_stt_model = "base.en"'
    }

    It "clears use_local_whisper when UseLocal is false" {
        $inst = Join-Path $root "whisper-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_local_whisper = false'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Set-VerityAiProvider"`
Expected: FAIL - assertions look for `use_ollama = true` etc., but the current implementation still writes the old `[GeneralSettings.AISettings]` / `aiProvider = "OLLAMA"` schema.

- [ ] **Step 3: Rewrite the function**

Replace `Set-VerityAiProvider` (`_shared/scripts/verity-helpers.ps1:65-121`) entirely with:

```powershell
# Points one Verity subsystem (LLM/TTS/STT) at its local sidecar, or turns it
# back off. All three toggles live in the same flat [AISettings] section (not
# separate per-service sections) as booleans: use_ollama, use_kokoro,
# use_local_whisper. config/verity-common.toml is the single source of truth
# for which sidecars a server wants running - there's no separate on/off
# state to keep in sync.
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
            $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_ollama" -Value $UseLocal
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_url" -Value "http://127.0.0.1:11434/v1/"
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_ai_model" -Value "timheinrich2011/verity-3b"
            }
        }
        "Kokoro" {
            $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_kokoro" -Value $UseLocal
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_tts_url" -Value "http://127.0.0.1:8880/v1/"
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_tts_model" -Value "kokoro"
            }
        }
        "Whisper" {
            $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_local_whisper" -Value $UseLocal
            if ($UseLocal) {
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_stt_url" -Value "http://127.0.0.1:9000/v1/"
                $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_stt_model" -Value "base.en"
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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Set-VerityAiProvider"`
Expected: PASS (7/7)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "fix: point Set-VerityAiProvider at Verity's real flat AISettings schema"
```

---

### Task 3: Rewrite `Get-VerityRequiredSidecars` for the real config schema

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1:126-139` (the whole `Get-VerityRequiredSidecars` function)
- Test: `tests/verity-helpers.tests.ps1:164-207` (the whole `Describe "Get-VerityRequiredSidecars"` block)

**Interfaces:**
- Produces: `Get-VerityRequiredSidecars -InstancePath <string>` → `string[]` subset of `@("Ollama", "Kokoro", "Whisper")` - same signature and return shape as before. Consumed by `Minecraft/servers/_template/start-with-tunnel.ps1:24` (unchanged caller).

- [ ] **Step 1: Replace the test fixture and assertions with the real schema**

Replace the entire `Describe "Get-VerityRequiredSidecars" { ... }` block (`tests/verity-helpers.tests.ps1:164-207`) with:

```powershell
Describe "Get-VerityRequiredSidecars" {

    $root = Join-Path $env:TEMP ("verity-required-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityToml([string]$Path, [bool]$UseOllama, [bool]$UseKokoro, [bool]$UseWhisper) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        $ollamaText = if ($UseOllama) { "true" } else { "false" }
        $kokoroText = if ($UseKokoro) { "true" } else { "false" }
        $whisperText = if ($UseWhisper) { "true" } else { "false" }
        @"
[AISettings]
	use_ollama = $ollamaText
	use_kokoro = $kokoroText
	use_local_whisper = $whisperText
"@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "returns all three when all are local" {
        $inst = Join-Path $root "all-local"
        New-FakeVerityToml -Path $inst -UseOllama $true -UseKokoro $true -UseWhisper $true
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama", "Kokoro", "Whisper")
    }

    It "returns only the ones set local, e.g. just the core LLM" {
        $inst = Join-Path $root "llm-only"
        New-FakeVerityToml -Path $inst -UseOllama $true -UseKokoro $false -UseWhisper $false
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama")
    }

    It "returns an empty array when nothing is local" {
        $inst = Join-Path $root "cloud-only"
        New-FakeVerityToml -Path $inst -UseOllama $false -UseKokoro $false -UseWhisper $false
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

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Get-VerityRequiredSidecars"`
Expected: FAIL - current implementation still matches `aiProvider\s*=\s*"OLLAMA"` etc., which no fixture in the new tests contains.

- [ ] **Step 3: Rewrite the function**

Replace `Get-VerityRequiredSidecars` (`_shared/scripts/verity-helpers.ps1:126-139`) entirely with:

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
    if ($content -match '(?m)^\s*use_ollama\s*=\s*true') { $required += "Ollama" }
    if ($content -match '(?m)^\s*use_kokoro\s*=\s*true') { $required += "Kokoro" }
    if ($content -match '(?m)^\s*use_local_whisper\s*=\s*true') { $required += "Whisper" }
    return $required
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Get-VerityRequiredSidecars"`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "fix: detect required Verity sidecars from the real boolean schema"
```

---

### Task 4: `Get-VerityApiKey` / `Set-VerityApiKey` helpers

**Files:**
- Modify: `_shared/scripts/verity-helpers.ps1` (add both functions after `Get-VerityRequiredSidecars`)
- Test: `tests/verity-helpers.tests.ps1` (add two new `Describe` blocks after `Describe "Get-VerityRequiredSidecars"`)

**Interfaces:**
- Produces: `Get-VerityApiKey -InstancePath <string>` → `string` (the saved key, or `""` if unset/missing config).
- Produces: `Set-VerityApiKey -InstancePath <string> -ApiKey <string>` → persists the key. Throws if `config\verity-common.toml` is missing (same error-handling pattern as `Set-VerityAiProvider`).
- Consumed by: `Start-Gui.ps1` (Task 6) - pre-fills and saves the GUI's API key field.

- [ ] **Step 1: Write the failing tests**

Add these two `Describe` blocks to `tests/verity-helpers.tests.ps1`, right after the closing `}` of `Describe "Get-VerityRequiredSidecars"`:

```powershell
Describe "Get-VerityApiKey" {

    $root = Join-Path $env:TEMP ("verity-getkey-" + [Guid]::NewGuid().ToString("N"))

    It "returns the saved key" {
        $inst = Join-Path $root "with-key"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "config") | Out-Null
        @'
[AISettings]
	apiKey = "gsk_abc123"
'@ | Set-Content -Path (Join-Path $inst "config\verity-common.toml") -Encoding utf8

        Get-VerityApiKey -InstancePath $inst | Should Be "gsk_abc123"
    }

    It "returns an empty string when the key is blank" {
        $inst = Join-Path $root "blank-key"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "config") | Out-Null
        @'
[AISettings]
	apiKey = ""
'@ | Set-Content -Path (Join-Path $inst "config\verity-common.toml") -Encoding utf8

        Get-VerityApiKey -InstancePath $inst | Should Be ""
    }

    It "returns an empty string when the config file doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        Get-VerityApiKey -InstancePath $inst | Should Be ""
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Set-VerityApiKey" {

    $root = Join-Path $env:TEMP ("verity-setkey-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	apiKey = ""
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "writes the given key" {
        $inst = Join-Path $root "set-key"
        New-FakeVerityInstance -Path $inst
        Set-VerityApiKey -InstancePath $inst -ApiKey "gsk_abc123"
        (Get-Content (Join-Path $inst "config\verity-common.toml") -Raw) | Should Match 'apiKey = "gsk_abc123"'
    }

    It "can clear the key back to empty" {
        $inst = Join-Path $root "clear-key"
        New-FakeVerityInstance -Path $inst
        Set-VerityApiKey -InstancePath $inst -ApiKey "gsk_abc123"
        Set-VerityApiKey -InstancePath $inst -ApiKey ""
        (Get-Content (Join-Path $inst "config\verity-common.toml") -Raw) | Should Match 'apiKey = ""'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityApiKey -InstancePath $inst -ApiKey "x" } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Get-VerityApiKey","Set-VerityApiKey"`
Expected: FAIL - neither function exists yet.

- [ ] **Step 3: Implement both functions**

Add this immediately after `Get-VerityRequiredSidecars`'s closing `}` in `_shared/scripts/verity-helpers.ps1`:

```powershell
# Reads the currently saved Groq API key (or "" if unset/missing config) -
# used to pre-fill the GUI's API key field so it reflects what's actually
# saved instead of always starting blank.
function Get-VerityApiKey {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) { return "" }

    $content = Get-Content -Path $tomlPath -Raw
    if ($content -match '(?m)^\s*apiKey\s*=\s*"([^"]*)"') { return $Matches[1] }
    return ""
}

# Persists the Groq API key entered in the GUI. Independent of
# Set-VerityAiProvider - apiKey is used for the cloud-fallback path and
# isn't touched by the Ollama/Kokoro/Whisper local-AI toggles.
function Set-VerityApiKey {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ApiKey
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8
    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "apiKey" -Value $ApiKey

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1 -TestName "Get-VerityApiKey","Set-VerityApiKey"`
Expected: PASS (6/6)

- [ ] **Step 5: Run the full test file to make sure nothing else broke**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1`
Expected: PASS, all Describe blocks.

- [ ] **Step 6: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add Get/Set-VerityApiKey for the GUI's API key field"
```

---

### Task 5: Add the API key field to `HomeScreen.xaml`

**Files:**
- Modify: `_shared/gui/HomeScreen.xaml:365-411` (the `VerityAiPanel` Border's inner `Grid`)

**Interfaces:**
- Produces: two new named XAML elements - `VerityApiKeyBox` (a `PasswordBox`) and `VerityApiKeySaveButton` (a `Button`) - inside `VerityAiPanel`. Consumed by `Start-Gui.ps1` (Task 6) via `$homeRoot.FindName(...)`.

This task has no automated test - there's no existing XAML/WPF test harness in this repo (confirmed: no test file references `XamlReader` or any `*.xaml`). Verification is the manual smoke-check in Step 2.

- [ ] **Step 1: Edit the XAML**

In `_shared/gui/HomeScreen.xaml`, change the `Grid.RowDefinitions` block (lines 365-371) from 5 rows to 7:

```xml
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
```

Then, between the Whisper row's closing `</Grid>` (line 406) and the `VerityAiStopAllButton` (currently line 408), insert two new rows - a label and the input row:

```xml
            <TextBlock Grid.Row="4" Text="GROQ API KEY (used when not local)" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI Semibold" FontSize="10" Margin="0,4,0,4"/>

            <Grid Grid.Row="5" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <PasswordBox Grid.Column="0" x:Name="VerityApiKeyBox" FontFamily="Consolas" FontSize="12"
                             Background="{StaticResource PanelElevatedBrush}" Foreground="{StaticResource TextBrush}"
                             BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="6,4"
                             VerticalContentAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityApiKeySaveButton" Content="SAVE" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}" Margin="8,0,0,0"/>
            </Grid>
```

Finally, change the `VerityAiStopAllButton`'s `Grid.Row` from `4` to `6`:

```xml
            <Button Grid.Row="6" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
```

- [ ] **Step 2: Smoke-check the XAML parses and the new names resolve**

Run this from the repo root to catch XML/markup errors before wiring anything up in `Start-Gui.ps1`:

```powershell
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[xml]$xaml = Get-Content -Path "_shared\gui\HomeScreen.xaml" -Raw
$rootElement = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
if (-not $rootElement.FindName("VerityApiKeyBox")) { throw "VerityApiKeyBox not found" }
if (-not $rootElement.FindName("VerityApiKeySaveButton")) { throw "VerityApiKeySaveButton not found" }
Write-Host "OK"
```

Expected: prints `OK` with no errors.

- [ ] **Step 3: Commit**

```bash
git add _shared/gui/HomeScreen.xaml
git commit -m "feat: add Groq API key field to the Verity AI panel"
```

---

### Task 6: Wire the API key field up in `Start-Gui.ps1`

**Files:**
- Modify: `Start-Gui.ps1:90` (add two `FindName` lookups after the existing `$verityAiStopAllButton` line)
- Modify: `Start-Gui.ps1:218-225` (`$serverCombo.Add_SelectionChanged` handler - add pre-fill)
- Modify: `Start-Gui.ps1:298-305` area (add a new `Add_Click` handler for the save button, and a `PasswordChanged` handler, near the existing `$verityAiStopAllButton.Add_Click` block)

**Interfaces:**
- Consumes: `Get-VerityApiKey`, `Set-VerityApiKey` (Task 4); `Test-VerityModPresent` (existing); `$verityApiKeyBox` / `$verityApiKeySaveButton` (Task 5's XAML names).

This task has no automated test - it's UI event wiring in the same style as the existing untested `Invoke-VerityServiceToggle` wiring. Verification is the manual walkthrough in Step 2.

- [ ] **Step 1: Add the FindName lookups and event handlers**

In `Start-Gui.ps1`, right after line 90 (`$verityAiStopAllButton = $homeRoot.FindName("VerityAiStopAllButton")`), add:

```powershell
$verityApiKeyBox = $homeRoot.FindName("VerityApiKeyBox")
$verityApiKeySaveButton = $homeRoot.FindName("VerityApiKeySaveButton")
```

In the `$serverCombo.Add_SelectionChanged` handler (currently lines 218-225), add the pre-fill line right after `$script:selected = ...` is set:

```powershell
$serverCombo.Add_SelectionChanged({
    if ($serverCombo.SelectedIndex -lt 0) { return }
    $script:selected = $script:instances[$serverCombo.SelectedIndex]
    $script:pendingStart = $false
    $script:pendingStop = $false
    $verityApiKeyBox.Password = if ($script:selected.Game -eq "Minecraft" -and (Test-VerityModPresent -InstancePath $script:selected.Path)) {
        Get-VerityApiKey -InstancePath $script:selected.Path
    } else { "" }
    Sync-StatusDisplay | Out-Null
    Update-AddressDisplay
})
```

(The pre-fill goes in the selection-changed handler, not in `Sync-StatusDisplay` - that function runs on a 2-second timer tick, and re-setting `.Password` every tick would overwrite whatever the user is actively typing.)

After the existing `$verityAiStopAllButton.Add_Click({ ... })` block, add:

```powershell
$verityApiKeySaveButton.Add_Click({
    if (-not $script:selected) { return }
    Set-VerityApiKey -InstancePath $script:selected.Path -ApiKey $verityApiKeyBox.Password
    $verityApiKeySaveButton.Content = "SAVED"
})

$verityApiKeyBox.Add_PasswordChanged({ $verityApiKeySaveButton.Content = "SAVE" })
```

- [ ] **Step 2: Manual walkthrough**

Run `Start-Gui.ps1` (or `Start.bat`), select `HorrorUltimateSelection` (a Verity-enabled server) in the server picker:

1. The Groq API Key field should appear blank (matches the live `apiKey = ""` in its config).
2. Type a value, click SAVE - button should read "SAVED".
3. Open `Minecraft/servers/HorrorUltimateSelection/config/verity-common.toml` and confirm `apiKey = "<what you typed>"`.
4. Switch to a different server in the picker and back - the field should show what you saved, not blank.
5. Click the Ollama START button - confirm (after Ollama sidecar comes up) that `use_ollama = true` in the same file, and `ollama_url`/`ollama_ai_model` are the sidecar's values (`http://127.0.0.1:11434/v1/`, `timheinrich2011/verity-3b`).

- [ ] **Step 3: Commit**

```bash
git add Start-Gui.ps1
git commit -m "feat: wire the Groq API key field to Get/Set-VerityApiKey"
```

---

### Task 7: Fix the live `HorrorUltimateSelection` server and verify in-game

Not a code change - applies the fix to the server that originally hit the `HTTP 401 Invalid API Key` error, and confirms it's actually resolved.

- [ ] **Step 1: Run the full Pester suite one more time**

Run: `Invoke-Pester -Script tests/verity-helpers.tests.ps1`
Expected: PASS, every `Describe` block.

- [ ] **Step 2: Fix the live server via the GUI**

Using the GUI (now that Task 6 is wired up), either:
- Paste a real Groq API key into the field and SAVE (simplest - keeps the cloud path), or
- Click the Ollama START button to switch `HorrorUltimateSelection` to the local sidecar.

- [ ] **Step 3: Confirm in-game**

Start (or restart) `HorrorUltimateSelection` from the GUI, join with a client, and talk to Verity in chat. Confirm the `[ERROR] ... HTTP Error 401` no longer appears in the server console log, and Verity responds.
