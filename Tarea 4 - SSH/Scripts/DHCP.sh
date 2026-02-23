#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/funciones_comunes.sh"

calcular_Rango() {
    local ip1=$1
    local ip2=$2
    local n=0
    local rango1=0
    local rango2=0
    local pot=0

    IFS='.' read -ra octetosIni <<< "$ip1"
    IFS='.' read -ra octetosFin <<< "$ip2"

    for ((i=3; i>=0; i--)); do
        pot=$(( 255 ** n ))
        rango1=$(( (${octetosIni[i]} * pot) + rango1 ))
        rango2=$(( (${octetosFin[i]} * pot) + rango2 ))
        n=$(( n + 1 ))
    done

    echo $(( rango2 - rango1 ))
}

calcular_Bits() {
    local masc="$1"
    local count=0
    IFS='.' read -r a b c d <<< "$masc"
    for octeto in $d $c $b $a; do
        local n=255
        if [ $octeto -eq 0 ]; then
            count=$(( count + 8 ))
            continue
        elif [ $octeto -eq 255 ]; then
            echo $count
            return 0
        else
            for i in {0..7}; do
                n=$(( n - (2 ** i) ))
                count=$(( count + 1 ))
                if [[ $n -eq $octeto ]]; then
                    echo $count
                    return 0
                fi
            done
        fi
    done
    return 0
}

validar_IP_Masc() {
    local mascRang="$3"
    local rango=$(calcular_Rango "$1" "$2")
    mascRang=$(calcular_Bits "$mascRang")
    mascRang=$(( (2 ** mascRang) - 2 ))
    if [ $rango -gt $mascRang ]; then
        echo "La mascara $3 no es suficiente para el rango de IPs indicado"
        return 1
    fi
    return 0
}

crear_Mascara() {
    local rango=$(calcular_Rango "$1" "$2")
    local n=0
    local bits=0
    local p=0
    local masc=255.255.255.255
    local octeto=0

    for i in {1..32}; do
        if [[ $n -ge $(( rango + 2 )) ]]; then
            break
        else
            n=$(( 2 ** i ))
            bits=$(( bits + 1 ))
        fi
    done

    IFS='.' read -r -a a_masc <<< "$masc"
    for ((i=${#a_masc[@]}-1; i>=0; i--)); do
        octeto=${a_masc[i]}
        p=0
        until [ $octeto -eq 0 ] || [ $p -eq $bits ]; do
            octeto=$(( octeto - (2 ** p) ))
            p=$(( p + 1 ))
        done
        if [ $p -eq $bits ]; then
            a_masc[i]=$octeto
            break
        fi
        bits=$(( bits - 8 ))
        a_masc[i]=$octeto
    done

    IFS=" "
    local resultado="${a_masc[*]}"
    resultado=${resultado// /.}
    echo "$resultado"
}

verificar_dhcp() {
    echo "Verificando paqueteria DHCP..."
    if rpm -q dhcp-server &>/dev/null; then
        echo "DHCP esta instalado"
        return 0
    else
        echo "DHCP no esta instalado"
        return 1
    fi
}

instalar_dhcp() {
    if verificar_dhcp; then
        if [ -f /etc/dhcpd.conf ] && [ -s /etc/dhcpd.conf ]; then
            echo "Se detecto una configuracion previa de DHCP"
            read -p "Deseas sobreescribir la configuracion existente? (y/n): " sobreescribir
            if [[ "$sobreescribir" =~ ^[Yy]$ ]]; then
                configurar_dhcp
            else
                echo "Operacion cancelada"
            fi
        else
            echo "DHCP ya instalado pero sin configuracion. Iniciando configuracion..."
            configurar_dhcp
        fi
        return 0
    fi

    instalar_paquete "dhcp-server" || return 1

    if [ -f /etc/dhcpd.conf ] && [ -s /etc/dhcpd.conf ]; then
        echo "Se detecto una configuracion previa de DHCP"
        read -p "Deseas sobreescribir la configuracion existente? (y/n): " sobreescribir
        if [[ "$sobreescribir" =~ ^[Yy]$ ]]; then
            configurar_dhcp
        fi
    else
        configurar_dhcp
    fi
}

configurar_dhcp() {
    local ip_Valida=""
    local uso_Mas=""
    local comp=""
    local masc_valida=""

    echo ""
    echo "Configuracion Dinamica"
    echo ""

    read -p "Nombre descriptivo del Ambito: " scope

    until [ "$masc_valida" = "si" ]; do
        read -p "Mascara (En blanco para asignar automaticamente): " mascara
        if [ "$mascara" != "" ]; then
            if validar_Mascara "$mascara"; then
                uso_Mas="si"
                masc_valida="si"
            fi
        else
            masc_valida="si"
        fi
    done

    until [ "$ip_Valida" = "si" ]; do
        read -p "IP del servidor (esta IP se asignara de forma estatica al servidor): " ip_Servidor
        local ip_Res=$(echo "$ip_Servidor" | cut -d'.' -f4)
        if [ "$ip_Res" -ne 255 ]; then
            if validar_IP "$ip_Servidor"; then
                ip_Valida="si"
                local ip_Res_Inicial=$(( ip_Res + 1 ))
                local ip_Prefijo=$(echo "$ip_Servidor" | cut -d'.' -f1-3)
                ip_Inicial="$ip_Prefijo.$ip_Res_Inicial"
            fi
        else
            echo "No use X.X.X.255 como ultimo octeto"
        fi
    done

    ip_Valida="no"

    until [ "$ip_Valida" = "si" ]; do
        read -p "Rango final de la IP: " ip_Final
        if validar_IP "$ip_Final"; then
            if [ "$(calcular_Rango "$ip_Inicial" "$ip_Final")" -gt 2 ]; then
                if [ "$uso_Mas" = "si" ]; then
                    if validar_IP_Masc "$ip_Inicial" "$ip_Final" "$mascara"; then
                        ip_Valida="si"
                    fi
                else
                    mascara=$(crear_Mascara "$ip_Inicial" "$ip_Final")
                    ip_Valida="si"
                fi
            else
                echo "La IP final no concuerda con el rango inicial"
            fi
        fi
        if [ "$ip_Valida" = "no" ]; then
            echo "Intentando nuevamente..."
        fi
    done

    read -p "Tiempo de la sesion en segundos: " lease_Time

    comp="no"
    until [[ "$comp" = "si" ]]; do
        read -p "Gateway (puede quedar vacio para red aislada): " gateway
        if [ "$gateway" = "" ]; then
            comp="si"
            echo "Sin gateway - los clientes no tendran acceso a internet"
        elif validar_IP "$gateway"; then
            comp="si"
        fi
        if [ "$comp" = "no" ]; then
            echo "Intentando nuevamente..."
        fi
    done

    comp="no"
    until [[ "$comp" = "si" ]]; do
        read -p "DNS principal (puede quedar vacio): " dns
        if [ "$dns" = "" ]; then
            comp="si"
            dns_Alt=""
        elif validar_IP "$dns"; then
            comp="si"
        fi
        if [ "$comp" = "no" ]; then
            echo "Intentando nuevamente..."
        fi
    done

    if [ -n "$dns" ]; then
        comp="no"
        until [[ "$comp" = "si" ]]; do
            read -p "DNS alternativo (puede quedar vacio): " dns_Alt
            if [ "$dns_Alt" = "" ]; then
                comp="si"
            elif validar_IP "$dns_Alt"; then
                comp="si"
            fi
            if [ "$comp" = "no" ]; then
                echo "Intentando nuevamente..."
            fi
        done
    else
        dns_Alt=""
    fi

    echo ""
    echo "Interfaces de red disponibles:"
    ip -br link show | grep -v "lo" | awk '{print $1}'
    read -p "Ingrese la interfaz de red a usar: " interfaz

    echo ""
    echo "La configuracion final es:"
    echo "Nombre del ambito: $scope"
    echo "Mascara: $mascara"
    echo "IP del servidor: $ip_Servidor"
    echo "IP inicial del rango DHCP: $ip_Inicial"
    echo "IP final: $ip_Final"
    echo "Tiempo de concesion: $lease_Time"
    echo "Gateway: $gateway"
    echo "DNS primario: $dns"
    echo "DNS alternativo: $dns_Alt"
    echo "Interfaz: $interfaz"
    echo ""

    read -p "Acepta esta configuracion? (y/n): " opc
    if [ "$opc" = "y" ]; then
        _aplicar_configuracion_dhcp
    else
        echo "Volviendo a configurar..."
        configurar_dhcp
    fi
}

_aplicar_configuracion_dhcp() {
    IFS='.' read -r a b c d <<< "$ip_Inicial"
    IFS='.' read -r ma mb mc md <<< "$mascara"

    local red="$((a & ma)).$((b & mb)).$((c & mc)).$((d & md))"
    local broadcast="$((a | (255 - ma))).$((b | (255 - mb))).$((c | (255 - mc))).$((d | (255 - md)))"

    echo "Red calculada: $red"
    echo "Broadcast calculado: $broadcast"

    echo "Creando configuracion DHCP..."

    cat > /etc/dhcpd.conf <<EOF
default-lease-time $lease_Time;
max-lease-time $((lease_Time * 2));
authoritative;

subnet $red netmask $mascara {
    range $ip_Inicial $ip_Final;
$([ -n "$gateway" ] && echo "    option routers $gateway;")
    option subnet-mask $mascara;
$(if [ -n "$dns" ] && [ -n "$dns_Alt" ]; then
    echo "    option domain-name-servers $dns, $dns_Alt;"
elif [ -n "$dns" ]; then
    echo "    option domain-name-servers $dns;"
fi)
    option broadcast-address $broadcast;
}
EOF

    echo "Configurando interfaz de red..."
    echo "DHCPD_INTERFACE=\"$interfaz\"" > /etc/sysconfig/dhcpd

    echo "Configurando IP estatica $ip_Servidor en la interfaz $interfaz..."
    ip addr flush dev "$interfaz"
    ip addr add "$ip_Servidor/$(calcular_Bits "$mascara")" dev "$interfaz"
    ip link set "$interfaz" up

    cat > "/etc/sysconfig/network/ifcfg-$interfaz" <<EOF
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$ip_Servidor'
NETMASK='$mascara'
EOF

    echo "Reiniciando servicio DHCP..."
    reiniciar_servicio dhcpd
    habilitar_servicio dhcpd

    if verificar_servicio dhcpd; then
        echo "Servidor DHCP configurado y funcionando correctamente"
        systemctl status dhcpd --no-pager
    else
        echo "Error al iniciar el servicio DHCP"
        echo "Ejecute: journalctl -xeu dhcpd.service"
    fi
}

monitorear_dhcp() {
    local archivo_leases="/var/lib/dhcp/db/dhcpd.leases"
    local opc=""

    if [ ! -f "$archivo_leases" ]; then
        echo "Error: No se encontro el archivo de leases"
        echo "Asegurate de que el servidor DHCP este funcionando"
        return 1
    fi

    if ! verificar_servicio dhcpd; then
        echo "El servicio DHCP no esta activo"
        read -p "Desea iniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            iniciar_servicio dhcpd
        else
            return 1
        fi
    fi

    echo ""
    echo "========== MONITOREO DE CLIENTES DHCP =========="
    echo ""
    echo "Seleccione una opcion:"
    echo "  1. Ver todos los leases"
    echo "  2. Ver solo leases activos"
    echo "  3. Monitoreo en tiempo real"
    echo "  4. Ver estadisticas del servidor"
    echo "  5. Exportar reporte a archivo"
    read -p "Opcion: " opc

    case $opc in
        1)
            echo ""
            echo "=== TODOS LOS LEASES ==="
            echo ""
            cat "$archivo_leases"
            ;;
        2)
            echo ""
            echo "=== LEASES ACTIVOS ==="
            echo ""
            printf "%-20s %-20s %-20s %s\n" "IP Address" "MAC Address" "Hostname" "Expira"
            echo "-------------------------------------------------------------------------------------"
            awk '
            /^lease/ {ip=$2; active=0; host=""}
            /hardware ethernet/ {mac=$3; gsub(";","",mac)}
            /client-hostname/ {host=$2; gsub(/[";]/,"",host)}
            /binding state active/ {active=1}
            /ends/ {
                if (active) {
                    expires=$3" "$4
                    gsub(";","",expires)
                    printf "%-20s %-20s %-20s %s\n", ip, mac, host, expires
                }
            }
            ' "$archivo_leases" | sort -u
            ;;
        3)
            echo ""
            echo "=== MONITOREO EN TIEMPO REAL (Ctrl+C para salir) ==="
            echo ""
            tail -f "$archivo_leases"
            ;;
        4)
            echo ""
            echo "=== ESTADISTICAS DEL SERVIDOR ==="
            echo ""
            local total=$(grep -c "^lease" "$archivo_leases")
            local activos=$(grep -c "binding state active" "$archivo_leases")
            echo "Total de leases registrados: $total"
            echo "Leases activos: $activos"
            echo ""
            echo "Estado del servicio:"
            systemctl status dhcpd --no-pager
            ;;
        5)
            local archivo_salida="reporte_dhcp_$(date +%Y%m%d_%H%M%S).txt"
            echo ""
            echo "=== GENERANDO REPORTE ==="
            echo ""
            {
                echo "REPORTE DHCP - $(date)"
                echo "================================"
                echo ""
                echo "CLIENTES ACTIVOS:"
                printf "%-20s %-20s %-20s %s\n" "IP Address" "MAC Address" "Hostname" "Expira"
                echo "-------------------------------------------------------------------------------------"
                awk '
                /^lease/ {ip=$2; active=0; host=""}
                /hardware ethernet/ {mac=$3; gsub(";","",mac)}
                /client-hostname/ {host=$2; gsub(/[";]/,"",host)}
                /binding state active/ {active=1}
                /ends/ {
                    if (active) {
                        expires=$3" "$4
                        gsub(";","",expires)
                        printf "%-20s %-20s %-20s %s\n", ip, mac, host, expires
                    }
                }
                ' "$archivo_leases" | sort -u
                echo ""
                echo "================================"
                echo "ESTADISTICAS:"
                echo "Total leases: $(grep -c "^lease" "$archivo_leases")"
                echo "Leases activos: $(grep -c "binding state active" "$archivo_leases")"
            } > "$archivo_salida"
            echo "Reporte guardado en: $archivo_salida"
            cat "$archivo_salida"
            ;;
        *)
            echo "Opcion invalida"
            ;;
    esac

    echo ""
    echo "==============================================="
    echo ""
}

reiniciar_dhcp() {
    echo "Reiniciando servidor DHCP..."
    if ! verificar_servicio dhcpd; then
        echo "El servicio DHCP no esta activo"
        read -p "Desea iniciarlo en lugar de reiniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            iniciar_servicio dhcpd
        else
            return 1
        fi
    else
        reiniciar_servicio dhcpd
    fi
}

ver_estado_dhcp() {
    echo "=== ESTADO DEL SERVIDOR DHCP ==="
    echo ""
    estado_servicio dhcpd
}

ver_configuracion_dhcp() {
    local config_file="/etc/dhcpd.conf"
    local sysconfig="/etc/sysconfig/dhcpd"

    if [ ! -f "$config_file" ]; then
        echo "No se encontro el archivo de configuracion"
        echo "Parece que el servidor DHCP no esta configurado aun"
        return 1
    fi

    echo ""
    echo "========== CONFIGURACION ACTUAL DEL SERVIDOR DHCP =========="
    echo ""
    echo "Archivo de configuracion principal: $config_file"
    echo "-----------------------------------------------------------"
    cat "$config_file"
    echo "-----------------------------------------------------------"
    echo ""

    if [ -f "$sysconfig" ]; then
        echo "Interfaz configurada:"
        cat "$sysconfig"
        echo ""
    fi

    echo "Estado del servicio:"
    estado_servicio dhcpd | head -n 5

    echo ""
    echo "============================================================"
    echo ""
}
