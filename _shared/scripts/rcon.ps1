# Cliente RCON en PowerShell puro (sin binarios ni descargas extra).
# RCON es el protocolo estandar de Minecraft para mandarle comandos por TCP.
# Este archivo NO se corre solo: otros scripts lo cargan con "dot-source"
# (. rcon.ps1) para reusar sus funciones.
#
# Formato de un paquete RCON (todos los enteros son int32 little-endian):
#   [ largo ][ id ][ tipo ][ cuerpo en ASCII + \0 ][ \0 de relleno ]
#   'largo' = cantidad de bytes que siguen (id + tipo + cuerpo + 2 ceros) = 10 + largo_cuerpo
#   tipo 3 = autenticacion, 2 = ejecutar comando, 0 = respuesta del server.

# Lee un archivo server.properties y devuelve una tabla clave -> valor.
function Read-ServerProperties {
    param([string]$Path)
    $props = @{}
    if (-not (Test-Path $Path)) { return $props }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#') { continue }        # comentario
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1)
        $props[$key] = $val
    }
    return $props
}

# Prueba rapida de si hay algo escuchando en un puerto TCP (sin bloquear mucho).
function Test-PortOpen {
    param(
        [string]$RconHost = "127.0.0.1",
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 800
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($RconHost, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# Devuelve el PID del proceso que esta escuchando en un puerto (o $null).
function Get-ListenerPid {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($conn) { return [int]$conn.OwningProcess }
    } catch { }
    return $null
}

# Se conecta por RCON, autentica y ejecuta un comando. Devuelve la respuesta (texto).
# Tira una excepcion si no puede conectar o si la contraseña es incorrecta.
function Invoke-RconCommand {
    param(
        [string]$RconHost = "127.0.0.1",
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutMs = 5000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($RconHost, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
        $client.Close()
        throw "No se pudo conectar a RCON en ${RconHost}:${Port}"
    }
    $client.EndConnect($iar)

    $stream = $client.GetStream()
    $stream.ReadTimeout = $TimeoutMs
    $stream.WriteTimeout = $TimeoutMs

    # --- helpers locales ---
    $sendPacket = {
        param($id, $type, $body)
        $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($body)
        $len = 10 + $bodyBytes.Length
        $ms = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter($ms)
        $bw.Write([int]$len)
        $bw.Write([int]$id)
        $bw.Write([int]$type)
        $bw.Write($bodyBytes)
        $bw.Write([byte]0)
        $bw.Write([byte]0)
        $bw.Flush()
        $data = $ms.ToArray()
        $stream.Write($data, 0, $data.Length)
        $stream.Flush()
        $bw.Dispose()
    }

    # Lee exactamente N bytes del stream (o tira excepcion si se corta).
    $readExact = {
        param($count)
        $buf = New-Object byte[] $count
        $off = 0
        while ($off -lt $count) {
            $r = $stream.Read($buf, $off, $count - $off)
            if ($r -le 0) { throw "Conexion RCON cerrada por el server" }
            $off += $r
        }
        return $buf
    }

    # Lee un paquete completo y devuelve un objeto con id/tipo/cuerpo.
    $readPacket = {
        $lenBytes = & $readExact 4
        $len = [System.BitConverter]::ToInt32($lenBytes, 0)
        if ($len -lt 10 -or $len -gt 4110) { throw "Paquete RCON con largo invalido ($len)" }
        $payload = & $readExact $len
        $id = [System.BitConverter]::ToInt32($payload, 0)
        $type = [System.BitConverter]::ToInt32($payload, 4)
        $bodyLen = $len - 10
        $body = ""
        if ($bodyLen -gt 0) {
            $body = [System.Text.Encoding]::ASCII.GetString($payload, 8, $bodyLen)
        }
        return [PSCustomObject]@{ Id = $id; Type = $type; Body = $body }
    }

    try {
        # 1) Autenticacion (tipo 3). Si falla, el server responde con Id = -1.
        & $sendPacket 1 3 $Password
        $auth = & $readPacket
        # Algunos servers mandan un paquete vacio (tipo 0) antes de la respuesta de auth.
        if ($auth.Type -eq 0) { $auth = & $readPacket }
        if ($auth.Id -eq -1) {
            throw "Autenticacion RCON rechazada (contraseña incorrecta)"
        }

        # 2) Ejecutar el comando (tipo 2) y leer la respuesta.
        & $sendPacket 2 2 $Command
        $resp = $null
        try {
            $resp = & $readPacket
        } catch {
            # 'stop' suele cerrar la conexion antes de responder: no es un error.
            $resp = [PSCustomObject]@{ Id = 2; Type = 0; Body = "" }
        }
        return $resp.Body
    } finally {
        $stream.Close()
        $client.Close()
    }
}
