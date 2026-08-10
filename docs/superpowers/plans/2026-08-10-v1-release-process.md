# v1.0.0 Release Process Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add version tracking (file + in-app label), a permanent automated fresh-install regression test, and release documentation so this project can cut a repeatable, tagged v1.0.0 release.

**Architecture:** Version is a single-line `VERSION` file read via a new testable `Get-AppVersion` helper in `gui-helpers.ps1` and displayed on the Home screen. The fresh-install gap is closed by reusing the existing `Get-ReleaseFiles` allow-list from `package-release.ps1` to stage a disposable copy of only the shippable files, then launching that copy's `Start-Gui.ps1` headlessly (same STA-subprocess technique as `tests/gui-load.tests.ps1`) via a new opt-in, inert-by-default `GUI_TEST_AUTOCLOSE_MS` hook. Release mechanics (`CHANGELOG.md`, `docs/RELEASE.md`) are plain files, not a new script.

**Tech Stack:** Windows PowerShell 5.1, WPF (loose XAML via `XamlReader.Load`), Pester 3.4.0 (old syntax).

## Global Constraints

- Windows PowerShell 5.1 / WPF only — no `App.xaml`, no compiled resources. Use `powershell.exe` in all bash tool invocations, never `pwsh` (not installed).
- Pester 3.4.0 uses old syntax (`Should Be`, `Should Not Be`, `Should Match`) — do not use `Should -Be` anywhere in this plan's tests.
- Run the full suite with: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`.
- `VERSION` is a single line, no JSON/YAML.
- The 3 deferred cosmetic findings from the prior GUI redesign session (type-scale drift, hardcoded literal colors, `Height="*"` row in a `ScrollViewer`) are out of scope for this plan.
- Spec: `docs/superpowers/specs/2026-08-10-v1-release-process-design.md`.

---

### Task 1: Version file + `Get-AppVersion` helper + Home screen label

**Files:**
- Create: `VERSION`
- Modify: `_shared\scripts\gui-helpers.ps1` (add `Get-AppVersion` function)
- Modify: `_shared\gui\HomeScreen.xaml:17-23` (add a `VersionText` TextBlock)
- Modify: `Start-Gui.ps1:84-94` (wire the label)
- Test: `tests\gui-helpers.tests.ps1`

**Interfaces:**
- Produces: `Get-AppVersion -Root <string>` → `[string]`. Returns the trimmed contents of `<Root>\VERSION`, or `""` if the file is missing/unreadable. Used by `Start-Gui.ps1` and by later tasks' fresh-install test indirectly (it's part of the normal startup path they exercise).

- [ ] **Step 1: Write the failing test for `Get-AppVersion`**

Add to `tests\gui-helpers.tests.ps1` (append a new `Describe` block after the existing ones, keeping the file's established style — fixture dirs under `$env:TEMP`, old Pester syntax):

```powershell
Describe "Get-AppVersion" {

    $root = Join-Path $env:TEMP ("gui-helpers-version-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "reads and trims the VERSION file contents" {
        Set-Content -Path (Join-Path $root "VERSION") -Value "1.0.0`r`n"
        Get-AppVersion -Root $root | Should Be "1.0.0"
    }

    It "returns an empty string when VERSION is missing" {
        $emptyRoot = Join-Path $env:TEMP ("gui-helpers-version-empty-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $emptyRoot | Out-Null
        Get-AppVersion -Root $emptyRoot | Should Be ""
        Remove-Item -Recurse -Force $emptyRoot -ErrorAction SilentlyContinue
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/gui-helpers.tests.ps1"`
Expected: FAIL — `Get-AppVersion` is not recognized as the name of a cmdlet/function.

- [ ] **Step 3: Implement `Get-AppVersion` in `gui-helpers.ps1`**

Add near the other small path-reading helpers in `_shared\scripts\gui-helpers.ps1` (e.g. right after `Get-ServerInstances`'s closing brace):

```powershell
# Best-effort read of the repo-root VERSION file for the Home screen label.
# Never throws - a missing/unreadable file just means no label is shown.
function Get-AppVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )
    $versionFile = Join-Path $Root "VERSION"
    if (-not (Test-Path $versionFile)) { return "" }
    try {
        return (Get-Content -Path $versionFile -Raw -ErrorAction Stop).Trim()
    } catch {
        return ""
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/gui-helpers.tests.ps1"`
Expected: PASS (all `Get-AppVersion` and pre-existing `Get-ServerInstances`/`Get-ScreenSize` tests green).

- [ ] **Step 5: Create the `VERSION` file**

Create `VERSION` at the repo root with exactly:

```
1.0.0
```

- [ ] **Step 6: Add the `VersionText` element to `HomeScreen.xaml`**

In `_shared\gui\HomeScreen.xaml`, the title block currently reads (lines 17-23):

```xml
    <!-- Title -->
    <StackPanel Grid.Row="0" Margin="0,0,0,24">
        <TextBlock Text="GAME SERVERS" Foreground="{StaticResource TextBrush}"
                   FontFamily="Segoe UI Black" FontSize="28" HorizontalAlignment="Center"/>
        <TextBlock Text="Your friends' world, one click away" Foreground="{StaticResource MutedTextBrush}"
                   FontFamily="Segoe UI" FontSize="13" HorizontalAlignment="Center" Margin="0,4,0,0"/>
    </StackPanel>
```

Add a third `TextBlock` inside that same `StackPanel`, after the subtitle, with an empty default `Text` (so it renders as nothing until `Start-Gui.ps1` sets it — matches the "never blocks launch" requirement):

```xml
    <!-- Title -->
    <StackPanel Grid.Row="0" Margin="0,0,0,24">
        <TextBlock Text="GAME SERVERS" Foreground="{StaticResource TextBrush}"
                   FontFamily="Segoe UI Black" FontSize="28" HorizontalAlignment="Center"/>
        <TextBlock Text="Your friends' world, one click away" Foreground="{StaticResource MutedTextBrush}"
                   FontFamily="Segoe UI" FontSize="13" HorizontalAlignment="Center" Margin="0,4,0,0"/>
        <TextBlock x:Name="VersionText" Text="" Foreground="{StaticResource MutedTextBrush}"
                   FontFamily="Segoe UI" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,0"/>
    </StackPanel>
```

- [ ] **Step 7: Wire the label in `Start-Gui.ps1`**

In `Start-Gui.ps1`, the Home screen element lookups currently read (lines 84-94):

```powershell
$serverCombo      = $homeRoot.FindName("ServerCombo")
$fireIcon         = $homeRoot.FindName("FireVisual")
$statusLabel      = $homeRoot.FindName("StatusLabel")
$addressText      = $homeRoot.FindName("AddressText")
$copyButton       = $homeRoot.FindName("CopyButton")
$actionButton     = $homeRoot.FindName("ActionButton")
$homeHintText     = $homeRoot.FindName("HintText")
$mapsButton       = $homeRoot.FindName("MapsButton")
$consoleButton    = $homeRoot.FindName("ConsoleButton")
$newServerButton  = $homeRoot.FindName("NewServerButton")
$setupTunnelButton = $homeRoot.FindName("SetupTunnelButton")
```

Add the version label lookup and assignment right after `$setupTunnelButton`:

```powershell
$setupTunnelButton = $homeRoot.FindName("SetupTunnelButton")
$versionText = $homeRoot.FindName("VersionText")
$appVersion = Get-AppVersion -Root $root
if ($appVersion) { $versionText.Text = "v$appVersion" }
```

- [ ] **Step 8: Commit**

```bash
git add VERSION _shared/scripts/gui-helpers.ps1 _shared/gui/HomeScreen.xaml Start-Gui.ps1 tests/gui-helpers.tests.ps1
git commit -m "feat: add VERSION file and Home screen version label"
```

---

### Task 2: Test-only auto-close hook + fresh-install regression test

**Files:**
- Modify: `Start-Gui.ps1:994-996` (add opt-in `GUI_TEST_AUTOCLOSE_MS` hook)
- Create: `tests\fresh-install.tests.ps1`

**Interfaces:**
- Consumes: `Get-ReleaseFiles -Root <string>` → `[string[]]` of full file paths (already defined in `_shared\scripts\package-release.ps1`, loadable via `. package-release.ps1 -TestOnlyLoadFunctions`, no changes needed to that file).
- Consumes: `Get-AppVersion` (Task 1) is exercised indirectly — this test launches the real `Start-Gui.ps1`, which calls it.
- Produces: nothing consumed by later tasks; this is the terminal regression guard.

- [ ] **Step 1: Write the failing test**

Create `tests\fresh-install.tests.ps1`:

```powershell
# Regression test for the "nobody has ever launched this on a clean
# machine" gap: stages a disposable copy containing ONLY the files that
# ship in a real release (same allow-list package-release.ps1 uses - so
# it has zero server instances, no Java runtime, no playit secrets), then
# launches that copy's Start-Gui.ps1 for real, headlessly, and confirms it
# starts up and shuts down cleanly with nothing pre-existing. WPF requires
# STA and Pester doesn't run in STA by default, so - same technique as
# gui-load.tests.ps1 - this spawns a real STA powershell.exe subprocess.

$repoRoot = Split-Path -Parent $PSScriptRoot

Describe "Fresh install (headless, STA, zero prior state)" {

    $stageRoot = Join-Path $env:TEMP ("fresh-install-stage-" + [Guid]::NewGuid().ToString("N"))
    $resultsFile = Join-Path $env:TEMP ("fresh-install-results-" + [Guid]::NewGuid().ToString("N") + ".txt")

    It "stages a fresh copy containing only the release file set" {
        . (Join-Path $repoRoot "_shared\scripts\package-release.ps1") -TestOnlyLoadFunctions
        $files = Get-ReleaseFiles -Root $repoRoot
        $files.Count | Should BeGreaterThan 0

        foreach ($f in $files) {
            $rel = $f.Substring($repoRoot.Length).TrimStart('\')
            $dest = Join-Path $stageRoot $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -Path $f -Destination $dest -Force
        }

        (Test-Path (Join-Path $stageRoot "Start-Gui.ps1")) | Should Be $true
    }

    It "has no real server instances in the staged copy (the actual fresh-machine condition)" {
        $serversDir = Join-Path $stageRoot "Minecraft\servers"
        $instanceDirs = @(Get-ChildItem -Path $serversDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "_template" })
        $instanceDirs.Count | Should Be 0
    }

    It "launches Start-Gui.ps1 from the staged copy without throwing" {
        $subScript = @"
`$ErrorActionPreference = 'Stop'
`$env:GUI_TEST_AUTOCLOSE_MS = '3000'
try {
    & '$stageRoot\Start-Gui.ps1'
    Set-Content -Path '$resultsFile' -Value 'OK'
} catch {
    Set-Content -Path '$resultsFile' -Value "FAIL:`$(`$_.Exception.Message)"
}
"@
        $tempScriptFile = Join-Path $env:TEMP ("fresh-install-test-" + [Guid]::NewGuid().ToString("N") + ".ps1")
        Set-Content -Path $tempScriptFile -Value $subScript

        & powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File $tempScriptFile
        $exitCode = $LASTEXITCODE

        $script:result = if (Test-Path $resultsFile) { Get-Content $resultsFile -Raw } else { "NO RESULT FILE" }

        Remove-Item -Path $tempScriptFile -ErrorAction SilentlyContinue
        Remove-Item -Path $resultsFile -ErrorAction SilentlyContinue

        $exitCode | Should Be 0
        $script:result | Should Match "^OK"
    }

    Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/fresh-install.tests.ps1"`
Expected: the first two `It` blocks pass (staging logic works using the pre-existing `Get-ReleaseFiles`), but the third fails — `Start-Gui.ps1` blocks forever on `$window.ShowDialog()` since `GUI_TEST_AUTOCLOSE_MS` isn't honored yet (the test will hang/timeout, or the subprocess will need to be killed manually the first time — that's expected, it's the "fails" step proving the hook doesn't exist yet). If it hangs, cancel it (Ctrl+C) before continuing to Step 3.

- [ ] **Step 3: Implement the auto-close hook in `Start-Gui.ps1`**

`Start-Gui.ps1` currently ends with (lines 992-996):

```powershell
Sync-StatusDisplay | Out-Null
Update-AddressDisplay
Show-Screen "Home"

$window.ShowDialog() | Out-Null
```

Change to:

```powershell
Sync-StatusDisplay | Out-Null
Update-AddressDisplay
Show-Screen "Home"

# Test-only: lets tests/fresh-install.tests.ps1 launch this script headlessly
# and close it after startup completes, without a human. Inert unless this
# env var is explicitly set - never active for a real user (Start.bat,
# manual `powershell.exe -File Start-Gui.ps1`).
if ($env:GUI_TEST_AUTOCLOSE_MS) {
    $autoCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
    $autoCloseTimer.Interval = [TimeSpan]::FromMilliseconds([int]$env:GUI_TEST_AUTOCLOSE_MS)
    $autoCloseTimer.Add_Tick({
        $autoCloseTimer.Stop()
        $script:okToClose = $true
        $window.Close()
    })
    $autoCloseTimer.Start()
}

$window.ShowDialog() | Out-Null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/fresh-install.tests.ps1"`
Expected: PASS, all 3 `It` blocks green. The subprocess launches, sits for 3 seconds, closes itself, exits 0.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS, all tests green (169 pre-existing + new `Get-AppVersion` tests + 3 new fresh-install tests).

- [ ] **Step 6: Commit**

```bash
git add Start-Gui.ps1 tests/fresh-install.tests.ps1
git commit -m "test: add permanent fresh-install regression test"
```

---

### Task 3: `CHANGELOG.md` + `docs/RELEASE.md`

**Files:**
- Create: `CHANGELOG.md`
- Create: `docs\RELEASE.md`

**Interfaces:**
- Consumes: nothing (pure documentation, references file/script names from Tasks 1-2 and the pre-existing `package-release.ps1`).
- Produces: nothing consumed by code; this is the terminal documentation task.

- [ ] **Step 1: Create `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to this project are documented here. Loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-08-10

First tracked release.

### Added
- Shared `Theme.xaml` resource dictionary consolidating styles/brushes
  previously duplicated across all 6 screens.
- Resizable main window (`MinWidth`/`MinHeight`, `ResizeMode="CanResize"`),
  replacing the old fixed-size-per-screen layout.
- Local AI (Verity) status panel redesigned as 3 sidecar cards
  (Core LLM / Voice out / Voice in), fixing cramped/overlapping text.
- Spacing and type-scale polish across Home, Console, Add Server, and
  Manage Maps screens.
- `tests/gui-load.tests.ps1` - headless regression test guarding WPF
  resource-loading order.
- `tests/fresh-install.tests.ps1` - headless regression test guarding the
  clean-machine install/launch path.
- In-app version label on the Home screen, sourced from the `VERSION` file.
```

- [ ] **Step 2: Create `docs\RELEASE.md`**

```markdown
# Release Checklist

How to cut a new release of this project. There is no automation script for
this - it's a short enough process to run by hand, and automating a release
cadence that doesn't exist yet would be premature.

1. Run the full test suite and confirm everything is green:
   ```
   powershell.exe -NoProfile -Command "Invoke-Pester tests/"
   ```
2. Update `VERSION` (repo root, single line, e.g. `1.0.1`) to the new version.
3. Add a new entry at the top of `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`
   summarizing what changed since the last release.
4. Commit both files:
   ```
   git add VERSION CHANGELOG.md
   git commit -m "chore: release vX.Y.Z"
   ```
5. Tag the release:
   ```
   git tag vX.Y.Z
   ```
6. Build the release zip:
   ```
   powershell.exe -NoProfile -File _shared\scripts\package-release.ps1
   ```
7. Spot-check the zip: unzip it somewhere else, confirm `Start.bat` is
   present, and confirm no server-instance data, Java runtime, or playit
   secrets leaked in (they shouldn't - `package-release.ps1` uses an
   explicit allow-list - but check once per release anyway).
8. Hand off the zip to the client / wherever it's distributed.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/RELEASE.md
git commit -m "docs: add CHANGELOG and release checklist"
```

---

## Self-Review Notes

- **Spec coverage:** `VERSION` file + label → Task 1. Auto-close hook + fresh-install test → Task 2. `CHANGELOG.md` + `docs/RELEASE.md` → Task 3. Actual tagging/packaging of v1.0.0 itself is the *first execution* of the Task 3 runbook, done once this plan lands — not a task here, since an implementing subagent shouldn't be cutting the actual release tag on its own authority.
- **No placeholders:** every step has literal code/content, no "add appropriate X".
- **Type/name consistency:** `Get-AppVersion -Root <string>` (Task 1) is the only new function signature and is used identically in Start-Gui.ps1 wiring (Task 1, Step 7) and referenced (not called directly) by Task 2's description. `Get-ReleaseFiles -Root <string>` (Task 2) matches its existing definition in `_shared\scripts\package-release.ps1` verified during brainstorming — unchanged, only consumed.

## After This Plan Lands

Run the `docs/RELEASE.md` checklist once by hand to actually cut `v1.0.0` — that's a real, once-only action (tagging, building the zip) that belongs with the user's go/no-go, not bundled into an automated task.
