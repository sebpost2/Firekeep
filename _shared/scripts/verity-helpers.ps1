# _shared/scripts/verity-helpers.ps1
# Detection, config, and local-AI-sidecar lifecycle for servers running the
# Verity mod. Loaded via dot-source.

. (Join-Path $PSScriptRoot "rcon.ps1")
. (Join-Path $PSScriptRoot "gui-helpers.ps1")

# A server is "Verity-enabled" if its mods/ folder has a verity-*.jar -
# same signature-file-scan pattern Get-DetectedJavaVersion already uses.
function Test-VerityModPresent {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $modsDir = Join-Path $InstancePath "mods"
    if (-not (Test-Path $modsDir)) { return $false }
    $jar = Get-ChildItem -Path $modsDir -Filter "verity-*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$jar
}

# Replaces `Key = "..."` with a new value, but only for lines that fall
# under the given `[Section]` header - so e.g. AISettings.aiProvider and a
# hypothetical same-named key elsewhere never collide. Preserves the
# original line's leading whitespace (verity-common.toml indents nested
# keys with a tab). Section headers are matched by exact text inside the
# brackets (e.g. "GeneralSettings.AISettings" for "[GeneralSettings.AISettings]").
function Set-TomlSectionValue {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    # Cast to [string[]] to ensure proper array handling:
    # - Scalar string inputs (e.g., from Get-Content on single line) become one-element array
    # - Arrays with empty strings (valid TOML blank lines) pass through intact
    # This approach works around Pester v4 issue where [string[]] type constraint fails with arrays containing empty strings
    [string[]]$Lines = @($Lines)

    $result = @()
    $inSection = $false
    $sectionHeader = "[$Section]"

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[.+\]$') {
            $inSection = ($trimmed -eq $sectionHeader)
            $result += $line
            continue
        }
        if ($inSection -and $trimmed -match "^$([regex]::Escape($Key))\s*=") {
            $leading = $line.Substring(0, $line.Length - $line.TrimStart().Length)
            # Escape backslashes first, then quotes, so the escaping backslash itself doesn't get double-escaped
            $escaped = $Value -replace '\\', '\\' -replace '"', '\"'
            $result += "$leading$Key = `"$escaped`""
            continue
        }
        $result += $line
    }
    return $result
}

# Same section/key matching as Set-TomlSectionValue, but for TOML booleans
# (use_ollama/use_kokoro/use_local_whisper) - these must be written unquoted
# (`true`/`false`), not as strings, or NightConfig reads them as the wrong type.
function Set-TomlSectionBoolValue {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][bool]$Value
    )

    [string[]]$Lines = @($Lines)
    $valueText = if ($Value) { "true" } else { "false" }

    $result = @()
    $inSection = $false
    $sectionHeader = "[$Section]"

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[.+\]$') {
            $inSection = ($trimmed -eq $sectionHeader)
            $result += $line
            continue
        }
        if ($inSection -and $trimmed -match "^$([regex]::Escape($Key))\s*=") {
            $leading = $line.Substring(0, $line.Length - $line.TrimStart().Length)
            $result += "$leading$Key = $valueText"
            continue
        }
        $result += $line
    }
    return $result
}

# This host runs Verity servers on two different config schemas: the older
# one (Verity 6.1) nests everything under [GeneralSettings.*] with string-enum
# providers, the newer one (5.7.1) uses a flat [AISettings] with booleans.
# Returns $true for the old schema, $false for the new one, and throws if the
# file matches neither - writing to a section that isn't there would silently
# no-op. Section headers are matched as whole lines because the old header
# textually contains the new one's name.
function Test-VerityOldSchema {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    # \s*$ rather than a bare $ so a CRLF file's trailing \r doesn't defeat the anchor.
    if ($Content -match '(?m)^\[GeneralSettings\.AISettings\]\s*$') { return $true }
    if ($Content -match '(?m)^\[AISettings\]\s*$') { return $false }
    throw "config\verity-common.toml under $InstancePath doesn't match a known Verity schema (no [AISettings] or [GeneralSettings.AISettings] section found)."
}

# Points one Verity subsystem (LLM/TTS/STT) at its local sidecar, or turns it
# back off. All three toggles live in the same flat [AISettings] section (not
# separate per-service sections) as booleans: use_ollama, use_kokoro,
# use_local_whisper. config/verity-common.toml is the single source of truth
# for which sidecars a server wants running - there's no separate on/off
# state to keep in sync.
function Set-VerityAiProvider {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][ValidateSet("Ollama", "Kokoro", "Whisper")][string]$Service,
        [Parameter(Mandatory = $true)][bool]$UseLocal
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8
    $isOldSchema = Test-VerityOldSchema -Content ($lines -join "`n") -InstancePath $InstancePath

    if ($isOldSchema) {
        switch ($Service) {
            "Ollama" {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value $(if ($UseLocal) { "OLLAMA" } else { "OPENAI" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiEndpoint" -Value $(if ($UseLocal) { "http://127.0.0.1:11434/v1" } else { "" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiModel" -Value $(if ($UseLocal) { "timheinrich2011/verity-3b" } else { "" })
            }
            "Kokoro" {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsProvider" -Value $(if ($UseLocal) { "KOKORO" } else { "NATIVE" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsEndpoint" -Value $(if ($UseLocal) { "http://127.0.0.1:8880/v1" } else { "" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "kokoroModel" -Value $(if ($UseLocal) { "kokoro" } else { "" })
            }
            "Whisper" {
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttProvider" -Value $(if ($UseLocal) { "WHISPER" } else { "NATIVE" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttEndpoint" -Value $(if ($UseLocal) { "http://127.0.0.1:9000/v1" } else { "" })
                $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttModel" -Value $(if ($UseLocal) { "base.en" } else { "" })
            }
        }
    } else {
        switch ($Service) {
            "Ollama" {
                $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_ollama" -Value $UseLocal
                if ($UseLocal) {
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_url" -Value "http://127.0.0.1:11434/v1/"
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_ai_model" -Value "timheinrich2011/verity-3b"
                }
            }
            "Kokoro" {
                $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_kokoro" -Value $UseLocal
                if ($UseLocal) {
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_tts_url" -Value "http://127.0.0.1:8880/v1/"
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_tts_model" -Value "kokoro"
                }
            }
            "Whisper" {
                $lines = Set-TomlSectionBoolValue -Lines $lines -Section "AISettings" -Key "use_local_whisper" -Value $UseLocal
                if ($UseLocal) {
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_stt_url" -Value "http://127.0.0.1:9000/v1/"
                    $lines = Set-TomlSectionValue -Lines $lines -Section "AISettings" -Key "ollama_stt_model" -Value "base.en"
                }
            }
        }
    }

    # Windows PowerShell 5.1's -Encoding utf8 always prepends a BOM, which
    # Forge's TOML parser (NightConfig) doesn't strip - it reads the BOM
    # bytes as the start of a bare key and refuses to load the file at all,
    # crashing every server boot. Write UTF-8 without a BOM instead.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}

# Reads which of the 3 sidecars this server's config currently points at
# locally - the toml IS the persisted on/off state, so this is the only
# place that needs to know how to read it back out.
function Get-VerityRequiredSidecars {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) { return @() }

    $content = Get-Content -Path $tomlPath -Raw
    $required = @()
    # Each sidecar has two "enabled" spellings - the new flat-boolean schema's
    # and the old nested schema's string-enum provider (see Test-VerityOldSchema).
    if ($content -match '(?m)^\s*use_ollama\s*=\s*true' -or $content -match '(?m)^\s*aiProvider\s*=\s*"OLLAMA"') { $required += "Ollama" }
    if ($content -match '(?m)^\s*use_kokoro\s*=\s*true' -or $content -match '(?m)^\s*ttsProvider\s*=\s*"KOKORO"') { $required += "Kokoro" }
    if ($content -match '(?m)^\s*use_local_whisper\s*=\s*true' -or $content -match '(?m)^\s*sttProvider\s*=\s*"WHISPER"') { $required += "Whisper" }
    return $required
}

# Reads the currently saved Groq API key (or "" if unset/missing config) -
# used to pre-fill the GUI's API key field so it reflects what's actually
# saved instead of always starting blank.
function Get-VerityApiKey {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )
    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) { return "" }

    $content = Get-Content -Path $tomlPath -Raw
    # Match quoted string, allowing escaped characters (\\ and \")
    if ($content -match '(?m)^\s*apiKey\s*=\s*"((?:\\.|[^"\\])*)"') {
        # Unescape: \\ becomes \, \" becomes ", etc.
        return $Matches[1] -replace '\\(.)', '$1'
    }
    return ""
}

# Persists the Groq API key entered in the GUI. Independent of
# Set-VerityAiProvider - apiKey is used for the cloud-fallback path and
# isn't touched by the Ollama/Kokoro/Whisper local-AI toggles.
function Set-VerityApiKey {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ApiKey
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8
    # Same key name in both schemas - only the enclosing section differs.
    $section = if (Test-VerityOldSchema -Content ($lines -join "`n") -InstancePath $InstancePath) { "GeneralSettings.AISettings" } else { "AISettings" }
    $lines = Set-TomlSectionValue -Lines $lines -Section $section -Key "apiKey" -Value $ApiKey

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tomlPath, $lines, $utf8NoBom)
}

# A quick, non-throwing health check for a sidecar's HTTP endpoint.
function Test-SidecarHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 1500
    )
    try {
        $resp = Invoke-WebRequest -Uri $Url -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($TimeoutMs / 1000))) -UseBasicParsing
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
    } catch {
        return $false
    }
}

# A 200 from Ollama's /v1/models isn't enough to know it's OUR Ollama - a
# pre-existing system-wide install (or any other Ollama already holding port
# 11434) answers the same way but won't have verity-3b loaded. This checks
# the model list itself so Start/Stop-VerityLocalAiStack can tell "ours"
# apart from a foreign instance instead of silently trusting the wrong one.
function Test-OllamaModelPresent {
    param(
        [string]$ModelPrefix = "timheinrich2011/verity-3b"
    )
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 5
        foreach ($m in $resp.models) {
            if ($m.name -like "$ModelPrefix*") { return $true }
        }
        return $false
    } catch {
        return $false
    }
}

# Installed once, shared host-wide under Minecraft/tools/ai/ - one Ollama/
# Kokoro/Whisper instance serves every Verity-enabled server on this
# machine. Each Start-<X>Sidecar is independent: a caller starts only the
# ones a given server's config actually needs (see Get-VerityRequiredSidecars).
function Start-OllamaSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )
    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "ollama\ollama.exe"))) {
        & (Join-Path $scriptsDir "install-ollama.ps1")
    }
    if (-not (Test-PortOpen -Port 11434)) {
        # Must match the OLLAMA_MODELS install-ollama.ps1 set in its own
        # process when it pulled verity-3b - otherwise this server (which
        # doesn't inherit that env var from the installer's process) reads
        # the default %USERPROFILE%\.ollama\models instead, finds nothing,
        # and serves an empty model list while still reporting healthy.
        $env:OLLAMA_MODELS = Join-Path $aiDir "ollama\models"
        Start-Process -FilePath (Join-Path $aiDir "ollama\ollama.exe") -ArgumentList "serve" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "ollama.log") -RedirectStandardError (Join-Path $logDir "ollama.err.log")
    }

    # A 200 from /v1/models isn't enough to know it's OUR Ollama - a
    # pre-existing system-wide install (or any other Ollama already holding
    # port 11434) answers the same way but won't have verity-3b loaded.
    $ollamaReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-OllamaModelPresent) { $ollamaReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ollamaReady) {
        throw "Ollama is listening on port 11434 but the timheinrich2011/verity-3b model isn't loaded - looks like a different Ollama instance is already running on that port. Check $(Join-Path $logDir 'ollama.err.log'), or free port 11434 and try again."
    }
}

function Start-KokoroSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )
    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "kokoro\kokoro_server.py"))) {
        & (Join-Path $scriptsDir "install-kokoro.ps1")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 8880)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'kokoro\kokoro_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "kokoro.log") -RedirectStandardError (Join-Path $logDir "kokoro.err.log")
    }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SidecarHealthy -Url "http://127.0.0.1:8880/health") { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "Kokoro didn't become ready within 30s - check $(Join-Path $logDir 'kokoro.err.log')"
    }
}

function Start-WhisperSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$McRoot
    )
    $scriptsDir = Join-Path $McRoot "scripts"
    $aiDir = Join-Path $McRoot "tools\ai"
    $logDir = Join-Path $aiDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    if (-not (Test-Path (Join-Path $aiDir "whisper\whisper_server.py"))) {
        & (Join-Path $scriptsDir "install-whisper.ps1")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 9000)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'whisper\whisper_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "whisper.log") -RedirectStandardError (Join-Path $logDir "whisper.err.log")
    }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SidecarHealthy -Url "http://127.0.0.1:9000/health") { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "Whisper didn't become ready within 30s - check $(Join-Path $logDir 'whisper.err.log')"
    }
}

# Ollama is only killed if verity-3b is confirmed loaded on port 11434 -
# this doesn't share in-memory state with whatever Start-Process call may
# have launched it, so a plain "whatever owns the port" kill would just as
# happily kill a pre-existing user-installed Ollama that happened to
# already be running when the stack started.
function Stop-OllamaSidecar {
    if (Test-OllamaModelPresent) {
        $ownerPid = Get-ListenerPid -Port 11434
        if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
    }
}

# Kokoro/Whisper have no such collision risk (nothing else on the system
# would be using those ports), so they use a simple by-port kill.
function Stop-KokoroSidecar {
    $ownerPid = Get-ListenerPid -Port 8880
    if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
}

function Stop-WhisperSidecar {
    $ownerPid = Get-ListenerPid -Port 9000
    if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
}

# Stops whichever of the 3 sidecars happen to be running - used by the
# GUI's "Stop All" and by the boot-safety stop-on-close check, neither of
# which needs to track which ones were actually started.
function Stop-VerityLocalAiStack {
    Stop-OllamaSidecar
    Stop-KokoroSidecar
    Stop-WhisperSidecar
}

# Every <Game>\servers\<Instance>\ folder under the GameServers root -
# "_shared" is infrastructure, not a game; "_template" is the generic
# scaffold, not a real instance. Same discovery rule as stop-server.ps1's
# Get-AllServerInstances and gui-helpers.ps1's Get-ServerInstances.
function Get-AllServerInstancePaths {
    param(
        [Parameter(Mandatory = $true)][string]$GsRoot
    )
    $result = @()
    Get-ChildItem -Path $GsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "_shared" } | ForEach-Object {
        $serversDir = Join-Path $_.FullName "servers"
        if (Test-Path $serversDir) {
            Get-ChildItem -Path $serversDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "_template" } | ForEach-Object {
                $result += $_.FullName
            }
        }
    }
    return $result
}

# The sidecars are shared host-wide - stopping them when ONE Verity server
# closes would break AI for another Verity server still running. This
# checks whether any other instance is both Verity-enabled and currently up
# (by its Minecraft port, not RCON - RCON may be disabled) before it's safe
# to stop the sidecars.
function Test-OtherVerityServerRunning {
    param(
        [Parameter(Mandatory = $true)][string]$GsRoot,
        [Parameter(Mandatory = $true)][string]$ExcludePath
    )
    foreach ($path in (Get-AllServerInstancePaths -GsRoot $GsRoot)) {
        if ($path -eq $ExcludePath) { continue }
        if (-not (Test-VerityModPresent -InstancePath $path)) { continue }

        $props = Read-ServerProperties (Join-Path $path "server.properties")
        $port = 25565
        if ($props["server-port"]) { $port = [int]$props["server-port"] }
        if (Test-PortOpen -Port $port) { return $true }
    }
    return $false
}
