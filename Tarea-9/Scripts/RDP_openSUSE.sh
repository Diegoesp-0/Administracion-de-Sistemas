#!/bin/bash

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]   $1${NC}"; }
info() { echo -e "${CYAN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
err()  { echo -e "${RED}[ERR]  $1${NC}"; exit 1; }


instalar_freerdp() {
    if command -v xfreerdp &>/dev/null; then
        warn "xfreerdp ya instalado (se omite)."
        return
    fi
    info "Instalando xfreerdp..."
    sudo zypper --non-interactive install -y freerdp 2>/dev/null || \
    sudo zypper --non-interactive install -y xfreerdp 2>/dev/null || \
        err "No se pudo instalar freerdp. Intenta: sudo zypper install freerdp"
    ok "xfreerdp instalado."
}


echo ""
echo "======== Conexion RDP ========"
echo ""

instalar_freerdp

read -rp "IP del servidor: " IP_SERVIDOR
[ -z "$IP_SERVIDOR" ] && err "La IP no puede estar vacia."

read -rp "Usuario: " USUARIO
[ -z "$USUARIO" ] && err "El usuario no puede estar vacio."

read -rsp "Contrasena: " PASS
echo ""
[ -z "$PASS" ] && err "La contrasenia no puede estar vacia."

info "Conectando como EMPRESA\\$USUARIO a $IP_SERVIDOR..."
info "Ten listo el codigo de Google Authenticator."
echo ""

xfreerdp \
    /v:"$IP_SERVIDOR" \
    /u:"EMPRESA\\$USUARIO" \
    /p:"$PASS" \
    /cert:ignore \
    /dynamic-resolution \
    +clipboard \
    2>/dev/null

[ $? -eq 0 ] && ok "Sesion RDP cerrada correctamente." || \
    warn "La sesion termino con un error o fue cerrada manualmente."
