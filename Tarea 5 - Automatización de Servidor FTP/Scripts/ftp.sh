#!/bin/bash

print_info()       { echo "[INFO] $1"; }
print_completado() { echo "[OK]   $1"; }
print_error()      { echo "[ERROR] $1"; }
print_titulo()     { echo ""; echo "=== $1 ==="; echo ""; }

readonly PAQUETE="vsftpd"
readonly VSFTPD_CONF="/etc/vsftpd.conf"
readonly FTP_ROOT="/srv/ftp"
readonly VSFTPD_USER_CONF_DIR="/etc/vsftpd/users"
readonly GRUPO_REPROBADOS="reprobados"
readonly GRUPO_RECURSADORES="recursadores"
readonly INTERFAZ_RED="enp0s9"

ayuda() {
    echo "Uso del script: $0 [opción]"
    echo "Opciones:"
    echo "  -v, --verify       Verifica si está instalado vsftpd"
    echo "  -i, --install      Instala y configura el servidor FTP"
    echo "  -u, --users        Gestionar usuarios FTP"
    echo "  -r, --restart      Reiniciar servidor FTP"
    echo "  -s, --status       Verificar estado del servidor FTP"
    echo "  -l, --list         Listar usuarios y estructura FTP"
    echo "  -?, --help         Muestra esta ayuda"
}

verificar_Instalacion() {
    print_info "Verificando instalación de vsftpd"

    if rpm -q $PAQUETE &>/dev/null; then
        local version
        version=$(rpm -q $PAQUETE --queryformat '%{VERSION}')
        print_completado "vsftpd ya está instalado (versión: $version)"
        return 0
    fi

    if command -v vsftpd &>/dev/null; then
        local version
        version=$(vsftpd -v 2>&1 | head -1)
        print_completado "vsftpd encontrado: $version"
        return 0
    fi

    print_error "vsftpd no está instalado"
    return 1
}

configurar_SELinux() {
    print_info "Verificando SELinux..."

    if ! command -v getenforce &>/dev/null; then
        print_info "SELinux no está presente en este sistema"
        return 0
    fi

    local estado
    estado=$(getenforce 2>/dev/null)
    print_info "Estado actual de SELinux: $estado"

    if ! command -v semanage &>/dev/null && [ ! -f /usr/sbin/semanage ]; then
        print_info "Instalando policycoreutils-python-utils..."
        zypper --non-interactive --quiet install policycoreutils-python-utils
    fi

    print_info "Configurando booleanos SELinux para vsftpd..."
    setsebool -P ftpd_full_access on 2>/dev/null && \
        print_completado "Booleano ftpd_full_access activado"

    print_info "Aplicando contexto SELinux a $FTP_ROOT..."
    /usr/sbin/semanage fcontext -a -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null || \
    /usr/sbin/semanage fcontext -m -t public_content_rw_t "$FTP_ROOT(/.*)?" 2>/dev/null
    print_completado "Contexto SELinux aplicado a $FTP_ROOT"

    restorecon -Rv "$FTP_ROOT" 2>/dev/null && \
        print_completado "Contextos restaurados con restorecon"

    print_completado "SELinux configurado para vsftpd"
}

configurar_PAM() {
    print_info "Configurando PAM para vsftpd..."

    tee /etc/pam.d/ftp > /dev/null << 'EOF'
auth     required    pam_unix.so     shadow nullok
account  required    pam_unix.so
session  required    pam_unix.so
EOF
    print_completado "PAM configurado en /etc/pam.d/ftp"

    if ! grep -q "^/sbin/nologin$" /etc/shells; then
        echo "/sbin/nologin" >> /etc/shells
        print_completado "/sbin/nologin agregado a /etc/shells"
    else
        print_info "/sbin/nologin ya está en /etc/shells"
    fi
}

crear_Estructura_Base() {
    print_info "Creando estructura de directorios FTP..."

    local dirs=(
        "$FTP_ROOT"
        "$FTP_ROOT/general"
        "$FTP_ROOT/$GRUPO_REPROBADOS"
        "$FTP_ROOT/$GRUPO_RECURSADORES"
        "$FTP_ROOT/personal"
        "$FTP_ROOT/usuarios"
        "$VSFTPD_USER_CONF_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_completado "Directorio creado: $dir"
        fi
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

    print_completado "Estructura base configurada"
}

crear_Grupos() {
    print_info "Verificando grupos del sistema..."

    for grupo in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES"; do
        if ! getent group "$grupo" &>/dev/null; then
            groupadd "$grupo"
            print_completado "Grupo '$grupo' creado"
        else
            print_info "Grupo '$grupo' ya existe"
        fi
    done

    print_completado "Grupos configurados"
}

configurar_Vsftpd() {
    print_info "Configurando vsftpd..."

    if [ -f "$VSFTPD_CONF" ]; then
        cp "$VSFTPD_CONF" "${VSFTPD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backup creado"
    fi

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

ftpd_banner=Bienvenido al servidor FTP - Acceso restringido

pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
EOF

    print_completado "vsftpd.conf creado"

    [ ! -f /etc/vsftpd.user_list ] && touch /etc/vsftpd.user_list && \
        print_completado "Archivo user_list creado"

    for u in anonymous ftp; do
        if ! grep -q "^$u$" /etc/vsftpd.user_list; then
            echo "$u" >> /etc/vsftpd.user_list
            print_completado "Usuario '$u' agregado a user_list"
        fi
    done

    if ! id ftp &>/dev/null; then
        useradd -r -d "$FTP_ROOT/general" -s /sbin/nologin ftp
        print_completado "Usuario 'ftp' (anónimo) creado"
    fi
}

construir_Jaula_Usuario() {
    local usuario="$1"
    local grupo="$2"
    local jaula="$FTP_ROOT/usuarios/$usuario"

    print_info "Construyendo jaula FTP para '$usuario'..."

    mkdir -p "$jaula"
    chown root:root "$jaula"
    chmod 755 "$jaula"

    mkdir -p "$jaula/general"
    chown root:root "$jaula/general"
    chmod 755 "$jaula/general"

    mkdir -p "$jaula/$grupo"
    chown root:root "$jaula/$grupo"
    chmod 755 "$jaula/$grupo"

    mkdir -p "$jaula/$usuario"
    chown "$usuario:$grupo" "$jaula/$usuario"
    chmod 700 "$jaula/$usuario"

    if ! mountpoint -q "$jaula/general" 2>/dev/null; then
        mount --bind "$FTP_ROOT/general" "$jaula/general"
        print_completado "Bind mount: general"
    fi

    if ! mountpoint -q "$jaula/$grupo" 2>/dev/null; then
        mount --bind "$FTP_ROOT/$grupo" "$jaula/$grupo"
        print_completado "Bind mount: $grupo"
    fi

    if ! mountpoint -q "$jaula/$usuario" 2>/dev/null; then
        mount --bind "$FTP_ROOT/personal/$usuario" "$jaula/$usuario"
        print_completado "Bind mount: $usuario (personal)"
    fi

    local fstab_entries=(
        "$FTP_ROOT/general  $jaula/general  none  bind  0  0"
        "$FTP_ROOT/$grupo  $jaula/$grupo  none  bind  0  0"
        "$FTP_ROOT/personal/$usuario  $jaula/$usuario  none  bind  0  0"
    )

    for entry in "${fstab_entries[@]}"; do
        if ! grep -Fx "$entry" /etc/fstab >/dev/null; then
            echo "$entry" >> /etc/fstab
            print_completado "fstab: $(echo $entry | awk '{print $2}')"
        fi
    done

    tee "$VSFTPD_USER_CONF_DIR/$usuario" > /dev/null << EOF
local_root=$jaula
EOF
    print_completado "Config individual: /etc/vsftpd/users/$usuario"
    print_completado "Jaula lista: $jaula"
}

destruir_Jaula_Usuario() {
    local usuario="$1"
    local jaula="$FTP_ROOT/usuarios/$usuario"

    print_info "Desmontando jaula de '$usuario'..."

    for punto in "$jaula/$usuario" "$jaula/$GRUPO_REPROBADOS" "$jaula/$GRUPO_RECURSADORES" "$jaula/general"; do
        if mountpoint -q "$punto" 2>/dev/null; then
            umount "$punto" && print_completado "Desmontado: $punto"
        fi
    done

    sed -i "\| $jaula/general |d" /etc/fstab
    sed -i "\| $jaula/$GRUPO_REPROBADOS |d" /etc/fstab
    sed -i "\| $jaula/$GRUPO_RECURSADORES |d" /etc/fstab
    sed -i "\| $jaula/$usuario |d" /etc/fstab

    rm -f "$VSFTPD_USER_CONF_DIR/$usuario"
    rm -rf "$jaula"
    print_completado "Jaula eliminada"
}

crear_Carpeta_Personal_Real() {
    local usuario="$1"
    local grupo="$2"
    local carpeta_real="$FTP_ROOT/personal/$usuario"

    if [ ! -d "$carpeta_real" ]; then
        mkdir -p "$carpeta_real"
        chown "$usuario:$grupo" "$carpeta_real"
        chmod 700 "$carpeta_real"
        print_completado "Carpeta personal: $carpeta_real"
    fi
}

validar_Usuario() {
    local usuario="$1"

    [ -z "$usuario" ] && print_error "El nombre no puede estar vacío" && return 1

    if [ ${#usuario} -lt 3 ] || [ ${#usuario} -gt 32 ]; then
        print_error "El nombre debe tener entre 3 y 32 caracteres"
        return 1
    fi

    if [[ ! "$usuario" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "Solo letras minúsculas, números, - y _. Debe iniciar con letra."
        return 1
    fi

    if id "$usuario" &>/dev/null; then
        print_error "El usuario '$usuario' ya existe"
        return 1
    fi

    return 0
}

validar_Contrasena() {
    local password="$1"
    [ ${#password} -lt 8 ] && \
        print_error "La contraseña debe tener al menos 8 caracteres" && return 1
    return 0
}

crear_Usuario_FTP() {
    local usuario="$1"
    local password="$2"
    local grupo="$3"

    print_info "Creando usuario '$usuario' en grupo '$grupo'..."

    useradd \
        -M \
        -d "$FTP_ROOT/usuarios/$usuario" \
        -s /sbin/nologin \
        -g "$grupo" \
        -G "users" \
        "$usuario" 2>/dev/null

    if [ $? -ne 0 ]; then
        print_error "Error al crear el usuario '$usuario'"
        return 1
    fi
    print_completado "Usuario del sistema creado"

    echo "$usuario:$password" | chpasswd
    if [ $? -ne 0 ]; then
        print_error "Error al establecer contraseña"
        userdel "$usuario" 2>/dev/null
        return 1
    fi
    print_completado "Contraseña establecida"

    crear_Carpeta_Personal_Real "$usuario" "$grupo"
    construir_Jaula_Usuario "$usuario" "$grupo"

    if ! grep -q "^$usuario$" /etc/vsftpd.user_list 2>/dev/null; then
        echo "$usuario" >> /etc/vsftpd.user_list
        print_completado "Agregado a /etc/vsftpd.user_list"
    fi

    echo ""
    echo "-----------------------------------------------"
    echo "  Usuario '$usuario' creado"
    echo "  Grupo    : $grupo"
    echo "  Jaula    : $FTP_ROOT/usuarios/$usuario/"
    echo "  Carpetas :"
    echo "    /general/     (publica)"
    echo "    /$grupo/      (grupo)"
    echo "    /$usuario/    (personal)"
    echo "-----------------------------------------------"
    return 0
}

cambiar_Grupo_Usuario() {
    local usuario="$1"

    if ! id "$usuario" &>/dev/null; then
        print_error "El usuario '$usuario' no existe"
        return 1
    fi

    local grupo_actual
    grupo_actual=$(id -gn "$usuario")
    print_info "Grupo actual de '$usuario': $grupo_actual"

    echo ""
    echo "Grupos disponibles:"
    echo "  1) $GRUPO_REPROBADOS"
    echo "  2) $GRUPO_RECURSADORES"
    read -rp "Seleccione el nuevo grupo [1-2]: " opcion

    local nuevo_grupo
    case $opcion in
        1) nuevo_grupo="$GRUPO_REPROBADOS" ;;
        2) nuevo_grupo="$GRUPO_RECURSADORES" ;;
        *)
            print_error "Opción inválida"
            return 1
            ;;
    esac

    if [ "$grupo_actual" == "$nuevo_grupo" ]; then
        print_info "El usuario ya pertenece a '$nuevo_grupo'"
        return 0
    fi

    print_info "Cambiando '$usuario': '$grupo_actual' -> '$nuevo_grupo'..."

    local carpeta_actual="$FTP_ROOT/personal/$usuario"
    local carpeta_nueva="$FTP_ROOT/personal/$usuario"
    local mover_contenido="n"

    if [ -d "$carpeta_actual" ] && [ "$(ls -A "$carpeta_actual" 2>/dev/null)" ]; then
        echo ""
        print_info "La carpeta personal actual ($carpeta_actual) contiene archivos."
        read -rp "¿Desea moverlos a la nueva ubicación? [s/N]: " mover_contenido
    fi

    destruir_Jaula_Usuario "$usuario"

    if [[ "$mover_contenido" =~ ^[Ss]$ ]]; then
        if [ -d "$carpeta_actual" ]; then
            mkdir -p "$carpeta_nueva"
            mv "$carpeta_actual"/* "$carpeta_nueva"/ 2>/dev/null
            rmdir "$carpeta_actual" 2>/dev/null
            print_completado "Contenido movido a $carpeta_nueva"
        fi
    else
        print_info "Los archivos se conservan en $carpeta_actual (sin acceso desde FTP)"
    fi

    usermod -g "$nuevo_grupo" "$usuario"
    print_completado "Grupo del sistema actualizado"

    crear_Carpeta_Personal_Real "$usuario" "$nuevo_grupo"
    construir_Jaula_Usuario "$usuario" "$nuevo_grupo"

    echo ""
    echo "Usuario '$usuario' movido a '$nuevo_grupo'"
    echo "  Nueva estructura FTP:"
    echo "  general/"
    echo "  $nuevo_grupo/"
    echo "  $usuario/"
}

instalar_FTP() {
    print_titulo "Instalación y Configuración de Servidor FTP"

    if verificar_Instalacion; then
        read -rp "vsftpd ya está instalado. ¿Reconfigurar? [s/N]: " reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando vsftpd con zypper..."
        zypper --non-interactive --quiet install $PAQUETE
        if [ $? -eq 0 ]; then
            print_completado "vsftpd instalado"
        else
            print_error "Error en la instalación"
            return 1
        fi
    fi

    echo ""
    configurar_SELinux
    echo ""
    crear_Grupos
    echo ""
    crear_Estructura_Base
    echo ""
    configurar_Vsftpd
    echo ""
    configurar_PAM
    echo ""

    print_info "Habilitando y arrancando vsftpd..."
    systemctl enable vsftpd 2>/dev/null && print_completado "Servicio habilitado"

    if systemctl is-active --quiet vsftpd; then
        systemctl restart vsftpd && print_completado "Servicio reiniciado"
    else
        systemctl start vsftpd && print_completado "Servicio iniciado"
    fi

    if ! systemctl is-active --quiet vsftpd; then
        print_error "El servicio no pudo iniciar"
        print_error "Revise: journalctl -xeu vsftpd.service"
        return 1
    fi

    print_info "Configurando firewall..."
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-service=ftp --permanent 2>/dev/null && \
            print_completado "Puerto 21 abierto (firewalld)"
        firewall-cmd --add-port=40000-40100/tcp --permanent 2>/dev/null && \
            print_completado "Puertos pasivos abiertos (firewalld)"
        firewall-cmd --reload 2>/dev/null && print_completado "Firewall recargado"
    elif command -v SuSEfirewall2 &>/dev/null; then
        sed -i 's/^FW_SERVICES_EXT_TCP.*/FW_SERVICES_EXT_TCP="ftp"/' /etc/sysconfig/SuSEfirewall2
        echo "FW_SERVICES_EXT_TCP=\"40000:40100\"" >> /etc/sysconfig/SuSEfirewall2
        systemctl restart SuSEfirewall2 && print_completado "SuSEfirewall2 recargado"
    else
        print_error "No se detectó firewall. Abra manualmente 21/tcp y 40000-40100/tcp."
    fi

    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    [ -z "$ip" ] && \
        ip=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)

    echo ""
    echo "----------------------------------------------"
    echo "  Servidor FTP listo"
    echo "  IP             : $ip"
    echo "  Puerto         : 21"
    echo "  Acceso anonimo : ftp://$ip  (solo lectura)"
    echo "  Jaulas         : $FTP_ROOT/usuarios/<nombre>/"
    echo "----------------------------------------------"
    echo ""
    print_info "Cree usuarios con: $0 -u"
}

gestionar_Usuarios() {
    print_titulo "Gestión de Usuarios FTP"

    if ! verificar_Instalacion &>/dev/null; then
        print_error "vsftpd no está instalado. Ejecute: $0 -i"
        return 1
    fi

    echo "Opciones:"
    echo "  1) Crear nuevos usuarios"
    echo "  2) Cambiar grupo de un usuario"
    echo "  3) Eliminar usuario"
    echo "  4) Volver"
    echo ""
    read -rp "Seleccione una opción [1-4]: " opcion

    case $opcion in
        1)
            echo ""
            read -rp "¿Cuántos usuarios desea crear?: " num_usuarios

            if ! [[ "$num_usuarios" =~ ^[0-9]+$ ]] || [ "$num_usuarios" -lt 1 ]; then
                print_error "Número inválido"
                return 1
            fi

            for ((i=1; i<=num_usuarios; i++)); do
                echo ""
                print_titulo "Usuario $i de $num_usuarios"

                while true; do
                    read -rp "Nombre de usuario: " usuario
                    validar_Usuario "$usuario" && break
                done

                while true; do
                    read -rsp "Contraseña (mín. 8 caracteres): " password
                    echo ""
                    if validar_Contrasena "$password"; then
                        read -rsp "Confirmar contraseña: " password2
                        echo ""
                        if [ "$password" == "$password2" ]; then
                            break
                        else
                            print_error "Las contraseñas no coinciden"
                        fi
                    fi
                done

                echo ""
                echo "¿A qué grupo pertenece?"
                echo "  1) $GRUPO_REPROBADOS"
                echo "  2) $GRUPO_RECURSADORES"
                read -rp "Seleccione el grupo [1-2]: " grupo_opcion

                local grupo
                case $grupo_opcion in
                    1) grupo="$GRUPO_REPROBADOS" ;;
                    2) grupo="$GRUPO_RECURSADORES" ;;
                    *)
                        print_error "Opción inválida, asignando a '$GRUPO_REPROBADOS'"
                        grupo="$GRUPO_REPROBADOS"
                        ;;
                esac

                crear_Usuario_FTP "$usuario" "$password" "$grupo"
            done

            echo ""
            print_info "Reiniciando vsftpd..."
            systemctl restart vsftpd && print_completado "Servicio reiniciado"
            ;;

        2)
            echo ""
            listar_Usuarios_FTP
            echo ""
            read -rp "Usuario a cambiar de grupo: " usuario
            cambiar_Grupo_Usuario "$usuario"
            systemctl restart vsftpd && print_completado "Servicio reiniciado"
            ;;

        3)
            echo ""
            listar_Usuarios_FTP
            echo ""
            read -rp "Usuario a eliminar: " usuario

            if ! id "$usuario" &>/dev/null; then
                print_error "El usuario '$usuario' no existe"
                return 1
            fi

            if pgrep -u "$usuario" > /dev/null; then
                print_error "El usuario tiene procesos activos."
                read -rp "¿Forzar eliminación? [s/N]: " force
                if [[ ! "$force" =~ ^[Ss]$ ]]; then
                    print_info "Operación cancelada"
                    return 1
                fi
                pkill -u "$usuario" 2>/dev/null
            fi

            read -rp "¿Confirma eliminar '$usuario'? [s/N]: " confirmar
            if [[ "$confirmar" =~ ^[Ss]$ ]]; then
                destruir_Jaula_Usuario "$usuario"
                sed -i "/^$usuario$/d" /etc/vsftpd.user_list
                rm -rf "$FTP_ROOT/personal/$usuario"
                userdel "$usuario" 2>/dev/null
                print_completado "Usuario '$usuario' eliminado"
                systemctl restart vsftpd && print_completado "Servicio reiniciado"
            else
                print_info "Operación cancelada"
            fi
            ;;

        4) return 0 ;;
        *) print_error "Opción inválida" ;;
    esac
}

listar_Usuarios_FTP() {
    print_titulo "Usuarios FTP Configurados"

    if [ ! -s /etc/vsftpd.user_list ]; then
        print_info "No hay usuarios FTP configurados"
        return 0
    fi

    printf "%-20s %-20s %-40s\n" "USUARIO" "GRUPO" "JAULA FTP"
    echo "--------------------------------------------------------------------------------"

    while IFS= read -r usuario; do
        if id "$usuario" &>/dev/null; then
            local grupo
            grupo=$(id -gn "$usuario")
            printf "%-20s %-20s %-40s\n" \
                "$usuario" "$grupo" "$FTP_ROOT/usuarios/$usuario"
        fi
    done < /etc/vsftpd.user_list
    echo ""
}

listar_Estructura() {
    print_titulo "Estructura del Servidor FTP"

    [ ! -d "$FTP_ROOT" ] && print_error "No existe: $FTP_ROOT" && return 1

    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    print_info "Raíz : $FTP_ROOT"
    print_info "IP   : ${ip:-no disponible}"
    echo ""

    if command -v tree &>/dev/null; then
        tree -L 3 -p -u -g "$FTP_ROOT"
    else
        find "$FTP_ROOT" -maxdepth 3 -exec ls -ld {} \;
    fi

    echo ""
    listar_Usuarios_FTP
}

reiniciar_FTP() {
    print_info "Reiniciando servidor FTP..."

    if systemctl is-active --quiet vsftpd; then
        systemctl restart vsftpd
    else
        print_info "Servicio inactivo, iniciando..."
        systemctl start vsftpd
    fi

    if systemctl is-active --quiet vsftpd; then
        print_completado "vsftpd activo"
        systemctl status vsftpd --no-pager
    else
        print_error "Error al reiniciar vsftpd"
        print_info "Revise: journalctl -xeu vsftpd.service"
    fi
}

ver_Estado() {
    print_titulo "ESTADO DEL SERVIDOR FTP"
    systemctl status vsftpd --no-pager
    echo ""
    print_info "Conexiones activas en :21"
    ss -tnp | grep :21 || echo "  Ninguna"
    echo ""
    local ip
    ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    [ -n "$ip" ] && print_info "IP $INTERFAZ_RED: $ip" || \
        print_error "No se pudo obtener IP de $INTERFAZ_RED"
}

if [[ $EUID -ne 0 ]]; then
    print_error "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) instalar_FTP ;;
    -u | --users)   gestionar_Usuarios ;;
    -s | --status)  ver_Estado ;;
    -r | --restart) reiniciar_FTP ;;
    -l | --list)    listar_Estructura ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac
