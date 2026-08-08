# Non-interactive core of server creation, shared by the console wizard
# (Minecraft\scripts\new-server.ps1) and the Add Modpack GUI window. No
# Read-Host here on purpose - the console script prompts, then calls this;
# the GUI collects the same values from its form fields instead.
# Loaded via dot-source.

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

# Copies the generic _template into a new named instance and pre-seeds
# server.properties with RCON enabled + a random password, so "Stop Server"
# works cleanly from the very first start.
function New-ServerFromTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$McRoot
    )

    $template = Join-Path $McRoot "servers\_template"
    $dest = Join-Path $McRoot "servers\$Name"
    if (Test-Path $dest) {
        throw "A server named '$Name' already exists at $dest"
    }

    Copy-Item -Recurse -Path $template -Destination $dest

    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $rconPass = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', ''

    $propsPath = Join-Path $dest "server.properties"
    @(
        "#Minecraft server properties (pre-configured by new-server-helpers.ps1)"
        "enable-rcon=true"
        "rcon.port=25575"
        "rcon.password=$rconPass"
    ) | Set-Content -Path $propsPath -Encoding ascii

    return $dest
}
