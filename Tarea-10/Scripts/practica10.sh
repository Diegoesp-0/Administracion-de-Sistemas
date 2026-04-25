#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCIONES="$SCRIPT_DIR/../../Funciones/Linux"

source "$FUNCIONES/colores.sh"
source "$FUNCIONES/docker_install.sh"
source "$FUNCIONES/docker_network.sh"
source "$FUNCIONES/docker_volumenes.sh"
source "$FUNCIONES/docker_web.sh"
source "$FUNCIONES/docker_db.sh"
source "$FUNCIONES/docker_ftp.sh"

pedir_credenciales() {
    print_titulo "Configuracion de credenciales"

    read -p "  Usuario PostgreSQL [admin]: " PG_USER
    PG_USER="${PG_USER:-admin}"

    read -s -p "  Contraseña PostgreSQL: " PG_PASS
    echo ""

    read -p "  Nombre base de datos [tarea10]: " PG_DB
    PG_DB="${PG_DB:-tarea10}"

    read -p "  Usuario FTP [ftpuser]: " FTP_USER
    FTP_USER="${FTP_USER:-ftpuser}"

    read -s -p "  Contraseña FTP: " FTP_PASS
    echo ""

    export PG_USER PG_PASS PG_DB FTP_USER FTP_PASS
}

instalar() {
    print_titulo "Instalacion completa"
    pedir_credenciales
    instalar_docker
    crear_red
    crear_volumenes
    construir_imagen_web
    iniciar_web
    iniciar_db
    iniciar_ftp
    print_titulo "Instalacion finalizada"
    verificar
}

verificar() {
    print_titulo "Estado de contenedores"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    print_titulo "Uso de recursos"
    docker stats --no-stream
}

detener() {
    print_titulo "Deteniendo servicios"
    detener_ftp
    detener_web
    detener_db
    print_completado "[OK] Todos los servicios detenidos"
}

iniciar() {
    print_titulo "Iniciando servicios"
    iniciar_web
    iniciar_db
    iniciar_ftp
    print_completado "[OK] Todos los servicios iniciados"
}

resetear() {
    print_titulo "Reseteo completo"
    print_info "[INFO] Esto eliminará contenedores, red y volúmenes"
    read -p "  ¿Estás seguro? (s/N): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        eliminar_ftp
        eliminar_web
        eliminar_db
        eliminar_red
        eliminar_volumenes
        print_completado "[OK] Reset completado"
    else
        print_info "[INFO] Operación cancelada"
    fi
}

ayuda() {
    print_titulo "Tarea 10 - Infraestructura con Docker"
    echo -e "  ${verde}-i${nc}   Instalar y levantar todos los servicios"
    echo -e "  ${verde}-v${nc}   Verificar estado de contenedores y recursos"
    echo -e "  ${verde}-s${nc}   Detener todos los contenedores"
    echo -e "  ${verde}-u${nc}   Iniciar contenedores detenidos"
    echo -e "  ${verde}-r${nc}   Resetear todo (elimina contenedores y volúmenes)"
    echo -e "  ${verde}-h${nc}   Mostrar esta ayuda"
    echo ""
}

if [ $# -eq 0 ]; then
    ayuda
    exit 0
fi

while getopts "ivsuhr" opt; do
    case $opt in
        i) instalar ;;
        v) verificar ;;
        s) detener ;;
        u) iniciar ;;
        r) resetear ;;
        h) ayuda ;;
        *) print_error "[ERROR] Opción inválida. Usa -h para ver la ayuda" ; exit 1 ;;
    esac
done
