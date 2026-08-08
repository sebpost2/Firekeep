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

Describe "Set-VerityLocalAI" {

    $root = Join-Path $env:TEMP ("verity-config-" + [Guid]::NewGuid().ToString("N"))

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

    It "points AISettings at the local Ollama sidecar" {
        $inst = Join-Path $root "server1"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'aiProvider = "OLLAMA"'
        $content | Should Match 'aiEndpoint = "http://127\.0\.0\.1:11434/v1"'
        $content | Should Match 'aiModel = "timheinrich2011/verity-3b"'
    }

    It "points VoiceSettings at the local Kokoro sidecar" {
        $inst = Join-Path $root "server2"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'ttsProvider = "KOKORO"'
        $content | Should Match 'ttsEndpoint = "http://127\.0\.0\.1:8880/v1"'
    }

    It "points SpeechSettings at the local Whisper sidecar" {
        $inst = Join-Path $root "server3"
        New-FakeVerityInstance -Path $inst
        Set-VerityLocalAI -InstancePath $inst
        $content = Get-Content (Join-Path $inst "config\verity-common.toml") -Raw
        $content | Should Match 'sttProvider = "WHISPER"'
        $content | Should Match 'sttEndpoint = "http://127\.0\.0\.1:9000/v1"'
    }

    It "throws a clear error when verity-common.toml doesn't exist" {
        $inst = Join-Path $root "no-config"
        New-Item -ItemType Directory -Force -Path $inst | Out-Null
        { Set-VerityLocalAI -InstancePath $inst } | Should Throw
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
            $job = Start-Job -ScriptBlock {
                param($listener)
                $ctx = $listener.GetContext()
                $ctx.Response.StatusCode = 200
                $ctx.Response.Close()
            } -ArgumentList $listener

            Test-SidecarHealthy -Url "http://127.0.0.1:39282/health" -TimeoutMs 3000 | Should Be $true
            Wait-Job $job -Timeout 5 | Out-Null
            Remove-Job $job -Force
        } finally {
            $listener.Stop()
        }
    }
}
