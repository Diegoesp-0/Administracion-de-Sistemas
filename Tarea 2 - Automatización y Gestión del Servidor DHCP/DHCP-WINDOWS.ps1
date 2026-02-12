Clear-Host

# ================= VARIABLES GLOBALES =================

$Global:SCOPE = $null
$Global:IPINICIAL = $null
$Global:IPFINAL = $null
$Global:GATEWAY = $null
$Global:DNS = $null
$Global:DNS2 = $null
$Global:LEASE = $null
$Global:MASCARA = $null

# ================= FUNCIONES =================

function Pausa {
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Validar-IP {
    param ($ip)

    if ($ip -match "^(\d{1,3}\.){3}\d{1,3}$") {
        $partes = $ip.Split(".")
        foreach ($p in $partes) {
            if ([int]$p -gt 255) { return $false }
        }
        return $true
    }
    return $false
}

function Verificar-DHCP {
    Clear-Host
    Write-Host "Verificando si DHCP Server esta instalado..."

    $dhcp = Get-WindowsFeature -Name DHCP

    if ($dhcp.Installed) {
        Write-Host "DHCP Server esta instalado"
    } else {
        Write-Host "DHCP Server NO esta instalado"
        $opc = Read-Host "Desea instalarlo? (S/N)"
        if ($opc -eq "S" -or $opc -eq "s") {
            Install-WindowsFeature DHCP -IncludeManagementTools
            Write-Host "Instalacion completada"
        }
    }

    Pausa
}

function Configurar-Parametros {
    Clear-Host

    $Global:SCOPE = Read-Host "Nombre del Scope"

    do {
        $ip1 = Read-Host "IP Inicial"
    } until (Validar-IP $ip1)

    do {
        $ip2 = Read-Host "IP Final"
    } until (Validar-IP $ip2)

    do {
        $mask = Read-Host "Mascara (Ej: 255.255.255.0)"
    } until (Validar-IP $mask)

    $gateway = Read-Host "Gateway (Enter para omitir)"
    $dns1 = Read-Host "DNS primario (Enter para omitir)"
    $dns2 = Read-Host "DNS secundario (Enter para omitir)"
    $lease = Read-Host "Lease en segundos"

    $Global:IPINICIAL = $ip1
    $Global:IPFINAL = $ip2
    $Global:MASCARA = $mask
    $Global:GATEWAY = $gateway
    $Global:DNS = $dns1
    $Global:DNS2 = $dns2
    $Global:LEASE = $lease

    Write-Host "Parametros guardados correctamente"
    Pausa
}

function Crear-Scope {
    Clear-Host

    if (-not $Global:SCOPE) {
        Write-Host "Debe configurar parametros primero"
        Pausa
        return
    }

    $red = ($Global:IPINICIAL.Split(".")[0..2] -join ".") + ".0"

    Add-DhcpServerv4Scope `
        -Name $Global:SCOPE `
        -StartRange $Global:IPINICIAL `
        -EndRange $Global:IPFINAL `
        -SubnetMask $Global:MASCARA `
        -State Active

    if ($Global:GATEWAY) {
        Set-DhcpServerv4OptionValue `
            -ScopeId $red `
            -Router $Global:GATEWAY
    }

    if ($Global:DNS) {
        if ($Global:DNS2) {
            Set-DhcpServerv4OptionValue `
                -ScopeId $red `
                -DnsServer $Global:DNS,$Global:DNS2
        }
        else {
            Set-DhcpServerv4OptionValue `
                -ScopeId $red `
                -DnsServer $Global:DNS
        }
    }

    if ($Global:LEASE) {
        Set-DhcpServerv4Scope `
            -ScopeId $red `
            -LeaseDuration (New-TimeSpan -Seconds $Global:LEASE)
    }

    Write-Host "Scope creado correctamente"
    Pausa
}

function Iniciar-Servicio {
    Start-Service DHCPServer
    Write-Host "Servicio DHCP iniciado"
    Pausa
}

function Detener-Servicio {
    Stop-Service DHCPServer
    Write-Host "Servicio DHCP detenido"
    Pausa
}

function Monitor-DHCP {
    Clear-Host
    Write-Host "Monitor DHCP. Ctrl+C para salir"
    Start-Sleep 2

    while ($true) {
        Clear-Host

        Get-DhcpServerv4Lease |
        Select-Object IPAddress, HostName, ClientId, AddressState |
        Format-Table -AutoSize

        Start-Sleep 3
    }
}

# ================= MENU =================

function Menu {
    do {
        Clear-Host
        Write-Host "========== DHCP MANAGER =========="
        Write-Host "1. Verificar DHCP"
        Write-Host "2. Configurar Parametros"
        Write-Host "3. Crear Scope"
        Write-Host "4. Iniciar Servicio"
        Write-Host "5. Detener Servicio"
        Write-Host "6. Monitor DHCP"
        Write-Host "0. Salir"
        Write-Host "=================================="

        $op = Read-Host "Seleccione una opcion"

        switch ($op) {
            "1" { Verificar-DHCP }
            "2" { Configurar-Parametros }
            "3" { Crear-Scope }
            "4" { Iniciar-Servicio }
            "5" { Detener-Servicio }
            "6" { Monitor-DHCP }
            "0" { exit }
        }

    } while ($true)
}

Menu
