# Non-interactive core of server creation, shared by the console wizard
# (Minecraft\scripts\new-server.ps1) and the Add Modpack GUI window. No
# Read-Host here on purpose - the console script prompts, then calls this;
# the GUI collects the same values from its form fields instead.
# Loaded via dot-source.

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
