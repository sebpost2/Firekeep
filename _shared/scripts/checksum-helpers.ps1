# Checks install-java.ps1 relies on: SHA256 verification of the downloaded
# Adoptium JDK, and whether an installed JDK actually runs. Loaded via dot-source.

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

# True only if <JavaHome>\bin\java.exe starts a JVM that lives in <JavaHome>.
# A half-extracted JDK keeps bin\java.exe but can't start on its own ("could
# not open ...\lib\jvm.cfg") - or its launcher quietly runs some other Java
# installed on the PC instead - so the file existing, or even exiting 0,
# isn't proof. The JVM's own java.home is.
function Test-JavaWorks {
    param(
        [Parameter(Mandatory = $true)][string]$JavaHome
    )
    $exe = Join-Path $JavaHome "bin\java.exe"
    if (-not (Test-Path $exe)) { return $false }
    # java prints to stderr; under a caller's "Stop" preference PS 5.1 would
    # turn that into an exception.
    $ErrorActionPreference = "Continue"
    try {
        $output = & $exe -XshowSettings:properties -version 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { return $false }
    } catch {
        return $false
    }
    $homeLine = $output | Where-Object { $_ -match '^\s*java\.home\s*=\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $homeLine) { return $false }
    $null = $homeLine -match '^\s*java\.home\s*=\s*(.+?)\s*$'
    # Java 8 reports <JavaHome>\jre, newer ones <JavaHome> itself.
    $expected = (Resolve-Path $JavaHome).Path.TrimEnd('\')
    return ($Matches[1] -eq $expected) -or $Matches[1].StartsWith("$expected\", [StringComparison]::OrdinalIgnoreCase)
}
