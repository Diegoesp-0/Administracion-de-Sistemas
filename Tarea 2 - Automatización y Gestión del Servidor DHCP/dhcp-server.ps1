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
    $contenido = Get-Content $SCRIPT_PATH -Raw
    $contenido = $contenido -replace '(?m)^\$SCOPE\s*=\s*".*?"',     "`$SCOPE     = `"$SCOPE`""
    $contenido = $contenido -replace '(?m)^\$IPINICIAL\s*=\s*".*?"', "`$IPINICIAL = `"$IPINICIAL`""
    $contenido = $contenido -replace '(?m)^\$IPFINAL\s*=\s*".*?"',   "`$IPFINAL   = `"$IPFINAL`""
    $contenido = $contenido -replace '(?m)^\$GATEWAY\s*=\s*".*?"',   "`$GATEWAY   = `"$GATEWAY`""
    $contenido = $contenido -replace '(?m)^\$DNS\s*=\s*".*?"',       "`$DNS       = `"$DNS`""
    $contenido = $contenido -replace '(?m)^\$DNS2\s*=\s*".*?"',      "`$DNS2      = `"$DNS2`""
    $contenido = $contenido -replace '(?m)^\$LEASE\s*=\s*".*?"',     "`$LEASE     = `"$LEASE`""
    $contenido = $contenido -replace '(?m)^\$MASCARA\s*=\s*".*?"',   "`$MASCARA   = `"$MASCARA`""
    Set-Content $SCRIPT_PATH $contenido -Encoding UTF8
}

function Validar-IP {
    param([string]$ip)
    if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    $p = $ip -split '\.'
    foreach ($o in $p) { if ([int]$o -gt 255) { return $false } }
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
    if ($p[0] -eq "127") { return $false }
    return $true
}

function IP-A-Numero  { param([string]$ip); $p = $ip -split '\.'; return ([long]$p[0]*16777216)+([long]$p[1]*65536)+([long]$p[2]*256)+[long]$p[3] }
function Numero-A-IP  { param([long]$n); return "$([int]($n/16777216)%256).$([int]($n/65536)%256).$([int]($n/256)%256).$([int]$n%256)" }
function Obtener-Red  { param([string]$ip); $p=$ip -split '\.'; return "$($p[0]).$($p[1]).$($p[2]).0" }
function Obtener-BC   { param([string]$ip); $p=$ip -split '\.'; return "$($p[0]).$($p[1]).$($p[2]).255" }
function Incrementar-IP { param([string]$ip); return Numero-A-IP((IP-A-Numero $ip)+1) }

function Validar-Rango {
    param([string]$i, [string]$f)
    if (-not (Validar-IP $i) -or -not (Validar-IP $f)) { return $false }
    return (IP-A-Numero $i) -lt (IP-A-Numero $f)
}

function Validar-Gateway {
    param([string]$gw, [string]$ref)
    if (-not (Validar-IP $gw)) { return $false }
    if ((Obtener-Red $gw) -ne (Obtener-Red $ref)) { return $false }
    if ($gw -eq (Obtener-Red $gw) -or $gw -eq (Obtener-BC $gw)) { return $false }
    return $true
}

function Calcular-Mascara {
    param([string]$i, [string]$f)
    $n1 = IP-A-Numero $i; $n2 = IP-A-Numero $f
    $cidr = 32
    while ($cidr -ge 8) {
        if (($n2 - $n1 + 1 + 2) -le ([math]::Pow(2, 32 - $cidr) - 2)) { break }
        $cidr--
    }
    $m = 0
    for ($b = 0; $b -lt $cidr; $b++) { $m = ($m -shl 1) -bor 1 }
    for ($b = $cidr; $b -lt 32; $b++) { $m = $m -shl 1 }
    return Numero-A-IP ([long]($m -band 0xFFFFFFFF))
}

function DHCP-Instalado {
    $f = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue
    return ($f -and $f.Installed)
}

function Params-Configurados {
    return ($SCOPE -ne "X" -and $IPINICIAL -ne "X" -and $IPFINAL -ne "X" -and $LEASE -ne "X" -and $MASCARA -ne "X")
}

# =============== OPCIONES DEL MENU =====================================

function Opcion-Verificar {
    Clear-Host
    if (DHCP-Instalado) {
        Write-Host ""; Write-Host "DHCP-SERVER esta instalado :D"; Write-Host ""
    } else {
        Write-Host ""; Write-Host "El rol DHCP-SERVER no esta instalado"; Write-Host ""
        $opc = Read-Host "Desea instalar el rol DHCP-SERVER? (S/s)"
        if ($opc -eq "S" -or $opc -eq "s") {
            Write-Host "Instalando..."
            Install-WindowsFeature -Name DHCP -IncludeManagementTools
            Write-Host ""; Write-Host "Instalacion completada"; Write-Host ""
        }
    }
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-VerParametros {
    Clear-Host
    if (-not (Params-Configurados)) {
        Write-Host ""; Write-Host "Parametros no asignados..."; Write-Host ""
    } else {
        Write-Host ""
        Write-Host "========== PARAMETROS CONFIGURADOS =========="
        Write-Host "SCOPE      = $SCOPE"
        Write-Host "IP INICIAL = $IPINICIAL (IP del servidor)"
        Write-Host "IP REPARTO = $(Incrementar-IP $IPINICIAL) (Primera IP a repartir)"
        Write-Host "IP FINAL   = $IPFINAL"
        if ($GATEWAY -ne "X") { Write-Host "GATEWAY    = $GATEWAY" }
        if ($DNS     -ne "X") { Write-Host "DNS        = $DNS" }
        if ($DNS2    -ne "X") { Write-Host "DNS 2      = $DNS2" }
        Write-Host "LEASE      = $LEASE segundos"
        Write-Host "MASCARA    = $MASCARA"
        Write-Host ""
    }
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-ConfParametros {
    Clear-Host
    if (-not (DHCP-Instalado)) {
        Write-Host ""; Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }

    Write-Host "========== CONFIGURAR PARAMETROS =========="
    $ST = Read-Host "Nombre del ambito"

    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST"
        $IT = Read-Host "IP inicial del rango (sera la IP del servidor)"
        if (-not (Validar-IP $IT)) { Write-Host "IP inicial no valida"; Start-Sleep 2; continue }

        $FT = Read-Host "IP final del rango"
        if (-not (Validar-IP $FT)) { Write-Host "IP final no valida"; Start-Sleep 2; continue }
        if (-not (Validar-Rango $IT $FT)) { Write-Host "La IP inicial debe ser menor a la final"; Start-Sleep 2; continue }
        break
    }

    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST | Rango: $IT - $FT"
        $GT = Read-Host "Gateway (Enter para omitir)"
        if ([string]::IsNullOrEmpty($GT)) { $GT = "X"; break }
        if (Validar-Gateway $GT $IT) { break }
        Write-Host "Gateway invalido..."; Start-Sleep 2
    }

    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="; Write-Host "Ambito: $ST | Rango: $IT - $FT"
        if ($GT -ne "X") { Write-Host "Gateway: $GT" }
        $D1T = Read-Host "DNS primario (Enter para omitir)"
        if ([string]::IsNullOrEmpty($D1T)) { $D1T = "X"; $D2T = "X"; break }
        if (-not (Validar-IP $D1T)) { Write-Host "DNS primario invalido..."; Start-Sleep 2; continue }

        $D2T = Read-Host "DNS secundario (Enter para omitir)"
        if ([string]::IsNullOrEmpty($D2T)) { $D2T = "X"; break }
        if (-not (Validar-IP $D2T)) { Write-Host "DNS secundario invalido..."; Start-Sleep 2; continue }
        if ($D1T -eq $D2T) { Write-Host "El DNS secundario no puede ser igual al primario..."; Start-Sleep 2; continue }
        break
    }

    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURAR PARAMETROS =========="
        $LT = Read-Host "Lease (en segundos)"
        if ($LT -match '^\d+$' -and [int]$LT -gt 0) { break }
        Write-Host "Lease invalido..."; Start-Sleep 2
    }

    $MT = Calcular-Mascara $IT $FT

    Clear-Host
    Write-Host "========== RESUMEN =========="
    Write-Host "Ambito  : $ST"
    Write-Host "Rango   : $IT - $FT"
    Write-Host "Mascara : $MT"
    if ($GT  -ne "X") { Write-Host "Gateway : $GT" }
    if ($D1T -ne "X") { Write-Host "DNS     : $D1T" }
    if ($D2T -ne "X") { Write-Host "DNS 2   : $D2T" }
    Write-Host "Lease   : $LT segundos"
    Write-Host "-----------------------------"
    Read-Host "Datos guardados, presione Enter para volver al menu"

    $script:SCOPE=$ST; $script:IPINICIAL=$IT; $script:IPFINAL=$FT
    $script:GATEWAY=$GT; $script:DNS=$D1T; $script:DNS2=$D2T
    $script:LEASE=$LT; $script:MASCARA=$MT
    Guardar-Variables
}

function Opcion-Iniciar {
    Clear-Host
    if (-not (DHCP-Instalado))      { Write-Host ""; Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""; Read-Host "Enter para volver"; return }
    if (-not (Params-Configurados)) { Write-Host ""; Write-Host "ERROR: Configure los parametros primero (opcion 3)"; Write-Host ""; Read-Host "Enter para volver"; return }

    Write-Host "========== INICIAR SERVIDOR DHCP =========="
    $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Loopback" } | Select-Object -First 1
    if (-not $adaptador) { Write-Host "ERROR: No se encontro adaptador de red activo"; Read-Host "Enter para volver"; return }

    Write-Host "Adaptador: $($adaptador.Name)"

    $maskBits = 0
    foreach ($o in ($MASCARA -split '\.')) { $maskBits += ([Convert]::ToString([int]$o,2).ToCharArray() | Where-Object {$_ -eq '1'}).Count }

    Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute     -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress    -InterfaceIndex $adaptador.ifIndex -IPAddress $IPINICIAL -PrefixLength $maskBits -ErrorAction Stop | Out-Null
    if ($GATEWAY -ne "X") { New-NetRoute -InterfaceIndex $adaptador.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop $GATEWAY -ErrorAction SilentlyContinue | Out-Null }

    Write-Host "IP estatica $IPINICIAL configurada"

    $red = Obtener-Red $IPINICIAL
    $scopeExistente = Get-DhcpServerv4Scope -ScopeId $red -ErrorAction SilentlyContinue
    if ($scopeExistente) { Remove-DhcpServerv4Scope -ScopeId $red -Force }

    Add-DhcpServerv4Scope -Name $SCOPE -StartRange (Incrementar-IP $IPINICIAL) -EndRange $IPFINAL -SubnetMask $MASCARA -LeaseDuration ([TimeSpan]::FromSeconds([int]$LEASE))
    if ($GATEWAY -ne "X") { Set-DhcpServerv4OptionValue -ScopeId $red -Router $GATEWAY }
    if ($DNS -ne "X" -and $DNS2 -ne "X") { Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS,$DNS2 }
    elseif ($DNS -ne "X")                { Set-DhcpServerv4OptionValue -ScopeId $red -DnsServer $DNS }

    try { Add-DhcpServerInDC -ErrorAction SilentlyContinue | Out-Null } catch {}

    Set-Service -Name "DHCPServer" -StartupType Automatic
    Restart-Service -Name "DHCPServer" -Force
    Start-Sleep 2

    if ((Get-Service "DHCPServer").Status -eq "Running") {
        Write-Host ""; Write-Host "Servidor DHCP iniciado correctamente :D"; Write-Host ""
    } else {
        Write-Host ""; Write-Host "ERROR: No se pudo iniciar el servicio DHCP"; Write-Host ""
    }
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Detener {
    Clear-Host
    Write-Host "========== DETENER SERVIDOR DHCP =========="
    Stop-Service -Name "DHCPServer" -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    if ((Get-Service "DHCPServer").Status -eq "Stopped") {
        Write-Host ""; Write-Host "Servidor DHCP detenido correctamente"; Write-Host ""
    } else {
        Write-Host ""; Write-Host "Error al detener el servidor DHCP"; Write-Host ""
    }
    Read-Host "Presione Enter para volver al menu"
}

function Opcion-Monitor {
    Clear-Host
    if (-not (DHCP-Instalado))      { Write-Host ""; Write-Host "ERROR: Instale el rol DHCP primero (opcion 1)"; Write-Host ""; Read-Host "Enter"; return }
    if (-not (Params-Configurados)) { Write-Host ""; Write-Host "ERROR: Configure los parametros primero (opcion 3)"; Write-Host ""; Read-Host "Enter"; return }
    if ((Get-Service "DHCPServer" -ErrorAction SilentlyContinue).Status -ne "Running") {
        Write-Host ""; Write-Host "ERROR: El servidor DHCP no esta en ejecucion (opcion 4)"; Write-Host ""; Read-Host "Enter"; return
    }

    $red = Obtener-Red $IPINICIAL
    Write-Host "Presione Ctrl+C para salir"; Start-Sleep 2

    try {
        while ($true) {
            Clear-Host
            Write-Host "========== MONITOR DHCP =========="
            Write-Host "Servidor : $SCOPE  |  Rango: $(Incrementar-IP $IPINICIAL) - $IPFINAL"
            Write-Host "Actualizando cada 3 segundos... (Ctrl+C para salir)"
            Write-Host "---------------------------------------"

            $activos = Get-DhcpServerv4Lease -ScopeId $red -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq "Active" }

            if ($activos) {
                Write-Host ""; Write-Host "CLIENTES CONECTADOS:"
                foreach ($l in $activos) {
                    Write-Host ("IP: {0,-15} | MAC: {1,-17} | Host: {2}" -f $l.IPAddress, $l.ClientId, $(if($l.HostName){$l.HostName}else{"Desconocido"}))
                }
                Write-Host "---------------------------------------"
                Write-Host "Total de clientes activos: $($activos.Count)"
            } else {
                Write-Host ""; Write-Host "No hay clientes conectados"; Write-Host ""
            }
            Start-Sleep 3
        }
    } catch {
        Write-Host ""; Write-Host "Saliendo del monitor..."
        Start-Sleep 1
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

    switch ($opc) {
        "1" { Opcion-Verificar }
        "2" { Opcion-VerParametros }
        "3" { Opcion-ConfParametros }
        "4" { Opcion-Iniciar }
        "5" { Opcion-Detener }
        "6" { Opcion-Monitor }
        "7" { Clear-Host; exit }
        default { Write-Host "Opcion no valida..."; Start-Sleep 2 }
    }
}
