. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\mrpack-helpers.ps1")

Describe "Get-JavaVersionForMinecraft" {

    It "maps 1.16.5 (last pre-1.17) to Java 8" {
        Get-JavaVersionForMinecraft -McVersion "1.16.5" | Should Be 8
    }

    It "maps 1.8.9 to Java 8" {
        Get-JavaVersionForMinecraft -McVersion "1.8.9" | Should Be 8
    }

    It "maps 1.9 to Java 8 (numeric compare, not string compare)" {
        Get-JavaVersionForMinecraft -McVersion "1.9" | Should Be 8
    }

    It "maps 1.17 (first 17-era version) to Java 17" {
        Get-JavaVersionForMinecraft -McVersion "1.17" | Should Be 17
    }

    It "maps 1.20.4 (last pre-1.20.5) to Java 17" {
        Get-JavaVersionForMinecraft -McVersion "1.20.4" | Should Be 17
    }

    It "maps 1.20.5 (first 21-era version) to Java 21" {
        Get-JavaVersionForMinecraft -McVersion "1.20.5" | Should Be 21
    }

    It "maps 1.21 to Java 21" {
        Get-JavaVersionForMinecraft -McVersion "1.21" | Should Be 21
    }

    It "throws a clear error for an unparseable version string" {
        { Get-JavaVersionForMinecraft -McVersion "not-a-version" } | Should Throw
    }
}
