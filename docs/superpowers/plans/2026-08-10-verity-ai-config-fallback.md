# Verity AI: Fallback Fix + Provider/Model Pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing "will fall back to cloud" warning actually true when a local Verity sidecar fails to start, and let users pick a remote LLM provider and (a single, expandable-later) local Ollama model from the GUI instead of only a local/remote toggle.

**Architecture:** One small fix in the server-launch template (`start-with-tunnel.ps1`) reuses the already-tested `Set-VerityAiProvider` to flip a failed sidecar to remote. Two new helper functions in `verity-helpers.ps1` (`Set-VerityRemoteProvider`, `Get-VerityRemoteProvider`, `Set-VerityOllamaModel`) back two new `ComboBox` controls added to the existing `VerityAiPanel` in `HomeScreen.xaml`, wired the same way the existing API-key field already is.

**Tech Stack:** Windows PowerShell 5.1, WPF (loose XAML via `XamlReader.Load`), Pester 3.4.0 (old syntax).

## Global Constraints

- Windows PowerShell 5.1 / WPF only — no `App.xaml`, no compiled resources. Use `powershell.exe` in all bash tool invocations, never `pwsh` (not installed).
- Pester 3.4.0 uses old syntax (`Should Be`, `Should Not Be`, `Should Match`) — do not use `Should -Be` anywhere in this plan's tests.
- Run the full suite with: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`.
- `verity-common.toml` has two live schemas — old (`[GeneralSettings.AISettings]`, nested, string-enum providers) and new (flat `[AISettings]`, booleans) — every toml-writing function in this plan must branch on `Test-VerityOldSchema`, exactly like `Set-VerityAiProvider` already does.
- Remote provider values are written UPPERCASE, matching the mod's own convention (`GEMINI`, `GROQ`, `OPENROUTER`, `MISTRAL`, `OPENAI`) — no case translation layer.
- The Verity mod's own factory default is already remote/cloud-first — no change needed to new-server defaults (confirmed against a live untouched instance before writing the spec).
- Spec: `docs/superpowers/specs/2026-08-10-verity-ai-config-fallback-design.md`.

---

### Task 1: Fallback fix in `start-with-tunnel.ps1`

**Files:**
- Modify: `Minecraft\servers\_template\start-with-tunnel.ps1` (lines 22-34 — this is the template every new server instance copies; existing live server instances each have their own already-copied file and are out of scope for this fix)
- Test: `tests\start-with-tunnel.tests.ps1` (new)

**Interfaces:**
- Consumes: `Set-VerityAiProvider -InstancePath <string> -Service <'Ollama'|'Kokoro'|'Whisper'> -UseLocal <bool>` (already exists, fully tested, in `_shared\scripts\verity-helpers.ps1`, dot-sourced at line 22 of `start-with-tunnel.ps1`) — no new toml-writing helper needed for this task.
- Produces: nothing consumed by later tasks — this task is independent of Tasks 2 and 3.

- [ ] **Step 1: Write the failing test**

Create `tests\start-with-tunnel.tests.ps1`:

```powershell
# Regression test for the bug where a failed local Verity sidecar logged
# "will fall back to its configured cloud provider" but never actually
# flipped the config - so Verity kept pointing at a dead local endpoint.
# This checks the fix is textually present in the right place (inside the
# sidecar-start catch block) rather than executing the real script, since
# start-with-tunnel.ps1 has real side effects (process locks, launching
# playit.exe, launching the actual Minecraft server) that make it unsafe
# to run directly in a test.

$templatePath = Join-Path (Split-Path -Parent $PSScriptRoot) "Minecraft\servers\_template\start-with-tunnel.ps1"
$content = Get-Content -Path $templatePath -Raw

Describe "start-with-tunnel.ps1 sidecar-failure fallback" {

    It "flips the failed sidecar to remote inside the catch block" {
        if ($content -notmatch '(?s)catch \{(.*?)\}') {
            throw "Could not find the sidecar-start catch block in start-with-tunnel.ps1 - has it moved?"
        }
        $catchBlock = $matches[1]
        $catchBlock | Should Match 'Set-VerityAiProvider\s+-InstancePath\s+\$PSScriptRoot\s+-Service\s+\$service\s+-UseLocal\s+\$false'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/start-with-tunnel.tests.ps1"`
Expected: FAIL — the catch block doesn't contain the `Set-VerityAiProvider` call yet.

- [ ] **Step 3: Implement the fix**

`Minecraft\servers\_template\start-with-tunnel.ps1` currently reads (lines 22-34):

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

Replace the `catch` block with:

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
                try { Set-VerityAiProvider -InstancePath $PSScriptRoot -Service $service -UseLocal $false } catch { }
            }
        }
    }
}
```

(The inner `try`/`catch` around `Set-VerityAiProvider` matches the project's established best-effort pattern for config writes that must never block server launch — see `Get-AppVersion`'s doc comment for the same rationale.)

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/start-with-tunnel.tests.ps1"`
Expected: PASS.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
git add Minecraft/servers/_template/start-with-tunnel.ps1 tests/start-with-tunnel.tests.ps1
git commit -m "fix: actually fall back to remote when a local Verity sidecar fails to start"
```

---

### Task 2: Remote provider dropdown

**Files:**
- Modify: `_shared\scripts\verity-helpers.ps1` (add `Set-VerityRemoteProvider`, `Get-VerityRemoteProvider`)
- Modify: `_shared\gui\HomeScreen.xaml` (`VerityAiPanel`, add a provider row)
- Modify: `Start-Gui.ps1` (element lookup, `SelectionChanged` wiring, pre-select on server switch)
- Test: `tests\verity-helpers.tests.ps1`

**Interfaces:**
- Produces: `Set-VerityRemoteProvider -InstancePath <string> -Provider <'GEMINI'|'GROQ'|'OPENROUTER'|'MISTRAL'|'OPENAI'> -> (none)`. Writes `aiProvider` in whichever schema the file uses (branches on `Test-VerityOldSchema`, same as `Set-VerityAiProvider`). Throws if `config\verity-common.toml` doesn't exist.
- Produces: `Get-VerityRemoteProvider -InstancePath <string> -> [string]`. Reads the current `aiProvider` value (e.g. `"GROQ"`, or `"OLLAMA"` if local is on, or `""` if unset/missing) — used to pre-select the dropdown when switching servers, same role `Get-VerityApiKey` plays for the API key field.
- Consumes (Task 3): none — Tasks 2 and 3 are independent of each other, both depending only on existing `verity-helpers.ps1` functions.

- [ ] **Step 1: Write the failing tests**

Append to `tests\verity-helpers.tests.ps1` (after the existing `Describe "Set-VerityAiProvider"` block, matching its fixture style):

```powershell
Describe "Set-VerityRemoteProvider" {

    $root = Join-Path $env:TEMP ("verity-remote-provider-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	apiKey = ""
	aiProvider = "OPENAI"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    function New-FakeOldSchemaInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[GeneralSettings.AISettings]
	apiKey = ""
	aiProvider = "OPENAI"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "writes the selected provider in the new flat schema" {
        $inst = Join-Path $root "new-schema"
        New-FakeVerityInstance -Path $inst
        Set-VerityRemoteProvider -InstancePath $inst -Provider "GROQ"
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "GROQ"'
    }

    It "writes the selected provider in the old nested schema" {
        $inst = Join-Path $root "old-schema"
        New-FakeOldSchemaInstance -Path $inst
        Set-VerityRemoteProvider -InstancePath $inst -Provider "OPENROUTER"
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OPENROUTER"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityRemoteProvider -InstancePath $inst -Provider "GEMINI" } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-VerityRemoteProvider" {

    $root = Join-Path $env:TEMP ("verity-get-provider-" + [Guid]::NewGuid().ToString("N"))

    It "returns the saved provider" {
        $inst = Join-Path $root "has-provider"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "config") | Out-Null
        @'
[AISettings]
	aiProvider = "MISTRAL"
'@ | Set-Content -Path (Join-Path $inst "config\verity-common.toml") -Encoding utf8
        Get-VerityRemoteProvider -InstancePath $inst | Should Be "MISTRAL"
    }

    It "returns an empty string when the config file doesn't exist" {
        $inst = Join-Path $root "no-config"
        Get-VerityRemoteProvider -InstancePath $inst | Should Be ""
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/verity-helpers.tests.ps1"`
Expected: FAIL — `Set-VerityRemoteProvider` and `Get-VerityRemoteProvider` are not recognized as the names of cmdlets/functions.

- [ ] **Step 3: Implement both functions in `verity-helpers.ps1`**

Add to `_shared\scripts\verity-helpers.ps1`, immediately after the existing `Set-VerityAiProvider` function's closing brace (after line 187):

```powershell
# Sets which cloud provider AISettings.aiProvider points at when running
# remote (not local Ollama). Independent of Set-VerityAiProvider's local/
# remote toggle - this only changes which remote provider is selected;
# toggling local Ollama on/off is still Set-VerityAiProvider's job. Values
# are written uppercase, matching the mod's own convention exactly (no
# case-translation layer needed).
function Set-VerityRemoteProvider {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][ValidateSet("GEMINI", "GROQ", "OPENROUTER", "MISTRAL", "OPENAI")][string]$Provider
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8
    $section = if (Test-VerityOldSchema -Content ($lines -join "`n") -InstancePath $InstancePath) { "GeneralSettings.AISettings" } else { "AISettings" }
    $lines = Set-TomlSectionValue -Lines $lines -Section $section -Key "aiProvider" -Value $Provider

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}

# Reads the currently saved aiProvider value (e.g. "GROQ", or "OLLAMA" if
# local is on, or "" if unset/missing config) - used to pre-fill the GUI's
# provider dropdown so it reflects what's actually saved, the same role
# Get-VerityApiKey plays for the API key field.
function Get-VerityRemoteProvider {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) { return "" }

    $content = Get-Content -Path $tomlPath -Raw
    if ($content -match '(?m)^\s*aiProvider\s*=\s*"([^"]*)"') {
        return $Matches[1]
    }
    return ""
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/verity-helpers.tests.ps1"`
Expected: PASS, all `Set-VerityRemoteProvider`/`Get-VerityRemoteProvider` tests green alongside the pre-existing ones.

- [ ] **Step 5: Add the provider dropdown to `HomeScreen.xaml`**

`VerityAiPanel`'s `Grid` currently has 5 `RowDefinition`s (rows 0-4), with the API key `Grid` at `Grid.Row="3"` and `VerityAiStopAllButton` at `Grid.Row="4"` (`_shared\gui\HomeScreen.xaml`, lines 144-206):

```xml
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
```

Change to 6 rows:

```xml
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
```

The `VerityAiStopAllButton` line currently reads (line 205):

```xml
            <Button Grid.Row="4" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
```

Change `Grid.Row="4"` to `Grid.Row="5"`, and insert the new provider row immediately before it (i.e. between the existing API-key `Grid Grid.Row="3"` block and this button):

```xml
            <Grid Grid.Row="4" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="REMOTE PROVIDER" Foreground="{StaticResource MutedTextBrush}"
                           FontFamily="Segoe UI Semibold" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <ComboBox Grid.Column="1" x:Name="VerityProviderCombo" FontFamily="Segoe UI" FontSize="12"
                          Background="{StaticResource PanelElevatedBrush}" Foreground="{StaticResource TextBrush}"
                          BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="6,4">
                    <ComboBoxItem Content="GEMINI"/>
                    <ComboBoxItem Content="GROQ"/>
                    <ComboBoxItem Content="OPENROUTER"/>
                    <ComboBoxItem Content="MISTRAL"/>
                    <ComboBoxItem Content="OPENAI"/>
                </ComboBox>
            </Grid>

            <Button Grid.Row="5" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
```

- [ ] **Step 6: Wire the dropdown in `Start-Gui.ps1`**

`Start-Gui.ps1`'s Verity element lookups currently include (line 106):

```powershell
$verityApiKeySaveButton = $homeRoot.FindName("VerityApiKeySaveButton")
```

Add right after it:

```powershell
$verityProviderCombo = $homeRoot.FindName("VerityProviderCombo")
```

`Start-Gui.ps1`'s `$serverCombo.Add_SelectionChanged` block currently reads (lines 234-244):

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

Add the provider pre-selection right after the `$verityApiKeyBox.Password = ...` block, before `Sync-StatusDisplay | Out-Null`:

```powershell
    $currentProvider = if ($script:selected.Game -eq "Minecraft" -and (Test-VerityModPresent -InstancePath $script:selected.Path)) {
        Get-VerityRemoteProvider -InstancePath $script:selected.Path
    } else { "" }
    $verityProviderCombo.SelectedItem = $verityProviderCombo.Items | Where-Object { $_.Content -eq $currentProvider } | Select-Object -First 1
```

`Start-Gui.ps1`'s `$verityApiKeySaveButton.Add_Click` handler currently reads (lines 326-334):

```powershell
$verityApiKeySaveButton.Add_Click({
    if (-not $script:selected) { return }
    try {
        Set-VerityApiKey -InstancePath $script:selected.Path -ApiKey $verityApiKeyBox.Password.Trim()
        $verityApiKeySaveButton.Content = "SAVED"
    } catch {
        $verityApiKeySaveButton.Content = "FAILED"
    }
})
```

Add right after it:

```powershell
$verityProviderCombo.Add_SelectionChanged({
    if (-not $script:selected -or $verityProviderCombo.SelectedIndex -lt 0) { return }
    try {
        Set-VerityRemoteProvider -InstancePath $script:selected.Path -Provider $verityProviderCombo.SelectedItem.Content.ToString()
    } catch { }
})
```

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS, all tests green.

- [ ] **Step 8: Manual smoke check**

Launch the app for real against a Verity-enabled server: confirm the "REMOTE PROVIDER" dropdown appears in the panel, selecting a value doesn't error, and switching to a different server and back preserves/reflects each server's saved provider correctly.

- [ ] **Step 9: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 _shared/gui/HomeScreen.xaml Start-Gui.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add remote AI provider dropdown to the Verity panel"
```

---

### Task 3: Local Ollama model dropdown

**Files:**
- Modify: `_shared\scripts\verity-helpers.ps1` (add `Set-VerityOllamaModel`)
- Modify: `_shared\gui\HomeScreen.xaml` (`VerityAiPanel`, add a model row)
- Modify: `Start-Gui.ps1` (element lookup, `SelectionChanged` wiring, default-select on server switch)
- Test: `tests\verity-helpers.tests.ps1`

**Interfaces:**
- Produces: `Set-VerityOllamaModel -InstancePath <string> -Model <string> -> (none)`. Writes `aiModel` (old schema) / `ollama_ai_model` (new schema) directly. Throws if `config\verity-common.toml` doesn't exist.
- Consumes: none from Task 2 — independent.

Ships with exactly one dropdown entry (today's hardcoded `timheinrich2011/verity-3b`), so there's no ambiguity to read back on server switch — the combo is simply defaulted to its one item. No `Get-VerityOllamaModel` reader is added in this task; it would only be useful once a second model exists, and adding it now would be speculative (YAGNI) — add it in the same change that adds a second dropdown entry.

- [ ] **Step 1: Write the failing tests**

Append to `tests\verity-helpers.tests.ps1` (after the `Describe "Get-VerityRemoteProvider"` block added in Task 2):

```powershell
Describe "Set-VerityOllamaModel" {

    $root = Join-Path $env:TEMP ("verity-ollama-model-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	use_ollama = true
	ollama_ai_model = "old-model"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    function New-FakeOldSchemaInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[GeneralSettings.AISettings]
	aiProvider = "OLLAMA"
	aiModel = "old-model"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "writes the selected model in the new flat schema" {
        $inst = Join-Path $root "new-schema"
        New-FakeVerityInstance -Path $inst
        Set-VerityOllamaModel -InstancePath $inst -Model "timheinrich2011/verity-3b"
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ollama_ai_model = "timheinrich2011/verity-3b"'
    }

    It "writes the selected model in the old nested schema" {
        $inst = Join-Path $root "old-schema"
        New-FakeOldSchemaInstance -Path $inst
        Set-VerityOllamaModel -InstancePath $inst -Model "timheinrich2011/verity-3b"
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiModel = "timheinrich2011/verity-3b"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityOllamaModel -InstancePath $inst -Model "timheinrich2011/verity-3b" } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/verity-helpers.tests.ps1"`
Expected: FAIL — `Set-VerityOllamaModel` is not recognized as the name of a cmdlet/function.

- [ ] **Step 3: Implement `Set-VerityOllamaModel` in `verity-helpers.ps1`**

Add to `_shared\scripts\verity-helpers.ps1`, immediately after `Get-VerityRemoteProvider` (added in Task 2):

```powershell
# Sets which Ollama model AISettings.aiModel/ollama_ai_model points at.
# Independent of Set-VerityAiProvider's local/remote toggle - ships with
# only one caller-supplied value today (the GUI's single-entry dropdown),
# but the write path exists now so adding a second model later is a list
# edit in HomeScreen.xaml, not new code here.
function Set-VerityOllamaModel {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][string]$Model
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8
    $isOldSchema = Test-VerityOldSchema -Content ($lines -join "`n") -InstancePath $InstancePath
    if ($isOldSchema) {
        $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiModel" -Value $Model
    } else {
        $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_ai_model" -Value $Model
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/verity-helpers.tests.ps1"`
Expected: PASS, all `Set-VerityOllamaModel` tests green alongside the pre-existing ones.

- [ ] **Step 5: Add the model dropdown to `HomeScreen.xaml`**

Task 2 left `VerityAiPanel`'s `Grid` with 6 `RowDefinition`s and `VerityAiStopAllButton` at `Grid.Row="5"`. Change to 7 rows:

```xml
        <Grid>
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

Change `VerityAiStopAllButton`'s `Grid.Row="5"` to `Grid.Row="6"`, and insert the new model row immediately before it (between the provider `Grid Grid.Row="4"` block Task 2 added and this button):

```xml
            <Grid Grid.Row="5" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="LOCAL MODEL (OLLAMA)" Foreground="{StaticResource MutedTextBrush}"
                           FontFamily="Segoe UI Semibold" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <ComboBox Grid.Column="1" x:Name="VerityOllamaModelCombo" FontFamily="Segoe UI" FontSize="12"
                          Background="{StaticResource PanelElevatedBrush}" Foreground="{StaticResource TextBrush}"
                          BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="6,4">
                    <ComboBoxItem Content="timheinrich2011/verity-3b"/>
                </ComboBox>
            </Grid>

            <Button Grid.Row="6" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
```

- [ ] **Step 6: Wire the dropdown in `Start-Gui.ps1`**

`Start-Gui.ps1`'s Verity element lookups now include (after Task 2's Step 6):

```powershell
$verityProviderCombo = $homeRoot.FindName("VerityProviderCombo")
```

Add right after it:

```powershell
$verityOllamaModelCombo = $homeRoot.FindName("VerityOllamaModelCombo")
```

In `$serverCombo.Add_SelectionChanged`, right after the `$currentProvider`/`$verityProviderCombo.SelectedItem = ...` lines Task 2 added, add:

```powershell
    if ($verityOllamaModelCombo.Items.Count -gt 0) { $verityOllamaModelCombo.SelectedIndex = 0 }
```

Right after the `$verityProviderCombo.Add_SelectionChanged` block Task 2 added, add:

```powershell
$verityOllamaModelCombo.Add_SelectionChanged({
    if (-not $script:selected -or $verityOllamaModelCombo.SelectedIndex -lt 0) { return }
    try {
        Set-VerityOllamaModel -InstancePath $script:selected.Path -Model $verityOllamaModelCombo.SelectedItem.Content.ToString()
    } catch { }
})
```

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS, all tests green.

- [ ] **Step 8: Manual smoke check**

Launch the app for real against a Verity-enabled server: confirm the "LOCAL MODEL (OLLAMA)" dropdown appears with its one entry pre-selected, and that toggling the Ollama sidecar on/off (existing START/STOP button) still works exactly as before.

- [ ] **Step 9: Commit**

```bash
git add _shared/scripts/verity-helpers.ps1 _shared/gui/HomeScreen.xaml Start-Gui.ps1 tests/verity-helpers.tests.ps1
git commit -m "feat: add local Ollama model dropdown to the Verity panel"
```

---

## Self-Review Notes

- **Spec coverage:** Fallback fix (Goal 1-2) → Task 1. Remote provider dropdown (Goal 3) → Task 2. Local model dropdown (Goal 4) → Task 3. The spec's "new-server default is already remote" correction required no task — confirmed as already-correct mod behavior, not something to build.
- **No placeholders:** every step has literal code, no "add appropriate X".
- **Type/name consistency:** `Set-VerityRemoteProvider -InstancePath <string> -Provider <ValidateSet(...)>` and `Get-VerityRemoteProvider -InstancePath <string> -> [string]` (Task 2) match their use in Task 2's `Start-Gui.ps1` wiring exactly. `Set-VerityOllamaModel -InstancePath <string> -Model <string>` (Task 3) matches its use in Task 3's wiring. All three follow the exact parameter-naming and schema-branching convention already established by `Set-VerityAiProvider`/`Get-VerityApiKey` in the existing codebase.

## After This Plan Lands

No follow-up manual action required. If a second Ollama model is ever added, that's a small follow-up: add a `ComboBoxItem` to `VerityOllamaModelCombo` and a `Get-VerityOllamaModel` reader (mirroring `Get-VerityRemoteProvider`) to correctly pre-select per-server on switch — deliberately deferred here since only one model exists today.
