# Logica compartida para elegir el tunel de Minecraft correcto entre los que
# devuelve la API de playit.gg (rundata). Se carga con dot-source desde los
# scripts que consultan el tunel (start-with-tunnel.ps1, show-address.ps1).

# Elige el tunel "minecraft-java" que apunta al puerto local pedido. Si ninguno
# coincide en puerto (ej. cuenta vieja sin ese campo), cae al primer tunel
# minecraft-java que encuentre. Devuelve $null si no hay ninguno.
function Select-MinecraftTunnel {
    param(
        [Parameter(Mandatory = $true)] $Tunnels,
        [int]$LocalPort = 25565
    )
    $porPuerto = @($Tunnels | Where-Object { $_.tunnel_type -eq "minecraft-java" -and $_.local_port -eq $LocalPort })
    if ($porPuerto.Count -gt 0) { return $porPuerto[0] }
    return $Tunnels | Where-Object { $_.tunnel_type -eq "minecraft-java" } | Select-Object -First 1
}
