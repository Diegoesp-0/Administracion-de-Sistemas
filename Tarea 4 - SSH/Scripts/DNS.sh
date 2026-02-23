#!/bin/bash

named_conf="/etc/named.conf"
zones_dir="/var/lib/named"

verificar_DNS() {
    echo "Verificando instalacion de BIND9..."

    if paquete_instalado bind; then
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        echo "BIND9 ya esta instalado (version: $version)"
        return 0
    fi

    if command -v named &>/dev/null; then
        echo "BIND9 encontrado: $(named -v 2>&1 | head -1)"
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
        echo "Servicio named encontrado en systemd"
        return 0
    fi

    echo "BIND9 no esta instalado"
    return 1
}

instalar_DNS() {
    configurar_ip_estatica || {
        echo "No se pudo configurar la IP estatica"
        return 1
    }

    echo ""
    echo "=== Instalacion de BIND9 ==="

    if verificar_DNS; then
        read -rp "Desea reconfigurar el servidor DNS? [s/N]: " reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            echo "Operacion cancelada"
            return 0
        fi
    else
        echo "Instalando BIND9 y utilidades..."
        echo "Actualizando repositorios..."
        zypper refresh &>/dev/null

        instalar_paquete bind || return 1

        if zypper install -y bind-utils &>/dev/null; then
            echo "Paquete bind-utils instalado correctamente"
        else
            echo "Error al instalar bind-utils (no critico)"
        fi
    fi

    if [[ ! -d "$zones_dir" ]]; then
        mkdir -p "$zones_dir"
        echo "Directorio de zonas creado: $zones_dir"
    fi

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

    if ! named-checkconf "$named_conf" 2>/dev/null; then
        echo "Error en la sintaxis de named.conf"
        return 1
    fi

    echo "Archivo named.conf generado correctamente"

    habilitar_servicio named || return 1

    if servicio_activo named; then
        echo "Servicio ya estaba activo, reiniciando..."
        reiniciar_servicio named || return 1
    else
        if ! iniciar_servicio named; then
            echo "Revise los logs: journalctl -u named"
            return 1
        fi
    fi

    abrir_puerto_firewall dns

    echo ""
    echo "Verificando estado del servidor DNS..."
    echo ""

    if servicio_activo named; then
        echo "Servicio named: activo y corriendo"
    else
        echo "Servicio named: NO esta corriendo"
        return 1
    fi

    ss -tulnp 2>/dev/null | grep -q ":53 " && echo "Puerto 53: escuchando" || echo "Puerto 53: NO esta escuchando"
    named-checkconf "$named_conf" 2>/dev/null && echo "Configuracion: sintaxis correcta" || echo "Configuracion: hay errores de sintaxis"

    echo ""
    echo "BIND9 instalado y configurado correctamente"
    echo "IP del servidor DNS: $server_ip"
    echo "Configure su DHCP con DNS: $server_ip"
}

reiniciar_DNS() {
    echo "Reiniciando servidor DNS..."

    if reiniciar_servicio named; then
        servicio_activo named && echo "Servicio named: activo" || echo "El servicio no quedo activo despues del reinicio"
    else
        echo "Revise los logs: journalctl -u named"
        return 1
    fi
}

agregar_dominio() {
    echo "=== Agregar Dominio ==="

    read -rp "Ingrese el nombre del dominio (ej: reprobados.com): " nuevo_dominio

    if ! validate_domain "$nuevo_dominio"; then
        echo "Dominio invalido, cancelando operacion"
        return 1
    fi

    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        echo "El dominio $nuevo_dominio ya esta configurado"
        return 1
    fi

    if [[ -n "$server_ip" ]]; then
        read -rp "Ingrese la IP para $nuevo_dominio [$server_ip]: " nueva_ip
    else
        read -rp "Ingrese la IP para $nuevo_dominio: " nueva_ip
    fi

    [[ -z "$nueva_ip" && -n "$server_ip" ]] && nueva_ip=$server_ip

    if ! validar_IP "$nueva_ip"; then
        echo "IP invalida, cancelando operacion"
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
    echo "Agregando zona a $named_conf..."

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
        echo "reload fallo, intentando restart..."
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

    read -rp "Ingrese el dominio a eliminar: " dominio_eliminar

    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        echo "El dominio $dominio_eliminar no existe en la configuracion"
        return 1
    fi

    echo ""
    read -rp "Esta seguro de eliminar el dominio $dominio_eliminar? [s/N]: " confirmacion

    if [[ ! "$confirmacion" =~ ^[Ss]$ ]]; then
        echo "Operacion cancelada por el usuario"
        return 0
    fi

    local zone_file="$zones_dir/${dominio_eliminar}.zone"

    echo "Eliminando entrada de named.conf..."
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
    else
        echo "Archivo de zona no encontrado: $zone_file"
    fi

    if systemctl reload named 2>/dev/null; then
        echo "Servicio recargado correctamente"
    else
        echo "reload fallo, intentando restart..."
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
    echo "──────────────────────────────────────────────────────────────"

    for dominio in "${dominios[@]}"; do
        local zone_file="$zones_dir/${dominio}.zone"
        local ip_dom="N/A"
        local estado="Sin archivo"

        if [[ -f "$zone_file" ]]; then
            ip_dom=$(grep "^@[[:space:]]*IN[[:space:]]*A" "$zone_file" 2>/dev/null | awk '{print $NF}')
            [[ -z "$ip_dom" ]] && ip_dom="N/A"
            estado="Activo"
        fi

        printf "%-30s %-20s %s\n" "$dominio" "$ip_dom" "$estado"
    done

    echo ""
    echo "Total de dominios: ${#dominios[@]}"
}

monitoreo_DNS() {
    while true; do
        echo ""
        echo "============================================================"
        echo "              Menu de Monitoreo DNS"
        echo "============================================================"
        echo ""
        echo "  1) Agregar dominio"
        echo "  2) Eliminar dominio"
        echo "  3) Listar dominios"
        echo "  0) Volver al menu principal"
        echo ""
        read -rp "Opcion: " opcion

        case $opcion in
            1) agregar_dominio ;;
            2) eliminar_dominio ;;
            3) listar_dominios ;;
            0) break ;;
            *) echo "Opcion invalida: $opcion" ;;
        esac
    done
}
