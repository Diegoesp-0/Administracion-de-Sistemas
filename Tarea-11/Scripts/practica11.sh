#!/bin/bash

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCIONES="$MAIN_DIR/../../Funciones/Linux"
COMPOSE_DIR="$MAIN_DIR"

source "$FUNCIONES/colores.sh"
source "$FUNCIONES/docker_install.sh"
source "$FUNCIONES/T11_verificaciones.sh"
source "$FUNCIONES/T11_infraestructura.sh"
source "$FUNCIONES/T11_firewall.sh"
source "$FUNCIONES/T11_stack.sh"

instalar() {
    print_titulo "Tarea 11 - Instalacion completa"
    verificar_dependencias
    crear_infraestructura "$COMPOSE_DIR"
    configurar_firewall_t11
    levantar_stack "$COMPOSE_DIR"
    print_titulo "Instalacion finalizada"
    estado_stack "$COMPOSE_DIR"
}

verificar() {
    estado_stack "$COMPOSE_DIR"
}

detener() {
    print_titulo "Deteniendo stack"
    detener_stack "$COMPOSE_DIR"
}

iniciar() {
    print_titulo "Iniciando stack"
    levantar_stack "$COMPOSE_DIR"
}

resetear() {
    print_titulo "Reseteo completo"
    print_info "[INFO] Esto eliminara contenedores, redes y volumenes de datos"
    read -p "  Estas seguro? (s/N): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        resetear_stack "$COMPOSE_DIR"
    else
        print_info "[INFO] Operacion cancelada"
    fi
}

ayuda() {
    print_titulo "Tarea 11 - Orquestacion de Microservicios"
    echo -e "  ${verde}-i${nc}   Instalar dependencias, generar archivos y levantar el stack"
    echo -e "  ${verde}-v${nc}   Verificar estado de contenedores y redes"
    echo -e "  ${verde}-s${nc}   Detener el stack (conserva datos)"
    echo -e "  ${verde}-u${nc}   Iniciar stack previamente detenido"
    echo -e "  ${verde}-r${nc}   Resetear todo (elimina contenedores y volumenes)"
    echo -e "  ${verde}-h${nc}   Mostrar esta ayuda"
    echo ""
    echo -e "  ${azul}Servicios desplegados:${nc}"
    echo -e "    nginx      Puerto 80  - Balanceador / punto de entrada publico"
    echo -e "    app_interna           - Apache httpd (solo via nginx)"
    echo -e "    postgresql            - Base de datos (red interna)"
    echo -e "    pgadmin  localhost:5050 - Panel admin (solo via tunel SSH)"
    echo ""
    echo -e "  ${azul}Acceso a pgAdmin:${nc}"
    echo -e "    ssh -L 8080:localhost:5050 usuario@ip_servidor"
    echo -e "    Luego abrir http://localhost:8080 en el navegador"
    echo ""
}

if [ $# -eq 0 ]; then
    ayuda
    exit 0
fi

while getopts "ivsurh" opt; do
    case $opt in
        i) instalar ;;
        v) verificar ;;
        s) detener ;;
        u) iniciar ;;
        r) resetear ;;
        h) ayuda ;;
        *) print_error "[ERROR] Opcion invalida. Usa -h para ver la ayuda" ; exit 1 ;;
    esac
done
