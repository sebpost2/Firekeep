# v1.0.0 Release Process — Design

**Date:** 2026-08-10
**Status:** Approved (pending user review of this doc)

## Context

The GUI redesign (merged to `master` at `424e975`) has been visually confirmed working by the user. This is the first release this project has ever tagged — no git tags or remote exist yet. The project already has a packaging script (`_shared\scripts\package-release.ps1`, tested by `tests/package-release.tests.ps1`) that builds a client-safe zip from an explicit allow-list. This spec covers what's needed to turn "code is merged" into a released, versioned v1.0.0 build, and to make that a repeatable process for future releases.

**Explicitly out of scope:** the 3 deferred cosmetic findings from the GUI redesign's final review (type-scale drift, hardcoded literal colors duplicating `Theme.xaml` keys, `Height="*"` row inside a `ScrollViewer` on `HomeScreen`). These remain parked as optional follow-up polish, not release blockers.

## Goals

1. Track version numbers, starting at `v1.0.0`, visible both in git history and in the running app.
2. Close the one untested gap flagged in the prior session: nobody has run this app against a genuinely clean machine (no prior server, no Java runtime, no playit setup). Automate that check so it can't silently regress.
3. Leave behind a short, repeatable checklist so future releases don't require re-deriving this process.

## Components

### 1. `VERSION` file

Plain text file at repo root, single line, e.g. `1.0.0`. Single source of truth for both the git tag (`git tag v1.0.0`) and the in-app label. No JSON/YAML — one line is all that's needed.

### 2. Home screen version label

`Start-Gui.ps1` reads `VERSION` once at startup (best-effort: if the file is missing or unreadable, the label is simply left blank — this must never block app launch). The value is passed into `HomeScreen.xaml`'s data context and rendered as a small, muted `TextBlock` appended directly under the existing title/subtitle `StackPanel` (`HomeScreen.xaml` row 0), matching the subtitle's existing muted styling at a smaller size so it reads as metadata, not a headline.

### 3. Test-only auto-close hook in `Start-Gui.ps1`

`Start-Gui.ps1` currently blocks on `$window.ShowDialog()` with no programmatic exit — fine for interactive use, but a fresh-install test needs to launch the real app, let it initialize, and close it without a human. Add a minimal, opt-in hook: if an environment variable (e.g. `GUI_TEST_AUTOCLOSE_MS`) is set, start a one-shot `DispatcherTimer` that calls `$window.Close()` after that many milliseconds. Unset (the normal case), this is inert — zero behavior change for real users. This mirrors the existing `-TestOnlyLoadFunctions` pattern already used in `package-release.ps1` for the same reason (give tests a hook without touching production behavior).

### 4. `tests/fresh-install.tests.ps1`

New Pester test, following the STA-subprocess pattern already established by `tests/gui-load.tests.ps1`:

1. Robocopy the repo's tracked files (code, `_shared`, `Minecraft\scripts`, `Minecraft\servers\_template`, etc. — the same allow-list `package-release.ps1` already defines) into a fresh temp directory. This guarantees the test never touches the real `Minecraft\servers\*` instances, portable Java runtime, or playit secrets — it operates on a disposable copy that starts with none of those things, which *is* the fresh-machine state under test.
2. Launch `Start-Gui.ps1` from that temp copy as an STA `powershell.exe` subprocess with `GUI_TEST_AUTOCLOSE_MS` set (a few seconds — enough for startup logic to run).
3. Assert: process exits cleanly (exit code 0, no unhandled exception written to stderr/output), and the server picker's empty state was reachable (reuse the existing `Get-ScreenXaml`/screen-load assertions style from `gui-load.tests.ps1` rather than inventing new UI-state introspection).
4. Clean up the temp directory afterward regardless of pass/fail.

This is a **launch/UI smoke test**, not a full end-to-end install — it does not download a real Java runtime or a real modpack (too slow/network-dependent/flaky for a Pester run that's part of the regular suite). It proves the app starts cleanly and presents the correct "nothing set up yet" UI when literally nothing exists, which is the actual gap identified.

### 5. `CHANGELOG.md`

Root file, Keep-a-Changelog-style headings. First entry `## [1.0.0] - 2026-08-10` summarizing this session's work (Theme.xaml consolidation, resizable window, Verity 3-card redesign, spacing polish) and noting this is the first tracked release.

### 6. `docs/RELEASE.md`

Short runbook, not a script:

1. Run the full suite: `powershell.exe -NoProfile -Command "Invoke-Pester tests/"` — must be green, including the new `fresh-install.tests.ps1`.
2. Update `VERSION` and add a `CHANGELOG.md` entry.
3. Commit those two files.
4. `git tag vX.Y.Z`.
5. Run `_shared\scripts\package-release.ps1` to produce the zip.
6. Spot-check the zip (unzip somewhere, confirm `Start.bat` present, no server-instance/secret files leaked in).

No new automation script wraps these steps — this is the first release ever, so building orchestration around a release cadence that doesn't exist yet would be premature. If releases become frequent, revisit.

## Data Flow

`VERSION` (file, repo root) → read once at `Start-Gui.ps1` startup → passed into Home screen's data context → rendered as static text on load. No other screen reads it. No network calls, no persistence beyond the file itself.

`GUI_TEST_AUTOCLOSE_MS` (env var, test-only) → checked once at `Start-Gui.ps1` startup → if set, arms a one-shot `DispatcherTimer` → timer fires → `$window.Close()` → `ShowDialog()` returns → script exits normally.

## Error Handling

- `VERSION` missing/malformed: label renders blank. No exception, no launch block.
- `fresh-install.tests.ps1`: if the robocopy staging step itself fails (disk space, permissions), the test fails loudly via a Pester assertion — a broken test harness must not silently report as passing.
- Test-only auto-close hook: only activates when `GUI_TEST_AUTOCLOSE_MS` is explicitly set; absent in every real invocation (`Start.bat`, manual `powershell.exe -File Start-Gui.ps1`), so it cannot affect a real user's session.

## Testing

- New: `tests/fresh-install.tests.ps1`, added to the existing suite (runs as part of `Invoke-Pester tests/`).
- Existing 168 tests: unaffected, still the baseline gate before tagging.
- No manual testing step required for the fresh-install scenario going forward — it's now automated and will re-run on every future regression pass, catching a regression the same way `gui-load.tests.ps1` now catches the theme-merge-timing bug class.

## Decisions Made

- **Git tags + local zip distribution, no GitHub remote.** No remote workflow exists for this repo; adding one is out of scope for getting v1.0.0 out.
- **Fresh-install check is a permanent automated Pester test**, not a one-time manual pass — consistent with this session's established pattern of turning a caught/flagged gap into a permanent regression guard.
- **Version is visible in the app** (Home screen footer-style label), not just in git tags — useful once more than one release exists in the wild and a client reports an issue.
- **No new release-orchestration script.** `docs/RELEASE.md` is a checklist a human follows; `package-release.ps1` stays as-is.
- **Fresh-install test isolates via a temp-directory copy of the repo**, not by renaming aside real state on the developer's machine — safer, since a failed cleanup can never hide the user's real server data.
