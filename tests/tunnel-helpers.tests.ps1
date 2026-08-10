. (Join-Path (Split-Path -Parent $PSScriptRoot) "_shared\scripts\tunnel-helpers.ps1")

Describe "Select-MinecraftTunnel" {

    It "prefers the tunnel matching the requested local port" {
        $tunnels = @(
            [PSCustomObject]@{ tunnel_type = "minecraft-java"; local_port = 25566; assigned_domain = "wrong.playit.gg" },
            [PSCustomObject]@{ tunnel_type = "minecraft-java"; local_port = 25565; assigned_domain = "right.playit.gg" }
        )
        $result = Select-MinecraftTunnel -Tunnels $tunnels
        $result.assigned_domain | Should Be "right.playit.gg"
    }

    It "falls back to any minecraft-java tunnel when no port matches" {
        $tunnels = @(
            [PSCustomObject]@{ tunnel_type = "minecraft-java"; local_port = 25566; assigned_domain = "only.playit.gg" }
        )
        $result = Select-MinecraftTunnel -Tunnels $tunnels
        $result.assigned_domain | Should Be "only.playit.gg"
    }

    It "returns null when there is no minecraft-java tunnel" {
        $tunnels = @(
            [PSCustomObject]@{ tunnel_type = "other"; local_port = 25565; assigned_domain = "nope.playit.gg" }
        )
        $result = Select-MinecraftTunnel -Tunnels $tunnels
        $result | Should Be $null
    }
}

Describe "Select-LanIPv4Address" {

    It "picks the first non-loopback, non-link-local address" {
        $result = Select-LanIPv4Address -Candidates @("127.0.0.1", "169.254.10.5", "192.168.1.42")
        $result | Should Be "192.168.1.42"
    }

    It "returns empty when only loopback/link-local addresses are present" {
        $result = Select-LanIPv4Address -Candidates @("127.0.0.1", "169.254.3.1")
        $result | Should Be ""
    }

    It "returns empty when given no candidates" {
        Select-LanIPv4Address -Candidates @() | Should Be ""
    }
}

Describe "Resolve-DisplayAddress" {

    It "prefers the manual override over everything else" {
        Resolve-DisplayAddress -Manual "my.ddns.net:25565" -Playit "abc.playit.gg" -Lan "192.168.1.5:25565" | Should Be "my.ddns.net:25565"
    }

    It "prefers playit over LAN when there is no manual override" {
        Resolve-DisplayAddress -Manual "" -Playit "abc.playit.gg" -Lan "192.168.1.5:25565" | Should Be "abc.playit.gg"
    }

    It "falls back to LAN when neither manual nor playit is set" {
        Resolve-DisplayAddress -Manual "" -Playit "" -Lan "192.168.1.5:25565" | Should Be "192.168.1.5:25565"
    }

    It "returns empty when nothing is available" {
        Resolve-DisplayAddress -Manual "" -Playit "" -Lan "" | Should Be ""
    }
}

Describe "Get-LanAddress" {

    It "returns an ip:port string or empty, and never throws" {
        { $script:result = Get-LanAddress -Port 25565 } | Should Not Throw
        ($result -eq "" -or $result -match '^\d+\.\d+\.\d+\.\d+:25565$') | Should Be $true
    }
}
