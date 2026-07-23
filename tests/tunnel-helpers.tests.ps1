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
