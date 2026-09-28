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

Describe "Test-JavaWorks" {

    function New-FakeJavaHome {
        $home_ = Join-Path $env:TEMP ("java-works-test-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path (Join-Path $home_ "bin") | Out-Null
        return $home_
    }

    It "returns false when bin\java.exe is missing" {
        $javaHome = New-FakeJavaHome
        Test-JavaWorks -JavaHome $javaHome | Should Be $false
        Remove-Item -Recurse -Force $javaHome
    }

    # A half-extracted JDK still has bin\java.exe but it can't start
    # ("could not open ...\lib\jvm.cfg") - existence alone isn't enough.
    It "returns false when java.exe exists but exits with an error" {
        $javaHome = New-FakeJavaHome
        Copy-Item (Join-Path $env:SystemRoot "System32\where.exe") (Join-Path $javaHome "bin\java.exe")
        Test-JavaWorks -JavaHome $javaHome | Should Be $false
        Remove-Item -Recurse -Force $javaHome
    }

    It "returns false when java.exe isn't a program at all" {
        $javaHome = New-FakeJavaHome
        Set-Content -Path (Join-Path $javaHome "bin\java.exe") -Value "not a program"
        Test-JavaWorks -JavaHome $javaHome | Should Be $false
        Remove-Item -Recurse -Force $javaHome
    }

    # Uses a real portable Java when this checkout has one (tools\ isn't in git).
    $realJava = Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) "Minecraft\tools\java") -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } | Select-Object -First 1
    It "returns true for a working Java" -Skip:(-not $realJava) {
        Test-JavaWorks -JavaHome $realJava.FullName | Should Be $true
    }

    # Last session's broken install: bin\java.exe present, lib\ gutted. The
    # launcher can then quietly run some OTHER Java on the PC (a system-wide
    # install) and exit 0, so success alone doesn't prove this JDK works.
    It "returns false for a real java.exe whose own lib folder is broken" -Skip:(-not $realJava) {
        $javaHome = New-FakeJavaHome
        Copy-Item (Join-Path $realJava.FullName "bin\java.exe") (Join-Path $javaHome "bin\java.exe")
        New-Item -ItemType Directory -Path (Join-Path $javaHome "lib") | Out-Null
        Set-Content -Path (Join-Path $javaHome "lib\modules") -Value "x"
        Test-JavaWorks -JavaHome $javaHome | Should Be $false
        Remove-Item -Recurse -Force $javaHome
    }

    # install-java.ps1 runs with ErrorActionPreference=Stop, which in PS 5.1
    # turns java's normal stderr banner into an exception.
    It "still returns true for a working Java under ErrorActionPreference Stop" -Skip:(-not $realJava) {
        $ErrorActionPreference = "Stop"
        Test-JavaWorks -JavaHome $realJava.FullName | Should Be $true
    }
}
