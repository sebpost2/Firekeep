# Verity Local AI — Design

## Goal

The "Verity" mod (present in the VerityWorld/VerityCraft server packs) drives an
in-world AI entity via an external LLM (chat), TTS (voice out), and STT (voice
in). Out of the box it's configured for cloud providers (Groq/OpenRouter),
which are rate/token-limited. The goal is to run all three locally on the
host machine (RTX 5050, 8GB VRAM / 24GB RAM) so the user and friends get
unlimited usage, and to make this a first-class, GUI-managed feature of the
GameServers toolkit rather than a one-off manual setup.

## Background / findings

- Verity's entity is **shared across all players on a server** — its AI
  config lives entirely server-side, in `config/verity-common.toml`
  (`GeneralSettings.AISettings`, `.VoiceSettings`, `.SpeechSettings`). The
  per-client `verity-client.toml` is not authoritative for a dedicated
  server. This means only the **host machine** needs to run the local AI
  services — not each player.
- `aiProvider` already supports `OLLAMA` as a first-class value (alongside
  GEMINI/GROQ/OPENROUTER/MISTRAL/OPENAI) — no proxy layer (e.g. LiteLLM)
  needed.
- `ttsProvider` supports `KOKORO` (and `NATIVE`, `LOCAL`, `GROQ`).
  `sttProvider` supports `WHISPER` (and `NATIVE`, `GROQ`).
- The mod already bundles an offline Sherpa-ONNX Whisper-tiny.en model at
  `config/verity/sherpa-model/` for its `NATIVE` STT option — worth knowing
  as a zero-install fallback, though this design uses the dedicated
  `WHISPER` sidecar for better quality, per the user's explicit choice.
- A community fine-tune, `timheinrich2011/verity-3b` (Qwen2.5-3B tuned to
  Verity's prompt format), is published on Ollama's official registry
  (verified reachable at ollama.com). Chosen as the default model over the
  mod's stock `qwen2.5:1.5b`, since 8GB VRAM leaves headroom.

## Architecture

### 1. Detection & scope

The GUI scans a server instance's `mods/` folder for a `verity-*.jar` at
load time (same place `Get-DetectedJavaVersion` already inspects mods). A
"Local AI" section appears in that server's console screen only when
detected. No changes to non-Verity servers.

### 2. Components — three portable sidecar services

Installed once, **shared host-wide** (not per server instance), under
`Minecraft/tools/ai/`:

| Service | Purpose | Install method |
|---|---|---|
| `tools/ai/ollama/` | LLM brain (`timheinrich2011/verity-3b`) | Portable Ollama, resolved via its release API at install time (pattern matches `install-java.ps1`'s dynamic Adoptium lookup — never hardcode a version/URL) |
| `tools/ai/whisper/` | STT | Portable `whisper.cpp` server binary (native Windows exe) |
| `tools/ai/kokoro/` | TTS | Packaging method (native binary vs. bundled-Python) to be confirmed during implementation — Kokoro's official distribution is Python/Docker-first; implementation picks the simplest genuinely-portable method available at that time |

Each gets its own `Minecraft/scripts/install-<name>.ps1`, mirroring
`install-java.ps1`'s structure (no-admin, portable, checksum-verified where
the upstream provides one).

### 3. Config writing

New helper `Set-VerityLocalAI` in a new `_shared/scripts/verity-helpers.ps1`
(alongside the existing `curseforge-helpers.ps1`/`modloader-helpers.ps1`
pattern), editing the target server's `config/verity-common.toml`:

- `[GeneralSettings.AISettings]`: `aiProvider = "OLLAMA"`,
  `aiEndpoint = "http://127.0.0.1:11434/v1"`,
  `aiModel = "timheinrich2011/verity-3b"`
- `[GeneralSettings.VoiceSettings]`: `ttsProvider = "KOKORO"`,
  `ttsEndpoint = "http://127.0.0.1:8880/v1"`
- `[GeneralSettings.SpeechSettings]`: `sttProvider = "WHISPER"`,
  `sttEndpoint = "http://127.0.0.1:9000/v1"`

Runs once, when Local AI is first enabled for that server instance (same
one-shot-on-enable timing as `Set-PortableJavaForVariablesFile` during
CurseForge install).

### 4. Lifecycle

Sidecars are shared, host-wide background processes — one Ollama/Kokoro/
Whisper instance serves every Verity-enabled server on the host, since
Verity is a single shared entity per world and there's no reason to
duplicate the stack per instance.

A Verity-enabled server's `start.ps1` / `start-with-tunnel.ps1`:

1. Port-checks each of the 3 sidecars (same technique the GUI already uses
   to detect MC server up/down).
2. Starts any that aren't running, and waits for a health-check response
   (e.g. `GET /v1/models`) before proceeding — avoids Verity's
   known crash-on-missing-backend behavior.
3. Then launches the MC server as normal.

Sidecars are **not** auto-stopped when the MC server stops — they're cheap
to leave idle, and multiple servers may share them. A separate "Stop Local
AI" GUI action stops them explicitly.

### 5. GUI integration

On the per-server console screen (`ConsoleScreen.xaml`), when Verity is
detected: a "Local AI" status block showing each of the 3 services
(LIT/OUT, reusing the existing campfire status idiom from
`Get-ServerStatusView`) with a single "Start Local AI" / "Stop Local AI"
button, following the same state-machine pattern as
`Get-ActionButtonView` for the main server lifecycle. No new screen.

### 6. Testing

- Pester tests for the pure-logic pieces: `Set-VerityLocalAI`'s TOML
  editing, and any port/health-check helper functions — mirroring
  `tests/curseforge-helpers.tests.ps1`.
- Actual sidecar process management (installing/starting Ollama/Kokoro/
  Whisper, GPU inference) is verified manually, the same way this
  session's server boot tests were done — it needs real GPU/network I/O
  that Pester can't meaningfully mock.

## Explicitly out of scope

- Per-server sidecar instances (host-wide sharing is sufficient — Verity is
  one shared entity per world, not per-player).
- Model management UI (pulling/switching Ollama models from the GUI) —
  fixed default model for now.
- Support for AI mods other than Verity.
