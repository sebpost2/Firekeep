# Pure PowerShell RCON client (no extra binaries or downloads).
# RCON is Minecraft's standard protocol for sending it commands over TCP.
# This file does NOT run on its own: other scripts load it via dot-source
# (. rcon.ps1) to reuse its functions.
#
# RCON packet format (all integers are little-endian int32):
#   [ length ][ id ][ type ][ ASCII body + \0 ][ padding \0 ]
#   'length' = number of bytes that follow (id + type + body + 2 zero bytes) = 10 + body length
#   type 3 = authentication, 2 = execute command, 0 = server response.

# Reads a server.properties file and returns a key -> value table.
function Read-ServerProperties {
    param([string]$Path)
    $props = @{}
    if (-not (Test-Path $Path)) { return $props }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#') { continue }        # comment
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1)
        $props[$key] = $val
    }
    return $props
}

# Quick check for whether something on this machine is listening on a TCP port.
# Reads the OS listener table instead of connecting: a connection to the RCON
# port gets logged by Minecraft ("RCON Client ... started/shutting down"), and
# the GUI polls this several times a second.
function Test-PortOpen {
    param(
        [Parameter(Mandatory = $true)][int]$Port
    )
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return [bool]($listeners | Where-Object { $_.Port -eq $Port })
}

# Returns the PID of the process listening on a port (or $null).
function Get-ListenerPid {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($conn) { return [int]$conn.OwningProcess }
    } catch { }
    return $null
}

# Connects via RCON, authenticates, and executes a command. Returns the response (text).
# Throws an exception if it can't connect or the password is wrong.
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
        throw "Could not connect to RCON at ${RconHost}:${Port}"
    }
    $client.EndConnect($iar)

    $stream = $client.GetStream()
    $stream.ReadTimeout = $TimeoutMs
    $stream.WriteTimeout = $TimeoutMs

    # --- local helpers ---
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

    # Reads exactly N bytes from the stream (or throws if cut short).
    $readExact = {
        param($count)
        $buf = New-Object byte[] $count
        $off = 0
        while ($off -lt $count) {
            $r = $stream.Read($buf, $off, $count - $off)
            if ($r -le 0) { throw "RCON connection closed by the server" }
            $off += $r
        }
        return $buf
    }

    # Reads a full packet and returns an object with id/type/body.
    $readPacket = {
        $lenBytes = & $readExact 4
        $len = [System.BitConverter]::ToInt32($lenBytes, 0)
        if ($len -lt 10 -or $len -gt 4110) { throw "RCON packet with invalid length ($len)" }
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
        # 1) Authentication (type 3). If it fails, the server responds with Id = -1.
        & $sendPacket 1 3 $Password
        $auth = & $readPacket
        # Some servers send an empty packet (type 0) before the auth response.
        if ($auth.Type -eq 0) { $auth = & $readPacket }
        if ($auth.Id -eq -1) {
            throw "RCON authentication rejected (wrong password)"
        }

        # 2) Execute the command (type 2) and read the response.
        & $sendPacket 2 2 $Command
        $resp = $null
        try {
            $resp = & $readPacket
        } catch {
            # 'stop' usually closes the connection before responding: not an error.
            $resp = [PSCustomObject]@{ Id = 2; Type = 0; Body = "" }
        }
        return $resp.Body
    } finally {
        $stream.Close()
        $client.Close()
    }
}
