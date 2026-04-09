$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$MULTIOTP_MSI  = "$PSScriptRoot\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\VC_redist.x64.exe"
$CSV_USUARIOS  = "$PSScriptRoot\usuarios_p9.csv"
$RUTA_CLAVES   = "C:\Users\Administrador\claves_mfa.txt"
$DOMINIO_MFA   = "empresa.local"

$ADMINS_MFA = @(
    "admin_identidad",
    "admin_storage",
    "admin_politicas",
    "admin_auditoria"
)


function Generar-ClaveTOTP {
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bytes       = New-Object byte[] 20
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $clave = ""
    for ($i = 0; $i -lt 20; $i++) {
        $clave += $base32Chars[$bytes[$i] % 32]
    }
    return $clave
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
        return
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        return
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}


function Habilitar-RDP {
    Print-Info "Habilitando RDP..."
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Escritorio remoto" -ErrorAction SilentlyContinue
    Print-Ok "RDP habilitado."
}


function Configurar-MultiOTP {
    Print-Info "Configurando multiOTP..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Instala primero multiOTP."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3      | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800  | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1
    Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1
    Print-Ok "Credential Provider configurado."
}


function Registrar-Usuarios-MFA {
    Print-Info "Registrando usuarios en multiOTP..."

    # Limpiar archivo de claves anterior
    "========== Claves MFA - $DOMINIO_MFA ==========" | Out-File $RUTA_CLAVES -Encoding UTF8
    "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "Agrega cada clave en Google Authenticator:" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "  Abre Google Authenticator -> + -> Ingresar clave -> Tipo: Basada en tiempo" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8

    # Registrar admins hardcodeados
    Write-Host ""
    Print-Info "Registrando administradores..."

    foreach ($sam in $ADMINS_MFA) {
        $info = & $MULTIOTP_EXE -user-info $sam 2>&1
        if ($info -notlike "*doesn't exist*") {
            Print-Warn "  $sam ya registrado (se omite)"
            continue
        }

        $clave = Generar-ClaveTOTP
        & $MULTIOTP_EXE -createga $sam $clave | Out-Null
        & $MULTIOTP_EXE -set $sam prefix-pin=0 | Out-Null

        Print-Ok "  $sam registrado"

        "Usuario: $sam" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Nombre en GA: $sam@$DOMINIO_MFA" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Clave:        $clave" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    }

    # Registrar usuarios del CSV
    if (Test-Path $CSV_USUARIOS) {
        Write-Host ""
        Print-Info "Registrando usuarios del CSV..."
        $usuarios = Import-Csv $CSV_USUARIOS

        foreach ($u in $usuarios) {
            $info = & $MULTIOTP_EXE -user-info $u.Usuario 2>&1
            if ($info -notlike "*doesn't exist*") {
                Print-Warn "  $($u.Usuario) ya registrado (se omite)"
                continue
            }

            $clave = Generar-ClaveTOTP
            & $MULTIOTP_EXE -createga $u.Usuario $clave | Out-Null
            & $MULTIOTP_EXE -set $u.Usuario prefix-pin=0 | Out-Null

            Print-Ok "  $($u.Usuario) registrado"

            "Usuario: $($u.Usuario)" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
            "  Nombre en GA: $($u.Usuario)@$DOMINIO_MFA" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
            "  Clave:        $clave" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
            "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        }
    } else {
        Print-Warn "CSV no encontrado, solo se registraron los admins."
    }

    Write-Host ""
    Print-Ok "Claves guardadas en: $RUTA_CLAVES"
    Write-Host ""
    Write-Host "========== Claves generadas ==========" -ForegroundColor Yellow
    Get-Content $RUTA_CLAVES
    Write-Host "======================================" -ForegroundColor Yellow
}


function Configurar-MFA {
    Clear-Host
    Write-Host "========== Configuracion de MFA =========="
    Write-Host ""

    Instalar-MultiOTP
    Write-Host ""
    Habilitar-RDP
    Write-Host ""
    Configurar-MultiOTP
    Write-Host ""
    Registrar-Usuarios-MFA

    Write-Host ""
    Print-Ok "MFA configurado correctamente."
    Print-Info "Cada usuario debe agregar su clave a Google Authenticator."
    Print-Info "Las claves estan en: $RUTA_CLAVES"
    Write-Host ""
}
