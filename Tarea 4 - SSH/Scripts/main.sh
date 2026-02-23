#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/funciones_comunes.sh"
source "$SCRIPT_DIR/DHCP.sh"
source "$SCRIPT_DIR/DNS.sh"

verificar_root

menu_dhcp() {
    while true; do
        echo ""
        echo "============================================================"
        echo "                     Menu DHCP"
        echo "============================================================"
        echo ""
        echo "  1) Verificar instalacion"
        echo "  2) Instalar DHCP"
        echo "  3) Configurar DHCP"
        echo "  4) Monitorear clientes"
        echo "  5) Reiniciar servidor"
        echo "  6) Ver estado"
        echo "  7) Ver configuracion actual"
        echo "  0) Volver al menu principal"
        echo ""
        read -rp "Opcion: " opcion

        case $opcion in
            1) verificar_dhcp ;;
            2) instalar_DHCP ;;
            3) configurar_DHCP ;;
            4) monitorear_Clientes ;;
            5) reiniciar_DHCP ;;
            6) ver_Estado_DHCP ;;
            7) ver_Configuracion_DHCP ;;
            0) break ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu_dns() {
    while true; do
        echo ""
        echo "============================================================"
        echo "                     Menu DNS"
        echo "============================================================"
        echo ""
        echo "  1) Verificar instalacion"
        echo "  2) Instalar BIND9"
        echo "  3) Administrar dominios"
        echo "  4) Reiniciar servidor"
        echo "  0) Volver al menu principal"
        echo ""
        read -rp "Opcion: " opcion

        case $opcion in
            1) verificar_DNS ;;
            2) instalar_DNS ;;
            3) monitoreo_DNS ;;
            4) reiniciar_DNS ;;
            0) break ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

while true; do
    echo ""
    echo "============================================================"
    echo "         Administracion de Servidor - openSUSE"
    echo "============================================================"
    echo ""
    echo "  1) Gestion DHCP"
    echo "  2) Gestion DNS"
    echo "  0) Salir"
    echo ""
    read -rp "Opcion: " opcion

    case $opcion in
        1) menu_dhcp ;;
        2) menu_dns ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done
