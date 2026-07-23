# SHA256 checksum verification for downloaded files (e.g. the Adoptium JDK in
# install-java.ps1). Loaded via dot-source.

# Compares a file's SHA256 against the expected value. Returns $false if the
# file doesn't exist or the hash doesn't match (never throws).
function Test-Sha256Checksum {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    return $actual -ieq $ExpectedSha256
}
