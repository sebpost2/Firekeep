# Regression test for the bug where a failed local Verity sidecar logged
# "will fall back to its configured cloud provider" but never actually
# flipped the config - so Verity kept pointing at a dead local endpoint.
# This checks the fix is textually present in the right place (inside the
# sidecar-start catch block) rather than executing the real script, since
# start-with-tunnel.ps1 has real side effects (process locks, launching
# playit.exe, launching the actual Minecraft server) that make it unsafe
# to run directly in a test.

$templatePath = Join-Path (Split-Path -Parent $PSScriptRoot) "Minecraft\servers\_template\start-with-tunnel.ps1"
$content = Get-Content -Path $templatePath -Raw

Describe "start-with-tunnel.ps1 sidecar-failure fallback" {

    It "flips the failed sidecar to remote inside the catch block" {
        # Verify the Write-Warning about sidecar failure exists (identifies the catch block)
        if ($content -notmatch "Write-Warning.*didn't come up") {
            throw "Could not find the sidecar failure Write-Warning in start-with-tunnel.ps1 - has the error message changed?"
        }

        # Extract the section starting from the Write-Warning, approximately 500 chars forward,
        # to verify Set-VerityAiProvider call appears shortly after (within same catch block).
        # This avoids brittle brace-matching since the try/catch is on one line with Set-VerityAiProvider.
        $failureMessageIndex = $content.IndexOf("Write-Warning")
        if ($failureMessageIndex -eq -1) {
            throw "Internal test error: could not find Write-Warning after checking it matched"
        }

        $catchBlockSection = $content.Substring($failureMessageIndex, [Math]::Min(500, $content.Length - $failureMessageIndex))

        if ($catchBlockSection -notmatch 'Set-VerityAiProvider\s+-InstancePath\s+\$PSScriptRoot\s+-Service\s+\$service\s+-UseLocal\s+\$false') {
            throw "Set-VerityAiProvider call not found after the sidecar failure warning, or has incorrect arguments"
        }
    }
}
