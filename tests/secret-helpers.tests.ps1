. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\secret-helpers.ps1")

Describe "Set-RestrictedSecretFile" {

    $path = Join-Path $env:TEMP ("secret-test-" + [Guid]::NewGuid().ToString("N") + ".key")

    It "writes the exact content" {
        Set-RestrictedSecretFile -Path $path -Content "shh-secret"
        (Get-Content -Path $path -Raw) | Should Be "shh-secret"
    }

    It "disables inherited permissions (no window where default/broader ACL applies)" {
        Set-RestrictedSecretFile -Path $path -Content "shh-secret"
        (Get-Acl -Path $path).AreAccessRulesProtected | Should Be $true
    }

    It "grants access only to the current user" {
        Set-RestrictedSecretFile -Path $path -Content "shh-secret"
        $acl = Get-Acl -Path $path
        $identities = $acl.Access | Select-Object -ExpandProperty IdentityReference | ForEach-Object { $_.ToString() }
        $me = "$env:USERDOMAIN\$env:USERNAME"
        ($identities | Where-Object { $_ -ne $me }) | Should Be $null
    }

    Remove-Item -Force $path -ErrorAction SilentlyContinue
}
