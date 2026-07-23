# Presentation helpers for the menu console (Start.ps1 and friends).
# ASCII characters only, on purpose: this repo's .ps1 files have no BOM, and
# PowerShell 5.1 parses them as ANSI without one, so any non-ASCII character
# in a string literal (accents, box-drawing, emoji) can render wrong in the
# console. See mrpack-helpers.ps1 / Set-RunConfigJavaAndRam for the same
# issue on the file-write side.
$Script:UiWidth = 64

function Write-UiBanner {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle
    )
    $bar = "+" + ("-" * ($Script:UiWidth - 2)) + "+"
    Write-Host ""
    Write-Host $bar -ForegroundColor Cyan
    Write-Host ("|  " + $Title.PadRight($Script:UiWidth - 4) + "|") -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host ("|  " + $Subtitle.PadRight($Script:UiWidth - 4) + "|") -ForegroundColor DarkCyan
    }
    Write-Host $bar -ForegroundColor Cyan
}

function Write-UiSection {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host ""
    Write-Host "  $($Text.ToUpper())" -ForegroundColor White
    Write-Host ("  " + ("-" * ($Script:UiWidth - 2))) -ForegroundColor DarkGray
}

function Write-UiMenuItem {
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$Action
    )
    $tag = "[{0}]" -f $Index
    Write-Host "    $tag " -ForegroundColor Yellow -NoNewline
    if ($Action) {
        Write-Host $Label -ForegroundColor Green
    }
    else {
        Write-Host $Label -ForegroundColor White
    }
}

function Write-UiHint {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host "  $Text" -ForegroundColor DarkGray
}

function Write-UiSuccess {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-UiWarn {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}
