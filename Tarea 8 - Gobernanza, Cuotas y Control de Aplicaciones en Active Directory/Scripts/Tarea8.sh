#!/bin/bash

set -e

DOMINIO="empresa.local"
DOMINIO_UPPER="EMPRESA.LOCAL"

# Colores
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]   $1${NC}"; }
info() { echo -e "${CYAN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
err()  { echo -e "${RED}[ERR]  $1${NC}"; exit 1; }

[ "$(id -u)" -ne 0 ] && err "Ejecuta como root: sudo bash $0"

echo ""
echo "============================================="
echo "  Union de openSUSE a empresa.local"
echo "============================================="
echo ""

read -rp "IP del servidor DC: " IP_DC
[ -z "$IP_DC" ] && err "IP no puede estar vacia."

info "Configurando DNS..."
cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
cat > /etc/resolv.conf <<EOF
search $DOMINIO
nameserver $IP_DC
EOF
ok "DNS -> $IP_DC"

info "Instalando paquetes..."
zypper --non-interactive refresh 2>/dev/null || warn "No se pudieron refrescar repos."

zypper --non-interactive install -y \
    realmd sssd sssd-ad sssd-tools \
    adcli samba-client krb5-client \
    oddjob oddjob-mkhomedir 2>/dev/null || {
        warn "Intentando instalacion minima..."
        zypper --non-interactive install -y realmd sssd adcli krb5-client samba-client 2>/dev/null || true
    }
ok "Paquetes instalados."

info "Descubriendo dominio $DOMINIO..."
realm discover "$DOMINIO" || err "No se pudo descubrir el dominio. Verifica IP y DNS."
ok "Dominio descubierto."

info "Uniendose al dominio (password de Administrador)..."
realm join --verbose "$DOMINIO" --user=Administrador || err "Fallo la union al dominio."
ok "Unido a $DOMINIO."

info "Configurando SSSD..."
cp /etc/sssd/sssd.conf /etc/sssd/sssd.conf.bak 2>/dev/null || true

cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam

[domain/$DOMINIO]
ad_domain = $DOMINIO
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
access_provider = ad
auth_provider = ad
chpass_provider = ad
fallback_homedir = /home/%u@%d
use_fully_qualified_names = True
default_shell = /bin/bash
ad_access_filter = (objectClass=user)
ldap_id_use_start_tls = False
ldap_tls_reqcert = never
EOF

chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
ok "SSSD configurado (fallback_homedir = /home/%u@%d)"

info "Habilitando mkhomedir..."
pam-config --add --mkhomedir 2>/dev/null || {
    grep -q "pam_mkhomedir" /etc/pam.d/common-session 2>/dev/null || \
        echo "session optional pam_mkhomedir.so skel=/etc/skel umask=0077" >> /etc/pam.d/common-session
}
systemctl enable oddjobd 2>/dev/null && systemctl start oddjobd 2>/dev/null || true
ok "mkhomedir habilitado."

info "Configurando sudo para AD..."
mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/ad-admins <<'EOF'
# Domain Admins con sudo completo
%domain\ admins@empresa.local ALL=(ALL) ALL

# Grupo Cuates con sudo
%cuates@empresa.local ALL=(ALL) ALL
EOF

chmod 0440 /etc/sudoers.d/ad-admins
chown root:root /etc/sudoers.d/ad-admins

visudo -cf /etc/sudoers.d/ad-admins 2>/dev/null && ok "sudoers valido." || {
    warn "Recreando sudoers simplificado..."
    echo '%domain\ admins@empresa.local ALL=(ALL) ALL' > /etc/sudoers.d/ad-admins
    chmod 0440 /etc/sudoers.d/ad-admins
}

info "Permitiendo login a todos los usuarios..."
realm permit --all 2>/dev/null || warn "realm permit no disponible."
ok "Login permitido."

info "Reiniciando SSSD..."
systemctl restart sssd
systemctl enable sssd
ok "SSSD activo."
echo ""
echo "============================================="
echo "          VERIFICACION"
echo "============================================="

info "Dominio:"
realm list 2>/dev/null || true

info "Probando usuario AD..."
id "usuario1@$DOMINIO" 2>/dev/null && ok "usuario1 resuelto." || \
    warn "usuario1 no resuelto aun (espera 30s: id usuario1@$DOMINIO)"

info "fallback_homedir:"
grep "fallback_homedir" /etc/sssd/sssd.conf

info "sudoers:"
[ -f /etc/sudoers.d/ad-admins ] && ok "/etc/sudoers.d/ad-admins existe" || warn "sudoers falta"

echo ""
echo "============================================="
echo "  LISTO - Para login usa:"
echo "  usuario1@empresa.local"
echo "  Home: /home/usuario1@empresa.local"
echo "============================================="
echo ""
