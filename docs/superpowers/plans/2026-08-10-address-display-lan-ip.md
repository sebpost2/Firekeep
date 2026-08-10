# Address Display: LAN IP + Manual Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When playit.gg isn't active, show the user's actual LAN IP instead of just "Same WiFi only", and let users who port-forward manually enter their own address to take priority over both playit and LAN detection.

**Architecture:** Two new pure/testable helpers in `_shared\scripts\tunnel-helpers.ps1` (`Select-LanIPv4Address`, `Get-LanAddress`, `Resolve-DisplayAddress`), a new app-wide `manual-address.txt` cache file (same folder as playit's existing `secret.key`/`address.txt`), a new text field + button in `HomeScreen.xaml`, and `Update-AddressDisplay` in `Start-Gui.ps1` rewired to read the three sources and resolve them through the new priority-chain function.

**Tech Stack:** Windows PowerShell 5.1, WPF (loose XAML via `XamlReader.Load`), Pester 3.4.0 (old syntax).

## Global Constraints

- Windows PowerShell 5.1 / WPF only — no `App.xaml`, no compiled resources. Use `powershell.exe` in all bash tool invocations, never `pwsh` (not installed).
- Pester 3.4.0 uses old syntax (`Should Be`, `Should Not Be`, `Should Match`) — do not use `Should -Be` anywhere in this plan's tests.
- Run the full suite with: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`.
- The manual override is app-wide, stored at `_shared\tools\playit\manual-address.txt` — NOT per-server-instance (corrected from the original spec draft once the existing playit.gg code turned out to already be app-wide, not per-instance).
- No address validation on the manual override — free text, trust the user.
- Priority order for the displayed address: manual override > playit.gg > LAN IP > "Same WiFi only" text.
- Spec: `docs/superpowers/specs/2026-08-10-address-display-lan-ip-design.md`.

---

### Task 1: `Select-LanIPv4Address` + `Get-LanAddress` + `Resolve-DisplayAddress`

**Files:**
- Modify: `_shared\scripts\tunnel-helpers.ps1` (add all three functions)
- Test: `tests\tunnel-helpers.tests.ps1`

**Interfaces:**
- Produces: `Select-LanIPv4Address -Candidates <string[]> -> [string]`. Pure function — given a list of IPv4 address strings, returns the first one that isn't loopback (`127.0.0.1`) or link-local (`169.254.x.x`), or `""` if none qualify.
- Produces: `Get-LanAddress -Port <int> -> [string]`. Queries this machine's real network adapters via `Get-NetIPAddress`, filters through `Select-LanIPv4Address`, and returns `"<ip>:<port>"` or `""`. Never throws.
- Produces: `Resolve-DisplayAddress -Manual <string> -Playit <string> -Lan <string> -> [string]`. Pure function — returns whichever of the three non-empty strings wins by priority (Manual > Playit > Lan), or `""` if all three are empty. Used by Task 2's `Update-AddressDisplay` rewrite.

- [ ] **Step 1: Write the failing tests for `Select-LanIPv4Address` and `Resolve-DisplayAddress`**

Append to `tests\tunnel-helpers.tests.ps1` (after the existing `Select-MinecraftTunnel` `Describe` block, same file, same old-Pester-syntax style):

```powershell
Describe "Select-LanIPv4Address" {

    It "picks the first non-loopback, non-link-local address" {
        $result = Select-LanIPv4Address -Candidates @("127.0.0.1", "169.254.10.5", "192.168.1.42")
        $result | Should Be "192.168.1.42"
    }

    It "returns empty when only loopback/link-local addresses are present" {
        $result = Select-LanIPv4Address -Candidates @("127.0.0.1", "169.254.3.1")
        $result | Should Be ""
    }

    It "returns empty when given no candidates" {
        Select-LanIPv4Address -Candidates @() | Should Be ""
    }
}

Describe "Resolve-DisplayAddress" {

    It "prefers the manual override over everything else" {
        Resolve-DisplayAddress -Manual "my.ddns.net:25565" -Playit "abc.playit.gg" -Lan "192.168.1.5:25565" | Should Be "my.ddns.net:25565"
    }

    It "prefers playit over LAN when there is no manual override" {
        Resolve-DisplayAddress -Manual "" -Playit "abc.playit.gg" -Lan "192.168.1.5:25565" | Should Be "abc.playit.gg"
    }

    It "falls back to LAN when neither manual nor playit is set" {
        Resolve-DisplayAddress -Manual "" -Playit "" -Lan "192.168.1.5:25565" | Should Be "192.168.1.5:25565"
    }

    It "returns empty when nothing is available" {
        Resolve-DisplayAddress -Manual "" -Playit "" -Lan "" | Should Be ""
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/tunnel-helpers.tests.ps1"`
Expected: FAIL — `Select-LanIPv4Address` and `Resolve-DisplayAddress` are not recognized as the names of cmdlets/functions.

- [ ] **Step 3: Implement `Select-LanIPv4Address` and `Resolve-DisplayAddress` in `tunnel-helpers.ps1`**

Add to `_shared\scripts\tunnel-helpers.ps1` (after the existing `Select-MinecraftTunnel` function):

```powershell
# Picks the first usable LAN IPv4 address from a list of candidate address
# strings - excludes loopback and link-local (169.254.x.x, assigned when no
# DHCP/adapter is actually up) addresses. Pure/testable: the live adapter
# query lives in Get-LanAddress: this just filters an already-fetched list.
function Select-LanIPv4Address {
    param([string[]]$Candidates = @())
    $valid = @($Candidates | Where-Object { $_ -and $_ -ne "127.0.0.1" -and -not $_.StartsWith("169.254.") })
    if ($valid.Count -gt 0) { return $valid[0] }
    return ""
}

# Priority chain for what to show/copy as the shareable address: a saved
# manual override wins outright, then playit.gg, then this machine's LAN
# IP. Pure function so it's testable without touching the filesystem or
# network - Update-AddressDisplay in Start-Gui.ps1 is the only caller.
function Resolve-DisplayAddress {
    param(
        [string]$Manual = "",
        [string]$Playit = "",
        [string]$Lan = ""
    )
    if ($Manual) { return $Manual }
    if ($Playit) { return $Playit }
    if ($Lan) { return $Lan }
    return ""
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/tunnel-helpers.tests.ps1"`
Expected: PASS for `Select-LanIPv4Address` and `Resolve-DisplayAddress` tests (the `Get-LanAddress` test added in the next step doesn't exist yet, so ignore that for now — this step is just to confirm the two pure functions work).

- [ ] **Step 5: Write the failing test for `Get-LanAddress`**

Append to `tests\tunnel-helpers.tests.ps1`:

```powershell
Describe "Get-LanAddress" {

    It "returns an ip:port string or empty, and never throws" {
        { $script:result = Get-LanAddress -Port 25565 } | Should Not Throw
        ($result -eq "" -or $result -match '^\d+\.\d+\.\d+\.\d+:25565$') | Should Be $true
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/tunnel-helpers.tests.ps1"`
Expected: FAIL — `Get-LanAddress` is not recognized as the name of a cmdlet/function.

- [ ] **Step 7: Implement `Get-LanAddress` in `tunnel-helpers.ps1`**

Add to `_shared\scripts\tunnel-helpers.ps1` (after `Select-LanIPv4Address`):

```powershell
# Best-effort local network address for same-WiFi sharing when playit.gg
# isn't active. Never throws - matches Get-AppVersion's established pattern
# for display helpers that must not block the GUI.
function Get-LanAddress {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $candidates = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
    } catch {
        return ""
    }
    $ip = Select-LanIPv4Address -Candidates $candidates
    if (-not $ip) { return "" }
    return "${ip}:$Port"
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/tunnel-helpers.tests.ps1"`
Expected: PASS, all `Select-MinecraftTunnel`/`Select-LanIPv4Address`/`Resolve-DisplayAddress`/`Get-LanAddress` tests green.

- [ ] **Step 9: Commit**

```bash
git add _shared/scripts/tunnel-helpers.ps1 tests/tunnel-helpers.tests.ps1
git commit -m "feat: add LAN IP detection and address priority-chain helpers"
```

---

### Task 2: Manual address override (UI + wiring)

**Files:**
- Modify: `_shared\gui\HomeScreen.xaml` (address Border block, roughly lines 86-97)
- Modify: `Start-Gui.ps1` (add `$manualAddressRow`/`$manualAddressBox`/`$manualAddressSaveButton` lookups, add `Get-SelectedServerPort`, rewrite `Update-AddressDisplay`, add the save button's click handler)

**Interfaces:**
- Consumes: `Get-LanAddress -Port <int> -> [string]` and `Resolve-DisplayAddress -Manual <string> -Playit <string> -Lan <string> -> [string]` (Task 1, `tunnel-helpers.ps1`, already dot-sourced into `Start-Gui.ps1` at line 15).
- Produces: nothing consumed by later tasks — this is the terminal task of this plan.

This task has no dedicated automated test (matches the project's established pattern: `HomeScreen.xaml`/`Start-Gui.ps1` wiring changes elsewhere in this codebase — e.g. the version-label wiring — aren't covered by new tests either, only by the full suite staying green plus a manual smoke check). Steps are still ordered as small, verifiable increments.

- [ ] **Step 1: Add the manual-address row to `HomeScreen.xaml`**

The address block currently reads (`_shared\gui\HomeScreen.xaml`, lines 86-97):

```xml
            <!-- Address -->
            <Border Grid.Row="1" Background="{StaticResource PanelElevatedBrush}" CornerRadius="6" Padding="14,12" Margin="0,18,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" x:Name="AddressText" Text="Checking..." Foreground="{StaticResource TextBrush}"
                               FontFamily="Consolas" FontSize="14" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <Button Grid.Column="1" x:Name="CopyButton" Content="Copy" Style="{StaticResource LinkButtonStyle}"
                            Foreground="{StaticResource AccentBrush}" IsEnabled="False"/>
                </Grid>
            </Border>
```

Replace with (adds row structure so a second row can hold the manual-override field, collapsed by default):

```xml
            <!-- Address -->
            <Border Grid.Row="1" Background="{StaticResource PanelElevatedBrush}" CornerRadius="6" Padding="14,12" Margin="0,18,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" x:Name="AddressText" Text="Checking..." Foreground="{StaticResource TextBrush}"
                               FontFamily="Consolas" FontSize="14" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <Button Grid.Row="0" Grid.Column="1" x:Name="CopyButton" Content="Copy" Style="{StaticResource LinkButtonStyle}"
                            Foreground="{StaticResource AccentBrush}" IsEnabled="False"/>

                    <Grid Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" x:Name="ManualAddressRow" Margin="0,10,0,0" Visibility="Collapsed">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox Grid.Column="0" x:Name="ManualAddressBox" FontFamily="Consolas" FontSize="12"
                                 Background="{StaticResource PanelBrush}" Foreground="{StaticResource TextBrush}"
                                 BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="6,4"
                                 VerticalContentAlignment="Center"
                                 ToolTip="Have your own port forwarded? Enter that address here."/>
                        <Button Grid.Column="1" x:Name="ManualAddressSaveButton" Content="USE THIS" Style="{StaticResource LinkButtonStyle}"
                                Foreground="{StaticResource AccentBrush}" Margin="8,0,0,0"/>
                    </Grid>
                </Grid>
            </Border>
```

- [ ] **Step 2: Add the element lookups in `Start-Gui.ps1`**

`Start-Gui.ps1`'s Home screen lookups currently include (line 88):

```powershell
$copyButton       = $homeRoot.FindName("CopyButton")
```

Add these three lines right after it:

```powershell
$manualAddressRow = $homeRoot.FindName("ManualAddressRow")
$manualAddressBox = $homeRoot.FindName("ManualAddressBox")
$manualAddressSaveButton = $homeRoot.FindName("ManualAddressSaveButton")
```

- [ ] **Step 3: Add `Get-SelectedServerPort` next to `Get-SelectedRconPort`**

`Start-Gui.ps1` already has (lines 152-157):

```powershell
function Get-SelectedRconPort {
    if (-not $script:selected) { return $null }
    $props = Read-ServerProperties (Join-Path $script:selected.Path "server.properties")
    if ($props["rcon.port"]) { return [int]$props["rcon.port"] }
    return 25575
}
```

Add immediately after it:

```powershell
function Get-SelectedServerPort {
    if (-not $script:selected) { return 25565 }
    $props = Read-ServerProperties (Join-Path $script:selected.Path "server.properties")
    if ($props["server-port"]) { return [int]$props["server-port"] }
    return 25565
}
```

- [ ] **Step 4: Rewrite `Update-AddressDisplay`**

`Start-Gui.ps1`'s current `Update-AddressDisplay` (lines 159-190):

```powershell
# Reads the shareable address the same way show-address.ps1 does: ask
# playit.gg once, fall back to the cached address.txt if that fails.
function Update-AddressDisplay {
    $toolDir = Join-Path $root "_shared\tools\playit"
    $secretFile = Join-Path $toolDir "secret.key"
    $addrFile = Join-Path $toolDir "address.txt"
    $addr = $null

    if (Test-Path $secretFile) {
        try {
            $secret = (Get-Content $secretFile -Raw).Trim()
            $rd = Invoke-RestMethod -Uri "https://api.playit.gg/agents/rundata" -Method Post -Body "{}" `
                -Headers @{ Authorization = "Agent-Key $secret"; "Content-Type" = "application/json" } -TimeoutSec 8
            $mc = Select-MinecraftTunnel -Tunnels $rd.data.tunnels
            if ($mc -and $mc.assigned_domain) {
                $addr = $mc.assigned_domain
                Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ascii
            }
        } catch { }
        if (-not $addr -and (Test-Path $addrFile)) { $addr = (Get-Content $addrFile -Raw).Trim() }
    }

    if ($addr) {
        $addressText.Text = $addr
        $copyButton.IsEnabled = $true
        $setupTunnelButton.Visibility = "Collapsed"
    } else {
        $addressText.Text = "Same WiFi only (no sharing set up yet)"
        $copyButton.IsEnabled = $false
        $setupTunnelButton.Visibility = "Visible"
    }
}
```

Replace with:

```powershell
# Reads the shareable address, in priority order: a saved manual override,
# then playit.gg (ask once, fall back to the cached address.txt if that
# fails - same as show-address.ps1), then this machine's LAN IP.
function Update-AddressDisplay {
    $toolDir = Join-Path $root "_shared\tools\playit"
    $secretFile = Join-Path $toolDir "secret.key"
    $addrFile = Join-Path $toolDir "address.txt"
    $manualFile = Join-Path $toolDir "manual-address.txt"
    $addr = $null

    $manual = if (Test-Path $manualFile) { (Get-Content $manualFile -Raw).Trim() } else { "" }
    $manualAddressBox.Text = $manual

    if (-not $manual -and (Test-Path $secretFile)) {
        try {
            $secret = (Get-Content $secretFile -Raw).Trim()
            $rd = Invoke-RestMethod -Uri "https://api.playit.gg/agents/rundata" -Method Post -Body "{}" `
                -Headers @{ Authorization = "Agent-Key $secret"; "Content-Type" = "application/json" } -TimeoutSec 8
            $mc = Select-MinecraftTunnel -Tunnels $rd.data.tunnels
            if ($mc -and $mc.assigned_domain) {
                $addr = $mc.assigned_domain
                Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ascii
            }
        } catch { }
        if (-not $addr -and (Test-Path $addrFile)) { $addr = (Get-Content $addrFile -Raw).Trim() }
    }

    $lan = if (-not $manual -and -not $addr) { Get-LanAddress -Port (Get-SelectedServerPort) } else { "" }
    $resolved = Resolve-DisplayAddress -Manual $manual -Playit $addr -Lan $lan

    if ($resolved) {
        $addressText.Text = $resolved
        $copyButton.IsEnabled = $true
    } else {
        $addressText.Text = "Same WiFi only (no sharing set up yet)"
        $copyButton.IsEnabled = $false
    }

    $setupTunnelButton.Visibility = if ($addr) { "Collapsed" } else { "Visible" }
    $manualAddressRow.Visibility = if ($addr) { "Collapsed" } else { "Visible" }
}
```

- [ ] **Step 5: Wire the save button**

`Start-Gui.ps1` currently has the copy-button wiring around line 338:

```powershell
$copyButton.Add_Click({
    if ($copyButton.IsEnabled) { Set-Clipboard -Value $addressText.Text }
})
```

Add right after it:

```powershell
$manualAddressSaveButton.Add_Click({
    $toolDir = Join-Path $root "_shared\tools\playit"
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $manualFile = Join-Path $toolDir "manual-address.txt"
    $value = $manualAddressBox.Text.Trim()
    if ($value) {
        Set-Content -Path $manualFile -Value $value -NoNewline -Encoding ascii
    } else {
        Remove-Item -Path $manualFile -Force -ErrorAction SilentlyContinue
    }
    Update-AddressDisplay
})
```

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"`
Expected: PASS, all tests green (existing 174 plus Task 1's new tests).

- [ ] **Step 7: Manual smoke check**

Launch the app for real (`powershell.exe -NoProfile -File Start-Gui.ps1`) with a server selected and no playit.gg configured: confirm the Home screen shows either a real `<lan-ip>:<port>` or "Same WiFi only" (never blank/error), the manual-address field is visible, typing an address and clicking "USE THIS" makes that address appear (and Copy copies it), and clearing the field + saving reverts to the LAN/playit-derived address.

- [ ] **Step 8: Commit**

```bash
git add _shared/gui/HomeScreen.xaml Start-Gui.ps1
git commit -m "feat: add LAN IP display and manual address override"
```

---

## Self-Review Notes

- **Spec coverage:** `Get-LanAddress`/`Select-LanIPv4Address` (Goal 1) → Task 1. Manual override storage + priority chain + UI (Goal 2) → Task 1 (`Resolve-DisplayAddress`) + Task 2 (UI/wiring). The spec's app-wide-vs-per-instance correction is reflected in Task 2's `_shared\tools\playit\manual-address.txt` path.
- **No placeholders:** every step has literal code, no "add appropriate X".
- **Type/name consistency:** `Get-LanAddress -Port <int> -> [string]`, `Select-LanIPv4Address -Candidates <string[]> -> [string]`, and `Resolve-DisplayAddress -Manual/-Playit/-Lan <string> -> [string]` (Task 1) are used identically in Task 2's `Update-AddressDisplay` rewrite — same parameter names, same call shape.

## After This Plan Lands

No follow-up manual action required — unlike the v1.0.0 release plan, this doesn't involve tagging or packaging. It's ready to ship in whatever the next release is.
