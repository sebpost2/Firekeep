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

# Picks the first usable LAN IPv4 address from a list of candidate address
# strings - excludes loopback and link-local (169.254.x.x, assigned when no
# DHCP/adapter is actually up) addresses. Pure/testable: the live adapter
# query lives in Get-LanAddress: this just filters an already-fetched list.
function Select-LanIPv4Address {
    param([string[]]$Candidates = @())
    $valid = @($Candidates | Where-Object { $_ -and $_ -ne "127.0.0.1" -and -not $_.StartsWith("169.254.") })
    if ($valid.Count -gt 0) { return $valid[0] }
    return ""
}

# Priority chain for what to show/copy as the shareable address: a saved
# manual override wins outright, then playit.gg, then this machine's LAN
# IP. Pure function so it's testable without touching the filesystem or
# network - Update-AddressDisplay in Start-Gui.ps1 is the only caller.
function Resolve-DisplayAddress {
    param(
        [string]$Manual = "",
        [string]$Playit = "",
        [string]$Lan = ""
    )
    if ($Manual) { return $Manual }
    if ($Playit) { return $Playit }
    if ($Lan) { return $Lan }
    return ""
}

# Best-effort local network address for same-WiFi sharing when playit.gg
# isn't active. Never throws - matches Get-AppVersion's established pattern
# for display helpers that must not block the GUI.
function Get-LanAddress {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $candidates = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
    } catch {
        return ""
    }
    $ip = Select-LanIPv4Address -Candidates $candidates
    if (-not $ip) { return "" }
    return "${ip}:$Port"
}
