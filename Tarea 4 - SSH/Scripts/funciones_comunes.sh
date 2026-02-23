#!/bin/bash

verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Este script debe ejecutarse como root"
        exit 1
    fi
}

instalar_paquete() {
    local paquete="$1"
    echo "Instalando $paquete..."
    if zypper install -y "$paquete" &>/dev/null; then
        echo "Paquete $paquete instalado correctamente"
        return 0
    else
        echo "Error al instalar $paquete"
        return 1
    fi
}

paquete_instalado() {
    rpm -q "$1" &>/dev/null
}

servicio_activo() {
    systemctl is-active --quiet "$1"
}

habilitar_servicio() {
    local servicio="$1"
    echo "Habilitando servicio $servicio..."
    if systemctl enable "$servicio" 2>/dev/null; then
        echo "Servicio $servicio habilitado"
        return 0
    else
        echo "No se pudo habilitar el servicio $servicio"
        return 1
    fi
}

iniciar_servicio() {
    local servicio="$1"
    echo "Iniciando servicio $servicio..."
    if systemctl start "$servicio" 2>/dev/null; then
        echo "Servicio $servicio iniciado"
        return 0
    else
        echo "Error al iniciar el servicio $servicio"
        return 1
    fi
}

reiniciar_servicio() {
    local servicio="$1"
    echo "Reiniciando servicio $servicio..."
    if systemctl restart "$servicio" 2>/dev/null; then
        echo "Servicio $servicio reiniciado correctamente"
        return 0
    else
        echo "Error al reiniciar el servicio $servicio"
        return 1
    fi
}

estado_servicio() {
    systemctl status "$1" --no-pager
}

abrir_puerto_firewall() {
    local servicio_fw="$1"
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-service="$servicio_fw" --permanent 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        echo "Puerto abierto en firewall para $servicio_fw"
    else
        echo "firewalld no encontrado, configure el firewall manualmente"
    fi
}

validar_IP() {
    local ip="$1"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos"
        return 1
    fi

    IFS='.' read -r a b c d <<< "$ip"

    if [[ "$a" -eq 0 || "$d" -eq 0 ]]; then
        echo "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0"
        return 1
    fi

    for octeto in $a $b $c $d; do
        if [[ "$octeto" =~ ^0[0-9]+ ]]; then
            echo "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0"
            return 1
        fi
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            echo "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0"
            return 1
        fi
    done

    if [[ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255" ]]; then
        echo "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255"
        return 1
    fi

    if [[ "$a" -eq 127 ]]; then
        echo "Direccion IP invalida, rango 127.x.x.x reservado para host local"
        return 1
    fi

    if [[ "$a" -ge 224 && "$a" -le 239 ]]; then
        echo "Direccion IP invalida, rango 224-239 reservado para multicast"
        return 1
    fi

    if [[ "$a" -ge 240 && "$a" -lt 255 ]]; then
        echo "Direccion IP invalida, rango 240-254 reservado para usos experimentales"
        return 1
    fi

    return 0
}

validar_Mascara() {
    local masc="$1"

    if ! [[ "$masc" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Mascara invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos"
        return 1
    fi

    IFS='.' read -r a b c d <<< "$masc"

    if [ "$a" -eq 0 ]; then
        echo "Mascara invalida, no puede ser 0.X.X.X"
        return 1
    fi

    for octeto in $a $b $c $d; do
        if [[ "$octeto" =~ ^0[0-9]+ ]]; then
            echo "Mascara invalida, no se pueden poner 0 a la izquierda a menos que sea 0"
            return 1
        fi
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            echo "Mascara invalida, no puede ser mayor a 255 ni menor a 0"
            return 1
        fi
    done

    if [ "$a" -lt 255 ]; then
        for octeto in $b $c $d; do
            if [ "$octeto" -gt 0 ]; then
                echo "Mascara invalida, ocupas acabar los bits del primer octeto (255.X.X.X)"
                return 1
            fi
        done
    elif [ "$b" -lt 255 ]; then
        for octeto in $c $d; do
            if [ "$octeto" -gt 0 ]; then
                echo "Mascara invalida, ocupas acabar los bits del segundo octeto (255.255.X.X)"
                return 1
            fi
        done
    elif [ "$c" -lt 255 ]; then
        if [ "$d" -gt 0 ]; then
            echo "Mascara invalida, ocupas acabar los bits del tercer octeto (255.255.255.X)"
            return 1
        fi
    elif [ "$d" -gt 252 ]; then
        echo "Mascara invalida, no puede superar 255.255.255.252"
        return 1
    fi

    return 0
}

validate_domain() {
    local domain="$1"
    local domain_regex='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    if [[ ! $domain =~ $domain_regex ]]; then
        echo "Formato de dominio invalido: $domain"
        return 1
    fi
    return 0
}

configurar_ip_estatica() {
    echo "=== Verificacion de IP Estatica ==="

    local interfaz=$(ip route | grep default | awk '{print $5}' | head -1)

    if [[ -z "$interfaz" ]]; then
        echo "No se pudo detectar una interfaz de red activa"
        read -rp "Ingrese el nombre de la interfaz (ej: eth0, ens33): " interfaz
        if ! ip link show "$interfaz" &>/dev/null; then
            echo "La interfaz $interfaz no existe"
            return 1
        fi
    fi

    echo "Interfaz detectada: $interfaz"
    local ifcfg="/etc/sysconfig/network/ifcfg-$interfaz"

    if [[ ! -f "$ifcfg" ]]; then
        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')

        if [[ -z "$IP_ACTUAL" ]]; then
            echo "No se pudo detectar IP actual"
            read -rp "Ingrese la IP fija deseada: " server_ip
            validar_IP "$server_ip" || return 1
            read -rp "Ingrese el Gateway: " GATEWAY
            validar_IP "$GATEWAY" || return 1
        else
            echo "IP actual: $IP_ACTUAL (DHCP) | Gateway: $GATEWAY"
            read -rp "Usar estos valores como IP fija? [S/n]: " respuesta
            if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
                server_ip=$IP_ACTUAL
            else
                read -rp "Ingrese la IP fija deseada: " server_ip
                validar_IP "$server_ip" || return 1
                read -rp "Ingrese el Gateway: " GATEWAY
                validar_IP "$GATEWAY" || return 1
            fi
        fi

        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF

        echo "Aplicando configuracion de red..."
        wicked ifdown "$interfaz" &>/dev/null
        wicked ifup "$interfaz" &>/dev/null
        sleep 2

        ping -c 1 "$GATEWAY" &>/dev/null && echo "Conectividad verificada con el gateway" || echo "No se pudo hacer ping al gateway"
        echo "IP estatica configurada: $server_ip"
        export server_ip
        return 0
    fi

    if grep -q "BOOTPROTO=['\"]static['\"]" "$ifcfg" || grep -q "BOOTPROTO=static" "$ifcfg"; then
        local ip_raw=$(grep "IPADDR=" "$ifcfg" | cut -d= -f2 | tr -d "'\"")
        server_ip=${ip_raw%/*}
        echo "IP estatica ya configurada: $server_ip"
        local gw=$(grep "GATEWAY=" "$ifcfg" | cut -d= -f2 | tr -d "'\"" 2>/dev/null)
        [[ -n "$gw" ]] && echo "Gateway: $gw"
        export server_ip
        return 0
    else
        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')
        echo "Configuracion DHCP detectada | IP actual: $IP_ACTUAL | Gateway: $GATEWAY"

        read -rp "Desea configurar IP estatica? [S/n]: " respuesta
        if [[ "$respuesta" =~ ^[Nn]$ ]]; then
            echo "ADVERTENCIA: Se mantendra DHCP. El servidor necesita IP estatica para funcionar correctamente"
            server_ip=$IP_ACTUAL
            export server_ip
            return 0
        fi

        read -rp "Usar estos valores como IP fija? [S/n]: " respuesta
        if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
            server_ip=$IP_ACTUAL
            GW=$GATEWAY
        else
            read -rp "Ingrese la IP fija deseada: " server_ip
            validar_IP "$server_ip" || return 1
            read -rp "Ingrese el Gateway: " GW
            validar_IP "$GW" || return 1
            GATEWAY=$GW
        fi

        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF

        echo "Aplicando configuracion de red..."
        wicked ifdown "$interfaz" &>/dev/null
        sleep 1
        wicked ifup "$interfaz" &>/dev/null
        sleep 2

        ping -c 1 "$GATEWAY" &>/dev/null && echo "Conectividad verificada con el gateway" || echo "No se pudo hacer ping al gateway"
        echo "IP estatica configurada: $server_ip"
        export server_ip
    fi
}
