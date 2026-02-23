function Validar-IP {
    param([string]$ip)
    if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    $p = $ip.Split('.')
    foreach ($o in $p) { if ([int]$o -gt 255) { return $false } }
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
    if ($p[0] -eq "127") { return $false }
    return $true
}

function IP-Num([string]$ip) {
    $p = $ip.Split('.')
    return ([int]$p[0] * 16777216) + ([int]$p[1] * 65536) + ([int]$p[2] * 256) + [int]$p[3]
}

function Siguiente-IP([string]$ip) {
    $p = $ip.Split('.')
    $p[3] = [string]([int]$p[3] + 1)
    if ([int]$p[3] -gt 255) { $p[3] = "0"; $p[2] = [string]([int]$p[2] + 1) }
    if ([int]$p[2] -gt 255) { $p[2] = "0"; $p[1] = [string]([int]$p[1] + 1) }
    return $p -join '.'
}

function Red-Base([string]$ip, [string]$mask = "") {
    if ($mask -ne "" -and $mask -ne "X") {
        $ipBytes   = ([System.Net.IPAddress]::Parse($ip)).GetAddressBytes()
        $maskBytes = ([System.Net.IPAddress]::Parse($mask)).GetAddressBytes()
        $net = for ($i = 0; $i -lt 4; $i++) { $ipBytes[$i] -band $maskBytes[$i] }
        return $net -join '.'
    }
    $p = $ip.Split('.')
    return "$($p[0]).$($p[1]).$($p[2]).0"
}

function Calcular-CIDR([string]$mask) {
    $cidr = 0
    foreach ($b in ([System.Net.IPAddress]::Parse($mask)).GetAddressBytes()) {
        $cidr += ([Convert]::ToString($b, 2).ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    return $cidr
}

function Configurar-IPEstatica {
    param([string]$ipDeseada = "")

    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notmatch "Loopback" }
    $adaptador   = $adaptadores | Select-Object -First 1
    $ifIndex     = $adaptador.ifIndex
    $dhcp        = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -ExpandProperty Dhcp

    if ($dhcp -eq "Enabled") {
        Write-Host ""
        Write-Host "La interfaz es dinamica"
        Write-Host ""

        if ([string]::IsNullOrEmpty($ipDeseada)) {
            do {
                $ipDeseada = Read-Host "Ingrese la IP fija"
                if (-not (Validar-IP $ipDeseada)) {
                    Write-Host "IP invalida, intente nuevamente"
                }
            } while (-not (Validar-IP $ipDeseada))
        }

        $prefijo = "24"
        $gateway = (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Select-Object -First 1).NextHop
        $dns     = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses | Select-Object -First 1

        Remove-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress    -InterfaceIndex $ifIndex -IPAddress $ipDeseada -PrefixLength $prefijo -DefaultGateway $gateway | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $dns

        Write-Host ""
        Write-Host "IP fija configurada: $ipDeseada"
        Write-Host ""
        return $ipDeseada
    } else {
        $ipActual = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).IPAddress
        Write-Host ""
        Write-Host "La interfaz ya tiene IP fija: $ipActual"
        Write-Host ""
        return $ipActual
    }
}

function Verificar-Administrador {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-Host "Este script debe ejecutarse como Administrador"
        exit 1
    }
}

function Pausa {
    Read-Host "`nPresione Enter para continuar" | Out-Null
}
