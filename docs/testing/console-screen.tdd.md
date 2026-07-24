# TDD Evidence: In-Window Server Console (logs + commands)

**Source plan**: inline plan from `/ecc:plan` ("In-Window Server Console (logs + commands)"), approved by the user with "Lets start /ecc:tdd-workflow".

## User Journeys

- As the host, I want to see the server's live log output inside the main window, so that I don't need a second console window to know what's happening.
- As the host, I want to type and send a command to the running server from the same window, so that I don't need to alt-tab to a separate console to run `list`, `say`, etc.
- As the host, I want the Console screen to clearly tell me when it can't do anything (server stopped, RCON disabled) instead of silently failing.
- As the host, I don't want checking the console to freeze the rest of the app — this app already had one UI-freeze bug this session (`Test-PortOpen` blocking the Dispatcher thread every 2s), so the same mistake must not repeat here.

## Task Report

### Task 1 — Screen shell + navigation
- Added `"Console"` to `Get-ScreenSize` (560x640) and `Get-BackTarget` (→ "Home") in `gui-helpers.ps1`, following the exact switch-statement pattern already used for Home/ManageMaps/AddServer.
- Created `_shared\gui\ConsoleScreen.xaml` mirroring `ManageMapsScreen.xaml`'s resource brushes, `BackButtonStyle`, and header layout; added a read-only log `TextBox`, hint text, and a command `TextBox` + `SendButtonStyle` button (same hover-overlay/press-scale pattern established earlier this session).
- Wired `ConsoleHost` into `MainWindow.xaml` and `Get-ScreenXaml`/`Show-Screen` in `Start-Gui.ps1`, mirroring the other three screens exactly.
- Added a "Console" button to the Home screen's secondary-actions row, gated to `Game -eq "Minecraft"` via `Sync-StatusDisplay` (which already runs on every selection change and every 2s tick).
- Validation: RED → GREEN via Pester (below); XAML files parse as well-formed XML; `Start-Gui.ps1` launches with no runtime errors (checked stdout/stderr logs, process stayed responsive).

### Task 2 — Non-blocking log tailing
- Added `Get-LogTailChunk -Path -Offset` to `gui-helpers.ps1`: opens the file with `FileShare.ReadWrite` (so it doesn't fight the Java process that has it open for writing), seeks to `Offset`, reads only the new bytes, returns `{Text, Offset}`. Resets to offset 0 if the given offset is past the current file length (rotation/truncation) or the file doesn't exist yet.
- Wired a `DispatcherTimer` (1.5s) in `Start-Gui.ps1` that only runs while the Console screen is showing (`Start()` in `Enter-ConsoleScreen`, `Stop()` on back-navigation), appends new text, and trims the displayed text to the last 2000 lines each tick to bound memory over a long session.
- Validation: RED → GREEN via Pester, 5 cases (missing file, fresh read, incremental read, offset-past-length reset, idle/no-new-content). See test table below.

### Task 3 — Sending commands via RCON
- `Send-ConsoleCommand` reads `rcon.port`/`rcon.password` from the selected instance's `server.properties` (reusing `Read-ServerProperties`/`Get-SelectedRconPort`), runs `Invoke-RconCommand` inside a background `Start-Job`, and polls it with a 300ms `DispatcherTimer` — the exact pattern already used for server creation (`$addJob`/`$addJobTimer`), specifically to avoid a repeat of the `Test-PortOpen`-on-the-Dispatcher-thread bug fixed earlier this session.
- Send is disabled (with an explanatory hint) whenever the server isn't running or `enable-rcon` isn't `true`, and while a command is in flight.
- Both the RCON job and the log-tail/RCON timers are cleaned up on window close (`$script:rconJob` added to the existing `Window.Closing` cleanup, `$logTailTimer`/`$rconJobTimer` stopped alongside the existing timers at shutdown).
- Validation: this is an I/O boundary (background job + real network RCON round-trip), which — per this repo's existing convention (see the `Stop-ProcessTree` comment in `gui-helpers.ps1`) — is not unit tested. Verified by code review against the working `stop-server.ps1`/`start-with-tunnel.ps1` RCON usage and the live GUI smoke test (screen loads, no exceptions). **Not yet verified against a real running server sending a live command** — that requires an actual Minecraft server up, which wasn't run in this session. Flagged as a follow-up manual check.

### Task 4 — Polish
- Reused the already-established hover-overlay + press-scale button styles from this session's earlier polish pass (`SendButtonStyle` mirrors `ActionButtonStyle`'s pattern; `BackButtonStyle` copied verbatim; command `TextBox` styled like Add Server's).

## Test Specification

| # | What is guaranteed | Test file or command | Test type | Result | Evidence |
|---|--------------------|----------------------|-----------|--------|----------|
| 1 | `Get-ScreenSize -Screen "Console"` returns 560x640 | `tests/gui-helpers.tests.ps1:"returns the Console screen size"` | unit | PASS | `Invoke-Pester tests\gui-helpers.tests.ps1` |
| 2 | `Get-BackTarget -Screen "Console"` returns "Home" | `tests/gui-helpers.tests.ps1:"returns Home as the back target from Console"` | unit | PASS | same run |
| 3 | Reading a nonexistent log file returns empty text at offset 0, doesn't throw | `tests/gui-helpers.tests.ps1:"returns empty text and offset 0 when the log file doesn't exist yet"` | unit | PASS | same run |
| 4 | A first read from offset 0 returns the whole file and the new offset equals the file length | `tests/gui-helpers.tests.ps1:"reads the whole file on a first read from offset 0"` | unit | PASS | same run |
| 5 | A second read from a prior offset returns only the newly appended bytes | `tests/gui-helpers.tests.ps1:"returns only the bytes appended since the given offset"` | unit | PASS | same run |
| 6 | An offset past the current file length resets to a full read from the start | `tests/gui-helpers.tests.ps1:"restarts from the beginning when the offset is past the current file length"` | unit | PASS | same run |
| 7 | Reading again with no new writes returns an empty chunk and an unchanged offset | `tests/gui-helpers.tests.ps1:"returns an unchanged chunk when nothing new has been written"` | unit | PASS | same run |

**RED evidence** (before implementation): `Passed: 27 Failed: 7` — 2 failures for the missing `"Console"` switch cases (`RuntimeException: Unrecognized screen 'Console'.`), 5 failures for `Get-LogTailChunk` not existing (`CommandNotFoundException`).

**GREEN evidence** (after implementation): `Passed: 34 Failed: 0` — same command, rerun after adding the two switch cases and `Get-LogTailChunk`, and again after wiring the screen/window/Home-button changes (no regressions).

## Coverage and Known Gaps

- All pure logic touched by this feature (`Get-ScreenSize`, `Get-BackTarget`, `Get-LogTailChunk`) is unit tested. This matches 100% of what this codebase's convention treats as unit-testable — see `gui-helpers.ps1`'s existing `Stop-ProcessTree` comment: I/O boundaries (file handles held by another process, real sockets, `Start-Job`, XAML/event wiring) are intentionally left untested and verified by manual/smoke testing instead, same as every other screen in this app.
- **Known gap**: the RCON send path (Task 3) has not been exercised against a real running server in this session — only code-reviewed against the working `Invoke-RconCommand` usage elsewhere and confirmed not to throw at screen-load time. Recommend a manual pass: start a real server, open Console, confirm log lines stream in, send `list`, confirm the response appears, then stop the server and confirm Send disables with the correct hint.
- No test for the 2000-line trim behavior specifically (would require simulating a very large log file); low risk since the trim logic is a simple array slice, not new business logic.
