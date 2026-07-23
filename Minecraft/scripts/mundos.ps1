# Gestor de mundos (mapas) para los servers de Minecraft.
# CRUD seguro: ver / crear / cambiar / importar / eliminar mundos.
#
# Reglas de seguridad (por diseno, no se pueden saltear desde el menu):
#   - "Eliminar" NUNCA borra de verdad: manda el mundo a la carpeta _papelera
#     dentro del mismo server. Siempre se puede recuperar.
#   - No se puede eliminar el mundo ACTIVO (primero hay que cambiar a otro).
#   - Si detecta que el server esta PRENDIDO, no deja tocar el mundo en uso.
#   - Antes de cambiar server.properties siempre hace un backup (.bak).
#   - Los mundos se detectan por su archivo 'level.dat', asi que NUNCA confunde
#     una carpeta de mods/config con un mundo.
#
# Nota: pensado para modpacks de Forge (un solo mundo con DIM-1/DIM1 adentro).

$ErrorActionPreference = "Stop"
$mcRoot = Split-Path -Parent $PSScriptRoot
$serversRoot = Join-Path $mcRoot "servers"

# Carpetas que NUNCA son un mundo (aunque por error tuvieran un level.dat).
$TrashDir = "_papelera"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Pausa {
    Write-Host ""
    Read-Host "Apreta Enter para volver al menu" | Out-Null
}

function Test-FileLocked($path) {
    # True si el archivo esta abierto en exclusiva por otro proceso (server vivo).
    if (-not (Test-Path $path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
        $fs.Close(); $fs.Dispose()
        return $false
    } catch {
        return $true
    }
}

function Get-ServerProperty($propsPath, $key) {
    foreach ($l in (Get-Content -Path $propsPath -Encoding ascii)) {
        if ($l -match "^\s*$([regex]::Escape($key))\s*=(.*)$") { return $matches[1].Trim() }
    }
    return $null
}

function Set-ServerProperty($propsPath, $key, $value) {
    # Cambia (o agrega) una clave sin tocar el resto del archivo. Hace backup 1 vez.
    Copy-Item -Path $propsPath -Destination "$propsPath.bak" -Force
    $lines = @(Get-Content -Path $propsPath -Encoding ascii)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($key))\s*=") {
            $lines[$i] = "$key=$value"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "$key=$value" }
    Set-Content -Path $propsPath -Value $lines -Encoding ascii
}

function Get-FolderSizeMB($path) {
    try {
        $bytes = (Get-ChildItem -Path $path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return 0 }
        return [math]::Round($bytes / 1MB, 1)
    } catch { return 0 }
}

function Test-ValidName($name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    if ($name -eq "." -or $name -eq "..") { return $false }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { if ($name.Contains($c)) { return $false } }
    if ($name -eq $TrashDir) { return $false }
    return $true
}

# Devuelve la lista de mundos de una instancia (carpetas con level.dat + el activo).
function Get-Worlds($instancePath, $activeName) {
    $result = @()
    $seen = @{}
    Get-ChildItem -Path $instancePath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $TrashDir } |
        ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "level.dat")) {
                $result += [PSCustomObject]@{
                    Name     = $_.Name
                    Path     = $_.FullName
                    IsActive = ($_.Name -eq $activeName)
                    Exists   = $true
                }
                $seen[$_.Name] = $true
            }
        }
    # El mundo activo puede no estar generado todavia (aun no tiene level.dat).
    if ($activeName -and -not $seen.ContainsKey($activeName)) {
        $p = Join-Path $instancePath $activeName
        $result += [PSCustomObject]@{
            Name     = $activeName
            Path     = $p
            IsActive = $true
            Exists   = (Test-Path $p)
        }
    }
    return @($result | Sort-Object -Property @{Expression = "IsActive"; Descending = $true}, "Name")
}

function Show-WorldsTable($worlds, $activeName) {
    Write-Host ""
    Write-Host ("  {0}  {1,-28} {2,10}   {3}" -f " ", "MUNDO", "TAMANO", "ESTADO")
    Write-Host "  ---------------------------------------------------------------------"
    for ($i = 0; $i -lt $worlds.Count; $i++) {
        $w = $worlds[$i]
        $size = if ($w.Exists) { "{0} MB" -f (Get-FolderSizeMB $w.Path) } else { "-" }
        $estado = if ($w.IsActive) { "<== ACTIVO" } elseif (-not $w.Exists) { "(se genera al arrancar)" } else { "" }
        $color = if ($w.IsActive) { "Green" } else { "Gray" }
        Write-Host ("  [{0}] {1,-28} {2,10}   {3}" -f $i, $w.Name, $size, $estado) -ForegroundColor $color
    }
    Write-Host "  ---------------------------------------------------------------------"
}

# ---------------------------------------------------------------------------
# Seleccion de server (instancia)
# ---------------------------------------------------------------------------

function Select-Instance {
    $instances = @(
        Get-ChildItem -Path $serversRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "_template" -and (Test-Path (Join-Path $_.FullName "server.properties")) }
    )
    if ($instances.Count -eq 0) {
        Write-Host "No hay ningun server de Minecraft creado todavia." -ForegroundColor Yellow
        exit 0
    }
    if ($instances.Count -eq 1) { return $instances[0] }

    Write-Host ""
    Write-Host "Que server queres administrar?"
    for ($i = 0; $i -lt $instances.Count; $i++) {
        Write-Host "  [$i] $($instances[$i].Name)"
    }
    while ($true) {
        $c = Read-Host "Numero"
        if ($c -match '^\d+$' -and [int]$c -lt $instances.Count) { return $instances[[int]$c] }
        Write-Host "Opcion invalida." -ForegroundColor Yellow
    }
}

# Pide elegir un mundo de una lista ya mostrada. Devuelve el objeto o $null.
function Pick-World($worlds, $prompt, [switch]$ExcludeActive) {
    $c = Read-Host $prompt
    if ($c -notmatch '^\d+$' -or [int]$c -ge $worlds.Count) {
        Write-Host "Opcion invalida." -ForegroundColor Yellow
        return $null
    }
    $w = $worlds[[int]$c]
    if ($ExcludeActive -and $w.IsActive) {
        Write-Host "Ese es el mundo ACTIVO. Primero cambia a otro mundo." -ForegroundColor Yellow
        return $null
    }
    return $w
}

# ---------------------------------------------------------------------------
# Acciones del CRUD
# ---------------------------------------------------------------------------

function Action-Ver($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = Get-Worlds $instance.FullName $active
    Show-WorldsTable $worlds $active
    Write-Host ""
    Write-Host "  Mundo activo: $active" -ForegroundColor Cyan
    Pausa
}

function Action-Cambiar($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = @(Get-Worlds $instance.FullName $active | Where-Object { $_.Exists })
    if ($worlds.Count -lt 2) {
        Write-Host ""
        Write-Host "Solo hay un mundo. Crea o importa otro antes de poder cambiar." -ForegroundColor Yellow
        Pausa; return
    }
    Show-WorldsTable $worlds $active
    Write-Host ""
    $w = Pick-World $worlds "Numero del mundo que queres ACTIVAR"
    if (-not $w) { Pausa; return }
    if ($w.IsActive) { Write-Host "Ese ya es el activo." -ForegroundColor Yellow; Pausa; return }

    Set-ServerProperty $propsPath "level-name" $w.Name
    Write-Host ""
    Write-Host "Listo. Ahora el server usa el mundo: $($w.Name)" -ForegroundColor Green
    Write-Host "(El mundo anterior '$active' quedo intacto; podes volver a el cuando quieras.)"
    Write-Host "El cambio aplica la proxima vez que arranques el server."
    Pausa
}

function Action-Crear($instance, $propsPath) {
    Write-Host ""
    Write-Host "Crea un mundo NUEVO y vacio. Minecraft lo genera al arrancar el server."
    $name = Read-Host "Nombre para el mundo nuevo (ej: mundo-2)"
    if (-not (Test-ValidName $name)) { Write-Host "Nombre invalido." -ForegroundColor Yellow; Pausa; return }
    $dest = Join-Path $instance.FullName $name
    if (Test-Path $dest) { Write-Host "Ya existe una carpeta '$name'." -ForegroundColor Yellow; Pausa; return }

    New-Item -ItemType Directory -Path $dest | Out-Null

    $seed = Read-Host "Seed (opcional, Enter para aleatoria)"
    Write-Host ""
    $activar = Read-Host "Activar este mundo ahora? (s/N)"
    if ($activar -match '^(s|si|y)$') {
        if ($seed) { Set-ServerProperty $propsPath "level-seed" $seed }
        Set-ServerProperty $propsPath "level-name" $name
        Write-Host ""
        Write-Host "Mundo '$name' creado y ACTIVADO." -ForegroundColor Green
        Write-Host "Se genera solo la proxima vez que arranques el server."
        if ($seed) { Write-Host "Usara la seed: $seed" }
    } else {
        Write-Host ""
        Write-Host "Mundo '$name' creado (todavia NO activo)." -ForegroundColor Green
        Write-Host "Cuando quieras usarlo, entra a 'Cambiar mundo activo'."
        if ($seed) { Write-Host "Nota: la seed se aplica al activarlo y arrancar el server." }
    }
    Pausa
}

function Action-Importar($instance, $propsPath) {
    Write-Host ""
    Write-Host "Importa un mapa descargado (.zip). Podes arrastrar el .zip a esta ventana."
    $zip = (Read-Host "Ruta del .zip").Trim().Trim('"')
    if (-not (Test-Path $zip)) { Write-Host "No encontre ese archivo." -ForegroundColor Yellow; Pausa; return }
    if ([System.IO.Path]::GetExtension($zip) -ne ".zip") { Write-Host "Tiene que ser un .zip." -ForegroundColor Yellow; Pausa; return }

    $name = Read-Host "Nombre para este mundo dentro del server"
    if (-not (Test-ValidName $name)) { Write-Host "Nombre invalido." -ForegroundColor Yellow; Pausa; return }
    $dest = Join-Path $instance.FullName $name
    if (Test-Path $dest) { Write-Host "Ya existe una carpeta '$name'." -ForegroundColor Yellow; Pausa; return }

    $tmp = Join-Path $env:TEMP ("mc-import-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Descomprimiendo..."
        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        # Buscar la carpeta que contiene el level.dat (la raiz real del mundo).
        $leveldat = Get-ChildItem -Path $tmp -Recurse -File -Filter "level.dat" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $leveldat) {
            Write-Host "Ese .zip no parece un mundo de Minecraft (no tiene level.dat)." -ForegroundColor Yellow
            Pausa; return
        }
        $worldRoot = Split-Path -Parent $leveldat.FullName
        Write-Host "Copiando el mundo a '$name'..."
        Copy-Item -Path $worldRoot -Destination $dest -Recurse -Force
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    $activar = Read-Host "Activar este mundo ahora? (s/N)"
    if ($activar -match '^(s|si|y)$') {
        Set-ServerProperty $propsPath "level-name" $name
        Write-Host "Mundo '$name' importado y ACTIVADO." -ForegroundColor Green
        Write-Host "El cambio aplica la proxima vez que arranques el server."
    } else {
        Write-Host "Mundo '$name' importado (NO activo). Activalo desde 'Cambiar mundo activo'." -ForegroundColor Green
    }
    Pausa
}

function Action-Eliminar($instance, $propsPath) {
    $active = Get-ServerProperty $propsPath "level-name"
    $worlds = @(Get-Worlds $instance.FullName $active | Where-Object { $_.Exists })
    $borrables = @($worlds | Where-Object { -not $_.IsActive })
    if ($borrables.Count -eq 0) {
        Write-Host ""
        Write-Host "No hay mundos para eliminar (el unico que hay es el ACTIVO," -ForegroundColor Yellow
        Write-Host "y el activo esta protegido). Cambia de mundo primero si queres borrarlo."
        Pausa; return
    }

    Write-Host ""
    Write-Host "  Mundos que se pueden mandar a la papelera (el ACTIVO no aparece):" -ForegroundColor Cyan
    Show-WorldsTable $worlds $active
    Write-Host ""
    Write-Host "  (No podes elegir el mundo ACTIVO.)" -ForegroundColor DarkGray
    $w = Pick-World $worlds "Numero del mundo a mandar a la papelera" -ExcludeActive
    if (-not $w) { Pausa; return }

    # Seguridad extra: si esa carpeta esta en uso (server prendido), abortar.
    if (Test-FileLocked (Join-Path $w.Path "session.lock")) {
        Write-Host "Ese mundo esta EN USO (server prendido). No lo toco." -ForegroundColor Red
        Pausa; return
    }

    Write-Host ""
    Write-Host "Vas a mandar '$($w.Name)' a la papelera (se puede recuperar despues)." -ForegroundColor Yellow
    $confirm = Read-Host "Para confirmar, escribi el nombre EXACTO del mundo"
    if ($confirm -ne $w.Name) { Write-Host "No coincide. Cancelado." -ForegroundColor Yellow; Pausa; return }

    $trash = Join-Path $instance.FullName $TrashDir
    if (-not (Test-Path $trash)) { New-Item -ItemType Directory -Path $trash | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $target = Join-Path $trash ("{0}__{1}" -f $w.Name, $stamp)
    Move-Item -Path $w.Path -Destination $target
    Write-Host ""
    Write-Host "Listo. '$($w.Name)' fue a la papelera." -ForegroundColor Green
    Write-Host "Si te arrepentis, esta en: $target"
    Pausa
}

function Action-Papelera($instance, $propsPath) {
    $trash = Join-Path $instance.FullName $TrashDir
    $items = @()
    if (Test-Path $trash) { $items = @(Get-ChildItem -Path $trash -Directory) }
    if ($items.Count -eq 0) {
        Write-Host ""
        Write-Host "La papelera esta vacia." -ForegroundColor Cyan
        Pausa; return
    }

    Write-Host ""
    Write-Host "  PAPELERA:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("  [{0}] {1}   ({2} MB)" -f $i, $items[$i].Name, (Get-FolderSizeMB $items[$i].FullName))
    }
    Write-Host ""
    Write-Host "  [r] Restaurar un mundo    [x] Vaciar la papelera (definitivo)    [Enter] Volver"
    $op = Read-Host "Que haces"

    if ($op -eq 'r') {
        $c = Read-Host "Numero a restaurar"
        if ($c -notmatch '^\d+$' -or [int]$c -ge $items.Count) { Write-Host "Invalido." -ForegroundColor Yellow; Pausa; return }
        $it = $items[[int]$c]
        # El nombre original es lo que esta antes del "__timestamp".
        $orig = ($it.Name -replace '__\d{8}-\d{6}$', '')
        $newName = Read-Host "Nombre para restaurarlo (Enter = '$orig')"
        if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $orig }
        if (-not (Test-ValidName $newName)) { Write-Host "Nombre invalido." -ForegroundColor Yellow; Pausa; return }
        $dest = Join-Path $instance.FullName $newName
        if (Test-Path $dest) { Write-Host "Ya existe '$newName'. Elegi otro nombre." -ForegroundColor Yellow; Pausa; return }
        Move-Item -Path $it.FullName -Destination $dest
        Write-Host "Restaurado como '$newName'." -ForegroundColor Green
        Write-Host "Para usarlo, activalo desde 'Cambiar mundo activo'."
        Pausa; return
    }

    if ($op -eq 'x') {
        Write-Host ""
        Write-Host "Esto BORRA para siempre todo lo que hay en la papelera. NO se recupera." -ForegroundColor Red
        $confirm = Read-Host "Para confirmar, escribi:  BORRAR TODO"
        if ($confirm -ne "BORRAR TODO") { Write-Host "Cancelado." -ForegroundColor Yellow; Pausa; return }
        Remove-Item -Path $trash -Recurse -Force
        Write-Host "Papelera vaciada." -ForegroundColor Green
        Pausa; return
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$instance = Select-Instance
$propsPath = Join-Path $instance.FullName "server.properties"

while ($true) {
    Clear-Host
    $active = Get-ServerProperty $propsPath "level-name"
    $activeLock = Join-Path (Join-Path $instance.FullName $active) "session.lock"
    $running = Test-FileLocked $activeLock

    Write-Host ""
    Write-Host "==================== GESTOR DE MUNDOS ====================" -ForegroundColor Cyan
    Write-Host "  Server: $($instance.Name)"
    Write-Host "  Mundo activo: $active"
    if ($running) {
        Write-Host "  !! El server parece estar PRENDIDO. Apagalo antes de tocar mundos." -ForegroundColor Yellow
    }
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Ver mundos"
    Write-Host "  [2] Cambiar mundo activo"
    Write-Host "  [3] Crear mundo nuevo"
    Write-Host "  [4] Importar mundo desde .zip"
    Write-Host "  [5] Eliminar mundo  (va a la papelera, recuperable)"
    Write-Host "  [6] Papelera  (restaurar / vaciar)"
    Write-Host "  [0] Salir"
    Write-Host ""
    $opt = Read-Host "Opcion"

    switch ($opt) {
        "1" { Action-Ver $instance $propsPath }
        "2" { Action-Cambiar $instance $propsPath }
        "3" { Action-Crear $instance $propsPath }
        "4" { Action-Importar $instance $propsPath }
        "5" { Action-Eliminar $instance $propsPath }
        "6" { Action-Papelera $instance $propsPath }
        "0" { break }
        default { }
    }
}
