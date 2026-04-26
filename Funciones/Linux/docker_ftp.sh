#!/bin/bash

iniciar_ftp() {
    print_info "[INFO] Verificando contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_completado "[OK] Contenedor ftp_server ya está corriendo"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_info "[INFO] Contenedor ftp_server detenido, iniciando..."
        docker start ftp_server &>/dev/null
    else
        print_info "[INFO] Creando contenedor ftp_server..."
        HOST_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
        docker run -d \
            --name ftp_server \
            --network infra_red \
            --volume web_content:/ftp/$FTP_USER \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -p 21:21 \
            -p 40000-40009:40000-40009 \
            -e USERS="$FTP_USER|$FTP_PASS|/ftp/$FTP_USER" \
            -e ADDRESS="$HOST_IP" \
            -e MIN_PORT=40000 \
            -e MAX_PORT=40009 \
            delfer/alpine-ftp-server &>/dev/null
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor ftp_server iniciado"
    else
        print_error "[ERROR] No se pudo iniciar el contenedor ftp_server"
        exit 1
    fi
}

detener_ftp() {
    print_info "[INFO] Deteniendo contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker stop ftp_server &>/dev/null
        print_completado "[OK] Contenedor ftp_server detenido"
    else
        print_info "[INFO] Contenedor ftp_server no esta corriendo"
    fi
}

eliminar_ftp() {
    detener_ftp
    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker rm ftp_server &>/dev/null
        print_completado "[OK] Contenedor ftp_server eliminado"
    fi
}
