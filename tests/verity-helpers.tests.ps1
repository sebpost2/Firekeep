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
}

Describe "Set-VerityAiProvider" {

    $root = Join-Path $env:TEMP ("verity-provider-" + [Guid]::NewGuid().ToString("N"))

    function New-FakeVerityInstance([string]$Path) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path "config") | Out-Null
        @'
[GeneralSettings.AISettings]
	apiKey = ""
	aiEndpoint = ""
	aiModel = ""
	aiProvider = "OPENAI"
	aiThink = true

[GeneralSettings.VoiceSettings]
	useTTS = true
	ttsProvider = "NATIVE"
	ttsEndpoint = ""
	voice = "Daniel"
	kokoroVoice = "am_fenrir"
	kokoroModel = ""

[GeneralSettings.SpeechSettings]
	sttProvider = "NATIVE"
	groqKey = ""
	sttEndpoint = ""
	sttModel = ""
'@ | Set-Content -Path (Join-Path $Path "config\verity-common.toml") -Encoding utf8
    }

    It "points AISettings at the local Ollama sidecar when UseLocal is true" {
        $inst = Join-Path $root "ollama-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OLLAMA"'
        $content | Should Match 'aiEndpoint = "http://127\.0\.0\.1:11434/v1"'
        $content | Should Match 'aiModel = "timheinrich2011/verity-3b"'
    }

    It "reverts aiProvider to OPENAI when UseLocal is false" {
        $inst = Join-Path $root "ollama-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OPENAI"'
    }

    It "points VoiceSettings at the local Kokoro sidecar when UseLocal is true" {
        $inst = Join-Path $root "kokoro-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "KOKORO"'
        $content | Should Match 'ttsEndpoint = "http://127\.0\.0\.1:8880/v1"'
    }

    It "reverts ttsProvider to NATIVE when UseLocal is false" {
        $inst = Join-Path $root "kokoro-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Kokoro" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "NATIVE"'
    }

    It "points SpeechSettings at the local Whisper sidecar when UseLocal is true" {
        $inst = Join-Path $root "whisper-on"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "WHISPER"'
        $content | Should Match 'sttEndpoint = "http://127\.0\.0\.1:9000/v1"'
    }

    It "reverts sttProvider to NATIVE when UseLocal is false" {
        $inst = Join-Path $root "whisper-off"
        New-FakeVerityInstance -Path $inst
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $true
        Set-VerityAiProvider -InstancePath $inst -Service "Whisper" -UseLocal $false
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "NATIVE"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityAiProvider -InstancePath $inst -Service "Ollama" -UseLocal $true } | Should Throw
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
