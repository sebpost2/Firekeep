. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\rcon.ps1")

Describe "Test-PortOpen" {

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port

    It "returns true when something is listening on the port" {
        Test-PortOpen -Port $port | Should Be $true
    }

    # Connecting made every check show up in the Minecraft console as an
    # RCON client starting and shutting down, several times a second.
    It "does not open a connection to the port" {
        Test-PortOpen -Port $port | Out-Null
        $listener.Pending() | Should Be $false
    }

    $listener.Stop()

    It "returns false once nothing is listening" {
        Test-PortOpen -Port $port | Should Be $false
    }
}

Describe "Invoke-RconCommand" {

    # Minimal fake RCON server in a background runspace: accepts the auth
    # packet, then either answers the command with $Reply (UTF-8) or, when
    # $Reply is $null, never answers - like a server stuck mid-tick.
    function Start-FakeRcon {
        param($Reply)  # untyped: [string] would turn $null into "" (a reply)
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $ready = New-Object System.Threading.ManualResetEvent($false)
        $ps = [powershell]::Create()
        $ps.AddScript({
            param($listener, $reply, $ready)
            $ready.Set() | Out-Null
            $client = $listener.AcceptTcpClient()
            $s = $client.GetStream()
            $r = New-Object System.IO.BinaryReader($s)
            $w = New-Object System.IO.BinaryWriter($s)
            # Auth packet: reply with the same id (success) and an empty body.
            $n = $r.ReadInt32(); $authId = $r.ReadInt32(); $r.ReadBytes($n - 4) | Out-Null
            $w.Write([int]10); $w.Write([int]$authId); $w.Write([int]2); $w.Write([byte[]](0, 0)); $w.Flush()
            # Command packet: reply with $reply, or stay silent.
            $n = $r.ReadInt32(); $cmdId = $r.ReadInt32(); $r.ReadBytes($n - 4) | Out-Null
            if ($null -ne $reply) {
                $body = [System.Text.Encoding]::UTF8.GetBytes($reply)
                $w.Write([int](10 + $body.Length)); $w.Write([int]$cmdId); $w.Write([int]0); $w.Write($body); $w.Write([byte[]](0, 0)); $w.Flush()
            }
            Start-Sleep -Seconds 3
            $client.Close()
        }).AddArgument($listener).AddArgument($Reply).AddArgument($ready) | Out-Null
        $handle = $ps.BeginInvoke()
        # A fresh runspace takes a moment to start; don't let the client's
        # timeout run out before the fake server is even accepting.
        $ready.WaitOne(10000) | Out-Null
        return [PSCustomObject]@{ Port = $listener.LocalEndpoint.Port; Listener = $listener; PS = $ps; Handle = $handle }
    }

    function Stop-FakeRcon($fake) {
        $fake.Listener.Stop()
        $fake.PS.Stop()
        $fake.PS.Dispose()
    }

    It "returns the reply decoded as UTF-8" {
        $text = "Jos" + [char]0x00E9 + " joined"
        $fake = Start-FakeRcon -Reply $text
        $result = Invoke-RconCommand -Port $fake.Port -Password "x" -Command "list" -TimeoutMs 2000
        Stop-FakeRcon $fake
        $result | Should Be $text
    }

    # The old catch-all turned a slow reply into an empty string, so the
    # console showed nothing at all for a command that was still running.
    It "throws when a normal command gets no reply in time" {
        $fake = Start-FakeRcon -Reply $null
        { Invoke-RconCommand -Port $fake.Port -Password "x" -Command "chunky start" -TimeoutMs 500 } | Should Throw
        Stop-FakeRcon $fake
    }

    It "treats no reply to 'stop' as success" {
        $fake = Start-FakeRcon -Reply $null
        $result = Invoke-RconCommand -Port $fake.Port -Password "x" -Command "stop" -TimeoutMs 500
        Stop-FakeRcon $fake
        $result | Should Be ""
    }
}
