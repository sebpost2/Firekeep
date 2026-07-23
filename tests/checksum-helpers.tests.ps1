. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\checksum-helpers.ps1")

Describe "Test-Sha256Checksum" {

    $tmpFile = Join-Path $env:TEMP ("checksum-test-" + [Guid]::NewGuid().ToString("N") + ".bin")
    "hello world" | Set-Content -Path $tmpFile -Encoding ascii -NoNewline
    $realHash = (Get-FileHash -Path $tmpFile -Algorithm SHA256).Hash

    It "returns true when the hash matches" {
        Test-Sha256Checksum -Path $tmpFile -ExpectedSha256 $realHash | Should Be $true
    }

    It "returns false when the hash does not match" {
        Test-Sha256Checksum -Path $tmpFile -ExpectedSha256 ("0" * 64) | Should Be $false
    }

    It "returns false when the file does not exist" {
        Test-Sha256Checksum -Path (Join-Path $env:TEMP "does-not-exist.bin") -ExpectedSha256 $realHash | Should Be $false
    }

    Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
}
