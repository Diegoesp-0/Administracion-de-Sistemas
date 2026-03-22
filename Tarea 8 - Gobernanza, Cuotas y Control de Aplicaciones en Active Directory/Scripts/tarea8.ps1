# Importar funciones
$rutaFunciones = Join-Path $PSScriptRoot "..\..\Funciones\Windows\T8_Funciones.ps1"
if (-not (Test-Path $rutaFunciones)) {
    Write-Host "[ERROR] No se encontro T8_Funciones.ps1 en: $rutaFunciones" -ForegroundColor Red
    Write-Host "Asegurate de que la estructura de carpetas sea correcta." -ForegroundColor Red
    exit 1
}
. $rutaFunciones

Verificar-Admin

#  MENU PRINCIPAL
while ($true) {
    Clear-Host
    Write-Host "=========================================="
    Write-Host "   TAREA 8 - Gobernanza y Control AD"
    Write-Host "=========================================="
    Write-Host ""

    # Mostrar IP actual siempre visible en el menu
    $ip = Obtener-IP
    Write-Host "  IP del Servidor: $ip"
    Write-Host ""
    Write-Host "  1. Configurar Active Directory"
    Write-Host "     (Instala AD DS, crea dominio, OUs y usuarios)"
    Write-Host ""
    Write-Host "  2. Configurar GPO y Horarios"
    Write-Host "     (Logon Hours + cierre de sesion automatico)"
    Write-Host ""
    Write-Host "  3. Configurar FSRM"
    Write-Host "     (Cuotas de disco + apantallamiento de archivos)"
    Write-Host ""
    Write-Host "  4. Configurar AppLocker"
    Write-Host "     (Control de ejecucion por grupo)"
    Write-Host ""
    Write-Host "  5. Ver informacion del servidor"
    Write-Host ""
    Write-Host "  6. Configurar todo (1 -> 2 -> 3 -> 4)"
    Write-Host ""
    Write-Host "  0. Salir"
    Write-Host "------------------------------------------"
    $opcion = Read-Host "Selecciona una opcion"
    $opcion = $opcion.Trim()

    switch ($opcion) {
        "1" {
            Clear-Host
            Configurar-AD
            Pausar
        }
        "2" {
            Clear-Host
            Configurar-GPO
            Pausar
        }
        "3" {
            Clear-Host
            Configurar-FSRM
            Pausar
        }
        "4" {
            Clear-Host
            Configurar-AppLocker
            Pausar
        }
        "5" {
            Mostrar-Info
        }
        "6" {
            Clear-Host
            Escribir-Titulo "Configuracion Completa"
            Configurar-AD
            Configurar-GPO
            Configurar-FSRM
            Configurar-AppLocker
            Escribir-Ok "Configuracion completa finalizada"
            Pausar
        }
        "0" {
            Clear-Host
            Write-Host "Saliendo..." -ForegroundColor Cyan
            exit
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Opcion invalida" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}