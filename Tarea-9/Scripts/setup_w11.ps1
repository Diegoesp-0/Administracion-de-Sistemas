#Requires -RunAsAdministrator

$DOMINIO       = "empresa.local"
$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$MULTIOTP_MSI  = "$PSScriptRoot\..\..\Funciones\Windows\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\..\..\Funciones\Windows\VC_redist.x64.exe"

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }


function Unir-Dominio {
    param([string]$IpServidor, [string]$PassAdmin)

    Print-Info "Verificando si ya esta en el dominio..."
    $domActual = (Get-WmiObject Win32_ComputerSystem).Domain
    if ($domActual -eq $DOMINIO) {
        Print-Warn "Ya esta unido a $DOMINIO (se omite)."
        return
    }

    Print-Info "Configurando DNS hacia el servidor..."
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($adaptador in $adaptadores) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adaptador.InterfaceIndex `
                -ServerAddresses $IpServidor -ErrorAction SilentlyContinue
        } catch {}
    }
    Print-Ok "DNS configurado: $IpServidor"

    Print-Info "Uniendo al dominio $DOMINIO..."
    $credencial = New-Object System.Management.Automation.PSCredential(
        "EMPRESA\Administrador",
        (ConvertTo-SecureString $PassAdmin -AsPlainText -Force)
    )

    try {
        Add-Computer -DomainName $DOMINIO -Credential $credencial -ErrorAction Stop
        Print-Ok "Unido al dominio $DOMINIO correctamente."
    } catch {
        Print-Err "Error al unirse al dominio: $_"
        exit 1
    }
}


function Instalar-RSAT {
    Print-Info "Instalando RSAT - Active Directory..."
    $rsat = Get-WindowsCapability -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -Online
    if ($rsat.State -eq "Installed") {
        Print-Warn "RSAT AD ya instalado (se omite)."
    } else {
        Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" | Out-Null
        Print-Ok "RSAT AD instalado."
    }

    Print-Info "Instalando RSAT - Group Policy..."
    $rsatGpo = Get-WindowsCapability -Name "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -Online
    if ($rsatGpo.State -eq "Installed") {
        Print-Warn "RSAT GPO ya instalado (se omite)."
    } else {
        Add-WindowsCapability -Online -Name "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" | Out-Null
        Print-Ok "RSAT GPO instalado."
    }
}


function Instalar-MultiOTP {
    Print-Info "Verificando instalacion de multiOTP..."

    $instalado = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                 Where-Object { $_.DisplayName -like "*multiOTP*" } |
                 Select-Object -First 1

    if ($instalado) {
        Print-Warn "multiOTP ya instalado: $($instalado.DisplayVersion) (se omite)"
        return
    }

    if (-not (Test-Path $VCREDIST_EXE)) {
        Print-Err "No se encontro: $VCREDIST_EXE"
        exit 1
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        exit 1
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}


function Configurar-MultiOTP {
    Print-Info "Configurando multiOTP..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3       | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800  | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1
    Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1
    Print-Ok "Credential Provider configurado."
}


function Configurar-WinRM {
    Print-Info "Configurando WinRM..."
    winrm quickconfig -force 2>$null | Out-Null
    winrm set winrm/config/client "@{TrustedHosts=""*""}" 2>$null | Out-Null
    Print-Ok "WinRM configurado."
}


function Registrar-Usuarios {
    param([string]$IpServidor, [string]$PassAdmin)

    Print-Info "Leyendo claves MFA del servidor..."

    $credencial = New-Object System.Management.Automation.PSCredential(
        "EMPRESA\Administrador",
        (ConvertTo-SecureString $PassAdmin -AsPlainText -Force)
    )

    try {
        New-PSDrive -Name "SRV" -PSProvider FileSystem -Root "\\$IpServidor\C`$" `
            -Credential $credencial -ErrorAction Stop | Out-Null
    } catch {
        Print-Err "No se pudo conectar al servidor: $_"
        exit 1
    }

    $rutaLocal = "SRV:\Users\Administrador\claves_mfa.txt"

    if (-not (Test-Path $rutaLocal)) {
        Print-Err "No se encontro claves_mfa.txt en el servidor."
        Print-Info "Corre primero la opcion 5 del menu principal en el servidor."
        Remove-PSDrive -Name "SRV" -ErrorAction SilentlyContinue
        exit 1
    }

    $contenido = Get-Content $rutaLocal
    Remove-PSDrive -Name "SRV" -ErrorAction SilentlyContinue

    $usuario = $null
    $clave   = $null

    foreach ($linea in $contenido) {
        if ($linea -match "^Usuario: (.+)$") {
            $usuario = $matches[1].Trim()
        }
        if ($linea -match "Clave:\s+(.+)$") {
            $clave = $matches[1].Trim()
        }

        if ($usuario -and $clave) {
            & $MULTIOTP_EXE -createga $usuario $clave | Out-Null
            if ($LASTEXITCODE -eq 11) {
                & $MULTIOTP_EXE -set $usuario prefix-pin=0 | Out-Null
                Print-Ok "  $usuario registrado"
            } elseif ($LASTEXITCODE -eq 22) {
                Print-Warn "  $usuario ya registrado (se omite)"
            } else {
                Print-Err "  Error al registrar $usuario (codigo: $LASTEXITCODE)"
            }
            $usuario = $null
            $clave   = $null
        }
    }
}

Clear-Host
Write-Host "========== Configuracion Windows 11 - Practica 09 =========="
Write-Host ""

$IpServidor = Read-Host "IP del servidor"
if (-not $IpServidor) { Print-Err "IP no puede estar vacia."; exit 1 }

$PassAdminSec = Read-Host "Contrasena del Administrador" -AsSecureString
$PassAdmin = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassAdminSec)
)
if (-not $PassAdmin) { Print-Err "Contrasena no puede estar vacia."; exit 1 }

Write-Host ""
Print-Info "Iniciando configuracion..."
Write-Host ""

# 1. Unir al dominio
Unir-Dominio -IpServidor $IpServidor -PassAdmin $PassAdmin
Write-Host ""

# 2. Instalar RSAT (requiere internet)
Instalar-RSAT
Write-Host ""

# 3. Instalar VC_redist + multiOTP
Instalar-MultiOTP
Write-Host ""

# 4. Configurar multiOTP
Configurar-MultiOTP
Write-Host ""

# 5. Configurar WinRM
Configurar-WinRM
Write-Host ""

# 6. Registrar usuarios con claves del servidor
Registrar-Usuarios -IpServidor $IpServidor -PassAdmin $PassAdmin

Write-Host ""
Print-Ok "Configuracion completada."
Print-Warn "El equipo se reiniciara en 10 segundos."
Print-Info "Al reiniciar inicia sesion con: usuario / contrasena / token GA"
Write-Host ""

Start-Sleep -Seconds 10
Restart-Computer -Force
