# tests/verity-helpers.tests.ps1
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\verity-helpers.ps1")

Describe "Test-VerityModPresent" {

    $root = Join-Path $env:TEMP ("verity-detect-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "returns true when a verity-*.jar exists in mods/" {
        $inst = Join-Path $root "with-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\verity-6.1.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $true
    }

    It "returns false when mods/ has no verity jar" {
        $inst = Join-Path $root "without-verity"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "mods") | Out-Null
        Set-Content -Path (Join-Path $inst "mods\somemod.jar") -Value "fake jar" -Encoding ascii

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    It "returns false when there's no mods/ folder at all" {
        $inst = Join-Path $root "no-mods-dir"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null

        Test-VerityModPresent -InstancePath $inst | Should Be $false
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Set-TomlSectionValue" {

    $sampleToml = @(
        '[GeneralSettings.AISettings]',
        "`taiKey = `"`"",
        "`taiEndpoint = `"`"",
        "`taiProvider = `"OPENAI`"",
        '',
        '[GeneralSettings.VoiceSettings]',
        "`tttsProvider = `"NATIVE`""
    )

    It "replaces a key's value only within the matching section" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
        ($result | Where-Object { $_ -match '^\s*aiProvider\s*=' }) | Should Be "`taiProvider = `"OLLAMA`""
    }

    It "leaves a same-named key in a different section untouched" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "ttsProvider" -Value "KOKORO"
        ($result | Where-Object { $_ -match '^\s*ttsProvider\s*=' }) | Should Be "`tttsProvider = `"NATIVE`""
    }

    It "preserves every other line unchanged" {
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value "OLLAMA"
        $result.Count | Should Be $sampleToml.Count
        $result[0] | Should Be '[GeneralSettings.AISettings]'
    }

    It "escapes quotes and backslashes in values" {
        $value = 'test"quote'
        $result = Set-TomlSectionValue -Lines $sampleToml -Section "GeneralSettings.AISettings" -Key "aiProvider" -Value $value
        ($result | Where-Object { $_ -match '^\s*aiProvider\s*=' }) | Should Match 'aiProvider = "test\\"quote"'
    }
}

Describe "Set-TomlSectionBoolValue" {

    $sampleToml = @(
        '[AISettings]',
        "`tuse_ollama = false",
        "`tuse_kokoro = false",
        '',
        '[Custom]',
        "`tsomeOtherFlag = true"
    )

    It "replaces a key's value only within the matching section" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_ollama" -Value $true
        ($result | Where-Object { $_ -match '^\s*use_ollama\s*=' }) | Should Be "`tuse_ollama = true"
    }

    It "leaves a key in a different section untouched" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_kokoro" -Value $true
        ($result | Where-Object { $_ -match '^\s*someOtherFlag\s*=' }) | Should Be "`tsomeOtherFlag = true"
    }

    It "preserves every other line unchanged" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_ollama" -Value $true
        $result.Count | Should Be $sampleToml.Count
        $result[0] | Should Be '[AISettings]'
    }

    It "writes false unquoted" {
        $result = Set-TomlSectionBoolValue -Lines $sampleToml -Section "AISettings" -Key "use_kokoro" -Value $false
        ($result | Where-Object { $_ -match '^\s*use_kokoro\s*=' }) | Should Be "`tuse_kokoro = false"
    }
}

Describe "Set-VerityAiProvider" {

    $root = Join-Path $env:TEMP ("verity-provider-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	voice = "Daniel"
	useLocalTts = true
	useLocalStt = false
	apiKey = ""
	aiModel = "FAST"
	aiProvider = "GROQ"
	use_ollama = false
	ollama_url = "http://127.0.0.1:4000/v1/"
	ollama_ai_model = "ollama/qwen2.5:1.5b"
	thinking_mode = false
	use_kokoro = false
	ollama_tts_url = "http://127.0.0.1:8880/v1/"
	ollama_tts_model = "kokoro"
	ollama_tts_voice = "am_fenrir"
	use_local_whisper = false
	ollama_stt_url = "http://127.0.0.1:9000/v1/"
	ollama_stt_model = "models/ggml-large-v3-turbo.bin"
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "points AISettings at the local Ollama sidecar when UseLocal is true" {
        $inst = Join-Path $root "ollama-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_ollama = true'
        $content | Should Match 'ollama_url = "http://127\.0\.0\.1:11434/v1/"'
        $content | Should Match 'ollama_ai_model = "timheinrich2011/verity-3b"'
    }

    It "clears use_ollama when UseLocal is false, without touching url/model" {
        $inst = Join-Path $root "ollama-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_ollama = false'
        $content | Should Match 'ollama_url = "http://127\.0\.0\.1:11434/v1/"'
    }

    It "points AISettings at the local Kokoro sidecar when UseLocal is true" {
        $inst = Join-Path $root "kokoro-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_kokoro = true'
        $content | Should Match 'ollama_tts_url = "http://127\.0\.0\.1:8880/v1/"'
        $content | Should Match 'ollama_tts_model = "kokoro"'
    }

    It "clears use_kokoro when UseLocal is false" {
        $inst = Join-Path $root "kokoro-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_kokoro = false'
    }

    It "points AISettings at the local Whisper sidecar when UseLocal is true" {
        $inst = Join-Path $root "whisper-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_local_whisper = true'
        $content | Should Match 'ollama_stt_url = "http://127\.0\.0\.1:9000/v1/"'
        $content | Should Match 'ollama_stt_model = "base.en"'
    }

    It "clears use_local_whisper when UseLocal is false" {
        $inst = Join-Path $root "whisper-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'use_local_whisper = false'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true } | Should Throw
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-VerityRequiredSidecars" {

    $root = Join-Path $env:TEMP ("verity-required-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityToml([string]$Path, [bool]$UseOllama, [bool]$UseKokoro, [bool]$UseWhisper) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        $ollamaText = if ($UseOllama) { "true" } else { "false" }
        $kokoroText = if ($UseKokoro) { "true" } else { "false" }
        $whisperText = if ($UseWhisper) { "true" } else { "false" }
        @"
[AISettings]
	use_ollama = $ollamaText
	use_kokoro = $kokoroText
	use_local_whisper = $whisperText
"@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "returns all three when all are local" {
        $inst = Join-Path $root "all-local"
        New-FakeVerityToml -Path $inst -UseOllama $true -UseKokoro $true -UseWhisper $true
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama", "Kokoro", "Whisper")
    }

    It "returns only the ones set local, e.g. just the core LLM" {
        $inst = Join-Path $root "llm-only"
        New-FakeVerityToml -Path $inst -UseOllama $true -UseKokoro $false -UseWhisper $false
        (Get-VerityRequiredSidecars -InstancePath $inst) | Should Be @("Ollama")
    }

    It "returns an empty array when nothing is local" {
        $inst = Join-Path $root "cloud-only"
        New-FakeVerityToml -Path $inst -UseOllama $false -UseKokoro $false -UseWhisper $false
        (Get-VerityRequiredSidecars -InstancePath $inst).Count | Should Be 0
    }

    It "returns an empty array when the config file doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        (Get-VerityRequiredSidecars -InstancePath $inst).Count | Should Be 0
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-VerityApiKey" {

    $root = Join-Path $env:TEMP ("verity-getkey-" + [Guid]::NewGuid().ToString("N"))

    It "returns the saved key" {
        $inst = Join-Path $root "with-key"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "config") | Out-Null
        @'
[AISettings]
	apiKey = "gsk_abc123"
'@ | Set-Content -Path (Join-Path $inst "config\verity-common.toml") -Encoding utf8

        Get-VerityApiKey -InstancePath $inst | Should Be "gsk_abc123"
    }

    It "returns an empty string when the key is blank" {
        $inst = Join-Path $root "blank-key"
        New-Item -ItemType Directory -Force -Path (Join-Path $inst "config") | Out-Null
        @'
[AISettings]
	apiKey = ""
'@ | Set-Content -Path (Join-Path $inst "config\verity-common.toml") -Encoding utf8

        Get-VerityApiKey -InstancePath $inst | Should Be ""
    }

    It "returns an empty string when the config file doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        Get-VerityApiKey -InstancePath $inst | Should Be ""
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Set-VerityApiKey" {

    $root = Join-Path $env:TEMP ("verity-setkey-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[AISettings]
	apiKey = ""
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "writes the given key" {
        $inst = Join-Path $root "set-key"
        New-FakeVerityInstance -Path $inst
        Set-VerityApiKey -InstancePath $inst -ApiKey "gsk_abc123"
        (Get-Content (Join-Path $inst "config\verity-common.toml") -Raw) | Should Match 'apiKey = "gsk_abc123"'
    }

    It "can clear the key back to empty" {
        $inst = Join-Path $root "clear-key"
        New-FakeVerityInstance -Path $inst
        Set-VerityApiKey -InstancePath $inst -ApiKey "gsk_abc123"
        Set-VerityApiKey -InstancePath $inst -ApiKey ""
        (Get-Content (Join-Path $inst "config\verity-common.toml") -Raw) | Should Match 'apiKey = ""'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityApiKey -InstancePath $inst -ApiKey "x" } | Should Throw
    }

    It "round-trips a key containing a quote character unchanged" {
        $inst = Join-Path $root "quoted-key"
        New-FakeVerityInstance -Path $inst
        $keyWithQuote = 'gsk_test"value'
        Set-VerityApiKey -InstancePath $inst -ApiKey $keyWithQuote
        (Get-VerityApiKey -InstancePath $inst) | Should Be $keyWithQuote
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Get-AllServerInstancePaths" {

    $root = Join-Path $env:TEMP ("verity-instances-" + [Guid]::NewGuid().ToString("N"))

    It "finds instance folders under each game, skipping _shared and _template" {
        New-Item -ItemType Directory -Force -Path (Join-Path $root "Minecraft\servers\ServerA") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "Minecraft\servers\_template") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "_shared\servers\NotAGame") | Out-Null

        $paths = Get-AllServerInstancePaths -GsRoot $root
        ($paths -contains (Join-Path $root "Minecraft\servers\ServerA")) | Should Be $true
        ($paths | Where-Object { $_ -like "*_template*" }) | Should Be $null
        ($paths | Where-Object { $_ -like "*_shared*" }) | Should Be $null
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Test-OtherVerityServerRunning" {

    $root = Join-Path $env:TEMP ("verity-other-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeInstance([string]$Path, [bool]$HasVerity, [int]$Port) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "mods") | Out-Null
        if ($HasVerity) {
            Set-Content -Path (Join-Path $Path "mods\verity-6.1.jar") -Value "fake jar" -Encoding ascii
        }
        Set-Content -Path (Join-Path $Path "server.properties") -Value "server-port=$Port" -Encoding ascii
    }

    It "returns false when no other instance has Verity installed" {
        $me = Join-Path $root "Minecraft\servers\Me"
        $other = Join-Path $root "Minecraft\servers\Other"
        New-FakeInstance -Path $me -HasVerity $true -Port 39301
        New-FakeInstance -Path $other -HasVerity $false -Port 39302

        Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $false
    }

    It "returns false when the other Verity instance isn't running" {
        $me = Join-Path $root "Minecraft\servers\Me2"
        $other = Join-Path $root "Minecraft\servers\Other2"
        New-FakeInstance -Path $me -HasVerity $true -Port 39303
        New-FakeInstance -Path $other -HasVerity $true -Port 39304

        Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $false
    }

    It "returns true when another Verity instance is running" {
        $me = Join-Path $root "Minecraft\servers\Me3"
        $other = Join-Path $root "Minecraft\servers\Other3"
        New-FakeInstance -Path $me -HasVerity $true -Port 39305
        New-FakeInstance -Path $other -HasVerity $true -Port 39306

        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 39306)
        $listener.Start()
        try {
            Test-OtherVerityServerRunning -GsRoot $root -ExcludePath $me | Should Be $true
        } finally {
            $listener.Stop()
        }
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Describe "Test-SidecarHealthy" {

    It "returns false when nothing is listening" {
        Test-SidecarHealthy -Url "http://127.0.0.1:39281/health" -TimeoutMs 300 | Should Be $false
    }

    It "returns true when the endpoint responds with 2xx" {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:39282/")
        $listener.Start()
        try {
            $helperScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\verity-helpers.ps1"

            # Run Test-SidecarHealthy inside the job; keep the live listener on the main thread
            $job = Start-Job -ScriptBlock {
                param($Url, $HelperPath)
                . $HelperPath
                Test-SidecarHealthy -Url $Url -TimeoutMs 3000
            } -ArgumentList "http://127.0.0.1:39282/health", $helperScriptPath

            # Accept the HTTP request on the main thread (where the listener is live)
            $ctx = $listener.GetContext()
            $ctx.Response.StatusCode = 200
            $ctx.Response.Close()

            # Get the result from the job
            $result = Receive-Job -Job $job -Wait
            $result | Should Be $true

            Remove-Job $job -Force
        } finally {
            $listener.Stop()
        }
    }
}
