# TDD Evidence: Public-Ready Modpack Server Toolkit

**Source plan**: inline plan from `/ecc:plan` ("Public-Ready Modpack Server Toolkit"), approved by the user with "Lets do all phases".

## User Journeys

- As a friend with a Modrinth `.mrpack` file, I want to create a working modpack server without hand-editing config files, so that I don't need to understand Java versions or JVM args.
- As the repo owner, I want to publish this toolkit without leaking my personal server's operator/whitelist/ban data or playit.gg secret.
- As the repo owner, I want a reliable way to build a public release zip that never includes my installed server or secrets.

## Task Report

### Task 1 — Stop leaking personal server data
- Rewrote `.gitignore` to blanket-ignore `Minecraft/servers/*/` except `_template/` (was a list of per-subfolder patterns that missed root-level files like `ops.json`/`whitelist.json`).
- `git rm --cached` on the 11 tracked `Cave Horror Project` files, then squashed all history into a single orphan commit so the leaked blobs are unreachable from any branch (no remote existed, so nothing was ever pushed).
- Validation: `git ls-files | grep -i "cave horror"` → empty; `git log --all --oneline` → one commit.
- Guarantee: no personal server data is tracked by git going forward, and none remains reachable in history.

### Task 2 — Java-version mapping helper
- RED: `tests/mrpack-helpers.tests.ps1` written first, dot-sourcing a not-yet-existing `_shared/scripts/mrpack-helpers.ps1` → `CommandNotFoundException`.
- GREEN: implemented `Get-JavaVersionForMinecraft -McVersion` (numeric major.minor.patch compare, not string compare) → 8/8 pass.
- Validation: `Invoke-Pester .\tests\mrpack-helpers.tests.ps1`.
- Guarantee: given any Minecraft version string, the correct Java major (8/17/21) is returned, with boundary versions (1.16.5, 1.17, 1.20.4, 1.20.5) explicitly covered, and unparseable strings throw instead of silently defaulting.

### Task 3 — Wire `mrpack.exe` into `new-server.ps1`
- RED → GREEN for two more pure helpers: `Get-MinecraftVersionFromMrpack` (reads `modrinth.index.json` out of the `.mrpack` zip) and `Set-RunConfigJavaAndRam` (patches `run.config.ps1` in place).
- Extended `Minecraft/scripts/new-server.ps1` with `-MrpackPath` (local file or URL): downloads if URL, reads MC version, maps to Java version, runs `mrpack.exe`, prompts for RAM, patches `run.config.ps1`, walks through EULA acceptance.
- **Real end-to-end run** (not mocked): downloaded the live "Fabulously Optimized" v8.2.0 Modrinth pack (MC 1.21.4, Fabric) and ran the full install flow against it.
  - Result: correctly detected `MC 1.21.4 -> Java 21`; `mrpack.exe` downloaded the server jar + 48 mod dependencies + config overrides successfully.
  - **Real bug found and fixed by this test**: `Set-RunConfigJavaAndRam` used `Get-Content -Raw`/`Set-Content` with no explicit encoding. Windows PowerShell 5.1 defaults to ANSI for files without a BOM, and the real `_template/run.config.ps1` has no BOM — so the Spanish comments' accented characters (e.g. `querés`) were mangled to `quierÃ©s` on write. Added a test reproducing this with a no-BOM fixture (RED), then fixed the helper to explicitly read/write UTF-8-without-BOM via `[System.IO.File]::ReadAllText/WriteAllText` (GREEN). The already-mangled test-run leftovers in `Minecraft/servers/_e2e-test/` are debris only (gitignored, not the source template, left on disk pending manual cleanup — deletion was declined during this session).
- Validation: `Invoke-Pester .\tests\mrpack-helpers.tests.ps1` (15/15 pass) plus the live end-to-end run above.
- Guarantee: a `.mrpack` file/URL installs into a working server instance with correct Java/RAM config and preserved file encoding.

### Task 4 — Menu integration
- Added a `[N] Crear un server nuevo` option to `Start.ps1`'s existing instance-discovery menu, prompting for name + optional `.mrpack` path/URL and delegating to `new-server.ps1`.
- Validation: syntax-checked via `[System.Management.Automation.Language.Parser]::ParseFile` (no test runner needed for a thin interactive wrapper with no new branching logic beyond what's already covered).

### Task 5 — Release packaging
- RED → GREEN: `tests/package-release.tests.ps1` exercises `Get-ReleaseFiles -Root` against a synthetic fixture tree, asserting the framework (menu, scripts, `_template`, tests) is included and personal/secret/large-binary paths (`Cave Horror Project`, `playit/secret.key`, `playit/address.txt`, portable Java runtimes) are excluded.
- One test-authoring bug surfaced along the way: Pester 3.4's `Should Contain` treats its argument as a regex, so Windows paths containing `\U...` broke with `Unrecognized escape sequence`. Fixed by asserting with plain `-contains`/`Should Be $true|$false` instead.
- Implemented `_shared/scripts/package-release.ps1` with an explicit include allow-list.
- **Real run**: built an actual release zip from the live repo and expanded it — confirmed 0 matches for `Cave Horror|secret\.key|address\.txt|\java\<ver>\bin` and a clean top-level layout (33 files).
- Validation: `Invoke-Pester .\tests\package-release.tests.ps1` (6/6 pass) + manual zip build/expand/grep.
- Guarantee: running `package-release.ps1` never includes personal server data, secrets, or large redownloadable runtimes, and the resulting zip contains the full self-service framework.

### Task 6 — Docs
- Replaced `LEEME.md`'s "pedímelo y te lo instalo" (personal-service) modpack section with self-service `.mrpack` instructions via the new menu option; kept the CurseForge manual path as a fallback.
- Validation: read-through only (no test target).

## Test Specification

| # | What is guaranteed | Test file or command | Test type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Minecraft version strings map to the correct Java major (8/17/21), including boundaries | `tests/mrpack-helpers.tests.ps1:Get-JavaVersionForMinecraft` | unit | PASS | `Invoke-Pester tests/mrpack-helpers.tests.ps1` |
| 2 | Unparseable version strings throw instead of defaulting silently | same file, "throws a clear error..." | unit | PASS | same |
| 3 | `.mrpack` zips are parsed for `dependencies.minecraft` via `modrinth.index.json` | `tests/mrpack-helpers.tests.ps1:Get-MinecraftVersionFromMrpack` | unit | PASS | same |
| 4 | Missing/malformed `modrinth.index.json` or missing file throws | same | unit | PASS | same |
| 5 | `run.config.ps1`'s `$JavaVersion`/`$MaxRam` are patched without touching other lines | `tests/mrpack-helpers.tests.ps1:Set-RunConfigJavaAndRam` | unit | PASS | same |
| 6 | UTF-8-without-BOM accented comments survive the patch unmangled | same, "does not mangle accented characters..." | unit | PASS (after fix) | same |
| 7 | Full `.mrpack` install flow works end-to-end against a real, live Modrinth pack | manual E2E run against "Fabulously Optimized" v8.2.0 | integration/E2E | PASS | transcript in this report |
| 8 | Release packaging includes the framework and excludes personal/secret/large-binary data | `tests/package-release.tests.ps1:Get-ReleaseFiles` | unit | PASS | `Invoke-Pester tests/package-release.tests.ps1` |
| 9 | A real release zip built from the live repo contains no leaked data | manual zip build + `Expand-Archive` + grep | integration | PASS | 0 matches, transcript in this report |
| 10 | No personal server data remains tracked/reachable in git | `git ls-files`, `git log --all` | manual check | PASS | 0 files, 1 commit |
| 11 | Writing a secret to disk never has a window with default/broader ACL before restriction | `tests/secret-helpers.tests.ps1:Set-RestrictedSecretFile` | unit | PASS | `Invoke-Pester tests/secret-helpers.tests.ps1` |
| 12 | Release packaging excludes per-instance personal notes files and includes the public LEEME.md | `tests/package-release.tests.ps1` (2 new assertions) | unit | PASS | `Invoke-Pester tests/package-release.tests.ps1` |
| 13 | A real release zip contains the corrected onboarding doc and no personal notes | manual zip build + `Expand-Archive` + `Select-String` | integration | PASS | 0 leak matches, `setup-playit.ps1` step found in shipped LEEME.md |
| 14 | Modpack loader (fabric/forge/quilt/neoforge) is correctly detected from `modrinth.index.json` dependencies | `tests/mrpack-helpers.tests.ps1:Get-ModpackLoader` | unit | PASS | `Invoke-Pester tests/mrpack-helpers.tests.ps1` |
| 15 | Non-Fabric modpacks fail the install fast, with cleanup and clear guidance, instead of crashing mid-install | manual E2E run against a real Forge pack (Create+ 5.2.1b) | integration/E2E | PASS | folder removed (`Test-Path` → `False`), clean message, transcript in this report |

## Follow-up work (this session, after initial delivery)

### Fix: TOCTOU in `setup-playit.ps1`'s secret write
- Flagged by a background security scan: the secret file was written, *then* its ACL restricted — a brief window where it held the folder's default/inherited permissions.
- RED: `tests/secret-helpers.tests.ps1` written first against a not-yet-existing `_shared/scripts/secret-helpers.ps1` → `CommandNotFoundException`.
- GREEN: implemented `Set-RestrictedSecretFile` (create empty file → restrict ACL → write content, reversing the vulnerable order) → 3/3 pass. Wired into `setup-playit.ps1` in place of the old two-line sequence.
- Validation: `Invoke-Pester tests/secret-helpers.tests.ps1`, full suite 30/30.

### Fix: `LEEME.md` not usable by a genuine first-time user
- User-reported gap after manual review: LEEME.md documented the personal `Cave Horror Project` server as if it shipped publicly (it doesn't — `package-release.ps1` already excluded it), the playit.gg "first time" section didn't match actual script behavior (never mentioned `setup-playit.ps1`, which `start-with-tunnel.ps1` actually requires), and there was no zero-to-server walkthrough or explanation of where to get a `.mrpack` file.
- Moved the personal section into `Minecraft/servers/Cave Horror Project/NOTAS.md` (already outside git tracking and the release allow-list — no code change needed to keep it private, just relocated the content).
- Added two regression assertions to `tests/package-release.tests.ps1` (excludes per-instance `NOTAS.md`, includes `LEEME.md`) — both passed immediately against the existing allow-list logic, confirming no production bug there; the assertions exist to lock the guarantee in for future changes.
- Rewrote `LEEME.md`: added a Requirements section, a "primera vez" zero-to-server walkthrough, a Modrinth `.mrpack` mini-guide, and corrected the playit.gg first-run steps to name `setup-playit.ps1` explicitly.
- Validation: full suite 32/32; real release zip rebuilt and inspected — confirmed no `NOTAS`/`Cave Horror` leak and confirmed the corrected `setup-playit.ps1` wording is present in the shipped `LEEME.md`.

### Fix: Forge modpacks crashed the install flow with a raw error
- **Real E2E test against a live Forge pack** (Create+ 5.2.1b, MC 1.19.2, server-pack `.mrpack`, ~20MB): `mrpack.exe` failed with `forge provider not implemented`, telling the user to manually acquire the Forge installer — meaning the previously-shipped `-MrpackPath` flow would crash with a raw Go stack trace for any non-Fabric modpack (a large share of real Modrinth packs), with no cleanup of the partially-created server folder.
- RED: `tests/mrpack-helpers.tests.ps1` extended with a `Get-ModpackLoader` describe block (4 cases: fabric/forge/quilt/neoforge detection from synthetic `modrinth.index.json` fixtures) against a not-yet-existing function → 4 failures.
- GREEN: implemented `Get-ModpackLoader -MrpackPath` (reads the same `dependencies` object already used by `Get-MinecraftVersionFromMrpack`, checks which loader key is populated) → 4/4 pass, 36/36 full suite.
- Wired into `new-server.ps1`: loader is now detected *before* calling `mrpack.exe`; for anything but `fabric`, the half-created server folder is removed and the user gets a clear message pointing to the manual install path, instead of a crash.
- **Real re-run** against the same live Forge pack confirmed: clean early exit, no leftover folder (`Test-Path` → `False`), readable guidance message.
- One bug caught by this same real run: the guidance message used an accented `í` (`creá`), which rendered as `creÃ¡` in the console — confirmed as a real PowerShell 5.1 behavior (non-BOM `.ps1` source is parsed as ANSI, so UTF-8 accented bytes in string literals get misread at parse time, not just at file-read time). This explained why every other `Write-Host` string in this codebase already avoids accents (`menu` not `menú`, `ahi` not `ahí`) — fixed the one inconsistent line to match.
- Validation: `Invoke-Pester tests/mrpack-helpers.tests.ps1`, full suite 36/36, plus two live runs against the real Forge pack (before and after the message fix).
- Guarantee: any non-Fabric modpack fails fast with actionable guidance and no orphaned folder, instead of crashing mid-install.

### Docs: FAQ for real first-run friction points
- Added a troubleshooting section to `LEEME.md` covering: the Windows Firewall "Allow access" prompt for Java/playit.exe (silent tunnel failure if dismissed), antivirus potentially quarantining the unsigned `playit.exe`/`mrpack.exe` binaries, RAM sizing guidance (check Task Manager before assigning server memory), and that the first run legitimately takes minutes (Java + mod downloads). Also clarified in the modpack section that automatic install is Fabric-only, matching the `Get-ModpackLoader` guard.
- Validation: read-through only; no test target (pure documentation, no runtime behavior to assert beyond what `Get-ModpackLoader`'s tests already cover).

## Coverage and Known Gaps

- Full Pester suite: **36/36 passing** (`Invoke-Pester .\tests\`), up from the pre-existing 20.
- Not covered by automated tests: `Start.ps1`'s new menu branch (thin interactive wrapper — validated by parse-check only, not a scripted interactive run) and CurseForge's manual install path (unchanged, out of scope per the approved plan).
- `Minecraft/servers/_e2e-test/` (debris from the first live E2E run) has been deleted by the user. `Minecraft/servers/_e2e-forge-guard-test*/` never persisted — the guard itself removes them as part of its correct behavior (confirmed via `Test-Path` in this session).
- The TOCTOU issue previously flagged here as out of scope has since been fixed (`Set-RestrictedSecretFile`, see above) — this line intentionally left to show the gap was tracked and closed, not silently dropped.
- Real end-to-end coverage now spans two loaders: Fabric (Fabulously Optimized, confirmed installs correctly) and Forge (Create+, confirmed the loader guard fails fast with cleanup). Quilt and NeoForge are detected by `Get-ModpackLoader` (unit-tested) but have not been run against a live pack — by the same guard logic, they're treated identically to Forge (fail fast, no auto-install), so the untested risk is limited to "does detection correctly classify a real quilt/neoforge pack," not "does the install silently break."
- The rewritten `LEEME.md` has not been tested against an actual outside person with zero context — only reviewed for internal consistency and correctness against script behavior.
