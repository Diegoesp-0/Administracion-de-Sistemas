Clear-Host
Write-Host "Verificando si DHCP Server esta instalado..."

$dhcp = Get-WindowsFeature -Name DHCP

if ($dhcp.Installed) {
    Write-Host "El servidor DHCP ya esta instalado :D"
} else {
    Write-Host "El servidor DHCP NO esta instalado"
    Write-Host "Instalando..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
}

Start-Sleep -Seconds 2
Clear-Host

Write-Host "========= CONFIGURACION DHCP ========="

$SCOPE = Read-Host "Nombre del ambito"

function Validar-IP {
    param ([string]$ip)

    if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $partes = $ip.Split('.')
        foreach ($p in $partes) {
            if ([int]$p -gt 255) {
                return $false
            }
        }
        return $true
    }
    return $false
}

do {
    $IPinicial = Read-Host "IP inicial del rango"
} while (-not (Validar-IP $IPinicial))

do {
    $IPfinal = Read-Host "IP final del rango"
} while (-not (Validar-IP $IPfinal))

do {
    $GATEWAY = Read-Host "Puerta de enlace (Gateway)"
} while (-not (Validar-IP $GATEWAY))

do {
    $DNS = Read-Host "Servidor DNS"
} while (-not (Validar-IP $DNS))

do {
    $LEASE = Read-Host "Tiempo de concesion en segundos"
} while (-not ($LEASE -match '^\d+$'))

Clear-Host
Write-Host "Configurando DHCP..."

$red = ($IPinicial.Split('.')[0..2] -join '.') + ".0"
$mascara = "255.255.255.0"

if (-not (Get-DhcpServerv4Scope -ScopeId $red -ErrorAction SilentlyContinue)) {
Add-DhcpServerv4Scope `
    -Name $SCOPE `
    -StartRange $IPinicial `
    -EndRange $IPfinal `
    -SubnetMask $mascara `
    -State Active
}

Set-DhcpServerv4OptionValue `
    -ScopeId $red `
    -Router $GATEWAY `
    -DnsServer $DNS

Set-DhcpServerv4Scope `
    -ScopeId $red `
    -LeaseDuration ([TimeSpan]::FromSeconds($LEASE))

Restart-Service DHCPServer

Clear-Host
Write-Host "========= SERVIDOR DHCP ACTIVO ========="
Get-Service DHCPServer

Write-Host ""
Write-Host "Scopes configurados:"
Get-DhcpServerv4Scope
