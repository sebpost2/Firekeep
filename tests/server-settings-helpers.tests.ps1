. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\server-settings-helpers.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\worlds-helpers.ps1")

Describe "Get-ServerPropertyDefaults" {
    It "has all 6 curated keys with sensible defaults" {
        $d = Get-ServerPropertyDefaults
        $d["difficulty"]       | Should Be "easy"
        $d["pvp"]              | Should Be "true"
        $d["white-list"]       | Should Be "false"
        $d["max-players"]      | Should Be "20"
        $d["motd"]             | Should Be "A Minecraft Server"
        $d["spawn-protection"] | Should Be "16"
    }
}

Describe "Get-ProtectedPropertyKeys" {
    It "returns exactly the 3 RCON keys" {
        (Get-ProtectedPropertyKeys) -join "," | Should Be "enable-rcon,rcon.port,rcon.password"
    }
}

Describe "Get-CuratedPropertyValues" {
    It "uses file values when present" {
        $props = @{ "difficulty" = "hard"; "pvp" = "false" }
        $result = Get-CuratedPropertyValues -Props $props
        $result["difficulty"] | Should Be "hard"
        $result["pvp"]        | Should Be "false"
    }

    It "falls back to defaults for keys missing from the file" {
        $result = Get-CuratedPropertyValues -Props @{}
        $result["max-players"] | Should Be "20"
        $result["motd"]        | Should Be "A Minecraft Server"
    }
}

Describe "ConvertTo-ClampedInt" {
    It "accepts a valid non-negative integer" {
        ConvertTo-ClampedInt -Value "42" -FallbackValue "20" | Should Be "42"
    }
    It "falls back on a negative number" {
        ConvertTo-ClampedInt -Value "-5" -FallbackValue "20" | Should Be "20"
    }
    It "falls back on non-numeric input" {
        ConvertTo-ClampedInt -Value "abc" -FallbackValue "16" | Should Be "16"
    }
    It "falls back on empty input" {
        ConvertTo-ClampedInt -Value "" -FallbackValue "16" | Should Be "16"
    }
}

Describe "Get-AdvancedPropertiesText / Save-AdvancedPropertiesLines" {
    $propsPath = Join-Path $env:TEMP ("server-settings-helpers-" + [Guid]::NewGuid().ToString("N") + ".properties")

    BeforeEach {
        @(
            "#Minecraft server properties"
            "enable-rcon=true"
            "rcon.port=25575"
            "rcon.password=secret123"
            "difficulty=easy"
            "pvp=true"
            "white-list=false"
            "max-players=20"
            "motd=A Minecraft Server"
            "spawn-protection=16"
            "level-seed=12345"
            "online-mode=true"
        ) | Set-Content -Path $propsPath -Encoding ascii
    }

    It "excludes protected and curated keys, keeps everything else" {
        $text = Get-AdvancedPropertiesText -Path $propsPath
        $text | Should Not Match "rcon"
        $text | Should Not Match "difficulty"
        $text | Should Match "level-seed=12345"
        $text | Should Match "online-mode=true"
    }

    It "returns empty string for a missing file" {
        Get-AdvancedPropertiesText -Path (Join-Path $env:TEMP "no-such-file.properties") | Should Be ""
    }

    It "saves non-protected, non-curated keys from the advanced text" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "level-seed=99999`r`nonline-mode=false"
        Get-ServerProperty $propsPath "level-seed"  | Should Be "99999"
        Get-ServerProperty $propsPath "online-mode" | Should Be "false"
    }

    It "never lets advanced text override protected keys" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "rcon.password=hacked"
        Get-ServerProperty $propsPath "rcon.password" | Should Be "secret123"
    }

    It "never lets advanced text override curated keys" {
        Save-AdvancedPropertiesLines -Path $propsPath -Text "difficulty=hard"
        Get-ServerProperty $propsPath "difficulty" | Should Be "easy"
    }

    Remove-Item -Path $propsPath, "$propsPath.bak" -Force -ErrorAction SilentlyContinue
}

Describe "Get-RunConfigMaxRam / Set-RunConfigMaxRam" {
    $configPath = Join-Path $env:TEMP ("run-config-" + [Guid]::NewGuid().ToString("N") + ".ps1")

    BeforeEach {
        @(
            '$JavaVersion = 21'
            '$MinRam = "2G"'
            '$MaxRam = "6G"'
            '$ServerJar = "server.jar"'
        ) -join "`r`n" | Set-Content -Path $configPath -Encoding ascii
    }

    It "reads the current MaxRam value" {
        Get-RunConfigMaxRam -Path $configPath | Should Be "6G"
    }

    It "returns 6G for a missing file" {
        Get-RunConfigMaxRam -Path (Join-Path $env:TEMP "no-such-config.ps1") | Should Be "6G"
    }

    It "writes a new MaxRam value, leaving the rest of the file untouched" {
        Set-RunConfigMaxRam -Path $configPath -MaxRam "8G"
        Get-RunConfigMaxRam -Path $configPath | Should Be "8G"
        (Get-Content -Path $configPath -Raw) | Should Match '\$JavaVersion = 21'
        (Get-Content -Path $configPath -Raw) | Should Match '\$MinRam = "2G"'
    }

    Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
}
