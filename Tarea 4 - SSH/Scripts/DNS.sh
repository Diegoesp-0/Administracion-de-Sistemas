#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/funciones_comunes.sh"

named_conf="/etc/named.conf"
zones_dir="/var/lib/named"

verificar_dns() {
    echo "Verificando instalacion de BIND9..."
    if rpm -q bind &>/dev/null; then
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        echo "BIND9 ya esta instalado (version: $version)"
        return 0
    fi
    echo "BIND9 no esta instalado"
    return 1
}

configurar_ip_estatica_dns() {
    local interfaz="enp0s8"

    if ! ip link show "$interfaz" &>/dev/null; then
        echo "La interfaz $interfaz no existe"
        echo "Interfaces disponibles:"
        ip -br link show | grep -v "lo" | awk '{print $1}'
        read -r interfaz
        if ! ip link show "$interfaz" &>/dev/null; then
            echo "Interfaz no valida"
            return 1
        fi
    fi

    echo "Interfaz detectada: $interfaz"
    local ifcfg="/etc/sysconfig/network/ifcfg-$interfaz"

    if grep -q "BOOTPROTO=['\"]static['\"]" "$ifcfg" 2>/dev/null || grep -q "BOOTPROTO=static" "$ifcfg" 2>/dev/null; then
        local ip_raw=$(grep "IPADDR=" "$ifcfg" | cut -d= -f2 | tr -d "'\"")
        server_ip=${ip_raw%/*}
        echo "IP estatica ya configurada: $server_ip"
        export server_ip
        return 0
    fi

    local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    local GATEWAY=$(ip route | grep default | awk '{print $3}')

    echo "IP actual: $IP_ACTUAL"
    echo "Gateway: $GATEWAY"

    read -p "Desea configurar IP estatica? [S/n]: " respuesta
    if [[ "$respuesta" =~ ^[Nn]$ ]]; then
        echo "Se mantendra la configuracion DHCP"
        server_ip=$IP_ACTUAL
        export server_ip
        return 0
    fi

    read -p "Usar IP actual $IP_ACTUAL como IP fija? [S/n]: " respuesta
    if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
        server_ip=$IP_ACTUAL
        GW=$GATEWAY
    else
        read -p "Ingrese la IP fija deseada: " server_ip
        validar_IP "$server_ip" || return 1
        read -p "Ingrese el Gateway: " GW
        validar_IP "$GW" || return 1
        GATEWAY=$GW
    fi

    cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF

    echo "Configuracion guardada en $ifcfg"
    wicked ifdown "$interfaz" &>/dev/null
    sleep 1
    wicked ifup "$interfaz" &>/dev/null
    sleep 2

    if ping -c 1 "$GATEWAY" &>/dev/null; then
        echo "Conectividad verificada con el gateway"
    else
        echo "No se pudo hacer ping al gateway, verifique la configuracion"
    fi

    echo "IP estatica configurada: $server_ip"
    export server_ip
}

instalar_dns() {
    configurar_ip_estatica_dns || {
        echo "No se pudo configurar la IP estatica"
        return 1
    }

    echo ""
    echo "=== Instalacion de BIND9 ==="

    if verificar_dns; then
        read -p "Desea reconfigurar el servidor DNS? [s/N]: " reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            echo "Operacion cancelada"
            return 0
        fi
    else
        instalar_paquete "bind" || return 1
        instalar_paquete "bind-utils"
    fi

    _configurar_named_conf
    habilitar_servicio named || return 1

    if verificar_servicio named; then
        reiniciar_servicio named || return 1
    else
        iniciar_servicio named || return 1
    fi

    _configurar_firewall_dns

    echo ""
    echo "BIND9 instalado y configurado correctamente"
    echo "IP del servidor DNS: $server_ip"
}

_configurar_named_conf() {
    [ ! -d "$zones_dir" ] && mkdir -p "$zones_dir"

    cat > "$named_conf" <<EOF
options {
    directory "$zones_dir";
    listen-on { any; };
    allow-query { any; };
    recursion no;
    forwarders { };
    allow-transfer { none; };
};

zone "localhost" {
    type master;
    file "localhost.zone";
};

zone "0.in-addr.arpa" {
    type master;
    file "0.in-addr.arpa.zone";
};

zone "127.in-addr.arpa" {
    type master;
    file "127.in-addr.arpa.zone";
};
EOF

    if named-checkconf "$named_conf" 2>/dev/null; then
        echo "Archivo named.conf generado correctamente"
        return 0
    else
        echo "Error en la sintaxis de named.conf"
        return 1
    fi
}

_configurar_firewall_dns() {
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-service=dns --permanent 2>/dev/null && echo "Puerto 53 abierto en firewall"
        firewall-cmd --reload 2>/dev/null && echo "Firewall recargado"
    else
        echo "firewalld no encontrado, configure el firewall manualmente (puerto 53 TCP/UDP)"
    fi
}

reiniciar_dns() {
    echo "Reiniciando servidor DNS..."
    reiniciar_servicio named
}

agregar_dominio() {
    echo "=== Agregar Dominio ==="

    read -p "Ingrese el nombre del dominio (ej: ejemplo.com): " nuevo_dominio

    if ! validate_domain "$nuevo_dominio"; then
        echo "Dominio invalido, cancelando"
        return 1
    fi

    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        echo "El dominio $nuevo_dominio ya esta configurado"
        return 1
    fi

    if [[ -n "$server_ip" ]]; then
        read -p "Ingrese la IP para $nuevo_dominio [$server_ip]: " nueva_ip
        [[ -z "$nueva_ip" ]] && nueva_ip=$server_ip
    else
        read -p "Ingrese la IP para $nuevo_dominio: " nueva_ip
    fi

    if ! validar_IP "$nueva_ip"; then
        echo "IP invalida, cancelando"
        return 1
    fi

    local zone_file="$zones_dir/${nuevo_dominio}.zone"
    local serial=$(date +%Y%m%d01)

    echo "Creando archivo de zona: $zone_file"

    cat > "$zone_file" <<EOF
\$TTL 86400
@   IN  SOA ns1.$nuevo_dominio. admin.$nuevo_dominio. (
            $serial ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

@           IN  NS      ns1.$nuevo_dominio.

@           IN  A       $nueva_ip
ns1         IN  A       $nueva_ip

www         IN  CNAME   $nuevo_dominio.
EOF

    if ! named-checkzone "$nuevo_dominio" "$zone_file" &>/dev/null; then
        echo "Error en la sintaxis del archivo de zona"
        rm -f "$zone_file"
        return 1
    fi

    echo "Archivo de zona creado correctamente"

    cat >> "$named_conf" <<EOF

zone "$nuevo_dominio" {
    type master;
    file "$zone_file";
};
EOF

    if ! named-checkconf "$named_conf" &>/dev/null; then
        echo "Error en la sintaxis de named.conf"
        return 1
    fi

    if systemctl reload named 2>/dev/null; then
        echo "Servicio recargado correctamente"
    else
        reiniciar_servicio named
    fi

    echo ""
    echo "Dominio $nuevo_dominio agregado exitosamente"
    echo "  IP configurada: $nueva_ip"
    echo "  Registro A: $nuevo_dominio -> $nueva_ip"
    echo "  Registro CNAME: www.$nuevo_dominio -> $nuevo_dominio"
    echo "  Archivo de zona: $zone_file"
}

eliminar_dominio() {
    echo "=== Eliminar Dominio ==="
    listar_dominios
    echo ""

    read -p "Ingrese el dominio a eliminar: " dominio_eliminar

    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        echo "El dominio $dominio_eliminar no existe en la configuracion"
        return 1
    fi

    read -p "Esta seguro de eliminar el dominio $dominio_eliminar? [s/N]: " confirmacion
    if [[ ! "$confirmacion" =~ ^[Ss]$ ]]; then
        echo "Operacion cancelada"
        return 0
    fi

    local zone_file="$zones_dir/${dominio_eliminar}.zone"

    sed -i "/zone \"$dominio_eliminar\"/,/^};/d" "$named_conf"

    if named-checkconf "$named_conf" 2>/dev/null; then
        echo "Entrada eliminada de named.conf"
    else
        echo "Error en named.conf despues de eliminar"
        return 1
    fi

    if [[ -f "$zone_file" ]]; then
        rm -f "$zone_file"
        echo "Archivo de zona eliminado"
    fi

    if systemctl reload named 2>/dev/null; then
        echo "Servicio recargado correctamente"
    else
        reiniciar_servicio named
    fi

    echo "Dominio $dominio_eliminar eliminado exitosamente"
}

listar_dominios() {
    echo "=== Dominios Configurados ==="

    if [[ ! -f "$named_conf" ]]; then
        echo "No se encontro el archivo $named_conf"
        return 1
    fi

    local dominios=($(grep "^zone " "$named_conf" | awk -F'"' '{print $2}' | grep -v "localhost\|0.in-addr\|127.in-addr"))

    if [[ ${#dominios[@]} -eq 0 ]]; then
        echo "No hay dominios configurados"
        return 0
    fi

    echo ""
    printf "%-30s %-20s %-15s\n" "DOMINIO" "IP CONFIGURADA" "ESTADO"
    echo "--------------------------------------------------------------"

    for dominio in "${dominios[@]}"; do
        local zone_file="$zones_dir/${dominio}.zone"
        local ip="N/A"
        local estado="Sin archivo"

        if [[ -f "$zone_file" ]]; then
            ip=$(grep "^@[[:space:]]*IN[[:space:]]*A" "$zone_file" 2>/dev/null | awk '{print $NF}')
            [[ -z "$ip" ]] && ip="N/A"
            estado="Activo"
        fi

        printf "%-30s %-20s %-15s\n" "$dominio" "$ip" "$estado"
    done

    echo ""
    echo "Total de dominios: ${#dominios[@]}"
}

monitorear_dns() {
    while true; do
        echo ""
        echo "============================================"
        echo "         Menu de Monitoreo DNS"
        echo "============================================"
        echo ""
        echo "  1) Agregar dominio"
        echo "  2) Eliminar dominio"
        echo "  3) Listar dominios"
        echo "  0) Salir"
        echo ""
        read -p "Opcion: " opcion

        case $opcion in
            1) agregar_dominio ;;
            2) eliminar_dominio ;;
            3) listar_dominios ;;
            0)
                echo "Saliendo del menu de monitoreo"
                break
                ;;
            *)
                echo "Opcion invalida: $opcion"
                ;;
        esac
    done
}
