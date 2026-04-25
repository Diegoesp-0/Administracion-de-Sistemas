#!/bin/bash

iniciar_db() {
    print_info "[INFO] Verificando contenedor db_server..."

    if docker ps --format '{{.Names}}' | grep -q "^db_server$"; then
        print_completado "[OK] Contenedor db_server ya está corriendo"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^db_server$"; then
        print_info "[INFO] Contenedor db_server detenido, iniciando..."
        docker start db_server &>/dev/null
    else
        print_info "[INFO] Creando contenedor db_server..."
        docker run -d \
            --name db_server \
            --network infra_red \
            --volume db_data:/var/lib/postgresql/data \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -e POSTGRES_USER="$PG_USER" \
            -e POSTGRES_PASSWORD="$PG_PASS" \
            -e POSTGRES_DB="$PG_DB" \
            postgres:16-alpine &>/dev/null
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor db_server iniciado"
    else
        print_error "[ERROR] No se pudo iniciar el contenedor db_server"
        exit 1
    fi
}

detener_db() {
    print_info "[INFO] Deteniendo contenedor db_server..."

    if docker ps --format '{{.Names}}' | grep -q "^db_server$"; then
        docker stop db_server &>/dev/null
        print_completado "[OK] Contenedor db_server detenido"
    else
        print_info "[INFO] Contenedor db_server no está corriendo"
    fi
}

eliminar_db() {
    detener_db
    if docker ps -a --format '{{.Names}}' | grep -q "^db_server$"; then
        docker rm db_server &>/dev/null
        print_completado "[OK] Contenedor db_server eliminado"
    fi
}
