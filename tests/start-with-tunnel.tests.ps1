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
        if ($content -notmatch '(?s)catch \{(.*?)\}') {
            throw "Could not find the sidecar-start catch block in start-with-tunnel.ps1 - has it moved?"
        }
        $catchBlock = $matches[1]
        $catchBlock | Should Match 'Set-VerityAiProvider\s+-InstancePath\s+\$PSScriptRoot\s+-Service\s+\$service\s+-UseLocal\s+\$false'
    }
}
