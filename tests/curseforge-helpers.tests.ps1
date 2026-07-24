. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\curseforge-helpers.ps1")

Describe "Install-CurseForgeServerZip" {

    function New-TestZip([string]$ZipPath, [hashtable]$Files, [string]$NestedFolder = $null) {
        $workDir = Join-Path $env:TEMP ("curseforge-fixture-" + [Guid]::NewGuid().ToString("N"))
        $filesRoot = $workDir
        if ($NestedFolder) {
            $filesRoot = Join-Path $workDir $NestedFolder
        }
        New-Item -ItemType Directory -Force -Path $filesRoot | Out-Null
        foreach ($relPath in $Files.Keys) {
            $full = Join-Path $filesRoot $relPath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
            Set-Content -Path $full -Value $Files[$relPath] -Encoding ascii
        }
        if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
        Compress-Archive -Path (Join-Path $workDir "*") -DestinationPath $ZipPath -Force
        Remove-Item -Recurse -Force $workDir
    }

    $root = Join-Path $env:TEMP ("curseforge-install-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    It "extracts a flat CurseForge zip and detects the Java version from variables.txt" {
        $zip = Join-Path $root "flat.zip"
        New-TestZip -ZipPath $zip -Files @{
            "variables.txt" = "MINECRAFT_VERSION=1.20.1`nMODLOADER=Forge`nRECOMMENDED_JAVA_VERSION=17"
            "mods\somemod.jar" = "fake jar bytes"
        }
        $dest = Join-Path $root "flat-dest"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        $detected = Install-CurseForgeServerZip -ZipPath $zip -DestPath $dest
        $detected | Should Be 17
        Test-Path (Join-Path $dest "mods\somemod.jar") | Should Be $true
    }

    It "finds the real Server Files root inside an extra nested folder (like Into_the_backrooms' real zip)" {
        $zip = Join-Path $root "nested.zip"
        New-TestZip -ZipPath $zip -NestedFolder "Some Modpack Name" -Files @{
            "start.bat" = "java -jar fabric-server-mc.1.20.1-loader.0.15.0-launcher.1.0.1.jar nogui"
            "fabric-server-mc.1.20.1-loader.0.15.0-launcher.1.0.1.jar" = "fake jar bytes"
        }
        $dest = Join-Path $root "nested-dest"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        $detected = Install-CurseForgeServerZip -ZipPath $zip -DestPath $dest
        $detected | Should Be 17
        Test-Path (Join-Path $dest "start.bat") | Should Be $true
    }

    It "throws a clear error when the zip has no recognizable Server Files signature (client modpack export, like DarkRPG)" {
        $zip = Join-Path $root "clientpack.zip"
        New-TestZip -ZipPath $zip -Files @{
            "manifest.json" = '{"minecraft":{"version":"1.20.1"}}'
            "modlist.html" = "<html></html>"
        }
        $dest = Join-Path $root "clientpack-dest"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        { Install-CurseForgeServerZip -ZipPath $zip -DestPath $dest } | Should Throw
    }

    It "returns null instead of throwing when a real signature exists but the Java version can't be detected from it" {
        $zip = Join-Path $root "undetectable.zip"
        New-TestZip -ZipPath $zip -Files @{
            "run.bat" = "java -jar server.jar nogui"
        }
        $dest = Join-Path $root "undetectable-dest"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        Install-CurseForgeServerZip -ZipPath $zip -DestPath $dest | Should Be $null
        Test-Path (Join-Path $dest "run.bat") | Should Be $true
    }

    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
