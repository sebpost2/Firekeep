. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\modloader-helpers.ps1")

Describe "Get-DetectedJavaVersion" {

    $root = Join-Path $env:TEMP ("modloader-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "returns null when the instance has neither variables.txt nor run.bat (vanilla, or nothing copied in yet)" {
        $empty = Join-Path $root "empty"
        New-Item -ItemType Directory -Force -Path $empty | Out-Null
        Get-DetectedJavaVersion -InstancePath $empty | Should Be $null
    }

    It "reads RECOMMENDED_JAVA_VERSION directly from a ServerPackCreator variables.txt (works for any loader it was built for)" {
        $dir = Join-Path $root "spc-recommended"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            "# ServerPackCreator variables"
            "MINECRAFT_VERSION=1.20.1"
            "MODLOADER=Fabric"
            "MODLOADER_VERSION=0.18.4"
            "RECOMMENDED_JAVA_VERSION=17"
        ) | Set-Content -Path (Join-Path $dir "variables.txt") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 17
    }

    It "falls back to MINECRAFT_VERSION in variables.txt when RECOMMENDED_JAVA_VERSION is missing" {
        $dir = Join-Path $root "spc-no-recommended"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            "MINECRAFT_VERSION=1.20.1"
            "MODLOADER=NeoForge"
        ) | Set-Content -Path (Join-Path $dir "variables.txt") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 17
    }

    It "detects modern Forge from run.bat's library path when there's no variables.txt" {
        $dir = Join-Path $root "raw-forge"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            "@echo off"
            "java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.20/win_args.txt %*"
            "pause"
        ) | Set-Content -Path (Join-Path $dir "run.bat") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 17
    }

    It "detects Forge from run.bat with a 3-segment forge version (DeceasedCraft's real format)" {
        $dir = Join-Path $root "raw-forge-3seg"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            "@echo off"
            "java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.0/win_args.txt %*"
            "pause"
        ) | Set-Content -Path (Join-Path $dir "run.bat") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 17
    }

    It "reads the Java version straight from an ATM-style startserver.bat (e.g. 'Minecraft 1.21 requires Java 21')" {
        $dir = Join-Path $root "neoforge-startserver-atm10"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            '@echo off'
            'set NEOFORGE_VERSION=21.1.234'
            '"%ATM10_JAVA%" -version 1>nul 2>nul || ('
            '   echo Minecraft 1.21 requires Java 21 - Java not found'
            '   pause'
            '   exit /b 1'
            ')'
        ) | Set-Content -Path (Join-Path $dir "startserver.bat") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 21
    }

    It "reads the Java version from a startserver.bat requiring a newer Java (e.g. 'Minecraft 26.1.2 requires Java 25')" {
        $dir = Join-Path $root "neoforge-startserver-atm11"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            '@echo off'
            'set NEOFORGE_VERSION=26.1.2.78'
            '"%ATM11_JAVA%" -version 1>nul 2>nul || ('
            '   echo Minecraft 26.1.2 requires Java 25 - Java not found'
            '   pause'
            '   exit /b 1'
            ')'
        ) | Set-Content -Path (Join-Path $dir "startserver.bat") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be 25
    }

    It "returns null when run.bat exists but doesn't match a recognized loader pattern" {
        $dir = Join-Path $root "custom-runbat"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @("@echo off", "java -jar server.jar nogui") | Set-Content -Path (Join-Path $dir "run.bat") -Encoding ascii
        Get-DetectedJavaVersion -InstancePath $dir | Should Be $null
    }

    It "returns null instead of throwing when variables.txt has an unparseable MINECRAFT_VERSION" {
        $dir = Join-Path $root "spc-bad-version"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @("MINECRAFT_VERSION=not-a-version") | Set-Content -Path (Join-Path $dir "variables.txt") -Encoding ascii
        { Get-DetectedJavaVersion -InstancePath $dir } | Should Not Throw
        Get-DetectedJavaVersion -InstancePath $dir | Should Be $null
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
