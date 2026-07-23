# Helpers de presentacion para la consola del menu (Start.ps1 y afines).
# Solo caracteres ASCII a proposito: los .ps1 de este repo no llevan BOM, y
# PowerShell 5.1 los parsea como ANSI sin BOM, asi que cualquier caracter no-ASCII
# en un string literal (acentos, box-drawing, emoji) puede salir mal en la
# consola. Ver mrpack-helpers.ps1 / Set-RunConfigJavaAndRam para el mismo tema
# del lado de archivos.
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
