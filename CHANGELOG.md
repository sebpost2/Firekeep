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
- "Server Settings" screen (Home screen button) for editing a server's
  `server.properties` - curated controls for difficulty, PvP, whitelist,
  max players, MOTD, and spawn protection, plus an advanced raw-text view
  for anything else in the file. RCON settings are never shown/editable.
  Requires the server to be stopped.
