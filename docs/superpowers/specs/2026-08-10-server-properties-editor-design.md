# Server Settings Editor (server.properties) — Design

**Date:** 2026-08-10
**Status:** Approved

## Context

Release readiness was reviewed alongside this design. The three connection
paths a user might use are already covered without new work:

- **LAN** — auto-detected via `Get-LanAddress` (`tunnel-helpers.ps1`).
- **Port-forward + own public IP** — covered by the manual address override
  field on the Home screen (`docs/superpowers/specs/2026-08-10-address-display-lan-ip-design.md`).
- **playit.gg** — one-time account link + one manual tunnel entry in the
  playit.gg dashboard (documented in `README.md`); reconnects on its own
  after that. Considered easy enough as-is.

Verity (the AI mod integration) is out of scope for this release check —
treated as an extra, not a blocker.

The one real gap: there's no way to tweak a server's day-to-day settings
(difficulty, PvP, whitelist, max players, etc.) without leaving the app and
hand-editing `server.properties` in a text editor. This blocks release per
the user's decision — it ships as part of 1.0.0.

## Goals

1. Let a user change the handful of settings people actually touch, via
   plain-English controls, without hand-editing a file.
2. Provide an escape hatch (raw editor) for anything not in the curated
   list, without exposing/risking the RCON lines the app depends on.
3. Reuse the existing `Read-ServerProperties` parser (`rcon.ps1`) rather
   than writing a second one.

## Components

### 1. `_shared\scripts\server-properties-helpers.ps1` (new file)

- `Read-ServerProperties` already exists in `rcon.ps1` (key/value hashtable,
  skips comments) — reused as-is, not duplicated.
- `Write-ServerProperties -Path -Values` (new): rewrites the file
  line-by-line, replacing only the lines for keys present in `$Values`,
  preserving every other line (comments, ordering, untouched keys)
  byte-for-byte. Keys in `$Values` that don't already have a line in the
  file are appended at the end.
- `Get-ServerPropertyDefaults` (new): hard-coded table of Minecraft's own
  defaults for the curated fields (`difficulty=easy`, `pvp=true`,
  `white-list=false`, `max-players=20`, `motd=A Minecraft Server`,
  `spawn-protection=16`) — used to pre-fill the form when a brand-new
  server's `server.properties` doesn't have these keys yet (only the RCON
  lines exist until Minecraft's first boot populates the rest).
- Both `Write-ServerProperties` and the raw-editor code path exclude
  `enable-rcon`, `rcon.port`, `rcon.password` — these are always read
  from the file and passed through untouched, never shown or editable, in
  either the curated or advanced view. They're auto-generated at server
  creation (`New-ServerFromTemplate`) and required by the existing Stop
  Server flow; letting a user clear/edit them would silently break it.

### 2. `_shared\gui\ServerSettingsScreen.xaml` (new screen)

Mirrors `ManageMapsScreen.xaml` conventions (same header/back-button
pattern, same screen-switching mechanism in `Start-Gui.ps1`).

- **Curated section:** Difficulty (dropdown), PvP (toggle), Whitelist
  (toggle), Max players (number box), Server name/MOTD (text box), Spawn
  protection radius (number box).
- **Advanced toggle:** reveals a multi-line text box containing the raw
  file content minus the three RCON lines (which stay hidden and are
  re-inserted verbatim on save regardless of what's in the box).
- **Save** button calls `Write-ServerProperties`; **Back** discards
  in-memory changes and returns to Home.

### 3. Home screen entry point

`HomeScreen.xaml`: new "Server Settings" button next to the existing
"Manage Maps" button. `Start-Gui.ps1`: same enable/disable wiring already
used for Manage Maps — disabled with a tooltip ("Stop the server first")
while the selected server is running, since `server.properties` is only
read by Minecraft at boot.

## Data Flow

Home screen → click "Server Settings" (only enabled when stopped) →
`Read-ServerProperties` loads the file → curated fields populated from
file values, falling back to `Get-ServerPropertyDefaults` for any missing
key → advanced box populated with remaining raw lines (RCON lines
stripped) → user edits → Save → `Write-ServerProperties` merges curated
field values + advanced box lines + untouched RCON lines back into the
file → return to Home.

## Error Handling

- File missing entirely (shouldn't happen post-creation, but defensive):
  treat as empty — curated fields show defaults, advanced box is empty,
  save creates the file fresh with RCON lines re-generated the same way
  `New-ServerFromTemplate` does.
- No validation on the advanced raw box beyond stripping RCON lines before
  write — the user can enter malformed `key=value` lines; Minecraft itself
  will ignore/default anything it can't parse on next boot, matching how
  hand-editing the file today already behaves.
- Numeric fields (max players, spawn protection) clamp to non-negative
  integers before write; invalid input reverts to the last valid value
  rather than blocking Save.

## Testing

- New Pester test file for `server-properties-helpers.ps1`:
  - Round-trip: read → change a value via `Write-ServerProperties` → 
    re-read → changed key updated, untouched keys/comments preserved
    verbatim.
  - RCON lines are never altered by `Write-ServerProperties` even when
    passed conflicting values for those keys.
  - `Get-ServerPropertyDefaults` values used when a key is absent from the
    file (fresh-server case).
- No XAML/interaction test — matches the project's existing pattern of
  testing shared script logic headlessly, not the GUI screens themselves.

## Decisions Made

- `server.properties` only (not `user_jvm_args.txt`/memory, not
  ops/whitelist JSON) — scoped to the most common day-to-day tuning file;
  other config files are a future/separate feature if needed.
- Curated form + advanced raw toggle, not form-only or raw-only — balances
  approachability for non-technical hosts with not silently losing access
  to settings outside the curated list.
- Stopped-only editing, matching the existing Manage Maps precedent, since
  the file is only read at boot — editing while running would be
  misleading (the running server wouldn't reflect the change).
- RCON lines are permanently hidden/protected in both views rather than
  trusted to user judgment, because breaking them breaks the existing Stop
  Server feature silently (no error surfaces until the next stop attempt).
