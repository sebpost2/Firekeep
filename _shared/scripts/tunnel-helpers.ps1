# Shared logic for picking the right Minecraft tunnel among the ones returned
# by the playit.gg API (rundata). Loaded via dot-source from the scripts that
# query the tunnel (start-with-tunnel.ps1, show-address.ps1).

# Picks the "minecraft-java" tunnel that points to the requested local port.
# If none match on port (e.g. an old account without that field), falls back
# to the first minecraft-java tunnel it finds. Returns $null if there's none.
function Select-MinecraftTunnel {
    param(
        [Parameter(Mandatory = $true)] $Tunnels,
        [int]$LocalPort = 25565
    )
    $byPort = @($Tunnels | Where-Object { $_.tunnel_type -eq "minecraft-java" -and $_.local_port -eq $LocalPort })
    if ($byPort.Count -gt 0) { return $byPort[0] }
    return $Tunnels | Where-Object { $_.tunnel_type -eq "minecraft-java" } | Select-Object -First 1
}
