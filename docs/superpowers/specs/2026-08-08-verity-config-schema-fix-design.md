# Verity local-AI config schema fix

## Problem

`_shared/scripts/verity-helpers.ps1` (which the GUI's "Local AI" panel calls)
was written against an older Verity config layout. The installed mod
(`verity-5.7.1.jar`) uses a different, flat schema. Concretely:

- The script reads/writes `[GeneralSettings.AISettings]`,
  `[GeneralSettings.VoiceSettings]`, `[GeneralSettings.SpeechSettings]` with
  enum-style keys (`aiProvider = "OLLAMA"`, `ttsProvider = "KOKORO"`,
  `sttProvider = "WHISPER"`).
- The real `config/verity-common.toml` has a single flat `[AISettings]`
  section with boolean toggles: `use_ollama`, `use_kokoro`,
  `use_local_whisper`.

Result: clicking Start/Stop on the GUI's Ollama/Kokoro/Whisper buttons
silently writes keys the mod never reads. The server falls back to its cloud
`aiProvider` (Groq), and with no `apiKey` set, players get `HTTP 401 Invalid
API Key` when talking to Verity.

Confirmed by decompiling `AiAPI.class` from the installed jar: when
`use_ollama` is true, Verity does a generic HTTP POST to
`{ollama_url}chat/completions` with `"model": <ollama_ai_model>` sent
verbatim. There's no LiteLLM-specific behavior - the stock default
(`http://127.0.0.1:4000/v1/` + `ollama/qwen2.5:1.5b`) is just Verity's
suggested LiteLLM setup, not a requirement. Kokoro/Whisper stock defaults
(`:8880`, `:9000`) already match the ports this repo's sidecars use, and
both sidecar servers ignore the `model` field they're sent, so those two
need no URL/model correction - only the boolean keys are wrong.

## Goals

- Fix `Set-VerityAiProvider` / `Get-VerityRequiredSidecars` to read/write the
  real schema, for all three services (Ollama, Kokoro, Whisper).
- Point the Ollama toggle at the raw Ollama sidecar (port 11434, model
  `timheinrich2011/verity-3b`) instead of a nonexistent LiteLLM proxy on
  port 4000. No new sidecar service is introduced.
- Add a Groq API key field to the GUI's Local AI panel, so the cloud-fallback
  path is also user-fixable without hand-editing TOML.
- Update `tests/verity-helpers.tests.ps1` fixtures/assertions to match the
  real schema.

## Non-goals

- Building a LiteLLM proxy sidecar. Not needed - see Problem section.
- Changing `aiModel` (intelligence level: FAST_LITE/FAST/INTELLIGENT) or
  `aiProvider` (GROQ/OPENROUTER) selection UI - out of scope for this fix.
- Auto-detecting or validating the pasted Groq key (e.g. a test call) -
  just persist what the user enters.

## Design

### Config schema mapping

All three toggles live under a single `[AISettings]` section:

| Service | Enable flag (bool) | URL key | Model key | Fixed value when enabling |
|---|---|---|---|---|
| Ollama | `use_ollama` | `ollama_url` | `ollama_ai_model` | `http://127.0.0.1:11434/v1/`, `timheinrich2011/verity-3b` |
| Kokoro | `use_kokoro` | `ollama_tts_url` | `ollama_tts_model` | `http://127.0.0.1:8880/v1/`, `kokoro` |
| Whisper | `use_local_whisper` | `ollama_stt_url` | `ollama_stt_model` | `http://127.0.0.1:9000/v1/`, `base.en` |

`apiKey` (also under `[AISettings]`) is a separate, independent field - not
touched by the Ollama/Kokoro/Whisper toggles.

### `Set-VerityAiProvider` rewrite

Same public signature (`-InstancePath`, `-Service`, `-UseLocal`). Internally:

- Section is always `"AISettings"` (not nested).
- Writes the boolean enable-flag via a new boolean-aware TOML setter (see
  below) - `true`/`false` unquoted, since these are TOML booleans, not
  strings.
- When `-UseLocal $true`: also force-writes the URL and model keys to the
  fixed values in the table above, so the config is always in a known-good
  state regardless of what was there before (matches the existing
  "toml is the single source of truth" pattern already used for the old
  schema).
- When `-UseLocal $false`: only clears the boolean flag. URL/model are left
  as-is - Verity ignores them once the flag is off, so there's nothing to
  clean up.

### New: `Set-TomlSectionBoolValue`

`Set-TomlSectionValue` always double-quotes its value, which is correct for
`ollama_url`/`ollama_ai_model` (TOML strings) but wrong for `use_ollama`
(TOML boolean - unquoted `true`/`false`). Add a sibling function with the
same section/key matching logic, writing `$Key = $Value` unquoted instead of
`$Key = "$Value"`. `Set-VerityAiProvider` uses this only for the three
enable-flags; existing quoted-string calls for URL/model keys are unchanged.

### `Get-VerityRequiredSidecars` rewrite

Same public signature and return shape (`@("Ollama", "Kokoro", "Whisper")`
subset). Internally, matches the flat boolean keys instead of the old enum
patterns:

```
use_ollama\s*=\s*true        -> "Ollama"
use_kokoro\s*=\s*true        -> "Kokoro"
use_local_whisper\s*=\s*true -> "Whisper"
```

### GUI: Groq API key field

Added to `_shared/gui/HomeScreen.xaml`'s existing `VerityAiPanel` (the same
collapsed-until-Verity-detected panel that already hosts the three
Start/Stop rows), as a new row above "STOP ALL":

- Label "Groq API Key"
- `PasswordBox` (masked input - avoids the key being visible over a
  shoulder or in a screen share)
- "SAVE" button

Wiring in `Start-Gui.ps1`, alongside the existing `Invoke-VerityServiceToggle`
wiring:

- On save: writes the entered value to `apiKey` under `[AISettings]` via the
  existing (string, quoted) `Set-TomlSectionValue`, for `$script:selected`'s
  instance path.
- On server selection change (`Sync-StatusDisplay`, where the panel's
  visibility is already toggled): pre-fill the PasswordBox's `.Password`
  from the current config's `apiKey`, so it reflects what's actually saved
  rather than always starting blank.
- Empty save is allowed (clears the key back to `""`) - no validation beyond
  that; matches the non-goal of not verifying the key against Groq.

### Error handling

Unchanged from the existing pattern: `Set-VerityAiProvider` still throws if
`config\verity-common.toml` doesn't exist under the instance path (caught
already by callers). No new failure modes introduced - reading/writing a
`PasswordBox` value can't itself fail in a way that needs handling here.

### Testing

`tests/verity-helpers.tests.ps1` fixtures currently build synthetic TOML
using the old nested-section schema. Rewrite them to use the real flat
`[AISettings]` schema (matching the shape of an actual
`config/verity-common.toml`), and update assertions to check the new
boolean keys and the fixed URL/model values. Covers:

- `Set-VerityAiProvider` toggling each of the 3 services on/off writes the
  correct boolean + URL/model.
- `Get-VerityRequiredSidecars` correctly detects each combination of the 3
  boolean flags.
- `Set-TomlSectionBoolValue` writes unquoted `true`/`false` without
  disturbing other keys/sections (same shape of test as the existing
  `Set-TomlSectionValue` coverage).
