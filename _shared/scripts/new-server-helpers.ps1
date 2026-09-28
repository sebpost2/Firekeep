# Non-interactive core of server creation, shared by the console wizard
# (Minecraft\scripts\new-server.ps1) and the Add Modpack GUI window. No
# Read-Host here on purpose - the console script prompts, then calls this;
# the GUI collects the same values from its form fields instead.
# Loaded via dot-source.

. (Join-Path $PSScriptRoot "worlds-helpers.ps1")   # Get/Set-ServerProperty

# Server names become a Windows folder name directly (servers\<Name>\), so
# spaces and path-unsafe characters are rejected here rather than letting a
# broken server get created - ServerPackCreator's vendored start.ps1 blocks
# on a "path contains spaces" prompt that silently strands the server if
# nobody's watching the console when it boots.
function Test-ServerNameValid {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -match '[\\/:*?"<>|\s]') { return $false }
    return $true
}

# Makes sure server.properties has RCON on, a port, and a random password.
# The GUI decides "running" by the RCON port and stops servers over RCON, so
# a server without it looks stopped forever and can't be stopped cleanly.
# Called at creation, after a modpack's files are copied in (they can ship
# their own server.properties), and by start.ps1 before every launch - which
# also covers servers built by hand. Existing port/password are never changed.
function Set-RconDefaults {
    param(
        [Parameter(Mandatory = $true)][string]$PropsPath
    )
    if (-not (Test-Path $PropsPath)) { New-Item -ItemType File -Path $PropsPath | Out-Null }

    if ((Get-ServerProperty $PropsPath "enable-rcon") -ne "true") {
        Set-ServerProperty $PropsPath "enable-rcon" "true"
    }
    if (-not (Get-ServerProperty $PropsPath "rcon.port")) {
        Set-ServerProperty $PropsPath "rcon.port" "25575"
    }
    if (-not (Get-ServerProperty $PropsPath "rcon.password")) {
        $bytes = New-Object byte[] 24
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        Set-ServerProperty $PropsPath "rcon.password" (([Convert]::ToBase64String($bytes)) -replace '[+/=]', '')
    }
}

# Copies the generic _template into a new named instance and pre-seeds
# server.properties with RCON (Set-RconDefaults), so "Stop Server" works
# cleanly from the very first start.
function New-ServerFromTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$McRoot
    )

    $template = Join-Path $McRoot "servers\_template"
    $dest = Join-Path $McRoot "servers\$Name"
    if (Test-Path $dest) {
        throw "A server named '$Name' already exists at $dest (maybe from an import that didn't finish) - delete that folder or pick another name."
    }

    Copy-Item -Recurse -Path $template -Destination $dest
    Set-RconDefaults -PropsPath (Join-Path $dest "server.properties")
    return $dest
}
