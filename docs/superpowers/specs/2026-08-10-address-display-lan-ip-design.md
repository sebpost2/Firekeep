# Address Display: LAN IP + Manual Override — Design

**Date:** 2026-08-10
**Status:** Approved

## Context

`Update-AddressDisplay` (`Start-Gui.ps1:161-189`) already degrades gracefully when playit.gg isn't configured — it shows "Same WiFi only (no sharing set up yet)" and reveals the `SetupTunnelButton`. This is confirmed working correctly; nothing here is broken. Two gaps remain:

1. It never computes or shows the actual LAN IP, so a user on the same network still doesn't know what address to type.
2. Some users can port-forward their own router (not everyone can — that's why playit.gg exists as an option) and want to show that address instead of setting up a tunnel at all. There's currently no way to enter one.

## Goals

1. Auto-detect and display the local LAN IP + server port when no playit.gg tunnel is active, so same-network sharing works without extra setup.
2. Let a user who port-forwards manually enter their own address (public IP, DDNS hostname, whatever they use) and have it take priority for both display and Copy.

## Components

### 1. `Get-LanAddress` helper

New function (co-located with other network/address helpers — likely `_shared\scripts\gui-helpers.ps1` or `tunnel-helpers.ps1`, matching wherever address logic already lives). Signature: `Get-LanAddress -Port <int> -> [string]`. Finds the machine's active local IPv4 address (excluding loopback/APIPA) and returns `"<ip>:<port>"`. Returns `""` if no suitable adapter is found (never throws — matches the project's established pattern for best-effort display helpers like `Get-AppVersion`).

### 2. Manual address override

**Correction found during planning:** `Update-AddressDisplay` and playit.gg's `secret.key`/`address.txt` are app-wide (`_shared\tools\playit\`), not per-server-instance — there's one tunnel for the whole app, not one per Minecraft server. The manual override follows the same shape: stored app-wide as `_shared\tools\playit\manual-address.txt`, alongside the existing `address.txt`, rather than inside each server's own folder. One override value applies regardless of which server is selected, since it represents "my network's address," not a per-server fact.

### 3. Home screen UI

`HomeScreen.xaml`: a text field + small "Use this address" button/link, added to the same area as `SetupTunnelButton`, visible whenever playit.gg isn't the active source (i.e., no tunnel currently resolved — same visibility condition already governing when `SetupTunnelButton` shows today).

`Start-Gui.ps1`: wire the field's save action to write `manual-address.txt`; wire `Update-AddressDisplay`'s priority chain (see Data Flow).

### 4. Priority chain in `Update-AddressDisplay`

Manual override (if `manual-address.txt` exists and is non-empty) → playit.gg cached/live domain (today's existing logic, untouched) → computed LAN IP via `Get-LanAddress` → today's final fallback text ("Same WiFi only...") if LAN detection also comes back empty.

## Data Flow

Home screen load / server select → `Update-AddressDisplay` reads `manual-address.txt` → if empty, existing playit logic runs unchanged → if playit has nothing, call `Get-LanAddress -Port <server's port>` → render whichever value won, enable Copy to copy that same value.

## Error Handling

- `Get-LanAddress` never throws; empty result falls through to existing "Same WiFi only" text.
- Manual override is free text with no validation beyond non-empty — the user is asserting their own port-forward exists; the app has no way to verify it.
- No change to playit.gg's existing error handling (API failure → cached `address.txt` → "Same WiFi only") — this spec only adds two new links to the front of that chain.

## Testing

- Unit test `Get-LanAddress`: given mocked/injected adapter info, assert correct `ip:port` formatting; given no suitable adapter, assert `""`.
- Unit test the extracted priority-chain logic (a pure function taking the three candidate values and returning the winner), independent of the WPF-bound `Update-AddressDisplay` itself — matches the project's existing pattern of testing helpers, not XAML interaction.

## Decisions Made

- Manual override lives on the Home screen, always visible when playit isn't active — not tucked into a secondary/advanced screen, since it's a direct alternative to the tunnel-setup button that's already there.
- No address validation — trust the user.
- Separate cache file from playit's `address.txt` rather than reusing/overloading it, to keep the two address sources independently inspectable and avoid cache-invalidation ordering bugs between them.
- App-wide storage (matching playit's own `_shared\tools\playit\` location), not per-server-instance — corrected during planning once the existing code showed playit itself is app-wide, not per-instance.
