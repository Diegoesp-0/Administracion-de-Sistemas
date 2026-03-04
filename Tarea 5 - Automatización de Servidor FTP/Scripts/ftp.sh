#!/bin/bash

print_info() { echo "[INFO] $1"; }
print_completado() { echo "[OK] $1"; }
print_error() { echo "[ERROR] $1"; }
print_titulo() { echo ""; echo "=== $1 ==="; echo ""; }

readonly PAQUETE="vsftpd"
readonly VSFTPD_CONF="/etc/vsftpd.conf"
readonly FTP_ROOT="/srv/ftp"
readonly VSFTPD_USER_CONF_DIR="/etc/vsftpd/users"
readonly GRUPO_REPROBADOS="reprobados"
readonly GRUPO_RECURSADORES="recursadores"
readonly INTERFAZ_RED="enp0s9"

ayuda() {
    echo "Uso: $0 [opcion]"
    echo "  -v, --verify    Verificar vsftpd"
    echo "  -i, --install   Instalar y configurar FTP"
    echo "  -u, --users     Gestionar usuarios"
    echo "  -r, --restart   Reiniciar FTP"
    echo "  -s, --status    Estado del servidor"
    echo "  -l, --list      Listar estructura"
    echo "  -?, --help      Ayuda"
}

verificar_Instalacion() {
    print_info "Verificando instalacion de vsftpd"
    if rpm -q $PAQUETE &>/dev/null; then
        version=$(rpm -q $PAQUETE --queryformat '%{VERSION}')
        print_completado "vsftpd instalado (version: $version)"
        return 0
    fi
    if command -v vsftpd &>/dev/null; then
        version=$(vsftpd -v 2>&1 | head -1)
        print_completado "vsftpd encontrado: $version"
        return 0
    fi
    print_error "vsftpd no instalado"
    return 1
}

configurar_SELinux() {
    print_info "Verificando SELinux"
    if ! command -v getenforce &>/dev/null; then
        print_info "SELinux no presente"
        return 0
    fi
    estado=$(getenforce 2>/dev/null)
    print_info "Estado SELinux: $estado"
    if ! command -v semanage &>/dev/null && [ ! -f /usr/sbin/semanage ]; then
        zypper --non-interactive --quiet install policycoreutils-python-utils
    fi
    setsebool -P ftpd_full_access on 2>/dev/null && print_completado "Booleano activado"
    /usr/sbin/semanage fcontext -a -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null || \
    /usr/sbin/semanage fcontext -m -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null
    restorecon -Rv "$FTP_ROOT" 2>/dev/null
    print_completado "SELinux configurado"
}

configurar_PAM() {
    tee /etc/pam.d/ftp > /dev/null << 'EOF'
auth     required    pam_unix.so     shadow nullok
account  required    pam_unix.so
session  required    pam_unix.so
EOF
    if ! grep -q "^/sbin/nologin$" /etc/shells; then
        echo "/sbin/nologin" >> /etc/shells
    fi
    print_completado "PAM configurado"
}

crear_Estructura_Base() {
    dirs=("$FTP_ROOT" "$FTP_ROOT/general" "$FTP_ROOT/$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_RECURSADORES" "$FTP_ROOT/personal" "$FTP_ROOT/usuarios" "$VSFTPD_USER_CONF_DIR")
    for dir in "${dirs[@]}"; do
        [ ! -d "$dir" ] && mkdir -p "$dir"
    done
    chown root:root "$FTP_ROOT"
    chmod 755 "$FTP_ROOT"
    chown root:users "$FTP_ROOT/general"
    chmod 775 "$FTP_ROOT/general"
    chown root:"$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_REPROBADOS"
    chmod 775 "$FTP_ROOT/$GRUPO_REPROBADOS"
    chown root:"$GRUPO_RECURSADORES" "$FTP_ROOT/$GRUPO_RECURSADORES"
    chmod 775 "$FTP_ROOT/$GRUPO_RECURSADORES"
    chown root:root "$FTP_ROOT/personal"
    chmod 755 "$FTP_ROOT/personal"
    chown root:root "$FTP_ROOT/usuarios"
    chmod 755 "$FTP_ROOT/usuarios"
    print_completado "Estructura base creada"
}

crear_Grupos() {
    for grupo in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES"; do
        getent group "$grupo" &>/dev/null || groupadd "$grupo"
    done
    print_completado "Grupos listos"
}

configurar_Vsftpd() {
    [ -f "$VSFTPD_CONF" ] && cp "$VSFTPD_CONF" "${VSFTPD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$VSFTPD_USER_CONF_DIR"
    tee "$VSFTPD_CONF" > /dev/null << 'EOF'
listen=YES
listen_ipv6=NO
local_enable=YES
write_enable=YES
local_umask=022
chmod_enable=YES
session_support=YES
anonymous_enable=YES
anon_root=/srv/ftp/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=$USER
local_root=/srv/ftp/usuarios/$USER
user_config_dir=/etc/vsftpd/users
hide_ids=YES
use_localtime=YES
file_open_mode=0666
local_umask=022
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
connect_from_port_20=YES
idle_session_timeout=600
data_connection_timeout=120
ftpd_banner=Bienvenido al servidor FTP
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
EOF
    [ ! -f /etc/vsftpd.user_list ] && touch /etc/vsftpd.user_list
    for u in anonymous ftp; do
        grep -q "^$u$" /etc/vsftpd.user_list || echo "$u" >> /etc/vsftpd.user_list
    done
    id ftp &>/dev/null || useradd -r -d "$FTP_ROOT/general" -s /sbin/nologin ftp
    print_completado "vsftpd configurado"
}

crear_Carpeta_Personal_Real() {
    usuario="$1"
    grupo="$2"
    carpeta_real="$FTP_ROOT/personal/$usuario"
    if [ ! -d "$carpeta_real" ]; then
        mkdir -p "$carpeta_real"
        chown "$usuario:$grupo" "$carpeta_real"
        chmod 700 "$carpeta_real"
    fi
}

validar_Usuario() {
    usuario="$1"
    [ -z "$usuario" ] && print_error "Nombre vacio" && return 1
    [ ${#usuario} -lt 3 ] || [ ${#usuario} -gt 32 ] && print_error "Longitud invalida" && return 1
    [[ ! "$usuario" =~ ^[a-z][a-z0-9_-]*$ ]] && print_error "Formato invalido" && return 1
    id "$usuario" &>/dev/null && print_error "Usuario ya existe" && return 1
    return 0
}

validar_Contrasena() {
    password="$1"
    [ ${#password} -lt 8 ] && print_error "Contrasena minima 8 caracteres" && return 1
    return 0
}

reiniciar_FTP() {
    print_info "Reiniciando servidor"
    systemctl is-active --quiet vsftpd && systemctl restart vsftpd || systemctl start vsftpd
    systemctl is-active --quiet vsftpd && print_completado "vsftpd activo" || print_error "Error al iniciar"
}

ver_Estado() {
    print_titulo "Estado del servidor FTP"
    systemctl status vsftpd --no-pager
    echo ""
    ss -tnp | grep :21 || echo "Sin conexiones"
}

if [[ $EUID -ne 0 ]]; then
    print_error "Ejecutar como root"
    exit 1
fi

case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) configurar_SELinux; crear_Grupos; crear_Estructura_Base; configurar_Vsftpd; configurar_PAM; systemctl enable vsftpd; systemctl start vsftpd ;;
    -u | --users)   echo "Use la version completa para gestion avanzada de usuarios" ;;
    -s | --status)  ver_Estado ;;
    -r | --restart) reiniciar_FTP ;;
    -l | --list)    ls -R "$FTP_ROOT" 2>/dev/null ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac
