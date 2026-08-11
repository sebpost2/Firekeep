# Server Settings Editor (server.properties) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user view and change a server's `server.properties` day-to-day
settings (difficulty, PvP, whitelist, max players, MOTD, spawn protection)
from a new in-app screen, plus an advanced raw-text escape hatch for
anything else in the file — without ever exposing the RCON lines the app
depends on for Stop Server.

**Architecture:** New pure-logic helper file
(`_shared\scripts\server-settings-helpers.ps1`) provides defaults, the
curated/protected key lists, numeric clamping, and raw-text extraction —
all unit-testable without a UI, following the same split the codebase
already uses for `worlds-helpers.ps1` / `gui-helpers.ps1`. A new
`ServerSettingsScreen.xaml` (mirroring `ManageMapsScreen.xaml`) is wired
into `Start-Gui.ps1`'s existing single-window screen-swap shell. Reads use
the existing `Read-ServerProperties` (`rcon.ps1`); writes reuse the
existing, already-tested `Set-ServerProperty` (`worlds-helpers.ps1`) — no
new file-writing logic needed.

**Tech Stack:** PowerShell + WPF/XAML (existing app), Pester 3/4-style
tests (`Describe`/`It`/`Should Be`, matching `tests/worlds-helpers.tests.ps1`).

## Global Constraints

- Curated fields cover exactly: difficulty, PvP, whitelist, max players,
  MOTD, spawn protection. No other `server.properties` keys get dedicated
  controls (per spec).
- `enable-rcon`, `rcon.port`, `rcon.password` are never shown or editable
  in either the curated or advanced view, in any task.
- Editing is stopped-only, matching the existing Manage Maps precedent —
  re-checked at Save time (not just on screen entry), the same way
  `Test-MapsServerRunning` is re-checked inside each Manage Maps button
  handler rather than trusted from entry time.
- All `server.properties` file I/O goes through the existing
  `Get-ServerProperty`/`Set-ServerProperty` (`worlds-helpers.ps1`) and
  `Read-ServerProperties` (`rcon.ps1`) — do not duplicate a second
  read/write implementation (spec originally proposed new
  `Write-ServerProperties`/`Read-ServerProperties`-style helpers; research
  during planning found equivalent, already-tested functions exist —
  reuse them instead, per the codebase's existing convention).
- File encoding for `server.properties` reads/writes: `-Encoding ascii`,
  matching every existing touch point (`New-ServerFromTemplate`,
  `Set-ServerProperty`, `Get-ServerProperty`).
- Test style: old Pester syntax (`Should Be`, not `Should -Be`) — matches
  every existing test file in `tests/`.

---

## Task 1: Pure logic helpers — defaults, protected keys, clamping, advanced-text extraction

**Files:**
- Create: `_shared\scripts\server-settings-helpers.ps1`
- Test: `tests\server-settings-helpers.tests.ps1`

**Interfaces:**
- Consumes: nothing from other tasks (pure, first task).
- Produces (used by Task 5's Start-Gui.ps1 wiring):
  - `Get-ServerPropertyDefaults() -> [hashtable]` — key/value defaults for
    the 6 curated keys.
  - `Get-ProtectedPropertyKeys() -> [string[]]` — `@("enable-rcon", "rcon.port", "rcon.password")`.
  - `Get-CuratedPropertyValues([hashtable]$Props) -> [hashtable]` — the 6
    curated keys, each filled from `$Props` if present else from
    `Get-ServerPropertyDefaults`.
  - `ConvertTo-ClampedInt([string]$Value, [string]$FallbackValue) -> [string]` —
    parses `$Value` as a non-negative integer; returns it (as string) if
    valid, else returns `$FallbackValue` unchanged.
  - `Get-AdvancedPropertiesText([string]$Path) -> [string]` — raw file
    content (CRLF-joined lines) with lines for protected keys AND curated
    keys removed (comments and all other keys pass through unchanged).
  - `Save-AdvancedPropertiesLines([string]$Path, [string]$Text)` — parses
    `$Text` line by line, calling the existing `Set-ServerProperty` for
    each `key=value` line whose key is NOT in `Get-ProtectedPropertyKeys`
    or `Get-ServerPropertyDefaults`'s keys (defense in depth — those keys
    should never appear in `$Text` in the first place since
    `Get-AdvancedPropertiesText` already excludes them, but a pasted-in
    line must not silently override RCON or fight the curated fields).
    Depends on `Set-ServerProperty` from `worlds-helpers.ps1` (dot-sourced
    by the caller — see step 6).

- [ ] **Step 1: Write the failing tests for the defaults/protected-key/clamp functions**

Create `tests\server-settings-helpers.tests.ps1`:

```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\server-settings-helpers.ps1")

Describe "Get-ServerPropertyDefaults" {
    It "has all 6 curated keys with sensible defaults" {
        $d = Get-ServerPropertyDefaults
        $d["difficulty"]       | Should Be "easy"
        $d["pvp"]              | Should Be "true"
        $d["white-list"]       | Should Be "false"
        $d["max-players"]      | Should Be "20"
        $d["motd"]             | Should Be "A Minecraft Server"
        $d["spawn-protection"] | Should Be "16"
    }
}

Describe "Get-ProtectedPropertyKeys" {
    It "returns exactly the 3 RCON keys" {
        (Get-ProtectedPropertyKeys) -join "," | Should Be "enable-rcon,rcon.port,rcon.password"
    }
}

Describe "Get-CuratedPropertyValues" {
    It "uses file values when present" {
        $props = @{ "difficulty" = "hard"; "pvp" = "false" }
        $result = Get-CuratedPropertyValues -Props $props
        $result["difficulty"] | Should Be "hard"
        $result["pvp"]        | Should Be "false"
    }

    It "falls back to defaults for keys missing from the file" {
        $result = Get-CuratedPropertyValues -Props @{}
        $result["max-players"] | Should Be "20"
        $result["motd"]        | Should Be "A Minecraft Server"
    }
}

Describe "ConvertTo-ClampedInt" {
    It "accepts a valid non-negative integer" {
        ConvertTo-ClampedInt -Value "42" -FallbackValue "20" | Should Be "42"
    }
    It "falls back on a negative number" {
        ConvertTo-ClampedInt -Value "-5" -FallbackValue "20" | Should Be "20"
    }
    It "falls back on non-numeric input" {
        ConvertTo-ClampedInt -Value "abc" -FallbackValue "16" | Should Be "16"
    }
    It "falls back on empty input" {
        ConvertTo-ClampedInt -Value "" -FallbackValue "16" | Should Be "16"
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\server-settings-helpers.tests.ps1"`
Expected: FAIL — `server-settings-helpers.ps1` doesn't exist yet (dot-source throws).

- [ ] **Step 3: Implement `Get-ServerPropertyDefaults`, `Get-ProtectedPropertyKeys`, `Get-CuratedPropertyValues`, `ConvertTo-ClampedInt`**

Create `_shared\scripts\server-settings-helpers.ps1`:

```powershell
# Pure logic behind the Server Settings screen (Start-Gui.ps1). Reads go
# through Read-ServerProperties (rcon.ps1); writes go through the existing
# Set-ServerProperty (worlds-helpers.ps1) - this file adds no new
# server.properties I/O of its own, only the curated-field/defaults/
# protection logic layered on top. Loaded via dot-source.

# Minecraft's own hard-coded defaults for the curated fields, used to
# pre-fill the form when a brand-new server's server.properties doesn't
# have these keys yet (only the RCON lines exist until Minecraft's first
# boot populates the rest).
function Get-ServerPropertyDefaults {
    return @{
        "difficulty"       = "easy"
        "pvp"              = "true"
        "white-list"       = "false"
        "max-players"      = "20"
        "motd"             = "A Minecraft Server"
        "spawn-protection" = "16"
    }
}

# Keys the Server Settings screen must never show or let a user edit -
# auto-generated at server creation (New-ServerFromTemplate) and required
# by the existing Stop Server flow. Clearing/editing them would silently
# break Stop Server.
function Get-ProtectedPropertyKeys {
    return @("enable-rcon", "rcon.port", "rcon.password")
}

# Merges a server.properties hashtable (from Read-ServerProperties) with
# the curated defaults - file value wins when present, default fills gaps.
function Get-CuratedPropertyValues {
    param([Parameter(Mandatory = $true)][hashtable]$Props)
    $defaults = Get-ServerPropertyDefaults
    $result = @{}
    foreach ($key in $defaults.Keys) {
        $result[$key] = if ($Props.ContainsKey($key)) { $Props[$key] } else { $defaults[$key] }
    }
    return $result
}

# Validates a numeric field (max players, spawn protection) without
# blocking Save - invalid input just reverts to the last known-good value.
function ConvertTo-ClampedInt {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$FallbackValue
    )
    $parsed = 0
    if ([int]::TryParse($Value.Trim(), [ref]$parsed) -and $parsed -ge 0) {
        return [string]$parsed
    }
    return $FallbackValue
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\server-settings-helpers.tests.ps1"`
Expected: PASS (all `It` blocks green).

- [ ] **Step 5: Write the failing tests for advanced-text extraction and saving**

Append to `tests\server-settings-helpers.tests.ps1`:

```powershell
Describe "Get-AdvancedPropertiesText / Save-AdvancedPropertiesLines" {
    $propsPath = Join-Path $env:TEMP ("server-settings-helpers-" + [Guid]::NewGuid().ToString("N") + ".properties")

    BeforeEach {
        @(
            "#Minecraft server properties"
            "enable-rcon=true"
            "rcon.port=25575"
            "rcon.password=secret123"
            "difficulty=easy"
            "pvp=true"
            "white-list=false"
            "max-players=20"
            "motd=A Minecraft Server"
            "spawn-protection=16"
            "level-seed=12345"
            "online-mode=true"
        ) | Set-Content -Path $propsPath -Encoding ascii
    }

    It "excludes protected and curated keys, keeps everything else" {
        $text = Get-AdvancedPropertiesText -Path $propsPath
        $text | Should Not Match "rcon"
        $text | Should Not Match "difficulty"
        $text | Should Match "level-seed=12345"
        $text | Should Match "online-mode=true"
    }

    It "returns empty string for a missing file" {
        Get-AdvancedPropertiesText -Path (Join-Path $env:TEMP "no-such-file.properties") | Should Be ""
    }

    It "saves non-protected, non-curated keys from the advanced text" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "level-seed=99999`r`nonline-mode=false"
        Get-ServerProperty $propsPath "level-seed"  | Should Be "99999"
        Get-ServerProperty $propsPath "online-mode" | Should Be "false"
    }

    It "never lets advanced text override protected keys" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "rcon.password=hacked"
        Get-ServerProperty $propsPath "rcon.password" | Should Be "secret123"
    }

    It "never lets advanced text override curated keys" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "difficulty=hard"
        Get-ServerProperty $propsPath "difficulty" | Should Be "easy"
    }

    Remove-Item -Path $propsPath, "$propsPath.bak" -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\server-settings-helpers.tests.ps1"`
Expected: FAIL — `Get-AdvancedPropertiesText`/`Save-AdvancedPropertiesLines` not defined, and `Get-ServerProperty`/`Set-ServerProperty` not yet dot-sourced in the test file.

- [ ] **Step 7: Implement `Get-AdvancedPropertiesText` and `Save-AdvancedPropertiesLines`**

Add to the top of `tests\server-settings-helpers.tests.ps1` (below the existing dot-source line), since these two functions call `Set-ServerProperty`/`Get-ServerProperty`:

```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\worlds-helpers.ps1")
```

Append to `_shared\scripts\server-settings-helpers.ps1`:

```powershell
# Raw server.properties content for the advanced/escape-hatch text box,
# with protected (RCON) and curated (already editable via the form) key
# lines stripped out - comments and every other key pass through as-is.
# Excluding curated keys too (not just protected ones) avoids the same
# key being editable in two places at once with no defined winner.
function Get-AdvancedPropertiesText {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    $skip = @(Get-ProtectedPropertyKeys) + @((Get-ServerPropertyDefaults).Keys)
    $lines = Get-Content -Path $Path -Encoding ascii | Where-Object {
        if ($_ -match '^\s*#') { return $true }
        $idx = $_.IndexOf('=')
        if ($idx -lt 1) { return $true }
        $key = $_.Substring(0, $idx).Trim()
        return -not ($skip -contains $key)
    }
    return ($lines -join "`r`n")
}

# Writes back whatever key=value lines the user left in the advanced text
# box, via the existing Set-ServerProperty (worlds-helpers.ps1) - one call
# per key, preserving the rest of the file untouched. Protected and
# curated keys are refused even if present in the text (defense in depth;
# Get-AdvancedPropertiesText already keeps them out of that text in normal
# use).
function Save-AdvancedPropertiesLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $skip = @(Get-ProtectedPropertyKeys) + @((Get-ServerPropertyDefaults).Keys)
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*#') { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1)
        if ($skip -contains $key) { continue }
        Set-ServerProperty $Path $key $val
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\server-settings-helpers.tests.ps1"`
Expected: PASS (all `It` blocks green).

- [ ] **Step 9: Commit**

```bash
git add _shared/scripts/server-settings-helpers.ps1 tests/server-settings-helpers.tests.ps1
git commit -m "feat: add pure logic helpers for the server settings editor"
```

---

## Task 2: Screen navigation wiring — Get-ScreenSize / Get-BackTarget

**Files:**
- Modify: `_shared\scripts\gui-helpers.ps1:83-109`
- Test: `tests\gui-helpers.tests.ps1`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Get-ScreenSize -Screen "ServerSettings"` and
  `Get-BackTarget -Screen "ServerSettings"`, used by Task 5's
  `Show-Screen`/`Enter-ServerSettingsScreen` wiring.

- [ ] **Step 1: Write the failing tests**

Add to `tests\gui-helpers.tests.ps1`, inside the existing `Describe "Get-ScreenSize"` and `Describe "Get-BackTarget"` blocks (alongside the existing `It "ManageMaps"` etc. cases):

```powershell
    It "returns the ServerSettings size" {
        $s = Get-ScreenSize -Screen "ServerSettings"
        $s.Width  | Should Be 480
        $s.Height | Should Be 640
    }
```

```powershell
    It "returns Home for ServerSettings" {
        Get-BackTarget -Screen "ServerSettings" | Should Be "Home"
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\gui-helpers.tests.ps1"`
Expected: FAIL — both new `It` blocks throw "Unrecognized screen 'ServerSettings'."

- [ ] **Step 3: Add the "ServerSettings" case to both switches**

In `_shared\scripts\gui-helpers.ps1`, `Get-ScreenSize` (around line 87-93):

```powershell
    switch ($Screen) {
        "Home"           { return [PSCustomObject]@{ Width = 640; Height = 860 } }
        "ManageMaps"     { return [PSCustomObject]@{ Width = 480; Height = 640 } }
        "AddServer"      { return [PSCustomObject]@{ Width = 480; Height = 580 } }
        "Console"        { return [PSCustomObject]@{ Width = 640; Height = 720 } }
        "ServerSettings" { return [PSCustomObject]@{ Width = 480; Height = 640 } }
        default { throw "Unrecognized screen '$Screen'." }
    }
```

`Get-BackTarget` (around line 102-108):

```powershell
    switch ($Screen) {
        "Home"           { return $null }
        "ManageMaps"     { return "Home" }
        "AddServer"      { return "Home" }
        "Console"        { return "Home" }
        "ServerSettings" { return "Home" }
        default { throw "Unrecognized screen '$Screen'." }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\gui-helpers.tests.ps1"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add _shared/scripts/gui-helpers.ps1 tests/gui-helpers.tests.ps1
git commit -m "feat: register the ServerSettings screen size and back target"
```

---

## Task 3: ServerSettingsScreen.xaml + window host + headless load test

**Files:**
- Create: `_shared\gui\ServerSettingsScreen.xaml`
- Modify: `_shared\gui\MainWindow.xaml`
- Modify: `tests\gui-load.tests.ps1`

**Interfaces:**
- Consumes: `LabelStyle`, `ActionButtonStyle`, `LinkButtonStyle`,
  `BackButtonStyle`, `TextBrush`, `MutedTextBrush` (all already defined in
  `Theme.xaml`, same resources `ManageMapsScreen.xaml`/`AddServerScreen.xaml`
  already use).
- Produces (named elements Task 5's `Start-Gui.ps1` wiring will
  `FindName()`): `BackButton`, `SubtitleText`, `DifficultyCombo`,
  `PvpCheck`, `WhitelistCheck`, `MaxPlayersBox`, `MotdBox`,
  `SpawnProtectionBox`, `AdvancedToggleButton`, `AdvancedBox`, `HintText`,
  `SaveButton`. Also `MainWindow.xaml`'s new `SettingsHost` ContentControl
  name.

- [ ] **Step 1: Create the screen XAML**

Create `_shared\gui\ServerSettingsScreen.xaml`:

```xml
<Grid
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Margin="28">

    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Button Grid.Column="0" x:Name="BackButton" Content="&#xE72B;" Style="{StaticResource BackButtonStyle}" Margin="0,0,8,0"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
            <TextBlock Text="SERVER SETTINGS" Foreground="{StaticResource TextBrush}"
                       FontFamily="Segoe UI Black" FontSize="22"/>
            <TextBlock x:Name="SubtitleText" Text="" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI" FontSize="12" Margin="0,4,0,0"/>
        </StackPanel>
    </Grid>

    <TextBlock Grid.Row="1" Text="Difficulty" Style="{StaticResource LabelStyle}"/>
    <ComboBox Grid.Row="2" x:Name="DifficultyCombo">
        <ComboBoxItem Content="peaceful"/>
        <ComboBoxItem Content="easy"/>
        <ComboBoxItem Content="normal"/>
        <ComboBoxItem Content="hard"/>
    </ComboBox>

    <CheckBox Grid.Row="3" x:Name="PvpCheck" Content="Allow PvP" Margin="0,14,0,0"
              Foreground="{StaticResource TextBrush}" FontFamily="Segoe UI" FontSize="12"/>
    <CheckBox Grid.Row="4" x:Name="WhitelistCheck" Content="Whitelist only" Margin="0,10,0,0"
              Foreground="{StaticResource TextBrush}" FontFamily="Segoe UI" FontSize="12"/>

    <TextBlock Grid.Row="5" Text="Max players" Style="{StaticResource LabelStyle}" Margin="0,14,0,0"/>
    <TextBox Grid.Row="6" x:Name="MaxPlayersBox"/>

    <TextBlock Grid.Row="7" Text="Server name (MOTD)" Style="{StaticResource LabelStyle}"/>
    <TextBox Grid.Row="8" x:Name="MotdBox"/>

    <TextBlock Grid.Row="9" Text="Spawn protection radius" Style="{StaticResource LabelStyle}"/>
    <TextBox Grid.Row="10" x:Name="SpawnProtectionBox"/>

    <Button Grid.Row="11" x:Name="AdvancedToggleButton" Content="Show advanced settings"
            Style="{StaticResource LinkButtonStyle}" HorizontalAlignment="Left" Margin="0,16,0,0"/>
    <TextBox Grid.Row="12" x:Name="AdvancedBox" Visibility="Collapsed"
             FontFamily="Consolas" FontSize="12" AcceptsReturn="True" TextWrapping="NoWrap"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             MinHeight="120" Margin="0,8,0,0"/>

    <TextBlock Grid.Row="13" x:Name="HintText" Text=" " Foreground="{StaticResource MutedTextBrush}"
               FontFamily="Segoe UI" FontSize="12" Margin="0,14,0,14" TextWrapping="Wrap"/>

    <Button Grid.Row="14" x:Name="SaveButton" Content="SAVE" Style="{StaticResource ActionButtonStyle}"/>
</Grid>
```

- [ ] **Step 2: Add the window host**

In `_shared\gui\MainWindow.xaml`, add a new `ContentControl` alongside the
existing hosts (inside the same `<Grid>`, after `ConsoleHost`):

```xml
        <ContentControl x:Name="SettingsHost" Focusable="False" Visibility="Collapsed"/>
```

- [ ] **Step 3: Add the new screen to the headless load test**

In `tests\gui-load.tests.ps1`, add `"ServerSettingsScreen.xaml"` to the
`$screenFiles` array (after `"ManageMapsScreen.xaml"`):

```powershell
$screenFiles = @(
    "MainWindow.xaml",
    "HomeScreen.xaml",
    "ManageMapsScreen.xaml",
    "ServerSettingsScreen.xaml",
    "AddServerScreen.xaml",
    "ConsoleScreen.xaml",
    "PromptOverlay.xaml"
)
```

- [ ] **Step 4: Run the headless load test**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\gui-load.tests.ps1"`
Expected: PASS — `ServerSettingsScreen.xaml` loads without a
`XamlParseException`, same as every other screen.

- [ ] **Step 5: Commit**

```bash
git add _shared/gui/ServerSettingsScreen.xaml _shared/gui/MainWindow.xaml tests/gui-load.tests.ps1
git commit -m "feat: add the Server Settings screen XAML and window host"
```

---

## Task 4: Home screen entry point button

**Files:**
- Modify: `_shared\gui\HomeScreen.xaml:127-152`

**Interfaces:**
- Consumes: `LinkButtonStyle`, `IconGlyphStyle` (existing `Theme.xaml`
  resources, same ones `MapsButton`/`ConsoleButton` already use).
- Produces: a `SettingsButton` named element for Task 5's `Start-Gui.ps1`
  wiring to `FindName()` and attach a click handler to.

- [ ] **Step 1: Add the button**

In `_shared\gui\HomeScreen.xaml`, add a new `Button` to the existing
`WrapPanel` (Grid.Row="5"), right after `MapsButton`:

```xml
        <Button x:Name="SettingsButton" Style="{StaticResource LinkButtonStyle}">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE713;" Style="{StaticResource IconGlyphStyle}"/>
                <TextBlock Text="Server Settings"/>
            </StackPanel>
        </Button>
```

- [ ] **Step 2: Run the headless load test to confirm HomeScreen.xaml still loads**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests\gui-load.tests.ps1"`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add _shared/gui/HomeScreen.xaml
git commit -m "feat: add Server Settings button to the Home screen"
```

---

## Task 5: Wire the screen into Start-Gui.ps1 (populate, save, running-guard)

**Files:**
- Modify: `Start-Gui.ps1`

**Interfaces:**
- Consumes: `Get-ServerPropertyDefaults`, `Get-ProtectedPropertyKeys`,
  `Get-CuratedPropertyValues`, `ConvertTo-ClampedInt`,
  `Get-AdvancedPropertiesText`, `Save-AdvancedPropertiesLines` (Task 1);
  `Get-ScreenSize -Screen "ServerSettings"`, `Get-BackTarget -Screen "ServerSettings"`
  (Task 2); the `SettingsHost` content control (Task 3); the
  `BackButton`/`SubtitleText`/`DifficultyCombo`/`PvpCheck`/`WhitelistCheck`/
  `MaxPlayersBox`/`MotdBox`/`SpawnProtectionBox`/`AdvancedToggleButton`/
  `AdvancedBox`/`HintText`/`SaveButton` named elements (Task 3); the
  `SettingsButton` named element (Task 4); existing
  `Read-ServerProperties` (`rcon.ps1`), `Set-ServerProperty`
  (`worlds-helpers.ps1`), `Test-PortOpen` (`rcon.ps1`),
  `Get-SelectedRconPort` (`Start-Gui.ps1:158`).
- Produces: nothing consumed by later tasks — this is the last wiring
  task.

This task has no isolated unit test (event-handler wiring in
`Start-Gui.ps1` isn't unit tested anywhere in this codebase — the
established pattern is: pure logic lives in helper files and gets Pester
tests, wiring gets the headless XAML-load test plus a manual smoke test).
Steps below substitute a manual verification checklist for the usual
red/green test cycle, matching how `ManageMapsScreen`'s wiring was
verified.

- [ ] **Step 1: Dot-source the new helper file**

In `Start-Gui.ps1`, add to the dot-source block near the top (after line 17,
`. (Join-Path $root "_shared\scripts\new-server-helpers.ps1")`):

```powershell
. (Join-Path $root "_shared\scripts\server-settings-helpers.ps1")
```

- [ ] **Step 2: Load the screen and wire the window host**

Near the existing screen-loading block (around line 46-56), add:

```powershell
$settingsRoot = Get-ScreenXaml "ServerSettingsScreen.xaml"
```

and:

```powershell
$settingsHost.Content = $settingsRoot
```

(add `$settingsHost = $window.FindName("SettingsHost")` alongside the
other `$window.FindName(...)` calls around line 40-44).

- [ ] **Step 3: Add the screen to `Show-Screen`**

In the `Show-Screen` function (around line 68-80), add:

```powershell
    $settingsHost.Visibility = if ($Screen -eq "ServerSettings") { "Visible" } else { "Collapsed" }
```

- [ ] **Step 4: FindName the Home screen's new button and the new screen's controls**

Near the existing Home screen `FindName` block (around line 84-98), add:

```powershell
$settingsButton = $homeRoot.FindName("SettingsButton")
```

Near the existing Manage Maps `FindName` block (search for
`$mapsBackButton = $mapsRoot.FindName`), add a matching block for the new
screen:

```powershell
$settingsBackButton      = $settingsRoot.FindName("BackButton")
$settingsSubtitleText    = $settingsRoot.FindName("SubtitleText")
$difficultyCombo         = $settingsRoot.FindName("DifficultyCombo")
$pvpCheck                = $settingsRoot.FindName("PvpCheck")
$whitelistCheck          = $settingsRoot.FindName("WhitelistCheck")
$maxPlayersBox           = $settingsRoot.FindName("MaxPlayersBox")
$motdBox                 = $settingsRoot.FindName("MotdBox")
$spawnProtectionBox      = $settingsRoot.FindName("SpawnProtectionBox")
$advancedToggleButton    = $settingsRoot.FindName("AdvancedToggleButton")
$advancedBox             = $settingsRoot.FindName("AdvancedBox")
$settingsHintText        = $settingsRoot.FindName("HintText")
$saveSettingsButton      = $settingsRoot.FindName("SaveButton")
```

- [ ] **Step 5: Add `Enter-ServerSettingsScreen` and populate logic**

Add this function near `Enter-ManageMapsScreen` (around line 488):

```powershell
# Called from the Home screen's "Server Settings" click, right before
# showing this screen, so it always reflects whichever server is currently
# selected and the file's current on-disk state.
function Enter-ServerSettingsScreen {
    $script:settingsPropsPath = Join-Path $script:selected.Path "server.properties"
    $settingsSubtitleText.Text = $script:selected.Name

    $props = Read-ServerProperties $script:settingsPropsPath
    $curated = Get-CuratedPropertyValues -Props $props

    $difficultyCombo.SelectedItem = $difficultyCombo.Items | Where-Object { $_.Content -eq $curated["difficulty"] } | Select-Object -First 1
    $pvpCheck.IsChecked = ($curated["pvp"] -eq "true")
    $whitelistCheck.IsChecked = ($curated["white-list"] -eq "true")
    $maxPlayersBox.Text = $curated["max-players"]
    $motdBox.Text = $curated["motd"]
    $spawnProtectionBox.Text = $curated["spawn-protection"]

    $advancedBox.Text = Get-AdvancedPropertiesText -Path $script:settingsPropsPath
    $advancedBox.Visibility = "Collapsed"
    $advancedToggleButton.Content = "Show advanced settings"

    if (Test-PortOpen -Port (Get-SelectedRconPort)) {
        $settingsHintText.Text = "The server looks like it's running - stop it first to make changes."
    } else {
        $settingsHintText.Text = " "
    }
}

$settingsBackButton.Add_Click({ Show-Screen "Home" })

$advancedToggleButton.Add_Click({
    if ($advancedBox.Visibility -eq "Visible") {
        $advancedBox.Visibility = "Collapsed"
        $advancedToggleButton.Content = "Show advanced settings"
    } else {
        $advancedBox.Visibility = "Visible"
        $advancedToggleButton.Content = "Hide advanced settings"
    }
})

$saveSettingsButton.Add_Click({
    if (Test-PortOpen -Port (Get-SelectedRconPort)) {
        $settingsHintText.Text = "Stop the server before saving changes."
        return
    }

    $props = Read-ServerProperties $script:settingsPropsPath
    $curated = Get-CuratedPropertyValues -Props $props

    Set-ServerProperty $script:settingsPropsPath "difficulty" $difficultyCombo.SelectedItem.Content
    Set-ServerProperty $script:settingsPropsPath "pvp" (if ($pvpCheck.IsChecked) { "true" } else { "false" })
    Set-ServerProperty $script:settingsPropsPath "white-list" (if ($whitelistCheck.IsChecked) { "true" } else { "false" })
    Set-ServerProperty $script:settingsPropsPath "max-players" (ConvertTo-ClampedInt -Value $maxPlayersBox.Text -FallbackValue $curated["max-players"])
    Set-ServerProperty $script:settingsPropsPath "motd" $motdBox.Text
    Set-ServerProperty $script:settingsPropsPath "spawn-protection" (ConvertTo-ClampedInt -Value $spawnProtectionBox.Text -FallbackValue $curated["spawn-protection"])

    Save-AdvancedPropertiesLines -Path $script:settingsPropsPath -Text $advancedBox.Text

    $settingsHintText.Text = "Saved."
    Enter-ServerSettingsScreen
})
```

- [ ] **Step 6: Wire the Home screen button**

Near the existing `$mapsButton.Add_Click` handler (around line 600), add:

```powershell
$settingsButton.Add_Click({
    if (-not $script:selected) { return }
    Enter-ServerSettingsScreen
    Show-Screen "ServerSettings"
})
```

- [ ] **Step 7: Run the full test suite**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS — every existing test still green, plus the new
`server-settings-helpers.tests.ps1` and updated `gui-helpers.tests.ps1`/
`gui-load.tests.ps1`.

- [ ] **Step 8: Manual smoke test**

Run: `powershell.exe -ExecutionPolicy Bypass -File Start-Gui.ps1`

- With a stopped server selected, click **Server Settings**. Confirm the
  form shows the server's current difficulty/PvP/whitelist/max
  players/MOTD/spawn protection (or defaults, if never set).
- Change difficulty and max players, click **Save**. Confirm the hint
  says "Saved." and re-opening the screen (Back, then Server Settings
  again) shows the new values.
- Click **Show advanced settings**. Confirm the box shows other
  `server.properties` lines (e.g. `level-seed`, `online-mode`) and does
  **not** show `enable-rcon`, `rcon.port`, `rcon.password`, or any of the
  6 curated keys.
- Start the server, then try to open **Server Settings** and Save.
  Confirm the hint blocks the save with "Stop the server before saving
  changes." (or, if reached before starting, the entry hint already warns
  it's running).
- Confirm **Stop Server** still works after all the above (RCON lines
  were never touched).

- [ ] **Step 9: Commit**

```bash
git add Start-Gui.ps1
git commit -m "feat: wire the Server Settings screen into the app"
```

---

## Task 6: Changelog entry

**Files:**
- Modify: `CHANGELOG.md`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Add an entry under the existing (untagged) `[1.0.0]` heading**

In `CHANGELOG.md`, under `## [1.0.0] - 2026-08-10` → `### Added`, add a
bullet (matching the existing bullet style) documenting the new screen:

```markdown
- "Server Settings" screen (Home screen button) for editing a server's
  `server.properties` - curated controls for difficulty, PvP, whitelist,
  max players, MOTD, and spawn protection, plus an advanced raw-text view
  for anything else in the file. RCON settings are never shown/editable.
  Requires the server to be stopped.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: note the Server Settings screen in the changelog"
```
