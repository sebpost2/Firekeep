# Configuracion de esta instancia de server. Editar segun el modpack.

# Version mayor de Java que pide el modpack (revisa la pagina del modpack en CurseForge,
# o el archivo settings.cfg / minecraftinstance.json que trae). Guia rapida:
#   Minecraft 1.16 y anteriores -> 8
#   Minecraft 1.17 - 1.20.4     -> 17
#   Minecraft 1.20.5+           -> 21
$JavaVersion = 21

# Memoria minima / maxima para la JVM. Modpacks grandes suelen pedir 6-8G de max.
$MinRam = "2G"
$MaxRam = "6G"

# La mayoria de los "Server Files" de CurseForge (Forge/NeoForge/Fabric) traen su
# propio start.bat que ya arma los argumentos de la JVM. En ese caso dejamos que
# ese script arranque el server; nosotros solo nos aseguramos de que el Java
# correcto quede primero en el PATH.
$UseModpackLauncher = $true

# Si el modpack NO trae start.bat (ej. vanilla, o querés lanzar el jar directo),
# poné $UseModpackLauncher = $false y completa el nombre del jar:
$ServerJar = "server.jar"
