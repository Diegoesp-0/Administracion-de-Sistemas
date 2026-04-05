#Requires -RunAsAdministrator

$scriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$funcionesPath = Join-Path $scriptDir "..\..\Funciones\Windows\T8_Funciones.ps1"
$funcionesPath = (Resolve-Path $funcionesPath -ErrorAction SilentlyContinue).Path

if (-not $funcionesPath -or -not (Test-Path $funcionesPath)) {
    Write-Host "[ERR] No se encontro T8_Funciones.ps1" -ForegroundColor Red
    Write-Host "      Esperado en: Funciones\Windows\T8_Funciones.ps1" -ForegroundColor Red
    Write-Host "      Relativo a:  $scriptDir" -ForegroundColor Red
    Read-Host "Enter para salir"
    exit 1
}

. $funcionesPath
Write-Host "[OK] Funciones cargadas desde: $funcionesPath" -ForegroundColor Green

$script:RUTA_CSV = Join-Path $scriptDir "usuarios.csv"

# MENU PRINCIPAL
function menuPrincipal {
    do {
        Clear-Host
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        Write-Host "   Gobernanza, Cuotas y Control de             " -ForegroundColor Red
        Write-Host "   Aplicaciones en Active Directory            " -ForegroundColor Red
        Write-Host "   VERSION FINAL - Sinaloa (UTC-7)            " -ForegroundColor DarkGray
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        Write-Host "  1. Inicializar entorno  (solo una vez, reinicia)"
        Write-Host "  2. Crear UOs, grupos y usuarios desde CSV"
        Write-Host "  3. Configurar horarios de sesion (LogonHours)"
        Write-Host "  4. Configurar FSRM (cuotas + apantallamiento)"
        Write-Host "  5. Configurar AppLocker"
        Write-Host "  6. Unir cliente Windows al dominio"
        Write-Host "  7. Verificar entorno"
        Write-Host "  8. Salir"
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { inicializarEntorno;    Read-Host "`nEnter para continuar" }
            "2" { crearEstructuraAD;     Read-Host "`nEnter para continuar" }
            "3" { configurarHorarios;    Read-Host "`nEnter para continuar" }
            "4" { configurarFSRM;        Read-Host "`nEnter para continuar" }
            "5" { configurarAppLocker;   Read-Host "`nEnter para continuar" }
            "6" { unirClienteWindows;    Read-Host "`nEnter para continuar" }
            "7" { verificar;             Read-Host "`nEnter para continuar" }
            "8" { Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

menuPrincipal