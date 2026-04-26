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
        HOST_IP=$(ip -4 addr show "$(ip route show default | head -1 | awk '{print $5}')" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        docker run -d \
            --name ftp_server \
            --network infra_red \
            --volume web_content:/home/vsftpd/$FTP_USER \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            --security-opt seccomp:unconfined \
            -p 21:21 \
            -p 21100-21110:21100-21110 \
            -e FTP_USER="$FTP_USER" \
            -e FTP_PASS="$FTP_PASS" \
            -e PASV_ADDRESS="$HOST_IP" \
            -e PASV_MIN_PORT=21100 \
            -e PASV_MAX_PORT=21110 \
            -e LOCAL_UMASK=022 \
            -e LOG_STDOUT=YES \
            fauria/vsftpd &>/dev/null
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
