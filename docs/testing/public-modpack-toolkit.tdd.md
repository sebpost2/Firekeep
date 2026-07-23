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

## Coverage and Known Gaps

- Full Pester suite: **27/27 passing** (`Invoke-Pester .\tests\`), up from the pre-existing 20.
- Not covered by automated tests: `Start.ps1`'s new menu branch (thin interactive wrapper — validated by parse-check only, not a scripted interactive run) and CurseForge's manual install path (unchanged, out of scope per the approved plan).
- `Minecraft/servers/_e2e-test/` (debris from the live E2E run, pre-dating the encoding fix) is left on disk — gitignored, harmless, deletion declined during this session; safe to delete manually at any time.
- Background security scan flagged a pre-existing TOCTOU issue in `_shared/scripts/setup-playit.ps1` (secret file briefly world-readable before `icacls` restricts it) — out of scope for this plan, not addressed here.
