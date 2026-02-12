# =============== VARIABLES ==============================================

$SCOPE     = "X"
$IPINICIAL = "X"
$IPFINAL   = "X"
$GATEWAY   = "X"
$DNS       = "X"
$DNS2      = "X"
$LEASE     = "X"
$MASCARA   = "X"

$SCRIPT_PATH = $MyInvocation.MyCommand.Path

# =============== FUNCIONES =============================================

function Guardar-Variables {
    $contenido = Get-Content $SCRIPT_PATH -Raw -Encoding UTF8
    $contenido = $contenido -replace '(?m)^\$SCOPE\s*=\s*".*?"',     "`$SCOPE     = `"$SCOPE`""
    $contenido = $contenido -replace '(?m)^\$IPINICIAL\s*=\s*".*?"', "`$IPINICIAL = `"$IPINICIAL`""
    $contenido = $contenido -replace '(?m)^\$IPFINAL\s*=\s*".*?"',   "`$IPFINAL   = `"$IPFINAL`""
    $contenido = $contenido -replace '(?m)^\$GATEWAY\s*=\s*".*?"',   "`$GATEWAY   = `"$GATEWAY`""
    $contenido = $contenido -replace '(?m)^\$DNS\s*=\s*".*?"',       "`$DNS       = `"$DNS`""
    $contenido = $contenido -replace '(?m)^\$DNS2\s*=\s*".*?"',      "`$DNS2      = `"$DNS2`""
    $contenido = $contenido -replace '(?m)^\$LEASE\s*=\s*".*?"',     "`$LEASE     = `"$LEASE`""
    $contenido = $contenido -replace '(?m)^\$MASCARA\s*=\s*".*?"',   "`$MASCARA   = `"$MASCARA`""
    [System.IO.File]::WriteAllText($SCRIPT_PATH, $contenido, [System.Text.Encoding]::UTF8)
}

function Validar-IP {
    param([string]$ip)
    $ip = $ip.Trim()
    if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    $p = $ip -split '\.'
    foreach ($o in $p) {
        $val = [int]$o
        if ($val -lt 0 -or $val -gt 255) { return $false }
    }
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
    if ($p[0] -eq "127") { return $false }
    if ($p[0] -eq "0")   { return $false }
    return $true
}

function IP-A-Numero {
    param([string]$ip)
    $ip = $ip.Trim()
    $p = $ip -split '\.'
    return ([long]$p[0] * 16777216) + ([long]$p[1] * 65536) + ([long]$p[2] * 256) + [long]$p[3]
}

function Numero-A-IP {
    param([long]$n)
    $a = [long]($n / 16777216) % 256
    $b = [long]($n / 65536)    % 256
    $c = [long]($n / 256)      % 256
    $d = $n % 256
    return "$a.$b.$c.$d"
}

function Incrementar-IP {
    param([string]$ip)
    return Numero-A-IP ((IP-A-Numero $ip) + 1)
}

function Calcular-Mascara {
    param([string]$i, [string]$f)
    $p1 = $i.Trim() -split '\.'
    $p2 = $f.Trim() -split '\.'

    # Mismo bloque /24
    if ($p1[0] -eq $p2[0] -and $p1[1] -eq $p2[1] -and $p1[2] -eq $p2[2]) {
        return "255.255.255.0"
    }
    # Mismo bloque /16
    if ($p1[0] -eq $p2[0] -and $p1[1] -eq $p2[1]) {
        return "255.255.0.0"
    }
    # Mismo bloque /8
    if ($p1[0] -eq $p2[0]) {
        return "255.0.0.0"
    }
    # Por defecto /24 (caso seguro)
    return "255.255.255.0"
}

function Mascara-A-Bits {
    param([string]$mascara)
    $bits = 0
    foreach ($octeto in ($mascara -split '\.')) {
        $byte = [Convert]::ToString([int]$octeto, 2)
        $bits += ($byte.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    return $bits
}

function Obtener-Red {
    param([string]$ip, [string]$mascara = "255.255.255.0")
    $pi = $ip.Trim()      -split '\.'
    $pm = $mascara.Trim() -split '\.'
    $red = @()
    for ($j = 0; $j -lt 4; $j++) {
        $red += ([int]$pi[$j] -band [int]$pm[$j])
    }
    return ($red -join '.')
}

function Obtener-Broadcast {
    param([string]$ip, [string]$mascara = "255.255.255.0")
    $pi = $ip.Trim()      -split '\.'
    $pm = $mascara.Trim() -split '\.'
    $bc = @()
    for ($j = 0; $j -lt 4; $j++) {
        $bc += ([int]$pi[$j] -bor (255 -bxor [int]$pm[$j]))
    }
    return ($bc -join '.')
}

function Validar-Rango {
    param([string]$i, [string]$f)
    if (-not (Validar-IP $i) -or -not (Validar-IP $f)) { return $false }
    $n1 = IP-A-Numero $i
    $n2 = IP-A-Numero $f
    if ($n1 -ge $n2) { return $false }
    # Deben estar en la misma /24 para mayor simplicidad
    $p1 = $i -split '\.'
    $p2 = $f -split '\.'
    if ($p1[0] -ne $p2[0] -or $p1[1] -ne $p2[1] -or $p1[2] -ne $p2[2]) {
        Write-Host "ADVERTENCIA: El rango abarca multiples subredes /24. Se usara /16 o /8."
        Start-Sleep 2
    }
    return $true
}

function Validar-Gateway {
    param([string]$gw, [string]$ref, [string]$mascara = "255.255.255.0")
    $gw = $gw.Trim()
    if (-not (Validar-IP $gw)) { return $false }
    $redGW  = Obtener-Red $gw  $mascara
    $redRef = Obtener-Red $ref $mascara
    if ($redGW -ne $redRef) { return $false }
    $bc = Obtener-Broadcast $gw $mascara
    $rd = Obtener-Red        $gw $mascara
    if ($gw -eq $rd -or $gw -eq $bc) { return $false }
    return $true
}

function DHCP-Instalado {
    try {
        $f = Get-WindowsFeature -Name DHCP -ErrorAction Stop
        return ($f -and $f.Installed)
    } catch {
        return $false
    }
}

function Params-Configurados {
    return (
        $SCOPE     -ne "X" -and
        $IPINICIAL -ne "X" -and
        $IPFINAL   -ne "X" -and
        $LEASE     -ne "X" -and
        $MASCARA   -ne "X"
    )
}

function DHCP-Corriendo {
    $svc = Get-Service "DHCPServer" -ErrorAction SilentlyContinue
    return ($svc -and $svc.Status -eq "Running")
}

# =============== OPCIONES DEL MENU =====================================

function Opcion-Verificar {
    Clear-Host
    Write-Host ""
    Write-Host "============ VERIFICAR / INSTALAR ROL DHCP ============"
    Write-Host ""
    if (DHCP-Instalado) {
        Write-Host "[OK] El rol DHCP-SERVER ya esta instalado." -ForegroundColor Green
        Write-Host ""
        $svc = Get-Service "DHCPServer" -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Host "Estado del servicio: $($svc.Status)"
        }
    } else {
        Write-Host "[!] El rol DHCP-SERVER NO esta instalado." -ForegroundColor Yellow
        Write-Host ""
        $opc = Read-Host "Desea instalar el rol DHCP-SERVER ahora? (S/N)"
        if ($opc -eq "S" -or $opc -eq "s") {
            Write-Host ""
            Write-Host "Instalando rol DHCP, espere..." -ForegroundColor Cyan
            try {
                Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
                Write-Host ""
                Write-Host "[OK] Instalacion completada correctamente." -ForegroundColor Green

                # Autorizar en AD si hay dominio
                try {
                    Add-DhcpServerInDC -ErrorAction SilentlyContinue | Out-Null
                } catch {}

                # Suprimir notificacion post-instalacion
                try {
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" `
                        -Name "ConfigurationState" -Value 2 -ErrorAction SilentlyContinue
                } catch {}

            } catch {
                Write-Host ""
                Write-Host "[ERROR] No se pudo instalar: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Instalacion cancelada."
        }
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-VerParametros {
    Clear-Host
    Write-Host ""
    Write-Host "============ PARAMETROS CONFIGURADOS ============"
    Write-Host ""
    if (-not (Params-Configurados)) {
        Write-Host "[!] No hay parametros configurados todavia." -ForegroundColor Yellow
        Write-Host "    Use la opcion 3 para configurarlos."
    } else {
        $primeraIP = Incrementar-IP $IPINICIAL
        Write-Host "  Ambito (Scope)   : $SCOPE"
        Write-Host "  IP del Servidor  : $IPINICIAL"
        Write-Host "  Primera IP Reparto: $primeraIP"
        Write-Host "  IP Final Reparto : $IPFINAL"
        Write-Host "  Mascara          : $MASCARA"
        if ($GATEWAY -ne "X") { Write-Host "  Gateway          : $GATEWAY" }
        else                  { Write-Host "  Gateway          : (no configurado)" }
        if ($DNS -ne "X")     { Write-Host "  DNS Primario     : $DNS" }
        else                  { Write-Host "  DNS Primario     : (no configurado)" }
        if ($DNS2 -ne "X")    { Write-Host "  DNS Secundario   : $DNS2" }
        else                  { Write-Host "  DNS Secundario   : (no configurado)" }
        Write-Host "  Lease            : $LEASE segundos ($([math]::Round([int]$LEASE/3600, 2)) horas)"

        Write-Host ""
        Write-Host "  Estado DHCP      : " -NoNewline
        if (DHCP-Corriendo) {
            Write-Host "CORRIENDO" -ForegroundColor Green
        } else {
            Write-Host "DETENIDO"  -ForegroundColor Red
        }
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-ConfParametros {
    Clear-Host
    if (-not (DHCP-Instalado)) {
        Write-Host ""
        Write-Host "[ERROR] Debe instalar el rol DHCP primero (opcion 1)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    # ---- Nombre del ambito ----
    $ST = ""
    while ([string]::IsNullOrWhiteSpace($ST)) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host ""
        $ST = (Read-Host "Nombre del ambito (Scope)").Trim()
        if ([string]::IsNullOrWhiteSpace($ST)) {
            Write-Host "El nombre no puede estar vacio." -ForegroundColor Red
            Start-Sleep 2
        }
    }

    # ---- IP Inicial ----
    $IT = ""
    while ($true) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host "Ambito: $ST"
        Write-Host ""
        $IT = (Read-Host "IP inicial del rango (sera la IP del servidor, ej: 192.168.1.1)").Trim()
        if (Validar-IP $IT) { break }
        Write-Host "IP inicial no valida. Ejemplo correcto: 192.168.1.1" -ForegroundColor Red
        Start-Sleep 2
    }

    # ---- IP Final ----
    $FT = ""
    while ($true) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host "Ambito: $ST  |  IP Inicial: $IT"
        Write-Host ""
        $FT = (Read-Host "IP final del rango (ej: 192.168.1.254)").Trim()
        if (-not (Validar-IP $FT)) {
            Write-Host "IP final no valida." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        if ((IP-A-Numero $IT) -ge (IP-A-Numero $FT)) {
            Write-Host "La IP inicial debe ser MENOR que la IP final." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        # Verificar que haya al menos 2 IPs de margen (1 para servidor + 1 para repartir)
        if ((IP-A-Numero $FT) - (IP-A-Numero $IT) -lt 1) {
            Write-Host "El rango debe tener al menos 2 IPs." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        break
    }

    # Calcular mascara antes de validar gateway
    $MT = Calcular-Mascara $IT $FT

    # ---- Gateway ----
    $GT = "X"
    while ($true) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host "Ambito: $ST  |  Rango: $IT - $FT  |  Mascara: $MT"
        Write-Host ""
        $inp = (Read-Host "Gateway (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp)) { $GT = "X"; break }
        if (Validar-Gateway $inp $IT $MT) { $GT = $inp; break }
        Write-Host "Gateway invalido. Debe estar en la misma red que la IP inicial y no ser red/broadcast." -ForegroundColor Red
        Start-Sleep 2
    }

    # ---- DNS ----
    $D1T = "X"
    $D2T = "X"
    while ($true) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host "Ambito: $ST  |  Rango: $IT - $FT"
        if ($GT -ne "X") { Write-Host "Gateway: $GT" }
        Write-Host ""
        $inp1 = (Read-Host "DNS primario (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp1)) { $D1T = "X"; $D2T = "X"; break }
        if (-not (Validar-IP $inp1)) {
            Write-Host "DNS primario no valido." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        $D1T = $inp1

        $inp2 = (Read-Host "DNS secundario (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp2)) { $D2T = "X"; break }
        if (-not (Validar-IP $inp2)) {
            Write-Host "DNS secundario no valido." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        if ($inp1 -eq $inp2) {
            Write-Host "El DNS secundario no puede ser igual al primario." -ForegroundColor Red
            Start-Sleep 2
            continue
        }
        $D2T = $inp2
        break
    }

    # ---- Lease ----
    $LT = ""
    while ($true) {
        Clear-Host
        Write-Host "============ CONFIGURAR PARAMETROS ============"
        Write-Host ""
        Write-Host "Ejemplos de lease: 3600 (1 hora) | 86400 (1 dia) | 604800 (1 semana)"
        $inp = (Read-Host "Lease en segundos").Trim()
        if ($inp -match '^\d+$' -and [long]$inp -gt 0) { $LT = $inp; break }
        Write-Host "Lease invalido. Debe ser un numero entero positivo." -ForegroundColor Red
        Start-Sleep 2
    }

    # ---- Resumen y confirmacion ----
    $primeraIP = Incrementar-IP $IT
    Clear-Host
    Write-Host ""
    Write-Host "============ RESUMEN DE CONFIGURACION ============"
    Write-Host ""
    Write-Host "  Ambito           : $ST"
    Write-Host "  IP del Servidor  : $IT"
    Write-Host "  Primera IP Reparto: $primeraIP"
    Write-Host "  IP Final         : $FT"
    Write-Host "  Mascara          : $MT"
    if ($GT  -ne "X") { Write-Host "  Gateway          : $GT"  }
    if ($D1T -ne "X") { Write-Host "  DNS Primario     : $D1T" }
    if ($D2T -ne "X") { Write-Host "  DNS Secundario   : $D2T" }
    Write-Host "  Lease            : $LT segundos ($([math]::Round([long]$LT/3600,2)) horas)"
    Write-Host ""
    Write-Host "=================================================="
    Write-Host ""
    $conf = Read-Host "Confirmar y guardar? (S/N)"
    if ($conf -ne "S" -and $conf -ne "s") {
        Write-Host "Configuracion cancelada." -ForegroundColor Yellow
        Start-Sleep 2
        return
    }

    $script:SCOPE     = $ST
    $script:IPINICIAL = $IT
    $script:IPFINAL   = $FT
    $script:GATEWAY   = $GT
    $script:DNS       = $D1T
    $script:DNS2      = $D2T
    $script:LEASE     = $LT
    $script:MASCARA   = $MT

    Guardar-Variables

    Write-Host ""
    Write-Host "[OK] Parametros guardados correctamente." -ForegroundColor Green
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Iniciar {
    Clear-Host
    Write-Host ""
    Write-Host "============ INICIAR SERVIDOR DHCP ============"
    Write-Host ""

    if (-not (DHCP-Instalado)) {
        Write-Host "[ERROR] Debe instalar el rol DHCP primero (opcion 1)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    if (-not (Params-Configurados)) {
        Write-Host "[ERROR] Debe configurar los parametros primero (opcion 3)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    # --- Buscar adaptador activo ---
    $adaptador = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.InterfaceDescription -notmatch "Loopback" -and
        $_.InterfaceDescription -notmatch "Virtual"
    } | Sort-Object -Property InterfaceIndex | Select-Object -First 1

    if (-not $adaptador) {
        Write-Host "[ERROR] No se encontro un adaptador de red activo." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    Write-Host "Adaptador detectado: $($adaptador.Name) ($($adaptador.InterfaceDescription))"
    Write-Host ""

    $maskBits = Mascara-A-Bits $MASCARA

    # --- Configurar IP estatica ---
    Write-Host "Configurando IP estatica $IPINICIAL/$maskBits en $($adaptador.Name)..."

    # Quitar IPs y rutas previas del adaptador
    try {
        Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    try {
        Get-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    Start-Sleep 1

    # Asignar nueva IP
    try {
        New-NetIPAddress `
            -InterfaceIndex $adaptador.ifIndex `
            -IPAddress      $IPINICIAL `
            -PrefixLength   $maskBits `
            -ErrorAction Stop | Out-Null
        Write-Host "[OK] IP $IPINICIAL/$maskBits asignada." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] No se pudo asignar la IP: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Presione Enter para volver al menu"
        return
    }

    # Asignar gateway si existe
    if ($GATEWAY -ne "X") {
        try {
            New-NetRoute `
                -InterfaceIndex    $adaptador.ifIndex `
                -DestinationPrefix "0.0.0.0/0" `
                -NextHop           $GATEWAY `
                -ErrorAction Stop | Out-Null
            Write-Host "[OK] Gateway $GATEWAY configurado." -ForegroundColor Green
        } catch {
            Write-Host "[AVISO] No se pudo configurar el gateway: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep 1

    # --- Configurar scope DHCP ---
    $red       = Obtener-Red $IPINICIAL $MASCARA
    $primeraIP = Incrementar-IP $IPINICIAL

    Write-Host ""
    Write-Host "Configurando scope DHCP..."
    Write-Host "  Red         : $red"
    Write-Host "  Rango reparto: $primeraIP - $IPFINAL"
    Write-Host "  Mascara     : $MASCARA"

    # Eliminar scope previo si existe
    try {
        $scopeExistente = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
            Where-Object { $_.ScopeId -eq $red }
        if ($scopeExistente) {
            Remove-DhcpServerv4Scope -ScopeId $red -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Scope anterior eliminado." -ForegroundColor Green
            Start-Sleep 1
        }
    } catch {}

    # Crear nuevo scope
    try {
        Add-DhcpServerv4Scope `
            -Name          $SCOPE `
            -StartRange    $primeraIP `
            -EndRange      $IPFINAL `
            -SubnetMask    $MASCARA `
            -LeaseDuration ([TimeSpan]::FromSeconds([long]$LEASE)) `
            -State         Active `
            -ErrorAction Stop | Out-Null
        Write-Host "[OK] Scope '$SCOPE' creado correctamente." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] No se pudo crear el scope: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Detalles tecnicos:"
        Write-Host "  Red calculada : $red"
        Write-Host "  Start         : $primeraIP"
        Write-Host "  End           : $IPFINAL"
        Write-Host "  Mask          : $MASCARA"
        Read-Host "Presione Enter para volver al menu"
        return
    }

    # Configurar opciones del scope
    if ($GATEWAY -ne "X") {
        try {
            Set-DhcpServerv4OptionValue -ScopeId $red -Router $GATEWAY -ErrorAction Stop | Out-Null
            Write-Host "[OK] Gateway $GATEWAY configurado en el scope." -ForegroundColor Green
        } catch {
            Write-Host "[AVISO] No se pudo configurar el gateway en el scope." -ForegroundColor Yellow
        }
    }

    if ($DNS -ne "X" -and $DNS2 -ne "X") {
        try {
            Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS, $DNS2 -ErrorAction Stop | Out-Null
            Write-Host "[OK] DNS $DNS y $DNS2 configurados." -ForegroundColor Green
        } catch {
            Write-Host "[AVISO] No se pudieron configurar los DNS." -ForegroundColor Yellow
        }
    } elseif ($DNS -ne "X") {
        try {
            Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS -ErrorAction Stop | Out-Null
            Write-Host "[OK] DNS $DNS configurado." -ForegroundColor Green
        } catch {
            Write-Host "[AVISO] No se pudo configurar el DNS." -ForegroundColor Yellow
        }
    }

    # Intentar autorizar en AD (no critico)
    try {
        Add-DhcpServerInDC -DnsName ([System.Net.Dns]::GetHostName()) -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # --- Iniciar servicio DHCP ---
    Write-Host ""
    Write-Host "Iniciando servicio DHCP..."
    try {
        Set-Service -Name "DHCPServer" -StartupType Automatic -ErrorAction SilentlyContinue
        Restart-Service -Name "DHCPServer" -Force -ErrorAction Stop
        Start-Sleep 3
    } catch {
        Write-Host "[ERROR] No se pudo iniciar el servicio: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Presione Enter para volver al menu"
        return
    }

    # Verificar estado final
    $estado = (Get-Service "DHCPServer").Status
    Write-Host ""
    if ($estado -eq "Running") {
        Write-Host "============================================" -ForegroundColor Green
        Write-Host " Servidor DHCP iniciado correctamente :D  " -ForegroundColor Green
        Write-Host " Repartiendo IPs: $primeraIP - $IPFINAL    " -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio DHCP termino con estado: $estado" -ForegroundColor Red
        Write-Host "Revise el visor de eventos para mas detalles."
    }

    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Detener {
    Clear-Host
    Write-Host ""
    Write-Host "============ DETENER SERVIDOR DHCP ============"
    Write-Host ""

    $svc = Get-Service "DHCPServer" -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "[AVISO] El servicio DHCPServer no existe en este sistema." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    if ($svc.Status -eq "Stopped") {
        Write-Host "[INFO] El servicio DHCP ya estaba detenido." -ForegroundColor Cyan
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    try {
        Stop-Service -Name "DHCPServer" -Force -ErrorAction Stop
        Start-Sleep 2
        $nuevoEstado = (Get-Service "DHCPServer").Status
        if ($nuevoEstado -eq "Stopped") {
            Write-Host "[OK] Servidor DHCP detenido correctamente." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Estado inesperado: $nuevoEstado" -ForegroundColor Red
        }
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Monitor {
    Clear-Host
    Write-Host ""

    if (-not (DHCP-Instalado)) {
        Write-Host "[ERROR] Instale el rol DHCP primero (opcion 1)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver"
        return
    }

    if (-not (Params-Configurados)) {
        Write-Host "[ERROR] Configure los parametros primero (opcion 3)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver"
        return
    }

    if (-not (DHCP-Corriendo)) {
        Write-Host "[ERROR] El servidor DHCP no esta en ejecucion. Use la opcion 4." -ForegroundColor Red
        Write-Host ""
        Read-Host "Presione Enter para volver"
        return
    }

    $red = Obtener-Red $IPINICIAL $MASCARA
    $primeraIP = Incrementar-IP $IPINICIAL

    Write-Host "Iniciando monitor... Presione Ctrl+C para salir." -ForegroundColor Cyan
    Start-Sleep 2

    try {
        while ($true) {
            Clear-Host
            $ahora = Get-Date -Format "HH:mm:ss"
            Write-Host "============ MONITOR DHCP | $ahora ============"
            Write-Host " Scope   : $SCOPE"
            Write-Host " Servidor: $IPINICIAL   Red: $red"
            Write-Host " Reparto : $primeraIP  -  $IPFINAL"
            Write-Host " Estado  : " -NoNewline
            if (DHCP-Corriendo) { Write-Host "ACTIVO" -ForegroundColor Green }
            else                { Write-Host "DETENIDO" -ForegroundColor Red }
            Write-Host "---------------------------------------------"

            try {
                $leases = Get-DhcpServerv4Lease -ScopeId $red -ErrorAction Stop
                $activos = $leases | Where-Object { $_.AddressState -eq "Active" }
                $total   = ($leases | Measure-Object).Count

                Write-Host " Total leases: $total   |   Activos: $(($activos | Measure-Object).Count)"
                Write-Host "---------------------------------------------"

                if ($activos) {
                    Write-Host ""
                    Write-Host (" {0,-17}  {1,-19}  {2,-22}  {3}" -f "IP", "MAC", "Hostname", "Expira")
                    Write-Host (" {0,-17}  {1,-19}  {2,-22}  {3}" -f "---", "---", "--------", "------")
                    foreach ($l in ($activos | Sort-Object IPAddress)) {
                        $host = if ($l.HostName) { $l.HostName } else { "Desconocido" }
                        $exp  = if ($l.LeaseExpiryTime) { $l.LeaseExpiryTime.ToString("MM/dd HH:mm") } else { "N/A" }
                        Write-Host (" {0,-17}  {1,-19}  {2,-22}  {3}" -f $l.IPAddress, $l.ClientId, $host, $exp)
                    }
                } else {
                    Write-Host ""
                    Write-Host " No hay clientes activos en este momento." -ForegroundColor Yellow
                }
            } catch {
                Write-Host " [Error al obtener leases]: $($_.Exception.Message)" -ForegroundColor Red
            }

            Write-Host ""
            Write-Host " Actualizando cada 5 segundos... (Ctrl+C para salir)" -ForegroundColor DarkGray
            Start-Sleep 5
        }
    } catch {
        Write-Host ""
        Write-Host "Monitor cerrado." -ForegroundColor Cyan
        Start-Sleep 1
    }
}

# =============== VERIFICAR QUE CORRE COMO ADMIN =========================

$identidad  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal  = New-Object System.Security.Principal.WindowsPrincipal($identidad)
$esAdmin    = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $esAdmin) {
    Write-Host ""
    Write-Host "[ERROR CRITICO] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    Write-Host "Haga clic derecho en PowerShell y seleccione 'Ejecutar como administrador'." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Presione Enter para salir"
    exit 1
}

# =============== MENU PRINCIPAL ========================================

while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "         SERVIDOR DHCP - MENU PRINCIPAL  " -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Estado rapido
    Write-Host "  Estado DHCP  : " -NoNewline
    if (-not (DHCP-Instalado)) {
        Write-Host "NO INSTALADO"  -ForegroundColor Red
    } elseif (DHCP-Corriendo) {
        Write-Host "CORRIENDO"     -ForegroundColor Green
    } else {
        Write-Host "INSTALADO / DETENIDO" -ForegroundColor Yellow
    }

    Write-Host "  Parametros   : " -NoNewline
    if (Params-Configurados) {
        Write-Host "CONFIGURADOS ($SCOPE | $IPINICIAL - $IPFINAL)" -ForegroundColor Green
    } else {
        Write-Host "NO CONFIGURADOS" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  ----------------------------------------"
    Write-Host "   1. Verificar / Instalar rol DHCP"
    Write-Host "   2. Ver parametros configurados"
    Write-Host "   3. Configurar parametros"
    Write-Host "   4. Iniciar servidor DHCP"
    Write-Host "   5. Detener servidor DHCP"
    Write-Host "   6. Monitor de clientes"
    Write-Host "   7. Salir"
    Write-Host "  ----------------------------------------"
    Write-Host ""

    $opc = Read-Host "  Seleccione una opcion [1-7]"

    switch ($opc.Trim()) {
        "1" { Opcion-Verificar      }
        "2" { Opcion-VerParametros  }
        "3" { Opcion-ConfParametros }
        "4" { Opcion-Iniciar        }
        "5" { Opcion-Detener        }
        "6" { Opcion-Monitor        }
        "7" { Clear-Host; Write-Host "Hasta luego."; exit 0 }
        default {
            Write-Host ""
            Write-Host "  Opcion no valida. Ingrese un numero del 1 al 7." -ForegroundColor Red
            Start-Sleep 2
        }
    }
}
