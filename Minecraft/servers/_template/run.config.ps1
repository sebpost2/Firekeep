# Configuration for this server instance. Edit according to the modpack.

# Java major version the modpack requires (check the modpack's page on
# CurseForge, or the settings.cfg / minecraftinstance.json file it includes).
# Quick guide:
#   Minecraft 1.16 and earlier  -> 8
#   Minecraft 1.17 - 1.20.4     -> 17
#   Minecraft 1.20.5+           -> 21
$JavaVersion = 21

# Minimum / maximum memory for the JVM. Large modpacks usually want 6-8G max.
$MinRam = "2G"
$MaxRam = "6G"

# Most CurseForge "Server Files" (Forge/NeoForge/Fabric) bring their own
# start.bat that already builds the JVM arguments. In that case we let that
# script start the server; we only make sure the right Java comes first on
# the PATH.
$UseModpackLauncher = $true

# If the modpack does NOT bring a start.bat (e.g. vanilla, or you want to
# launch the jar directly), set $UseModpackLauncher = $false and fill in the jar name:
$ServerJar = "server.jar"
