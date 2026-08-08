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
