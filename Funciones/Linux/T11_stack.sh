#!/bin/bash

levantar_stack() {
    local dir="$1"
    print_titulo "Levantando stack de microservicios"

    if [ ! -f "$dir/docker-compose.yml" ]; then
        print_error "[ERROR] No se encontro docker-compose.yml en $dir"
        exit 1
    fi

    if [ ! -f "$dir/.env" ]; then
        print_error "[ERROR] No se encontro .env en $dir"
        exit 1
    fi

    print_info "[INFO] Descargando imagenes y levantando contenedores..."
    docker compose -f "$dir/docker-compose.yml" --env-file "$dir/.env" up -d

    if [ $? -eq 0 ]; then
        print_completado "[OK] Stack levantado"
        print_info "[INFO] Esperando healthcheck de PostgreSQL..."
        local intentos=0
        until docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null | grep -q "healthy"; do
            sleep 5
            intentos=$((intentos + 1))
            if [ "$intentos" -ge 12 ]; then
                print_error "[ERROR] PostgreSQL no alcanzo estado healthy en 60s"
                exit 1
            fi
            print_info "[INFO] Esperando... ($((intentos * 5))s)"
        done
        print_completado "[OK] PostgreSQL healthy - todos los servicios listos"
    else
        print_error "[ERROR] Fallo al levantar el stack"
        exit 1
    fi
}

estado_stack() {
    local dir="$1"
    print_titulo "Estado del stack"
    docker compose -f "$dir/docker-compose.yml" ps
    echo ""
    print_info "[INFO] Redes activas:"
    docker network ls | grep t11
    echo ""
    print_info "[INFO] Volumen de datos:"
    docker volume ls | grep t11
    echo ""
    print_info "[INFO] Para acceder a pgAdmin via tunel SSH:"
    print_info "       ssh -L 8080:localhost:5050 usuario@ip_servidor"
    print_info "       Luego abrir: http://localhost:8080"
}

detener_stack() {
    local dir="$1"
    print_info "[INFO] Deteniendo stack (los datos se conservan)..."
    docker compose -f "$dir/docker-compose.yml" down
    print_completado "[OK] Stack detenido"
}

resetear_stack() {
    local dir="$1"
    print_info "[INFO] Eliminando contenedores y volumenes..."
    docker compose -f "$dir/docker-compose.yml" down -v
    print_completado "[OK] Stack y volumenes eliminados"
}
