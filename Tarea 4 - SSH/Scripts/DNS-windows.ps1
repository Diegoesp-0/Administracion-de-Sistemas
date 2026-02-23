$DOMINIO = "reprobados.com"

function DNS-Instalado {
    return (Get-WindowsFeature -Name DNS).Installed
}

function Menu-Verificar-DNS {
    Clear-Host
    if (DNS-Instalado) {
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

function Menu-Iniciar-DNS {
    $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Clear-Host
        Write-Host ""
        Write-Host "El servidor DNS ya esta corriendo"
        Write-Host ""
        Start-Sleep -Seconds 2
    } else {
        Clear-Host
        Set-Service -Name DNS -StartupType Automatic
        Start-Service -Name DNS
        Write-Host ""
        Write-Host "Iniciando servicio DNS..."
        Write-Host ""
        $svc = Get-Service -Name DNS
        if ($svc.Status -eq "Running") {
            Write-Host "Servicio DNS iniciado correctamente"
        } else {
            Write-Host "Error al iniciar el servicio DNS"
        }
    }
    Pausa
}

function Menu-IPFija-DNS {
    Configurar-IPEstatica | Out-Null
    Pausa
}

function Menu-ConfigurarZona {
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
    Write-Host "Zona '$DOMINIO' configurada y servicio reiniciado"
    Pausa
}

function Menu-Validar-DNS {
    Clear-Host
    Write-Host "Probando resolucion DNS para $DOMINIO ..."
    nslookup $DOMINIO 127.0.0.1
    Write-Host ""
    Write-Host "Probando ping a www.$DOMINIO ..."
    ping -n 3 "www.$DOMINIO"
    Pausa
}

function Menu-SeleccionarDominio {
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
        Write-Host "  0. Volver"
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

function Menu-DNS {
    while ($true) {
        Clear-Host
        $svc    = Get-Service -Name DNS -ErrorAction SilentlyContinue
        $estado = if ($svc -and $svc.Status -eq "Running") { "ACTIVO" } else { "INACTIVO" }

        Write-Host "=========================================="
        Write-Host "         CONFIGURADOR DNS"
        Write-Host "=========================================="
        Write-Host " Dominio : $script:DOMINIO"
        Write-Host " Servicio: $estado"
        Write-Host "------------------------------------------"
        Write-Host "  1. Verificar instalacion"
        Write-Host "  2. Configurar IP fija"
        Write-Host "  3. Iniciar servicio"
        Write-Host "  4. Configurar zona"
        Write-Host "  5. Validar resolucion"
        Write-Host "  6. Seleccionar dominio"
        Write-Host "  0. Volver al menu principal"
        Write-Host "------------------------------------------"

        $op = Read-Host "Seleccione una opcion"
        switch ($op) {
            "1" { Menu-Verificar-DNS    }
            "2" { Menu-IPFija-DNS       }
            "3" { Menu-Iniciar-DNS      }
            "4" { Menu-ConfigurarZona   }
            "5" { Menu-Validar-DNS      }
            "6" { Menu-SeleccionarDominio }
            "0" { return                }
            default { Write-Host "Opcion invalida"; Start-Sleep -Seconds 2 }
        }
    }
}
