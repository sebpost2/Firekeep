# CurseForge Client-Export Import — Design

**Date:** 2026-09-28
**Status:** Approved in conversation; awaiting written-spec review

## Context

Add Server accepts a CurseForge "Server Files" zip (`Install-CurseForgeServerZip`, `curseforge-helpers.ps1`) but throws on a **client export** (the zip the CurseForge app/website gives for a modpack: `manifest.json` + `overrides/`). Many packs ship no Server Files, so a non-technical user has no path to a server for them.

The Arcadia [RPG] server was built from such an export by hand on 2026-09-27. That build established the method and two rules:

1. **Extract with a real zip reader and byte-verify against the source zip.** A wildcard `unzip` silently dropped every file inside subfolders (858 config files, including all FTB quests and Paxi datapacks).
2. **Never remove "client-only" mods by name.** Removing Subtle Effects (it registers particles and sounds that Forge syncs from the server) crashed clients on join. Keep every mod; remove only what the server itself refuses to load, as named by the crash ("invalid dist DEDICATED_SERVER", or a Mixin apply failure). For Arcadia that was exactly 7 jars: Oculus, Blur, RyoamicLights, Great Scrollable Tooltips, ExtraSounds, ShoulderSurfing, ItemPhysicLite.

Facts checked against the real export (`Arcadia [RPG]-v3.8.2-fixed.zip`):

- `manifest.json`: `manifestType=minecraftModpack`, `minecraft.version=1.20.1`, `modLoaders[0].id=forge-47.4.20`, 367 `files` entries of `{projectID, fileID, required}`.
- `overrides/`: `config/` (1451 files), `defaultconfigs/`, `kubejs/`, `mods/` (3 hand-added jars that are not in the manifest), `resourcepacks/`, `shaderpacks/`, `paragliderSettings.nbt`.
- `https://www.curseforge.com/api/v1/mods/{projectID}/files/{fileID}/download` needs no API key and answers `307` with `Location: https://edge.forgecdn.net/files/.../<FileName>.jar?...`. So the real filename (and whether it's a `.jar`) is known from a HEAD request, before downloading anything.

## Decisions (made with the user)

| Question | Decision |
|---|---|
| Loaders in the first version | **Forge only.** NeoForge/Fabric exports get a clear "not supported yet" message. NeoForge is a later follow-up (same installer model). |
| Client-only mod crashes | **One-click fix with confirmation**: a Home button moves the named jar to `_excluded\client-only\` and starts again. Never automatic. |
| Mods that can't be downloaded | **Finish the import and list them.** Start stays blocked until the listed jars are present. |
| Implementation | **Built into Firekeep in PowerShell**, downloads 6 at a time. Not ServerPackCreator (it removes client-only mods by built-in name lists, violating rule 2). |

## Goals

1. Dropping a Forge client export on Add Server produces a server that boots, with no hand editing beyond confirming client-only mod removals.
2. The resulting `mods/` and configs match what a correct hand build produces (rules 1 and 2).
3. Nothing fails silently: every file that couldn't be fetched is listed by name with a link, and the server can't be started while one is missing.

## Non-goals

- NeoForge, Fabric, Quilt exports.
- Removing client-only mods proactively or by name.
- Resource packs, shader packs, and other non-`.jar` manifest files (a server doesn't use them; this matches the Arcadia hand build).
- Updating an existing server to a newer pack version.
- Automatically cleaning up a half-built folder left by closing Firekeep mid-import.

## Components

All new import code lives in `_shared\scripts\curseforge-helpers.ps1` unless stated.

### 1. `Get-CurseForgeZipKind -ZipPath`

Reads the zip's entry list without extracting. Returns `"ServerFiles"` when any of today's Server Files markers is present (`variables.txt`, `run.bat`, `startserver.bat`, `fabric-server-mc.*`, `forge-*-installer.jar` — the same list `Install-CurseForgeServerZip` searches for), else `"ClientExport"` when a root `manifest.json` has `manifestType` `minecraftModpack`, else `$null`. The Add Server job branches on it; `$null` keeps today's "doesn't look like CurseForge" error.

### 2. `Read-CurseForgeManifest -ZipPath`

Returns `{ McVersion; ForgeVersion; Files = @({ProjectId; FileId}); OverridesDir }`. Throws a user-facing message when the loader isn't `forge-*` ("This modpack uses NeoForge, which Firekeep can't import yet.").

### 3. `Resolve-CurseForgeFile -ProjectId -FileId [-BaseUrl]`

HEAD request with redirects disabled; returns `{ FileName; Url }` from the `Location` header (filename URL-decoded, query string dropped). `-BaseUrl` defaults to `https://www.curseforge.com` and exists so tests can point at a local fake server.

### 4. `Invoke-ParallelDownload -Items -Throttle 6 -Retries 3`

Runs a script block per item in a runspace pool (6 at a time). Used twice: to resolve names, then to download the `.jar` files. Each item returns ok or a failure reason. A download is written to `<name>.part` and renamed only when complete, so a failed download never leaves a truncated jar in `mods/`. Reports progress through `Write-Progress`, which the Add Server job already surfaces (component 9).

### 5. `Expand-ZipFolderVerified -ZipPath -Prefix "overrides/" -Destination -ExcludeTop @("resourcepacks","shaderpacks")`

Copies every entry under the prefix with `System.IO.Compression.ZipFile`, creating subfolders, skipping the excluded top-level folders. Then verifies every copied file against its entry (length + SHA-256 of the entry stream). Throws naming the first mismatch. The three hand-added jars in `overrides/mods/` arrive this way.

### 6. `Install-ForgeServer -McVersion -ForgeVersion -DestPath -JavaExe`

Downloads `https://maven.minecraftforge.net/net/minecraftforge/forge/{mc}-{forge}/forge-{mc}-{forge}-installer.jar`, runs `java -jar <installer> --installServer <DestPath>`, and confirms that `run.bat` exists afterwards. Deletes the installer jar on success. On failure it throws, keeping the installer log at a `%TEMP%` path named in the message.

### 7. `Install-CurseForgeClientExport -ZipPath -DestPath -McRoot`

Orchestrates 2 → 3 (all files) → filter `.jar` → 4 (download into `mods/`) → 5 → Java (`install-java.ps1` for `Get-JavaVersionForMinecraft`) → 6. Writes `MISSING-MODS.txt` when anything failed. Returns `{ JavaVersion; MissingCount }`. If **every** file failed to resolve or download, throws "Couldn't reach CurseForge - check the internet connection" instead of creating a server with nothing in it.

### 8. Missing-mods list (`gui-helpers.ps1`)

`MISSING-MODS.txt` in the server folder, human-readable, one mod per block: expected filename (when known), `https://www.curseforge.com/projects/{projectID}`, and the direct download link. A marker line per entry lets code read it back.

`Get-MissingModDownloads -InstancePath` returns the entries whose exact filename isn't in `mods/` (an entry with an unknown filename stays missing until the file is removed by hand). When none remain it deletes the file and returns an empty list. Only the exact filename counts: a different version could mismatch players' clients.

### 9. GUI (`Start-Gui.ps1`, `HomeScreen.xaml`)

- **Add Server job:** calls `Get-CurseForgeZipKind` and the matching import. The add-job timer shows the job's latest progress record (`$job.ChildJobs[0].Progress`) in the hint text, e.g. "Downloading mods 120/363…".
- **Start blocked while mods are missing:** on Start, if `Get-MissingModDownloads` returns anything, show "N mods still need a manual download" and a **Show missing mods** link that opens `MISSING-MODS.txt` and the `mods` folder.
- **One-click client-only fix:** `Get-ClientOnlyModJar -InstancePath -ConsoleText` returns the jar to move: from the "invalid dist" crash's `Mod File:` path, or, for a Mixin failure (mod ID only), by reading `META-INF/mods.toml` inside `mods/*.jar` to find the matching `modId`. When a start failure has such a jar, Home shows **Move it aside and start again**. After a confirmation that names the file, the jar moves to `_excluded\client-only\` and the server starts again.

## Error handling

| Failure | Behaviour |
|---|---|
| Loader isn't Forge | Stop before downloading; no folder created. |
| Name lookup fails | Retry 3 times; then listed in `MISSING-MODS.txt` by project link. |
| Jar download fails (blocked, removed, network) | Retry 3 times; delete the `.part` file; list as missing. |
| Every lookup/download fails | Import fails ("Couldn't reach CurseForge - check the internet connection"); folder removed. |
| Overrides file doesn't match the zip | Import fails naming the file; folder removed. |
| Java install fails | Import fails with the existing Java message; folder removed. |
| Forge installer fails / no `run.bat` | Import fails; folder removed; installer log kept in `%TEMP%`, path in the message. |
| Firekeep closed mid-import | Background job stops (existing behaviour). A re-import with the same name gets "a half-built server named X exists; delete that folder or pick another name". |
| Wrong jar offered by the one-click fix | The confirmation names the file; the jar is moved, never deleted, so it can be put back. |

## Testing

**Pester (offline).** Fixture zips and a fake local HTTP server (`System.Net.HttpListener` in a runspace, same pattern as the fake RCON server in `tests/rcon.tests.ps1`), with cleanup in `finally` blocks:

- Zip kind: Server Files, Forge client export, NeoForge export, unrelated zip.
- Manifest: Forge versions read; NeoForge/Fabric throw the friendly message.
- Name resolution: filename taken from the redirect; no body downloaded.
- Parallel download: all files arrive intact; fails twice then succeeds → kept; always fails → reported missing with no file or `.part` left; only `.jar` downloaded.
- Verified extraction: nested-folder files all present (rule 1 regression); excluded folders skipped; a file altered after extraction → mismatch detected.
- Missing mods: blocked while a listed jar is absent; allowed and list removed once present; unknown-filename entries stay missing.
- Client-only jar lookup: `Mod File:` path; Mixin mod ID matched through `mods.toml` in test jars.

**End to end (with the user).** Import the real `Arcadia [RPG]-v3.8.2-fixed.zip` into a throwaway `ArcadiaImportTest` server. Compare it with the hand-built Arcadia: the same jars in `mods/`, allowing for the 7 client-only jars Arcadia excluded and the 5 server-only mods added to it by hand (Chunky, Structure Layout Optimizer, Smooth Chunk Save, Noisium, Ksyxis), and every file from `overrides/` identical (configs later edited on the running Arcadia server aside). Start it and use the one-click fix until it boots; it should offer exactly those 7 mods. The user deletes `ArcadiaImportTest` afterwards. The real Arcadia server is not touched.

**Done:** all tests pass, and the real Arcadia export becomes a booting server with at most 7 confirmation clicks and no hand editing.
