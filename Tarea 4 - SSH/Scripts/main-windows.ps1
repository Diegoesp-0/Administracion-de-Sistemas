$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$SCRIPT_DIR\funciones_comunes-windows.ps1"
. "$SCRIPT_DIR\DHCP-windows.ps1"
. "$SCRIPT_DIR\DNS-windows.ps1"

Verificar-Administrador

while ($true) {
    Clear-Host
    Write-Host "============================================"
    Write-Host "    Administracion de Servidor - Windows"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "  1. Gestion DHCP"
    Write-Host "  2. Gestion DNS"
    Write-Host "  0. Salir"
    Write-Host ""
    Write-Host "============================================"

    $op = Read-Host "Seleccione una opcion"
    switch ($op) {
        "1" { Menu-DHCP }
        "2" { Menu-DNS  }
        "0" { Clear-Host; exit }
        default { Write-Host "Opcion invalida."; Start-Sleep 1 }
    }
}
