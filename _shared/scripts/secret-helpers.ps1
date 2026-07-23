# Helper for saving secrets to disk without a window where the file has the
# folder's default/inherited permissions (which other accounts on the same
# PC might be able to read). Loaded via dot-source.

# Creates the file EMPTY, restricts access to the current user, and only then
# writes the content. This way the content never exists on disk with wider
# permissions than the restricted ones (avoids the create-then-restrict
# TOCTOU window).
function Set-RestrictedSecretFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    New-Item -ItemType File -Path $Path -Force | Out-Null
    icacls $Path /inheritance:r /grant:r "${env:USERDOMAIN}\${env:USERNAME}:(R,W)" | Out-Null
    Set-Content -Path $Path -Value $Content -NoNewline -Encoding ascii
}
