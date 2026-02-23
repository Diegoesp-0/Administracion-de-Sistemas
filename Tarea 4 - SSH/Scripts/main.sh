#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/funciones_comunes.sh"
source "$SCRIPT_DIR/dhcp.sh"
source "$SCRIPT_DIR/dns.sh"

verificar_root

menu_dhcp() {
    while true; do
        echo ""
        echo "============================================"
        echo "         Gestion del Servidor DHCP"
        echo "============================================"
        echo ""
        echo "  1) Verificar instalacion"
        echo "  2) Instalar y configurar"
        echo "  3) Configurar (reconfigurar)"
        echo "  4) Monitorear clientes"
        echo "  5) Ver configuracion actual"
        echo "  6) Estado del servicio"
        echo "  7) Reiniciar servicio"
        echo "  0) Volver al menu principal"
        echo ""
        read -p "Opcion: " opcion

        case $opcion in
            1) verificar_dhcp ;;
            2) instalar_dhcp ;;
            3) configurar_dhcp ;;
            4) monitorear_dhcp ;;
            5) ver_configuracion_dhcp ;;
            6) ver_estado_dhcp ;;
            7) reiniciar_dhcp ;;
            0) break ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu_dns() {
    while true; do
        echo ""
        echo "============================================"
        echo "         Gestion del Servidor DNS"
        echo "============================================"
        echo ""
        echo "  1) Verificar instalacion"
        echo "  2) Instalar y configurar"
        echo "  3) Gestionar dominios"
        echo "  4) Reiniciar servicio"
        echo "  0) Volver al menu principal"
        echo ""
        read -p "Opcion: " opcion

        case $opcion in
            1) verificar_dns ;;
            2) instalar_dns ;;
            3) monitorear_dns ;;
            4) reiniciar_dns ;;
            0) break ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu_principal() {
    while true; do
        echo ""
        echo "============================================"
        echo "    Administracion de Servicios de Red"
        echo "============================================"
        echo ""
        echo "  1) Gestion DHCP"
        echo "  2) Gestion DNS"
        echo "  0) Salir"
        echo ""
        read -p "Opcion: " opcion

        case $opcion in
            1) menu_dhcp ;;
            2) menu_dns ;;
            0)
                echo "Saliendo..."
                exit 0
                ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu_principal
