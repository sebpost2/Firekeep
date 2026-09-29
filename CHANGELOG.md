# Changelog

All notable changes to this project are documented here. Loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.1] - 2026-09-29

### Fixed
- After creating a server, Home kept the smaller Add Server window size,
  so the "Created - but..." message and **Show missing mods** were hidden
  below the START button. Each screen gets its own size again; a size you
  drag the window to is still kept.
- The Add Server drop zone called every .zip "CurseForge Server Files",
  even regular CurseForge modpack downloads. It now says "CurseForge
  modpack".
- "1 mods" now reads "1 mod" in the missing-mod messages.

## [1.2.0] - 2026-09-28

### Added
- Add Server imports regular CurseForge modpack downloads (Forge packs for
  Minecraft 1.17 and newer), not just "Server Files": it downloads the
  mods itself (6 at a time, with progress shown), copies the pack's
  settings with a byte-for-byte check, and installs Forge. Resource packs,
  shaders and optional mods are skipped, like the CurseForge app does.
- Mods that can't be downloaded are listed in `MISSING-MODS.txt` with a
  link to each (Home shows **Show missing mods**); Start waits until
  they're added.
- When the server refuses a mod that only works in the game client, Home
  names it and offers **Move it aside and start again** (after you
  confirm; the jar goes to `_excluded\client-only`, never deleted). This
  also covers mods that need one already moved aside.
- NeoForge, Fabric, and pre-1.17 Forge packs are refused up front with a
  clear message instead of failing after a long download.

### Fixed
- Modpack files with `[brackets]` in their name (common on CurseForge) were
  reported as missing - for CurseForge, `.mrpack` and world imports alike.
- A failed Add Server import could leave a half-built server behind,
  blocking its name for the next try.
- Packs with the "Default Server Properties" mod turned RCON off at
  startup, so Firekeep showed the running server as stopped and couldn't
  stop it.
- Start-failure messages no longer blame the wrong mod when harmless
  client-class warnings appear in the log, and name the mod that actually
  failed (e.g. ShoulderSurfing, not Create; Controllable, not Framework).

## [1.1.0] - 2026-09-28

### Added
- Automatic world backup on the first start of each day, into the server's
  `backups\` folder (newest 5 kept). Restore with Manage Maps -> Import.
- Failed starts are explained in one sentence on the Home screen (memory,
  wrong or broken Java, client-only or failing mod, missing dependency, port
  or world already in use, EULA, Java download) instead of staying on
  "Starting" forever. Server output is captured to
  `logsirekeep-console.log`.
- Suggested max memory (from the PC's RAM and the mod count) in Add Server
  and Server Settings, with a warning when a value leaves Windows too little.
- Aikar's GC flags are added when a modpack sets no garbage collector.
- Existing servers pick up `start.ps1` fixes automatically when their copy
  is an unmodified earlier template (customized copies are left alone).

### Fixed
- Max memory was ignored by Forge/NeoForge and ServerPackCreator servers
  (they read `user_jvm_args.txt` / `variables.txt`, not `run.config.ps1`).
- A broken or half-installed portable Java was never repaired; it's now
  checked by actually running it, and reinstalled.
- Servers not created from the template had no RCON, so they showed as
  stopped forever and couldn't be stopped. Every server now gets it.
- Forge's `run.bat` "pause" left a hidden window holding the server folder
  after a stop, which blocked deleting it and the next start. Such leftovers
  are also cleared automatically on Start.
- Console: slow or empty replies (e.g. Chunky) looked like the command did
  nothing; a leading "/" is now accepted.
- The GUI's status polling no longer makes Minecraft log an RCON client
  connecting several times a second.
- Home screen header still said "GAME SERVERS".

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
- "Server Settings" screen (Home screen button) for editing a server's
  `server.properties` - curated controls for difficulty, PvP, whitelist,
  max players, MOTD, spawn protection, and max memory (`run.config.ps1`'s
  `$MaxRam`), plus an advanced raw-text view for anything else in the file.
  RCON settings are never shown/editable. Requires the server to be stopped.

### Changed

- Project renamed from "Game Servers" to **Firekeep** ahead of the public
  GitHub release (app window title, README, release-zip naming).

### Fixed

- Advanced Server Settings text box could grow past the visible window with
  no scrollbar, hiding everything below it.
- Starting a server popped up a bare PowerShell console window; it now
  launches hidden, matching how Stop Server already runs.
- The manual-address box on the Home screen was hidden once playit.gg
  produced an address, leaving no way to override it with a port-forwarded
  IP or force LAN-only. It's now always visible - fill it in to override,
  clear it to go back to playit.gg/auto.
