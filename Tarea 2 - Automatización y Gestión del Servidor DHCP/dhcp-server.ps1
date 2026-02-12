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
    if ($p[0] -eq "127" -or $p[0] -eq "0") { return $false }
    return $true
}

function IP-A-Numero {
    param([string]$ip)
    $p = $ip.Trim() -split '\.'
    $a = [long]([int]$p[0])
    $b = [long]([int]$p[1])
    $c = [long]([int]$p[2])
    $d = [long]([int]$p[3])
    return ($a -shl 24) -bor ($b -shl 16) -bor ($c -shl 8) -bor $d
}

function Incrementar-IP {
    param([string]$ip)
    $p = $ip.Trim() -split '\.'
    $d = [int]$p[3] + 1
    $c = [int]$p[2]
    $b = [int]$p[1]
    $a = [int]$p[0]
    if ($d -gt 255) { $d = 0; $c++ }
    if ($c -gt 255) { $c = 0; $b++ }
    if ($b -gt 255) { $b = 0; $a++ }
    return "$a.$b.$c.$d"
}

function Calcular-Mascara {
    param([string]$i, [string]$f)
    $p1 = $i.Trim() -split '\.'
    $p2 = $f.Trim() -split '\.'
    if ($p1[0] -eq $p2[0] -and $p1[1] -eq $p2[1] -and $p1[2] -eq $p2[2]) { return "255.255.255.0" }
    if ($p1[0] -eq $p2[0] -and $p1[1] -eq $p2[1]) { return "255.255.0.0" }
    if ($p1[0] -eq $p2[0]) { return "255.0.0.0" }
    return "255.255.255.0"
}

function Mascara-A-Bits {
    param([string]$mascara)
    $bits = 0
    foreach ($o in ($mascara -split '\.')) {
        $byte = [Convert]::ToString([int]$o, 2)
        $bits += ($byte.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    return $bits
}

function Obtener-Red {
    param([string]$ip, [string]$mascara = "255.255.255.0")
    $pi = $ip.Trim()      -split '\.'
    $pm = $mascara.Trim() -split '\.'
    $red = @()
    for ($j = 0; $j -lt 4; $j++) { $red += ([int]$pi[$j] -band [int]$pm[$j]) }
    return ($red -join '.')
}

function Validar-Gateway {
    param([string]$gw, [string]$ref, [string]$mascara)
    $gw = $gw.Trim()
    if (-not (Validar-IP $gw)) { return $false }
    if ((Obtener-Red $gw $mascara) -ne (Obtener-Red $ref $mascara)) { return $false }
    return $true
}

function DHCP-Instalado {
    try {
        $f = Get-WindowsFeature -Name DHCP -ErrorAction Stop
        return ($f -and $f.Installed)
    } catch { return $false }
}

function Params-Configurados {
    return ($SCOPE -ne "X" -and $IPINICIAL -ne "X" -and $IPFINAL -ne "X" -and $LEASE -ne "X" -and $MASCARA -ne "X")
}

function DHCP-Corriendo {
    $svc = Get-Service "DHCPServer" -ErrorAction SilentlyContinue
    return ($svc -and $svc.Status -eq "Running")
}

# =============== OPCIONES DEL MENU =====================================

function Opcion-Verificar {
    Clear-Host
    Write-Host ""
    if (DHCP-Instalado) {
        Write-Host "DHCP-SERVER esta instalado :D"
    } else {
        Write-Host "El rol DHCP-SERVER no esta instalado"
        Write-Host ""
        $opc = Read-Host "Desea instalarlo? (S/N)"
        if ($opc -eq "S" -or $opc -eq "s") {
            Write-Host "Instalando..."
            try {
                Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
                Write-Host "Instalacion completada"
                try { Add-DhcpServerInDC -ErrorAction SilentlyContinue | Out-Null } catch {}
            } catch {
                Write-Host "ERROR: $($_.Exception.Message)"
            }
        }
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-VerParametros {
    Clear-Host
    Write-Host ""
    if (-not (Params-Configurados)) {
        Write-Host "Parametros no asignados..."
    } else {
        Write-Host "========== PARAMETROS CONFIGURADOS =========="
        Write-Host "SCOPE      = $SCOPE"
        Write-Host "IP INICIAL = $IPINICIAL  (IP del servidor)"
        Write-Host "IP REPARTO = $(Incrementar-IP $IPINICIAL)  (Primera IP a repartir)"
        Write-Host "IP FINAL   = $IPFINAL"
        if ($GATEWAY -ne "X") { Write-Host "GATEWAY    = $GATEWAY" }
        if ($DNS     -ne "X") { Write-Host "DNS        = $DNS" }
        if ($DNS2    -ne "X") { Write-Host "DNS 2      = $DNS2" }
        Write-Host "LEASE      = $LEASE segundos"
        Write-Host "MASCARA    = $MASCARA"
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-ConfParametros {
    Clear-Host
    if (-not (DHCP-Instalado)) {
        Write-Host ""; Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    $ST = ""
    while ([string]::IsNullOrWhiteSpace($ST)) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="
        $ST = (Read-Host "Nombre del ambito").Trim()
        if ([string]::IsNullOrWhiteSpace($ST)) { Write-Host "El nombre no puede estar vacio"; Start-Sleep 2 }
    }

    $IT = ""
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST"
        $IT = (Read-Host "IP inicial del rango (sera la IP del servidor)").Trim()
        if (Validar-IP $IT) { break }
        Write-Host "IP inicial no valida"; Start-Sleep 2
    }

    $FT = ""
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST | IP Inicial: $IT"
        $FT = (Read-Host "IP final del rango").Trim()
        if (-not (Validar-IP $FT))                   { Write-Host "IP final no valida"; Start-Sleep 2; continue }
        if ((IP-A-Numero $IT) -ge (IP-A-Numero $FT)) { Write-Host "La IP inicial debe ser menor que la final"; Start-Sleep 2; continue }
        break
    }

    $MT = Calcular-Mascara $IT $FT

    $GT = "X"
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST | Rango: $IT - $FT"
        $inp = (Read-Host "Gateway (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp)) { $GT = "X"; break }
        if (Validar-Gateway $inp $IT $MT)  { $GT = $inp; break }
        Write-Host "Gateway invalido"; Start-Sleep 2
    }

    $D1T = "X"; $D2T = "X"
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="
        if ($GT -ne "X") { Write-Host "Gateway: $GT" }
        $inp1 = (Read-Host "DNS primario (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp1)) { $D1T = "X"; $D2T = "X"; break }
        if (-not (Validar-IP $inp1)) { Write-Host "DNS primario no valido"; Start-Sleep 2; continue }
        $D1T = $inp1
        $inp2 = (Read-Host "DNS secundario (Enter para omitir)").Trim()
        if ([string]::IsNullOrEmpty($inp2)) { $D2T = "X"; break }
        if (-not (Validar-IP $inp2)) { Write-Host "DNS secundario no valido"; Start-Sleep 2; continue }
        if ($inp1 -eq $inp2)         { Write-Host "El DNS secundario no puede ser igual al primario"; Start-Sleep 2; continue }
        $D2T = $inp2; break
    }

    $LT = ""
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="
        $inp = (Read-Host "Lease en segundos (ej: 86400)").Trim()
        if ($inp -match '^\d+$' -and [long]$inp -gt 0) { $LT = $inp; break }
        Write-Host "Lease invalido"; Start-Sleep 2
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

    Write-Host ""; Write-Host "Parametros guardados"; Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Iniciar {
    Clear-Host
    Write-Host ""
    Write-Host "========== INICIAR SERVIDOR DHCP =========="

    if (-not (DHCP-Instalado))      { Write-Host ""; Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""; Read-Host "Enter para volver"; return }
    if (-not (Params-Configurados)) { Write-Host ""; Write-Host "ERROR: Configure los parametros primero (opcion 3)"; Write-Host ""; Read-Host "Enter para volver"; return }

    $adaptador = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Loopback"
    } | Select-Object -First 1

    if (-not $adaptador) { Write-Host ""; Write-Host "ERROR: No se encontro adaptador de red activo"; Write-Host ""; Read-Host "Enter para volver"; return }

    Write-Host "Adaptador: $($adaptador.Name)"

    $maskBits = Mascara-A-Bits $MASCARA

    try {
        Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    Start-Sleep 1

    try {
        New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $IPINICIAL -PrefixLength $maskBits -ErrorAction Stop | Out-Null
        Write-Host "IP estatica $IPINICIAL/$maskBits configurada"
    } catch {
        Write-Host "ERROR al asignar IP: $($_.Exception.Message)"
        Write-Host ""; Read-Host "Enter para volver"; return
    }

    if ($GATEWAY -ne "X") {
        try {
            New-NetRoute -InterfaceIndex $adaptador.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop $GATEWAY -ErrorAction Stop | Out-Null
        } catch {}
    }

    Start-Sleep 1

    $red       = Obtener-Red $IPINICIAL $MASCARA
    $primeraIP = Incrementar-IP $IPINICIAL

    # Eliminar scope previo si existe
    try {
        $existe = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId -eq $red }
        if ($existe) { Remove-DhcpServerv4Scope -ScopeId $red -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
    } catch {}

    # Crear scope
    try {
        Add-DhcpServerv4Scope `
            -Name          $SCOPE `
            -StartRange    $primeraIP `
            -EndRange      $IPFINAL `
            -SubnetMask    $MASCARA `
            -LeaseDuration ([TimeSpan]::FromSeconds([long]$LEASE)) `
            -State         Active `
            -ErrorAction   Stop | Out-Null
        Write-Host "Scope '$SCOPE' creado: $primeraIP - $IPFINAL"
    } catch {
        Write-Host "ERROR al crear el scope: $($_.Exception.Message)"
        Write-Host ""; Read-Host "Enter para volver"; return
    }

    if ($GATEWAY -ne "X") {
        try { Set-DhcpServerv4OptionValue -ScopeId $red -Router $GATEWAY -ErrorAction Stop | Out-Null } catch {}
    }
    if ($DNS -ne "X" -and $DNS2 -ne "X") {
        try { Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS, $DNS2 -ErrorAction Stop | Out-Null } catch {}
    } elseif ($DNS -ne "X") {
        try { Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS -ErrorAction Stop | Out-Null } catch {}
    }

    try { Add-DhcpServerInDC -ErrorAction SilentlyContinue | Out-Null } catch {}

    Set-Service     -Name "DHCPServer" -StartupType Automatic
    Restart-Service -Name "DHCPServer" -Force
    Start-Sleep 3

    Write-Host ""
    if ((Get-Service "DHCPServer").Status -eq "Running") {
        Write-Host "Servidor DHCP iniciado correctamente :D"
    } else {
        Write-Host "ERROR: No se pudo iniciar el servicio DHCP"
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Detener {
    Clear-Host
    Write-Host ""
    Write-Host "========== DETENER SERVIDOR DHCP =========="
    $svc = Get-Service "DHCPServer" -ErrorAction SilentlyContinue
    if (-not $svc)                    { Write-Host "El servicio DHCPServer no existe"; Write-Host ""; Read-Host "Enter para volver"; return }
    if ($svc.Status -eq "Stopped")    { Write-Host "El servidor DHCP ya estaba detenido"; Write-Host ""; Read-Host "Enter para volver"; return }
    try {
        Stop-Service -Name "DHCPServer" -Force -ErrorAction Stop
        Start-Sleep 2
        if ((Get-Service "DHCPServer").Status -eq "Stopped") {
            Write-Host "Servidor DHCP detenido correctamente"
        } else {
            Write-Host "Error al detener el servidor DHCP"
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)"
    }
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Monitor {
    Clear-Host
    Write-Host ""
    if (-not (DHCP-Instalado))      { Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""; Read-Host "Enter"; return }
    if (-not (Params-Configurados)) { Write-Host "ERROR: Configure los parametros primero (opcion 3)"; Write-Host ""; Read-Host "Enter"; return }
    if (-not (DHCP-Corriendo))      { Write-Host "ERROR: El servidor DHCP no esta en ejecucion (opcion 4)"; Write-Host ""; Read-Host "Enter"; return }

    $red = Obtener-Red $IPINICIAL $MASCARA
    Write-Host "Presione Ctrl+C para salir"; Start-Sleep 2

    try {
        while ($true) {
            Clear-Host
            Write-Host "========== MONITOR DHCP =========="
            Write-Host "Servidor : $SCOPE  |  Rango: $(Incrementar-IP $IPINICIAL) - $IPFINAL"
            Write-Host "Actualizando cada 3 segundos... (Ctrl+C para salir)"
            Write-Host "----------------------------------"
            $activos = Get-DhcpServerv4Lease -ScopeId $red -ErrorAction SilentlyContinue |
                       Where-Object { $_.AddressState -eq "Active" }
            if ($activos) {
                Write-Host ""
                Write-Host "CLIENTES CONECTADOS:"
                foreach ($l in $activos) {
                    $h = if ($l.HostName) { $l.HostName } else { "Desconocido" }
                    Write-Host ("IP: {0,-15} | MAC: {1,-17} | Host: {2}" -f $l.IPAddress, $l.ClientId, $h)
                }
                Write-Host "----------------------------------"
                Write-Host "Total activos: $($activos.Count)"
            } else {
                Write-Host ""; Write-Host "No hay clientes conectados"
            }
            Start-Sleep 3
        }
    } catch {
        Write-Host ""; Write-Host "Saliendo del monitor..."; Start-Sleep 1
    }
}

# =============== MENU PRINCIPAL ========================================

while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "============ SERVIDOR DHCP ============"
    Write-Host " 1. Verificar / Instalar rol DHCP"
    Write-Host " 2. Ver parametros configurados"
    Write-Host " 3. Configurar parametros"
    Write-Host " 4. Iniciar servidor"
    Write-Host " 5. Detener servidor"
    Write-Host " 6. Monitor de clientes"
    Write-Host " 7. Salir"
    Write-Host "======================================="
    Write-Host ""
    $opc = Read-Host "Seleccione una opcion"
    switch ($opc.Trim()) {
        "1" { Opcion-Verificar      }
        "2" { Opcion-VerParametros  }
        "3" { Opcion-ConfParametros }
        "4" { Opcion-Iniciar        }
        "5" { Opcion-Detener        }
        "6" { Opcion-Monitor        }
        "7" { Clear-Host; exit }
        default { Write-Host "Opcion no valida..."; Start-Sleep 2 }
    }
}
