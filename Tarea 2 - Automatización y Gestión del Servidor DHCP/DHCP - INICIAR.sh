#!/bin/bash

# ================== VALIDACION ROOT =====================

if [ "$EUID" -ne 0 ]; then
	echo "Este script debe ejecutarse como root..."
	exit 1
fi

# ================== VARIABLES ===========================

SCOPE=Conexion
IPINICIAL=192.168.100.30
IPFINAL=192.168.100.60
GATEWAY=192.168.100.1
DNS=8.8.8.8
DNS2=4.4.4.4
LEASE=5000
MASCARA=255.255.255.0

# ================== FUNCIONES ===========================

normalizar_ip(){
	IFS='.' read -r p1 p2 p3 p4 <<< "$1"
	echo "$((10#$p1)).$((10#$p2)).$((10#$p3)).$((10#$p4))"
}

validar_ip(){
	local ip=$1
	
	[[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 1
	
	IFS='.' read -r p1 p2 p3 p4 <<< "$ip"
	for p in $p1 $p2 $p3 $p4
	do
		[[ $p -gt 255 ]] && return 1
	done
	
	return 0
}

ip_a_numero(){
	IFS='.' read -r p1 p2 p3 p4 <<< "$1"
	echo $(( (p1<<24)+(p2<<16)+(p3<<8)+p4 ))
}

numero_a_ip(){
	local num=$1
	echo "$(( (num>>24)&255 )).$(( (num>>16)&255 )).$(( (num>>8)&255 )).$(( num&255 ))"
}

obtener_ip_local(){
	ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n1
}

obtener_red(){
	IFS='.' read -r p1 p2 p3 _ <<< "$1"
	echo "$p1.$p2.$p3.0"
}

validar_instalacion(){
	if ! rpm -q dhcp-server > /dev/null 2>&1
	then
		echo "DHCP-SERVER no esta instalado..."
		echo "Instalando..."
		zypper install -y dhcp-server || exit 1
	fi
}

validar_rango_final(){
	n_inicio=$(ip_a_numero "$IPINICIAL")
	n_fin=$(ip_a_numero "$IPFINAL")
	
	if [[ $n_inicio -ge $n_fin ]]
	then
		echo "Error: IP inicial mayor o igual a IP final..."
		exit 1
	fi
}

validar_gateway_red(){
	red1=$(obtener_red "$IPINICIAL")
	red2=$(obtener_red "$GATEWAY")
	
	if [[ "$red1" != "$red2" ]]
	then
		echo "Gateway no pertenece a la misma red..."
		exit 1
	fi
}

ajustar_rango(){
	IP_LOCAL=$(obtener_ip_local)

	if [[ -z "$IP_LOCAL" ]]
	then
		echo "No se pudo detectar IP local..."
		exit 1
	fi

	if [[ "$IPINICIAL" == "$IP_LOCAL" ]]
	then
		echo "IP inicial coincide con IP del servidor..."
		num=$(ip_a_numero "$IPINICIAL")
		num=$((num+1))
		IPINICIAL=$(numero_a_ip $num)
	fi

	red_local=$(obtener_red "$IP_LOCAL")
	red_rango=$(obtener_red "$IPINICIAL")

	if [[ "$red_local" != "$red_rango" ]]
	then
		echo "Red diferente detectada..."
		echo "Ajustando IP inicial a IP del servidor..."
		IPINICIAL="$IP_LOCAL"
	fi
}

validar_lease(){
	[[ "$1" =~ ^[0-9]+$ ]] || return 1
	[[ "$1" -gt 0 ]] || return 1
	return 0
}

# ================== CONFIGURACION ========================

conf_parametros(){

clear
echo "========== CONFIGURAR PARAMETROS =========="

read -p "Nombre del ambito: " SCOPE
read -p "IP inicial: " IPINICIAL
read -p "IP final: " IPFINAL
read -p "Gateway: " GATEWAY
read -p "DNS primario: " DNS
read -p "DNS secundario (Enter para omitir): " DNS2
read -p "Lease (segundos): " LEASE

IPINICIAL=$(normalizar_ip "$IPINICIAL")
IPFINAL=$(normalizar_ip "$IPFINAL")
GATEWAY=$(normalizar_ip "$GATEWAY")
DNS=$(normalizar_ip "$DNS")

if [[ -n "$DNS2" ]]
then
	DNS2=$(normalizar_ip "$DNS2")
fi

validar_ip "$IPINICIAL" || exit 1
validar_ip "$IPFINAL" || exit 1
validar_ip "$GATEWAY" || exit 1
validar_ip "$DNS" || exit 1
[[ -n "$DNS2" ]] && validar_ip "$DNS2" || DNS2=""

validar_lease "$LEASE" || exit 1

ajustar_rango
validar_rango_final
validar_gateway_red

echo ""
echo "Parametros validados correctamente..."
sleep 2
}

crear_config(){

cat > /etc/dhcpd.conf <<EOF
default-lease-time $LEASE;
max-lease-time $LEASE;
authoritative;

subnet $(obtener_red "$IPINICIAL") netmask $MASCARA {
	range $IPINICIAL $IPFINAL;
	option routers $GATEWAY;
	option domain-name-servers $DNS $DNS2;
}
EOF

if [[ ! -f /etc/dhcpd.conf ]]
then
	echo "Error creando archivo dhcpd.conf"
	exit 1
fi

echo "Archivo dhcpd.conf creado correctamente..."
}

iniciar_dhcp(){

systemctl enable dhcpd > /dev/null 2>&1
systemctl restart dhcpd

if ! systemctl is-active dhcpd > /dev/null 2>&1
then
	echo "Error iniciando servicio DHCP..."
	exit 1
fi

echo "Servidor DHCP iniciado correctamente..."
}

monitorear(){

clear
echo "========== MONITOREO EN TIEMPO REAL =========="

if ! systemctl is-active dhcpd > /dev/null 2>&1
then
	echo "Servicio DHCP no esta activo..."
	exit 1
fi

if journalctl -u dhcpd > /dev/null 2>&1
then
	echo "Presione CTRL+C para salir..."
	journalctl -u dhcpd -f
else
	echo "No se encontraron logs del servicio..."
	exit 1
fi
}

# ================== EJECUCION ============================

validar_instalacion

if [ -z "$1" ]
then
	conf_parametros
	crear_config
	iniciar_dhcp
	monitorear
	exit 0
fi

if [ "$1" = "configurar" ]; then
	conf_parametros
fi

if [ "$1" = "crear" ]; then
	crear_config
fi

if [ "$1" = "iniciar" ]; then
	iniciar_dhcp
fi

if [ "$1" = "monitor" ]; then
	monitorear
fi

if [ "$1" = "help" ]; then
	echo ""
	echo "============ COMANDOS ============"
	echo "Sin parametros : Configura todo automaticamente"
	echo "configurar : Configurar parametros"
	echo "crear : Crear archivo dhcpd.conf"
	echo "iniciar : Iniciar servicio"
	echo "monitor : Monitoreo en tiempo real"
	echo ""
fi
