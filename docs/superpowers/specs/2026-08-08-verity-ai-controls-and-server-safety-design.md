# Verity AI Per-Process Controls & Server-Creation Safety — Design

## Goal

Two problems surfaced while testing the "Horror Ultimate Selection" pack:

1. Its folder name has spaces, which trips ServerPackCreator's vendored
   `start.ps1` into a blocking `Are you sure? (Yes/No)` console prompt. Left
   unanswered, the Minecraft server process never launches — but the
   playit.gg tunnel comes up anyway and hands out an address, so players get
   `Connection reset` trying to join a server that was never actually there.
2. The Local AI stack ([2026-08-07 design](2026-08-07-verity-local-ai-design.md))
   is all-or-nothing: one GUI button starts/stops Ollama+Kokoro+Whisper
   together, and `start-with-tunnel.ps1` unconditionally tries to start all
   three on every boot regardless of what's configured. There's no way to
   run just the parts you want (e.g. local LLM + cloud TTS), and the
   sidecars are left running indefinitely after you stop playing.

This design fixes the immediate stuck server, prevents the spaces problem at
its source (server creation), adds per-service Local AI controls, and stops
the sidecars automatically when they're no longer needed.

## 1. Immediate fix

Rename `Minecraft/servers/Horror Ultimate Selection` →
`Minecraft/servers/HorrorUltimateSelection`. One-time operational step, no
code change. Any GUI state that references the old folder name (recent
selection, etc.) is derived at runtime from `Get-ServerInstances`, so no
stored references need updating.

## 2. Block spaces at server-creation time

In `Start-Gui.ps1`'s `$createButton.Add_Click` handler (~line 614-616),
validate `$name` before calling `New-ServerFromTemplate`: if it contains a
space (or any other character invalid in a Windows path), stop and show an
error in `$addHintText` — e.g. *"Server names can't contain spaces — some
modpacks' launch scripts break on spaced paths. Try 'HorrorUltimate'
instead."* No job is started; the user edits the name box and retries.

This is a hard block, not a warning — creating a broken server should not be
possible. The same validation is added to the console wizard
(`Minecraft/scripts/new-server.ps1`) at the point it collects a name, since
both paths call the same `New-ServerFromTemplate`.

Pester coverage: extend `tests/new-server-helpers.tests.ps1` (or add a
validation helper, e.g. `Test-ServerNameValid`, that both the GUI and the
console wizard call, and test that directly) for: name with a space →
rejected; name with only safe characters → accepted.

## 3. Per-process Local AI controls

Supersedes section 4 ("Lifecycle") of the 2026-08-07 design, which made all
three sidecars start/stop together and never auto-stop.

### Source of truth: the TOML, not new state

`config/verity-common.toml` already independently records which provider
each of the 3 subsystems uses (`aiProvider`, `ttsProvider`, `sttProvider`).
Rather than inventing separate on/off storage, that config **is** the
persisted preference:

- A service is "on" (local) when its provider field equals the local value
  (`OLLAMA` / `KOKORO` / `WHISPER`).
- Turning a service "off" reverts just that field to Verity's vanilla
  default (`aiProvider = "OPENAI"`, `ttsProvider = "NATIVE"`,
  `sttProvider = "NATIVE"`) — never leaves it pointed at a dead endpoint.

### `verity-helpers.ps1` changes

- Replace `Set-VerityLocalAI` (which unconditionally sets all three) with
  `Set-VerityAiProvider -InstancePath -Service <Ollama|Kokoro|Whisper>
  -UseLocal <bool>`, editing only that service's section via the existing
  `Set-TomlSectionValue`.
- Replace `Start-VerityLocalAiStack` / `Stop-VerityLocalAiStack` with
  per-service functions: `Start-OllamaSidecar`, `Start-KokoroSidecar`,
  `Start-WhisperSidecar` (each: install-if-needed, launch, health-check —
  same bodies as today's combined function, just split) and matching
  `Stop-OllamaSidecar` / `Stop-KokoroSidecar` / `Stop-WhisperSidecar`
  (stop-by-port, same logic as today, split out).
- Add `Get-VerityRequiredSidecars -InstancePath`, reading the toml and
  returning which of the 3 services are currently configured local — used
  by the boot-time auto-start (below) and by the GUI to render initial
  toggle state.
- Keep a thin `Stop-VerityLocalAiStack` wrapper (calls all three `Stop-*`)
  for the boot-safety and stop-server use cases in sections 1 and 4, where
  "stop whatever's running" is simpler than tracking which were on.

### Boot-time auto-start (`start-with-tunnel.ps1`)

Change from "always start all 3" to: call `Get-VerityRequiredSidecars`,
start only the ones actually configured local. If none are configured
local, skip the Local AI step entirely (no warning spam for someone who
deliberately runs cloud-only).

### GUI (`HomeScreen.xaml` + `Start-Gui.ps1`)

The current single `VerityAiPanel` (one status line + one button) becomes 3
rows, one per service (Core LLM / TTS / STT), each showing LIT/OUT and its
own Start/Stop button — same visual idiom as the existing campfire
status/action-button pattern. Each button's click handler:

1. Disables itself, runs the corresponding `Start-<X>Sidecar` /
   `Stop-<X>Sidecar` + `Set-VerityAiProvider` pair in a background job
   (same `Start-Job` pattern as today's handler).
2. On completion, re-enables and refreshes via `Sync-StatusDisplay`.

A "Stop All" link remains for convenience, calling the three `Stop-*`
functions plus reverting all three provider fields.

### Testing

Extend `tests/verity-helpers.tests.ps1` with the split functions' TOML-only
logic (`Set-VerityAiProvider` per service, `Get-VerityRequiredSidecars`
reading various toml states) — same Pester-mockable scope as existing
coverage. Actual process start/stop and GPU inference remain manually
verified, per the prior design's rationale.

## 4. Auto-stop sidecars when no longer needed

In `_shared/scripts/stop-server.ps1`, after `Stop-OneServer` successfully
stops a server: if that server has Verity installed
(`Test-VerityModPresent`), check every *other* instance from
`Get-AllServerInstances` — if none of them are **both** Verity-enabled
**and** currently running (RCON port open, same check the "no -ServerPath"
branch already does), call `Stop-VerityLocalAiStack`. Since that function
stops whatever happens to be listening on ports 11434/8880/9000, it
correctly handles any subset (just the LLM, all three, etc.) without needing
to know which were on.

This runs for both the GUI's stop button and the console `Stop Server.bat`,
since both go through this script. If another Verity server is still
running, the sidecars are left alone.

## Explicitly out of scope

- Migrating already-created servers with spaces in their names (handled
  case-by-case, as with Horror Ultimate Selection today).
- A "some services on, some off" indicator anywhere other than the GUI's 3
  status rows (e.g. no console-log summary).
- Changing the shared, host-wide nature of the sidecars (still one set for
  the whole machine, per the 2026-08-07 design).
