. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\package-release.ps1") -TestOnlyLoadFunctions

Describe "Get-ReleaseFiles" {

    $fixtureRoot = Join-Path $env:TEMP ("release-fixture-" + [Guid]::NewGuid().ToString("N"))
    $paths = @(
        "Start.bat", "Start-Gui.ps1",
        "README.md", ".gitignore", "VERSION",
        "_shared\scripts\rcon.ps1",
        "_shared\gui\MainWindow.xaml",
        "_shared\gui\ManageMapsScreen.xaml",
        "_shared\gui\AddServerScreen.xaml",
        "_shared\tools\mrpack.exe",
        "_shared\tools\playit\secret.key",
        "_shared\tools\playit\address.txt",
        "Minecraft\scripts\install-java.ps1",
        "Minecraft\servers\_template\run.config.ps1",
        "Minecraft\servers\Cave Horror Project\ops.json",
        "Minecraft\servers\Cave Horror Project\world\level.dat",
        "Minecraft\servers\Cave Horror Project\NOTES.md",
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
        ($result -contains (Join-Path $fixtureRoot "Start.bat")) | Should Be $true
        ($result -contains (Join-Path $fixtureRoot "Minecraft\scripts\install-java.ps1")) | Should Be $true
    }

    It "includes the GUI launcher and its window markup" {
        ($result -contains (Join-Path $fixtureRoot "Start-Gui.ps1")) | Should Be $true
        ($result -contains (Join-Path $fixtureRoot "_shared\gui\MainWindow.xaml")) | Should Be $true
    }

    It "includes the Manage Maps and Add Server screen markup" {
        ($result -contains (Join-Path $fixtureRoot "_shared\gui\ManageMapsScreen.xaml")) | Should Be $true
        ($result -contains (Join-Path $fixtureRoot "_shared\gui\AddServerScreen.xaml")) | Should Be $true
    }

    It "includes the generic _template" {
        ($result -contains (Join-Path $fixtureRoot "Minecraft\servers\_template\run.config.ps1")) | Should Be $true
    }

    It "excludes the personal Cave Horror Project server instance" {
        ($result -contains (Join-Path $fixtureRoot "Minecraft\servers\Cave Horror Project\ops.json")) | Should Be $false
        ($result -contains (Join-Path $fixtureRoot "Minecraft\servers\Cave Horror Project\world\level.dat")) | Should Be $false
    }

    It "excludes personal per-instance notes (e.g. NOTES.md living inside an installed server folder)" {
        ($result -contains (Join-Path $fixtureRoot "Minecraft\servers\Cave Horror Project\NOTES.md")) | Should Be $false
    }

    It "includes the public README.md" {
        ($result -contains (Join-Path $fixtureRoot "README.md")) | Should Be $true
    }

    It "includes the VERSION file" {
        ($result -contains (Join-Path $fixtureRoot "VERSION")) | Should Be $true
    }

    It "excludes the playit secret and cached address" {
        ($result -contains (Join-Path $fixtureRoot "_shared\tools\playit\secret.key")) | Should Be $false
        ($result -contains (Join-Path $fixtureRoot "_shared\tools\playit\address.txt")) | Should Be $false
    }

    It "excludes portable Java runtimes (redownloadable, large)" {
        ($result -contains (Join-Path $fixtureRoot "Minecraft\tools\java\21\bin\java.exe")) | Should Be $false
    }

    It "includes the test suite" {
        ($result -contains (Join-Path $fixtureRoot "tests\checksum-helpers.tests.ps1")) | Should Be $true
    }

    Remove-Item -Recurse -Force $fixtureRoot -ErrorAction SilentlyContinue
}
