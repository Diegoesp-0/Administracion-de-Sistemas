$DOMINIO = "reprobados.com"

function Verificar {
    if ((Get-WindowsFeature -Name DNS).Installed) {
        Write-Host ""
        Write-Host "El DNS ya esta instalado"
        Write-Host ""
        Start-Sleep -Seconds 2
    } else {
        Write-Host ""
        Write-Host "El DNS no esta instalado"
        Write-Host ""
        $opc = Read-Host "Quieres instalar el rol DNS? (S/s)"
        if ($opc -eq "S" -or $opc -eq "s") {
            Clear-Host
            Write-Host ""
            Write-Host "Instalando DNS..."
            Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
            Write-Host "Instalacion completada"
            Write-Host ""
        }
    }
}

function Iniciar {
    $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Clear-Host
        Write-Host ""
        Write-Host "El servidor ya esta corriendo"
        Write-Host ""
        Start-Sleep -Seconds 2
    } else {
        Clear-Host
        Set-Service -Name DNS -StartupType Automatic
        Start-Service -Name DNS
        Write-Host ""
        Write-Host "Iniciando servicio..."
        Write-Host ""
        $svc = Get-Service -Name DNS
        if ($svc.Status -eq "Running") {
            Write-Host "Servicio iniciado correctamente"
        } else {
            Write-Host "Error al iniciar el servicio"
            exit 1
        }
    }
}

function Validar-IP {
    param($ip)
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    $partes = $ip -split '\.'
    foreach ($p in $partes) { if ([int]$p -gt 255) { return $false } }
    if ($ip -eq "0.0.0.0")         { return $false }
    if ($ip -eq "255.255.255.255") { return $false }
    if ($ip -match '^127\.')       { return $false }
    return $true
}

function Validar-IPFija {
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notmatch "Loopback" }
    $adaptador   = $adaptadores | Select-Object -First 1
    $ifIndex     = $adaptador.ifIndex
    $dhcp        = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -ExpandProperty Dhcp

    if ($dhcp -eq "Enabled") {
        Clear-Host
        Write-Host ""
        Write-Host "La interfaz es dinamica"
        Write-Host ""

        do {
            $ipFija = Read-Host "Ingrese la IP fija"
            if (-not (Validar-IP $ipFija)) {
                Clear-Host
                Write-Host ""
                Write-Host "IP invalida"
                Write-Host ""
                Start-Sleep -Seconds 2
            }
        } while (-not (Validar-IP $ipFija))

        $prefijo = "24"
        $gateway = (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Select-Object -First 1).NextHop
        $dns     = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses | Select-Object -First 1

        Remove-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress    -InterfaceIndex $ifIndex -IPAddress $ipFija -PrefixLength $prefijo -DefaultGateway $gateway | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $dns

        $script:IP_FIJA = $ipFija
        Write-Host ""
        Write-Host "IP fija configurada: $ipFija"
        Write-Host ""
    } else {
        Clear-Host
        Write-Host ""
        Write-Host "La interfaz ya tiene IP fija"
        Write-Host ""
        $script:IP_FIJA = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).IPAddress
        Start-Sleep -Seconds 2
    }
}

function Configurar-Zona {
    Clear-Host
    $IP_SERVER = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^127\." } | Select-Object -First 1).IPAddress

    do {
        Write-Host "=============== IP CLIENTE =============="
        Write-Host ""
        $IP_CLIENTE = Read-Host "Ingrese la IP a la que apuntara el Dominio"
        if (-not (Validar-IP $IP_CLIENTE)) {
            Clear-Host
            Write-Host ""
            Write-Host "La IP del cliente no es valida"
            Write-Host ""
            Start-Sleep -Seconds 2
        }
    } while (-not (Validar-IP $IP_CLIENTE))

    $zona = Get-DnsServerZone -Name $DOMINIO -ErrorAction SilentlyContinue
    if (-not $zona) {
        Add-DnsServerPrimaryZone -Name $DOMINIO -ZoneFile "$DOMINIO.dns" -DynamicUpdate None
    }

    Remove-DnsServerResourceRecord -ZoneName $DOMINIO -Name "@"   -RRType A -Force -ErrorAction SilentlyContinue
    Remove-DnsServerResourceRecord -ZoneName $DOMINIO -Name "www" -RRType A -Force -ErrorAction SilentlyContinue
    Remove-DnsServerResourceRecord -ZoneName $DOMINIO -Name "ns1" -RRType A -Force -ErrorAction SilentlyContinue

    Add-DnsServerResourceRecordA     -ZoneName $DOMINIO -Name "ns1" -IPv4Address $IP_SERVER
    Add-DnsServerResourceRecordA     -ZoneName $DOMINIO -Name "@"   -IPv4Address $IP_CLIENTE
    Add-DnsServerResourceRecordCName -ZoneName $DOMINIO -Name "www" -HostNameAlias "$DOMINIO."

    Restart-Service -Name DNS
    Write-Host ""
    Write-Host "Zona configurada y servicio reiniciado"
}

function Validar {
    Clear-Host
    Write-Host "Probando resolucion DNS..."
    nslookup $DOMINIO 127.0.0.1
    Write-Host "Probando ping..."
    ping -n 3 "www.$DOMINIO"
}

function Menu {
    $DOMINIOS = @("reprobados.com")

    while ($true) {
        Clear-Host
        Write-Host "========================================="
        Write-Host "         SELECCIONAR DOMINIO"
        Write-Host "========================================="
        Write-Host ""
        Write-Host "  Dominio activo: $script:DOMINIO"
        Write-Host ""
        for ($i = 0; $i -lt $DOMINIOS.Count; $i++) {
            Write-Host "  $($i+1). $($DOMINIOS[$i])"
        }
        Write-Host ""
        Write-Host "  A. Agregar dominio"
        Write-Host "  0. Salir"
        Write-Host ""
        $opc = Read-Host "Seleccione una opcion"

        if ($opc -eq "0") {
            break
        } elseif ($opc -eq "A" -or $opc -eq "a") {
            Write-Host ""
            $nuevoDom = Read-Host "Ingrese el nuevo dominio (ej: midominio.com)"
            if ([string]::IsNullOrWhiteSpace($nuevoDom)) {
                Write-Host "El dominio no puede estar vacio"
                Start-Sleep -Seconds 2
                continue
            }
            if ($DOMINIOS -contains $nuevoDom) {
                Write-Host "El dominio [$nuevoDom] ya existe en la lista"
                Start-Sleep -Seconds 2
            } else {
                $DOMINIOS += $nuevoDom
                Write-Host "Dominio [$nuevoDom] agregado"
                Start-Sleep -Seconds 2
            }
        } elseif ($opc -match '^\d+$' -and [int]$opc -ge 1 -and [int]$opc -le $DOMINIOS.Count) {
            $script:DOMINIO = $DOMINIOS[[int]$opc - 1]
            Write-Host ""
            Write-Host "Dominio seleccionado: $script:DOMINIO"
            Start-Sleep -Seconds 2
            break
        } else {
            Write-Host "Opcion invalida"
            Start-Sleep -Seconds 2
        }
    }
}

# ==================== MENU PRINCIPAL ====================

$op = $args[0]

if ($op -eq "verificar") { Verificar }
elseif ($op -eq "iniciar")    { Iniciar }
elseif ($op -eq "configurar") { Configurar-Zona }
elseif ($op -eq "validar")    { Validar }
elseif ($op -eq "ipfija")     { Validar-IPFija }
elseif ($op -eq "menu")       { Menu }
elseif ($op -eq "todo") {
    Verificar
    Validar-IPFija
    Iniciar
    Configurar-Zona
    Validar
} else {
    while ($true) {
        Clear-Host
        Write-Host "========== CONFIGURADOR DNS =========="
        Write-Host ""
        Write-Host "  1. Verificar instalacion"
        Write-Host "  2. IP fija"
        Write-Host "  3. Iniciar servicio"
        Write-Host "  4. Configurar zona"
        Write-Host "  5. Validar"
        Write-Host "  6. Seleccionar dominio"
        Write-Host "  7. Todo"
        Write-Host "  0. Salir"
        Write-Host "-----------------------------------------"
        $op = Read-Host "Seleccione una opcion"

        switch ($op) {
            "1" { Verificar }
            "2" { Validar-IPFija }
            "3" { Iniciar }
            "4" { Configurar-Zona }
            "5" { Validar }
            "6" { Menu }
            "7" { Verificar; Validar-IPFija; Iniciar; Configurar-Zona; Validar }
            "0" { exit }
            default { Write-Host "Opcion invalida"; Start-Sleep -Seconds 2 }
        }
    }
}
