$MULTIOTP_EXE = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_REG = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$MULTIOTP_MSI = "$PSScriptRoot\multiOTP.msi"
$VCREDIST_EXE = "$PSScriptRoot\VC_redist.x64.exe"


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

    # COSO QUE BLOQUEA A LOS 3 INTENTOS
    & $MULTIOTP_EXE -config max-block-failures=3    | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800 | Out-Null
    Print-Ok "Lockout configurado: 3 intentos, 30 minutos."

    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1
    Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1
    Print-Ok "Credential Provider configurado."
}


function Registrar-UsuarioMFA {
    Print-Info "Verificando usuario MFA..."

    $info = & $MULTIOTP_EXE -user-info Administrador 2>&1
    if ($info -notlike "*doesn't exist*") {
        Print-Warn "Usuario Administrador ya registrado (se omite)"
        return
    }

    # GENERADOR DE CLAVE
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bytes        = New-Object byte[] 20
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $clave = ""
    for ($i = 0; $i -lt 20; $i++) {
        $clave += $base32Chars[$bytes[$i] % 32]
    }

    & $MULTIOTP_EXE -createga Administrador $clave | Out-Null
    & $MULTIOTP_EXE -set Administrador prefix-pin=0 | Out-Null

    Print-Ok "Usuario Administrador registrado."
    Write-Host ""
    Write-Host "========== Vincula Google Authenticator ==========" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Abre Google Authenticator en tu celular"
    Write-Host "  2. Toca + -> Ingresar clave de configuracion"
    Write-Host "  3. Ingresa estos datos:"
    Write-Host ""
    Write-Host "     Nombre: Administrador@empresa.local" -ForegroundColor Green
    Write-Host "     Clave:  $clave"                      -ForegroundColor Green
    Write-Host "     Tipo:   Basada en tiempo"            -ForegroundColor Green
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Yellow
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
    Registrar-UsuarioMFA

    Write-Host ""
    Print-Ok "MFA configurado correctamente."
    Print-Info "Conéctate por RDP para verificar el funcionamiento."
    Write-Host ""
}
