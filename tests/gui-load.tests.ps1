# Regression test for the Task-2 bug where every screen XAML threw a
# XamlParseException on startup: Get-ScreenXaml merged Theme.xaml into each
# screen's Resources AFTER XamlReader::Load() already evaluated its
# {StaticResource ...} references. WPF requires STA, and Pester itself
# doesn't run in STA by default, so this spawns a real STA powershell.exe
# subprocess that extracts Start-Gui.ps1's actual theme-setup + Get-ScreenXaml
# code (so it tests the real codepath, not a copy of it) and loads every
# screen XAML through it.

$repoRoot = Split-Path -Parent $PSScriptRoot
$startGuiPath = Join-Path $repoRoot "Start-Gui.ps1"
$startGuiContent = Get-Content -Path $startGuiPath -Raw

# Pull out the block from the Application/theme setup through the end of the
# Get-ScreenXaml function definition - the exact codepath this test guards.
if ($startGuiContent -notmatch '(?s)(if \(-not \[System\.Windows\.Application\]::Current\).*?return \[Windows\.Markup\.XamlReader\]::Load\(\(New-Object System\.Xml\.XmlNodeReader \$xamlXml\)\)\r?\n})') {
    throw "Could not find the theme-setup/Get-ScreenXaml block in Start-Gui.ps1 - has it moved?"
}
$setupBlock = $matches[1]

$screenFiles = @(
    "MainWindow.xaml",
    "HomeScreen.xaml",
    "ManageMapsScreen.xaml",
    "ServerSettingsScreen.xaml",
    "AddServerScreen.xaml",
    "ConsoleScreen.xaml",
    "PromptOverlay.xaml"
)

Describe "Get-ScreenXaml loads every screen (headless, STA)" {

    $script:results = $null

    It "runs the real Get-ScreenXaml codepath in an STA process without throwing" {
        $guiDir = Join-Path $repoRoot "_shared\gui"
        $resultsFile = Join-Path $env:TEMP ("gui-load-results-" + [Guid]::NewGuid().ToString("N") + ".txt")

        $subScript = @"
`$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
`$root = '$repoRoot'
$setupBlock

`$screenFiles = @('$($screenFiles -join "','")')
`$lines = @()
foreach (`$f in `$screenFiles) {
    try {
        `$el = Get-ScreenXaml `$f
        `$lines += "OK:`${f}:`$(`$null -ne `$el)"
    } catch {
        `$lines += "FAIL:`${f}:`$(`$_.Exception.Message)"
    }
}
Set-Content -Path '$resultsFile' -Value `$lines
"@

        $tempScriptFile = Join-Path $env:TEMP ("gui-load-test-" + [Guid]::NewGuid().ToString("N") + ".ps1")
        Set-Content -Path $tempScriptFile -Value $subScript

        & powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File $tempScriptFile
        $exitCode = $LASTEXITCODE

        $script:results = if (Test-Path $resultsFile) { Get-Content $resultsFile } else { @() }

        Remove-Item -Path $tempScriptFile -ErrorAction SilentlyContinue
        Remove-Item -Path $resultsFile -ErrorAction SilentlyContinue

        $exitCode | Should Be 0
        $script:results.Count | Should Be $screenFiles.Count
    }

    foreach ($f in $screenFiles) {
        It "loads $f without throwing a XamlParseException" {
            $line = $script:results | Where-Object { $_ -like "*:$($f):*" }
            $line | Should Not Be $null
            $line | Should Match "^OK:"
        }
    }
}
