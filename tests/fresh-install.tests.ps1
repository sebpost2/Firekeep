# Regression test for the "nobody has ever launched this on a clean
# machine" gap: stages a disposable copy containing ONLY the files that
# ship in a real release (same allow-list package-release.ps1 uses - so
# it has zero server instances, no Java runtime, no playit secrets), then
# launches that copy's Start-Gui.ps1 for real, headlessly, and confirms it
# starts up and shuts down cleanly with nothing pre-existing. WPF requires
# STA and Pester doesn't run in STA by default, so - same technique as
# gui-load.tests.ps1 - this spawns a real STA powershell.exe subprocess.

$repoRoot = Split-Path -Parent $PSScriptRoot

Describe "Fresh install (headless, STA, zero prior state)" {

    $stageRoot = Join-Path $env:TEMP ("fresh-install-stage-" + [Guid]::NewGuid().ToString("N"))
    $resultsFile = Join-Path $env:TEMP ("fresh-install-results-" + [Guid]::NewGuid().ToString("N") + ".txt")

    It "stages a fresh copy containing only the release file set" {
        . (Join-Path $repoRoot "_shared\scripts\package-release.ps1") -TestOnlyLoadFunctions
        $files = Get-ReleaseFiles -Root $repoRoot
        $files.Count | Should BeGreaterThan 0

        foreach ($f in $files) {
            $rel = $f.Substring($repoRoot.Length).TrimStart('\')
            $dest = Join-Path $stageRoot $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -Path $f -Destination $dest -Force
        }

        (Test-Path (Join-Path $stageRoot "Start-Gui.ps1")) | Should Be $true
    }

    It "has no real server instances in the staged copy (the actual fresh-machine condition)" {
        $serversDir = Join-Path $stageRoot "Minecraft\servers"
        $instanceDirs = @(Get-ChildItem -Path $serversDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "_template" })
        $instanceDirs.Count | Should Be 0
    }

    It "launches Start-Gui.ps1 from the staged copy without throwing" {
        $subScript = @"
`$ErrorActionPreference = 'Stop'
`$env:GUI_TEST_AUTOCLOSE_MS = '3000'
try {
    & '$stageRoot\Start-Gui.ps1'
    Set-Content -Path '$resultsFile' -Value 'OK'
} catch {
    Set-Content -Path '$resultsFile' -Value "FAIL:`$(`$_.Exception.Message)"
}
"@
        $tempScriptFile = Join-Path $env:TEMP ("fresh-install-test-" + [Guid]::NewGuid().ToString("N") + ".ps1")
        Set-Content -Path $tempScriptFile -Value $subScript

        # Bounded well above GUI_TEST_AUTOCLOSE_MS (3000ms) so a healthy run
        # never trips it, but a regressed/removed auto-close hook fails this
        # test instead of hanging forever.
        $job = Start-Job -ScriptBlock {
            param($file)
            & powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File $file
            $LASTEXITCODE
        } -ArgumentList $tempScriptFile

        $timedOut = -not (Wait-Job -Job $job -Timeout 30)
        if ($timedOut) {
            Stop-Job -Job $job
        }
        $exitCode = if ($timedOut) { $null } else { Receive-Job -Job $job }
        Remove-Job -Job $job -Force

        $script:result = if (Test-Path $resultsFile) { Get-Content $resultsFile -Raw } else { "NO RESULT FILE" }

        Remove-Item -Path $tempScriptFile -ErrorAction SilentlyContinue
        Remove-Item -Path $resultsFile -ErrorAction SilentlyContinue

        $timedOut | Should Be $false "subprocess did not exit within timeout"
        $exitCode | Should Be 0
        $script:result | Should Match "^OK"
    }

    Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
}
