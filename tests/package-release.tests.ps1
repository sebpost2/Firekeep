. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\package-release.ps1") -TestOnlyLoadFunctions

Describe "Get-ReleaseFiles" {

    $fixtureRoot = Join-Path $env:TEMP ("release-fixture-" + [Guid]::NewGuid().ToString("N"))
    $paths = @(
        "Start.bat", "Start.ps1", "Detener Server.bat", "LEEME.md", ".gitignore",
        "_shared\scripts\rcon.ps1",
        "_shared\tools\mrpack.exe",
        "_shared\tools\playit\secret.key",
        "_shared\tools\playit\address.txt",
        "Minecraft\scripts\new-server.ps1",
        "Minecraft\servers\_template\run.config.ps1",
        "Minecraft\servers\Cave Horror Project\ops.json",
        "Minecraft\servers\Cave Horror Project\world\level.dat",
        "Minecraft\tools\java\21\bin\java.exe",
        "tests\checksum-helpers.tests.ps1"
    )
    foreach ($rel in $paths) {
        $full = Join-Path $fixtureRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
        Set-Content -Path $full -Value "x"
    }

    $result = Get-ReleaseFiles -Root $fixtureRoot

    It "includes the framework menu and scripts" {
        $result | Should Contain (Join-Path $fixtureRoot "Start.bat")
        $result | Should Contain (Join-Path $fixtureRoot "Minecraft\scripts\new-server.ps1")
    }

    It "includes the generic _template" {
        $result | Should Contain (Join-Path $fixtureRoot "Minecraft\servers\_template\run.config.ps1")
    }

    It "excludes the personal Cave Horror Project server instance" {
        $result | Should Not Contain (Join-Path $fixtureRoot "Minecraft\servers\Cave Horror Project\ops.json")
        $result | Should Not Contain (Join-Path $fixtureRoot "Minecraft\servers\Cave Horror Project\world\level.dat")
    }

    It "excludes the playit secret and cached address" {
        $result | Should Not Contain (Join-Path $fixtureRoot "_shared\tools\playit\secret.key")
        $result | Should Not Contain (Join-Path $fixtureRoot "_shared\tools\playit\address.txt")
    }

    It "excludes portable Java runtimes (redownloadable, large)" {
        $result | Should Not Contain (Join-Path $fixtureRoot "Minecraft\tools\java\21\bin\java.exe")
    }

    It "includes the test suite" {
        $result | Should Contain (Join-Path $fixtureRoot "tests\checksum-helpers.tests.ps1")
    }

    Remove-Item -Recurse -Force $fixtureRoot -ErrorAction SilentlyContinue
}
