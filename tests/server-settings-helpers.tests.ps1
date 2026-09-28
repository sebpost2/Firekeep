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

Describe "Get-ServerMaxRam / Set-ServerMaxRam" {

    function New-Instance {
        $dir = Join-Path $env:TEMP ("server-maxram-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "run.config.ps1") -Value @('$JavaVersion = 17', '$MaxRam = "6G"')
        return $dir
    }

    # Forge/NeoForge servers start through run.bat, which reads memory from
    # user_jvm_args.txt - $MaxRam alone was silently ignored for them.
    It "writes the memory into user_jvm_args.txt, keeping the pack's other lines" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "user_jvm_args.txt") -Value @("# pack notes", "-Xms4G", "-Xmx4G", "-XX:+UseG1GC", "-Dfoo=bar")
        Set-ServerMaxRam -InstancePath $dir -MaxRam "10G"
        $lines = Get-Content (Join-Path $dir "user_jvm_args.txt")
        ($lines -contains "-Xmx10G") | Should Be $true
        ($lines -contains "-Xms10G") | Should Be $true
        @($lines | Where-Object { $_ -match '^-Xm[sx]4G' }).Count | Should Be 0
        ($lines -contains "# pack notes") | Should Be $true
        ($lines -contains "-Dfoo=bar") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "adds Aikar's flags when the pack has no garbage-collector flags" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "user_jvm_args.txt") -Value @("# Xmx here")
        Set-ServerMaxRam -InstancePath $dir -MaxRam "8G"
        $lines = Get-Content (Join-Path $dir "user_jvm_args.txt")
        ($lines -contains "-XX:+UseG1GC") | Should Be $true
        ($lines -contains "-Daikars.new.flags=true") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "leaves a pack's own garbage-collector choice alone" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "user_jvm_args.txt") -Value @("-XX:+UseZGC")
        Set-ServerMaxRam -InstancePath $dir -MaxRam "8G"
        $lines = Get-Content (Join-Path $dir "user_jvm_args.txt")
        ($lines -contains "-XX:+UseG1GC") | Should Be $false
        ($lines -contains "-XX:+UseZGC") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "updates JAVA_ARGS in a ServerPackCreator variables.txt" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "variables.txt") -Value @("MINECRAFT_VERSION=1.20.1", 'JAVA_ARGS="-Xms4G -Xmx4G -Dlog4j2.formatMsgNoLookups=true"')
        Set-ServerMaxRam -InstancePath $dir -MaxRam "12G"
        $vars = Get-Content (Join-Path $dir "variables.txt")
        ($vars -contains 'JAVA_ARGS="-Xms12G -Xmx12G -Dlog4j2.formatMsgNoLookups=true"') | Should Be $true
        ($vars -contains "MINECRAFT_VERSION=1.20.1") | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "always updates run.config.ps1 too" {
        $dir = New-Instance
        Set-ServerMaxRam -InstancePath $dir -MaxRam "9G"
        Get-RunConfigMaxRam -Path (Join-Path $dir "run.config.ps1") | Should Be "9G"
        Remove-Item -Recurse -Force $dir
    }

    It "reads the memory the server really uses: user_jvm_args.txt first" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "user_jvm_args.txt") -Value @("-Xmx10G")
        Get-ServerMaxRam -InstancePath $dir | Should Be "10G"
        Remove-Item -Recurse -Force $dir
    }

    It "reads JAVA_ARGS from variables.txt when there's no user_jvm_args.txt" {
        $dir = New-Instance
        Set-Content -Path (Join-Path $dir "variables.txt") -Value @('JAVA_ARGS="-Xms5G -Xmx5G"')
        Get-ServerMaxRam -InstancePath $dir | Should Be "5G"
        Remove-Item -Recurse -Force $dir
    }

    It "falls back to run.config.ps1" {
        $dir = New-Instance
        Get-ServerMaxRam -InstancePath $dir | Should Be "6G"
        Remove-Item -Recurse -Force $dir
    }
}

Describe "Get-SuggestedMaxRam" {
    It "suggests more memory for bigger modpacks" {
        Get-SuggestedMaxRam -TotalRamGB 64 -ModCount 0   | Should Be "3G"
        Get-SuggestedMaxRam -TotalRamGB 64 -ModCount 40  | Should Be "4G"
        Get-SuggestedMaxRam -TotalRamGB 64 -ModCount 120 | Should Be "6G"
        Get-SuggestedMaxRam -TotalRamGB 64 -ModCount 200 | Should Be "8G"
        Get-SuggestedMaxRam -TotalRamGB 64 -ModCount 356 | Should Be "10G"
    }

    It "leaves Windows at least 4 GB" {
        Get-SuggestedMaxRam -TotalRamGB 12 -ModCount 356 | Should Be "8G"
    }

    It "never suggests less than 2 GB" {
        Get-SuggestedMaxRam -TotalRamGB 4 -ModCount 356 | Should Be "2G"
    }
}

Describe "ConvertTo-RamGB" {
    It "reads G and M values" {
        ConvertTo-RamGB "10G" | Should Be 10
        ConvertTo-RamGB "4096M" | Should Be 4
        ConvertTo-RamGB "8g" | Should Be 8
    }

    It "returns null for anything else" {
        ConvertTo-RamGB "lots" | Should Be $null
    }
}
