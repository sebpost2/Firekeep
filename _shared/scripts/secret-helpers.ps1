# Helper para guardar secretos en disco sin dejar una ventana donde el
# archivo tenga los permisos por defecto/heredados de la carpeta (que pueden
# ser legibles por otras cuentas de la misma laptop). Se carga con dot-source.

# Crea el archivo VACIO, le restringe el acceso al usuario actual, y recien
# despues escribe el contenido. Asi el contenido nunca existe en disco con
# permisos mas amplios que los restringidos (evita el TOCTOU de crear-luego-
# restringir).
function Set-RestrictedSecretFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    New-Item -ItemType File -Path $Path -Force | Out-Null
    icacls $Path /inheritance:r /grant:r "${env:USERDOMAIN}\${env:USERNAME}:(R,W)" | Out-Null
    Set-Content -Path $Path -Value $Content -NoNewline -Encoding ascii
}
