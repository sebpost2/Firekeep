. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\mrpack-helpers.ps1")

Describe "Get-JavaVersionForMinecraft" {

    It "maps 1.16.5 (last pre-1.17) to Java 8" {
        Get-JavaVersionForMinecraft -McVersion "1.16.5" | Should Be 8
    }

    It "maps 1.8.9 to Java 8" {
        Get-JavaVersionForMinecraft -McVersion "1.8.9" | Should Be 8
    }

    It "maps 1.9 to Java 8 (numeric compare, not string compare)" {
        Get-JavaVersionForMinecraft -McVersion "1.9" | Should Be 8
    }

    It "maps 1.17 (first 17-era version) to Java 17" {
        Get-JavaVersionForMinecraft -McVersion "1.17" | Should Be 17
    }

    It "maps 1.20.4 (last pre-1.20.5) to Java 17" {
        Get-JavaVersionForMinecraft -McVersion "1.20.4" | Should Be 17
    }

    It "maps 1.20.5 (first 21-era version) to Java 21" {
        Get-JavaVersionForMinecraft -McVersion "1.20.5" | Should Be 21
    }

    It "maps 1.21 to Java 21" {
        Get-JavaVersionForMinecraft -McVersion "1.21" | Should Be 21
    }

    It "throws a clear error for an unparseable version string" {
        { Get-JavaVersionForMinecraft -McVersion "not-a-version" } | Should Throw
    }
}

Describe "Get-MinecraftVersionFromMrpack" {

    function New-TestMrpack([string]$Path, [string]$IndexJson) {
        if (Test-Path $Path) { Remove-Item -Force $Path }
        $workDir = Join-Path $env:TEMP ("mrpack-fixture-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null
        if ($null -ne $IndexJson) {
            Set-Content -Path (Join-Path $workDir "modrinth.index.json") -Value $IndexJson -Encoding utf8
        }
        else {
            # Compress-Archive needs at least one file; give it a harmless placeholder.
            Set-Content -Path (Join-Path $workDir "overrides.txt") -Value "x" -Encoding utf8
        }
        $zipPath = "$Path.zip"
        Compress-Archive -Path (Join-Path $workDir "*") -DestinationPath $zipPath -Force
        Move-Item -Path $zipPath -Destination $Path -Force
        Remove-Item -Recurse -Force $workDir
    }

    $validPack = Join-Path $env:TEMP ("valid-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpack -Path $validPack -IndexJson '{"dependencies":{"minecraft":"1.20.1","fabric-loader":"0.15.0"}}'

    $noIndexPack = Join-Path $env:TEMP ("noindex-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpack -Path $noIndexPack -IndexJson $null

    $badJsonPack = Join-Path $env:TEMP ("badjson-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpack -Path $badJsonPack -IndexJson '{not valid json'

    It "reads the minecraft version from modrinth.index.json inside the .mrpack zip" {
        Get-MinecraftVersionFromMrpack -MrpackPath $validPack | Should Be "1.20.1"
    }

    It "throws when the .mrpack has no modrinth.index.json" {
        { Get-MinecraftVersionFromMrpack -MrpackPath $noIndexPack } | Should Throw
    }

    It "throws when modrinth.index.json is not valid JSON" {
        { Get-MinecraftVersionFromMrpack -MrpackPath $badJsonPack } | Should Throw
    }

    It "throws when the file does not exist" {
        { Get-MinecraftVersionFromMrpack -MrpackPath (Join-Path $env:TEMP "does-not-exist.mrpack") } | Should Throw
    }

    Remove-Item -Force $validPack, $noIndexPack, $badJsonPack -ErrorAction SilentlyContinue
}

Describe "Get-ModpackLoader" {

    function New-TestMrpackWithDeps([string]$Path, [string]$DepsJson) {
        if (Test-Path $Path) { Remove-Item -Force $Path }
        $workDir = Join-Path $env:TEMP ("mrpack-loader-fixture-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null
        Set-Content -Path (Join-Path $workDir "modrinth.index.json") -Value "{`"dependencies`":$DepsJson}" -Encoding utf8
        $zipPath = "$Path.zip"
        Compress-Archive -Path (Join-Path $workDir "*") -DestinationPath $zipPath -Force
        Move-Item -Path $zipPath -Destination $Path -Force
        Remove-Item -Recurse -Force $workDir
    }

    $fabricPack = Join-Path $env:TEMP ("fabric-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpackWithDeps -Path $fabricPack -DepsJson '{"minecraft":"1.20.1","fabric-loader":"0.15.0"}'

    $forgePack = Join-Path $env:TEMP ("forge-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpackWithDeps -Path $forgePack -DepsJson '{"minecraft":"1.19.2","forge":"43.5.1"}'

    $quiltPack = Join-Path $env:TEMP ("quilt-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpackWithDeps -Path $quiltPack -DepsJson '{"minecraft":"1.20.1","quilt-loader":"0.20.0"}'

    $neoforgePack = Join-Path $env:TEMP ("neoforge-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
    New-TestMrpackWithDeps -Path $neoforgePack -DepsJson '{"minecraft":"1.20.4","neoforge":"20.4.100"}'

    It "detects fabric" {
        Get-ModpackLoader -MrpackPath $fabricPack | Should Be "fabric"
    }

    It "detects forge" {
        Get-ModpackLoader -MrpackPath $forgePack | Should Be "forge"
    }

    It "detects quilt" {
        Get-ModpackLoader -MrpackPath $quiltPack | Should Be "quilt"
    }

    It "detects neoforge" {
        Get-ModpackLoader -MrpackPath $neoforgePack | Should Be "neoforge"
    }

    Remove-Item -Force $fabricPack, $forgePack, $quiltPack, $neoforgePack -ErrorAction SilentlyContinue
}

Describe "Set-RunConfigJavaAndRam" {

    $configPath = Join-Path $env:TEMP ("run.config-" + [Guid]::NewGuid().ToString("N") + ".ps1")

    BeforeEach {
        $text = @(
            '# Configuracion de esta instancia de server.'
            '$JavaVersion = 21'
            ''
            '$MinRam = "2G"'
            '$MaxRam = "6G"'
            ''
            '# Comentario con acentos: si el modpack no trae start.bat, poné esto en false.'
            '$UseModpackLauncher = $true'
        ) -join "`r`n"
        # Escribe UTF-8 SIN BOM a proposito: asi esta el run.config.ps1 real de
        # _template, y Get-Content sin -Encoding lo interpreta mal (ANSI) si no
        # se especifica explicitamente.
        [System.IO.File]::WriteAllText($configPath, $text, (New-Object System.Text.UTF8Encoding($false)))
    }

    It "updates JavaVersion and MaxRam while leaving other lines untouched" {
        Set-RunConfigJavaAndRam -Path $configPath -JavaVersion 17 -MaxRam "8G"
        $content = Get-Content -Path $configPath -Raw
        $content | Should Match '\$JavaVersion = 17'
        $content | Should Match '\$MaxRam = "8G"'
        $content | Should Match '\$UseModpackLauncher = \$true'
    }

    It "leaves MinRam untouched" {
        Set-RunConfigJavaAndRam -Path $configPath -JavaVersion 17 -MaxRam "8G"
        Get-Content -Path $configPath -Raw | Should Match '\$MinRam = "2G"'
    }

    It "does not mangle accented characters in untouched comments" {
        Set-RunConfigJavaAndRam -Path $configPath -JavaVersion 17 -MaxRam "8G"
        $content = Get-Content -Path $configPath -Raw -Encoding UTF8
        $content | Should Match 'poné esto en false'
    }
}

# Modpack files are often named like "Pack [1.20.1].mrpack"; square
# brackets are wildcards to Test-Path/Resolve-Path.
Describe "mrpack helpers with brackets in the file name" {
    It "reads a .mrpack whose name has square brackets" {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $work = Join-Path $env:TEMP ("mrpack-bracket-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $plain = Join-Path $work "plain.mrpack"
        $zip = [System.IO.Compression.ZipFile]::Open($plain, 'Create')
        $w = New-Object System.IO.StreamWriter($zip.CreateEntry("modrinth.index.json").Open())
        $w.Write('{"dependencies":{"minecraft":"1.20.1","forge":"47.2.0"}}')
        $w.Dispose(); $zip.Dispose()
        $pack = Join-Path $work "Pack [1.20.1].mrpack"
        [System.IO.File]::Move($plain, $pack)
        try {
            Get-MinecraftVersionFromMrpack -MrpackPath $pack | Should Be "1.20.1"
            Get-ModpackLoader -MrpackPath $pack | Should Be "forge"
        } finally { Remove-Item -LiteralPath $work -Recurse -Force }
    }
}
