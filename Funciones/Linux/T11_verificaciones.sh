#!/bin/bash

verificar_docker_compose() {
    print_info "[INFO] Verificando Docker Compose..."
    if docker compose version &>/dev/null; then
        print_completado "[OK] Docker Compose disponible: $(docker compose version --short 2>/dev/null)"
        return
    fi
    print_info "[INFO] Instalando docker-compose-plugin..."
    if sudo zypper install -y docker-compose-plugin &>/dev/null; then
        print_completado "[OK] Docker Compose instalado"
    else
        print_error "[ERROR] No se pudo instalar Docker Compose"
        exit 1
    fi
}

verificar_dependencias() {
    print_titulo "Verificando dependencias"
    verificar_docker
    verificar_servicio_docker
    verificar_grupo_docker
    verificar_docker_compose
}
