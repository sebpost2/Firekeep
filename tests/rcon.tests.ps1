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
