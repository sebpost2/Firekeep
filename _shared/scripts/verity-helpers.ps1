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
        [Parameter(Mandatory = $true)][string]$Value
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
            $result += "$leading$Key = `"$Value`""
            continue
        }
        $result += $line
    }
    return $result
}

# Points a Verity-enabled server's config/verity-common.toml at the local
# AI sidecars (Ollama/Kokoro/Whisper) instead of a cloud provider. Run once
# when Local AI is enabled for that server from the GUI.
function Set-VerityLocalAI {
    param(
        [Parameter(Mandatory = $true)][string]$InstancePath
    )

    $tomlPath = Join-Path $InstancePath "config\verity-common.toml"
    if (-not (Test-Path $tomlPath)) {
        throw "Could not find config\verity-common.toml under $InstancePath - is Verity actually installed on this server?"
    }

    $lines = Get-Content -Path $tomlPath -Encoding utf8

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiEndpoint" -Value "http://127.0.0.1:11434/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.AISettings" -Key "aiModel" -Value "timheinrich2011/verity-3b"

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsProvider" -Value "KOKORO"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "ttsEndpoint" -Value "http://127.0.0.1:8880/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.VoiceSettings" -Key "kokoroModel" -Value "kokoro"

    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttProvider" -Value "WHISPER"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttEndpoint" -Value "http://127.0.0.1:9000/v1"
    $lines = Set-TomlSectionValue -Lines $lines -Section "GeneralSettings.SpeechSettings" -Key "sttModel" -Value "base.en"

    Set-Content -Path $tomlPath -Value $lines -Encoding utf8
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

# Installs (if needed) and starts the 3 local-AI sidecars, waiting for each
# to answer a health check before returning. Shared host-wide - one set of
# sidecars serves every Verity-enabled server on this machine.
function Start-VerityLocalAiStack {
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
    if (-not (Test-Path (Join-Path $aiDir "kokoro\kokoro_server.py"))) {
        & (Join-Path $scriptsDir "install-kokoro.ps1")
    }
    if (-not (Test-Path (Join-Path $aiDir "whisper\whisper_server.py"))) {
        & (Join-Path $scriptsDir "install-whisper.ps1")
    }

    if (-not (Test-PortOpen -Port 11434)) {
        Start-Process -FilePath (Join-Path $aiDir "ollama\ollama.exe") -ArgumentList "serve" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "ollama.log") -RedirectStandardError (Join-Path $logDir "ollama.err.log")
    }
    $pythonExe = Join-Path $aiDir "python\python.exe"
    if (-not (Test-PortOpen -Port 8880)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'kokoro\kokoro_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "kokoro.log") -RedirectStandardError (Join-Path $logDir "kokoro.err.log")
    }
    if (-not (Test-PortOpen -Port 9000)) {
        Start-Process -FilePath $pythonExe -ArgumentList "`"$(Join-Path $aiDir 'whisper\whisper_server.py')`"" -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logDir "whisper.log") -RedirectStandardError (Join-Path $logDir "whisper.err.log")
    }

    $checks = @(
        @{ Url = "http://127.0.0.1:11434/v1/models"; Name = "Ollama"; LogFile = "ollama.err.log" },
        @{ Url = "http://127.0.0.1:8880/health"; Name = "Kokoro"; LogFile = "kokoro.err.log" },
        @{ Url = "http://127.0.0.1:9000/health"; Name = "Whisper"; LogFile = "whisper.err.log" }
    )
    foreach ($check in $checks) {
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            if (Test-SidecarHealthy -Url $check.Url) { $ready = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw "$($check.Name) didn't become ready within 30s - check $(Join-Path $logDir $check.LogFile)"
        }
    }
}

# Stops all 3 sidecars by whatever's listening on their ports.
function Stop-VerityLocalAiStack {
    foreach ($port in @(11434, 8880, 9000)) {
        $ownerPid = Get-ListenerPid -Port $port
        if ($ownerPid) { Stop-ProcessTree -ProcessId $ownerPid }
    }
}
