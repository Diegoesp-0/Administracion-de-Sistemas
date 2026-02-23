#!/bin/bash

verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Este script debe ejecutarse como root"
        exit 1
    fi
}

validar_IP() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! "$ip" =~ $regex ]]; then
        echo "IP invalida: $ip"
        return 1
    fi

    IFS='.' read -r a b c d <<< "$ip"
    for octeto in $a $b $c $d; do
        if [[ $octeto -lt 0 || $octeto -gt 255 ]]; then
            echo "IP invalida: $ip"
            return 1
        fi
    done
    return 0
}

validar_Mascara() {
    local masc="$1"
    local validos="0 128 192 224 240 248 252 254 255"

    if ! validar_IP "$masc"; then
        return 1
    fi

    IFS='.' read -r a b c d <<< "$masc"
    local octetos=($a $b $c $d)
    local encontro_no_255=0

    for octeto in "${octetos[@]}"; do
        if [[ $encontro_no_255 -eq 1 && $octeto -ne 0 ]]; then
            echo "Mascara invalida: $masc"
            return 1
        fi
        if [[ $octeto -ne 255 ]]; then
            encontro_no_255=1
            if [[ ! " $validos " =~ " $octeto " ]]; then
                echo "Mascara invalida: $masc"
                return 1
            fi
        fi
    done
    return 0
}

validate_domain() {
    local domain="$1"
    local regex='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

    if [[ ! "$domain" =~ $regex ]]; then
        echo "Dominio invalido: $domain"
        return 1
    fi
    return 0
}

instalar_paquete() {
    local paquete="$1"
    if rpm -q "$paquete" &>/dev/null; then
        echo "El paquete $paquete ya esta instalado"
        return 0
    fi
    echo "Instalando $paquete..."
    zypper --non-interactive --quiet install "$paquete" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Paquete $paquete instalado correctamente"
        return 0
    else
        echo "Error al instalar $paquete"
        return 1
    fi
}

verificar_servicio() {
    local servicio="$1"
    systemctl is-active --quiet "$servicio"
    return $?
}

iniciar_servicio() {
    local servicio="$1"
    if verificar_servicio "$servicio"; then
        echo "El servicio $servicio ya esta activo"
        return 0
    fi
    systemctl start "$servicio"
    if verificar_servicio "$servicio"; then
        echo "Servicio $servicio iniciado correctamente"
        return 0
    else
        echo "Error al iniciar $servicio"
        return 1
    fi
}

reiniciar_servicio() {
    local servicio="$1"
    systemctl restart "$servicio"
    if verificar_servicio "$servicio"; then
        echo "Servicio $servicio reiniciado correctamente"
        return 0
    else
        echo "Error al reiniciar $servicio"
        return 1
    fi
}

habilitar_servicio() {
    local servicio="$1"
    systemctl enable "$servicio" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "Servicio $servicio habilitado en el arranque"
        return 0
    else
        echo "Error al habilitar $servicio"
        return 1
    fi
}

estado_servicio() {
    local servicio="$1"
    systemctl status "$servicio" --no-pager
}
