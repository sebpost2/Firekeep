# Verificacion de checksum SHA256 para archivos descargados (ej. el JDK de
# Adoptium en install-java.ps1). Se carga con dot-source.

# Compara el SHA256 de un archivo contra el esperado. Devuelve $false si el
# archivo no existe o si el hash no coincide (nunca tira excepcion).
function Test-Sha256Checksum {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    return $actual -ieq $ExpectedSha256
}
