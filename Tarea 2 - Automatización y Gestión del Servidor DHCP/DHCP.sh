#!/bin/bash

# =============== VARIABLES ==============================================

SCOPE=X
IPINICIAL=X
IPFINAL=X
GATEWAY=X
DNS=X
DNS2=X
LEASE=X
MASCARA=X
INTERFAZ=X

#  =============== FUNCIONES =============================================

calcular_mascara(){
   local ipInicial="$1"
   local ipFinal="$2"
   
   _ip2dec() {
      local ip="$1"
      IFS='.' read -r a b c d <<< "$ip"
      echo $(( (a * 256 * 256 * 256) + (b * 256 * 256) + (c * 256) + d ))
   }
   
   _dec2ip() {
      local dec="$1"
      local o1=$(( (dec / (256 * 256 * 256)) % 256 ))
      local o2=$(( (dec / (256 * 256)) % 256 ))
      local o3=$(( (dec / 256) % 256 ))
      local o4=$(( dec % 256 ))
      echo "$o1.$o2.$o3.$o4"
   }
   
   local ip1_dec=$(_ip2dec "$ipInicial")
   local ip2_dec=$(_ip2dec "$ipFinal")
   
   if [[ $ip2_dec -lt $ip1_dec ]]; then
      return 1
   fi
   
   local diferencia=$((ip2_dec - ip1_dec + 1))
   local hosts_necesarios=$((diferencia + 2))
   
   local cidr_hosts=32
   while [[ $cidr_hosts -ge 8 ]]; do
      local bits=$((32 - cidr_hosts))
      local potencia=1
      for ((i=0; i<bits; i++)); do
         potencia=$((potencia * 2))
      done
      local hosts_disponibles=$((potencia - 2))
      
      if [[ $hosts_necesarios -le $hosts_disponibles ]]; then
         break
      fi
      ((cidr_hosts--))
   done
   
   local cidr_subred=32
   while [[ $cidr_subred -ge 8 ]]; do
      local mascara_tmp=0
      for ((i=0; i<cidr_subred; i++)); do
         mascara_tmp=$(( (mascara_tmp * 2) + 1 ))
      done
      for ((i=cidr_subred; i<32; i++)); do
         mascara_tmp=$((mascara_tmp * 2))
      done
      
      local red1=$(( ip1_dec & mascara_tmp ))
      local red2=$(( ip2_dec & mascara_tmp ))
      if [[ $red1 -eq $red2 ]]; then
         break
      fi
      ((cidr_subred--))
   done
   
   local cidr_final=$(( cidr_hosts < cidr_subred ? cidr_hosts : cidr_subred ))
   
   local mascara_dec=0
   for ((i=0; i<cidr_final; i++)); do
      mascara_dec=$(( (mascara_dec * 2) + 1 ))
   done
   for ((i=cidr_final; i<32; i++)); do
      mascara_dec=$((mascara_dec * 2))
   done
   
   mascara=$(_dec2ip "$mascara_dec")
   
   local red_base=$(( ip1_dec & mascara_dec ))
   
   local broadcast=$(( (~mascara_dec) & 0x7FFFFFFF ))
   if [[ $mascara_dec -gt 0 ]]; then
      broadcast=$(( red_base | (0xFFFFFFFF & ~mascara_dec) ))
   else
      broadcast=0xFFFFFFFF
   fi
   
   if [[ $ip1_dec -lt $red_base || $ip2_dec -gt $broadcast ]]; then
      return 1
   fi
   
   return 0
}

validar_ip(){
	local ip=$1
	
	if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
		return 1
	fi
	
	IFS='.' read -r p1 p2 p3 p4 <<< "$ip"

	for p in $p1 $p2 $p3 $p4; do
		[[ $p -le 255 ]] || return 1
	done

	[[ $p1 -eq 0 && $p2 -eq 0 && $p3 -eq 0 && $p4 -eq 0 ]] && return 1
	[[ $p1 -eq 255 && $p2 -eq 255 && $p3 -eq 255 && $p4 -eq 255 ]] && return 1
	[[ $p1 -eq 127 ]] && return 1

	return 0
}

ip_a_numero(){
	IFS='.' read -r p1 p2 p3 p4 <<< "$1"
	echo $(( (p1 << 24) + (p2 << 16) + (p3 << 8) + p4 ))
}

validar_rango(){
	local ip_inicio=$1
	local ip_fin=$2

	validar_ip "$ip_inicio" || return 1
	validar_ip "$ip_fin" || return 1

	local n_inicio
	local n_fin
	
	n_inicio=$(ip_a_numero "$ip_inicio")
	n_fin=$(ip_a_numero "$ip_fin")

	[[ $n_inicio -lt $n_fin ]]
}

validar_dns(){
	validar_ip "$1"
}

obtener_red(){
	IFS='.' read -r p1 p2 p3 _ <<< "$1"
	echo "$p1.$p2.$p3.0"
}

obtener_broadcast(){
	IFS="." read -r p1 p2 p3 _ <<< "$1"
	echo "$p1.$p2.$p3.255"
}

validar_gateway(){
	local gateway=$1
	local ip_ref=$2
	
	validar_ip "$gateway" || return 1
	
	local red
	local broadcast
	local gw_red

	red=$(obtener_red "$ip_ref")
	broadcast=$(obtener_broadcast "$ip_ref")
	gw_red=$(obtener_red "$gateway")

	[[ "$gw_red" == "$red" ]] || return 1
	[[ "$gateway" == "$red" ]] && return 1
	[[ "$gateway" == "$broadcast" ]] && return 1

	return 0
}

validar_lease(){
	local lease=$1
	
	[[ "$lease" =~ ^[0-9]+$ ]] || return 1
	[[ "$lease" -gt 0 ]] || return 1
	return 0
}

obtener_interfaz(){
	local ip_inicial=$1
	
	IFS='.' read -r p1 p2 p3 _ <<< "$ip_inicial"
	local red="$p1.$p2.$p3"
	
	local interfaz=$(ip -4 addr show | grep -B 2 "inet $red" | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | head -n 1)
	
	if [[ -z "$interfaz" ]]; then
		interfaz=$(ip -4 addr show | grep "^[0-9]" | grep -v "lo:" | awk '{print $2}' | tr -d ':' | head -n 1)
	fi
	
	echo "$interfaz"
}

incrementar_ip(){
	local ip=$1
	IFS='.' read -r p1 p2 p3 p4 <<< "$ip"
	
	p4=$((p4 + 1))
	
	if [[ $p4 -gt 255 ]]; then
		p4=0
		p3=$((p3 + 1))
	fi
	
	if [[ $p3 -gt 255 ]]; then
		p3=0
		p2=$((p2 + 1))
	fi
	
	if [[ $p2 -gt 255 ]]; then
		p2=0
		p1=$((p1 + 1))
	fi
	
	echo "$p1.$p2.$p3.$p4"
}

configurar_ip_estatica(){
	local ip=$1
	local mascara=$2
	local interfaz=$3
	
	echo ""
	echo "Configurando IP estatica en la interfaz $interfaz..."
	echo "IP: $ip"
	echo "Mascara: $mascara"
	
	IFS='.' read -r m1 m2 m3 m4 <<< "$mascara"
	local mascara_bin=""
	for octet in $m1 $m2 $m3 $m4; do
		mascara_bin+=$(printf "%08d" $(echo "obase=2; $octet" | bc 2>/dev/null || echo "0"))
	done
	local cidr=$(echo "$mascara_bin" | tr -cd '1' | wc -c)
	
	sudo ip addr flush dev "$interfaz" 2>/dev/null
	sudo ip addr add "$ip/$cidr" dev "$interfaz"
	sudo ip link set "$interfaz" up
	
	if [[ $? -eq 0 ]]; then
		echo "IP estatica configurada correctamente"
		sed -i "s/^INTERFAZ=.*/INTERFAZ=$interfaz/" "$0"
		return 0
	else
		echo "Error al configurar la IP estatica"
		return 1
	fi
}

verificar(){
	clear
	if zypper se -i dhcp-server > /dev/null 2>&1; then
		echo ""
		echo "DHCP-SERVER esta instalado :D"
		echo ""
	else
		echo ""
		echo "El paquete DHCP-SERVER no esta instalado"
		echo ""
		read -p "Desea descargar DHCP-SERVER? (S/s): " OPC

		if [ "$OPC" = "S" ] || [ "$OPC" = "s" ]; then
			echo "Descargando..."
			sudo zypper install -y dhcp-server
		fi
	fi
}

conf_parametros(){
	clear
	
	if ! zypper se -i dhcp-server > /dev/null 2>&1; then
		echo ""
		echo "ERROR: DHCP-SERVER no esta instalado"
		echo "Ejecute el comando 'verificar' primero"
		echo ""
		return 1
	fi
	
	echo "========== CONFIGURAR PARAMETROS =========="
	read -p "Nombre del ambito: " SCOPE_T
	
	while true; do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		read -p "IP inicial del rango (sera la IP del servidor): " INICIAL_T
		
		if ! validar_ip "$INICIAL_T"; then
			clear
			echo "La IP inicial no es valida"
			sleep 2
			continue
		fi

		read -p "IP final del rango: " FINAL_T
		
		if ! validar_ip "$FINAL_T"; then
			clear
			echo "La IP final no es valida"
			sleep 2
			continue
		fi

		if ! validar_rango "$INICIAL_T" "$FINAL_T"; then
			clear
			echo "La IP inicial debe ser menor a la IP final"
			sleep 2
			continue
		fi
		break
	done
	
	while true; do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		read -p "Gateway (Enter para omitir): " GATEWAY_T
		
		if [[ -z "$GATEWAY_T" ]]; then
			GATEWAY_T="X"
			break
		fi
		
		if validar_gateway "$GATEWAY_T" "$INICIAL_T" >/dev/null 2>&1; then
			break
		else
			clear
			echo "Gateway invalido..."
			sleep 2
		fi
	done
	clear
	
	while true; do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		[[ "$GATEWAY_T" != "X" ]] && echo "Gateway: $GATEWAY_T"
		read -p "DNS primario (Enter para omitir): " DNS_T

		if [[ -z "$DNS_T" ]]; then
			DNS_T="X"
			DNS2_T="X"
			break
		fi

		if ! validar_dns "$DNS_T"; then
			clear
			echo "DNS primario invalido..."
			sleep 2
			continue
		fi
		
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		[[ "$GATEWAY_T" != "X" ]] && echo "Gateway: $GATEWAY_T"
		echo "DNS primario: $DNS_T"
		read -p "DNS secundario (Enter para omitir): " DNS2_T

		if [[ -z "$DNS2_T" ]]; then
			DNS2_T="X"
			break
		fi

		if ! validar_dns "$DNS2_T"; then
			clear
			echo "DNS secundario invalido..."
			sleep 2
			continue
		fi
		
		if [[ "$DNS_T" == "$DNS2_T" ]]; then
			clear
			echo "El DNS secundario no puede ser igual al primario..."
			sleep 2
			continue
		fi

		break
	done

	while true; do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		[[ "$GATEWAY_T" != "X" ]] && echo "Gateway: $GATEWAY_T"
		[[ "$DNS_T" != "X" ]] && echo "DNS primario: $DNS_T"
		[[ "$DNS2_T" != "X" ]] && echo "DNS secundario: $DNS2_T"
		
		read -p "Lease (en segundos): " LEASE_T
		
		if ! validar_lease "$LEASE_T"; then
			clear
			echo "Lease invalido..."
			sleep 2
			continue
		fi
		break
	done

	clear
	echo "========== CONFIGURAR PARAMETROS =========="
	echo "Nombre del ambito: $SCOPE_T"
	echo "IP inicial del rango: $INICIAL_T"
	echo "IP final del rango: $FINAL_T"
	[[ "$GATEWAY_T" != "X" ]] && echo "Gateway: $GATEWAY_T"
	[[ "$DNS_T" != "X" ]] && echo "DNS primario: $DNS_T"
	[[ "$DNS2_T" != "X" ]] && echo "DNS secundario: $DNS2_T"
	echo "Lease (en segundos): $LEASE_T"
	echo "---------------------------------------------"
	
	echo ""
	echo "Calculando mascara de subred..."
	if calcular_mascara "$INICIAL_T" "$FINAL_T"; then
		echo "Mascara calculada: $mascara"
		MASCARA_T="$mascara"
	else
		echo "Error al calcular la mascara"
		read -p "Presione enter para volver..."
		return 1
	fi
	
	echo ""
	read -p "Datos capturados, presione enter para continuar..."

	sed -i "s/^SCOPE=.*/SCOPE=$SCOPE_T/" "$0"
	sed -i "s/^IPINICIAL=.*/IPINICIAL=$INICIAL_T/" "$0"
	sed -i "s/^IPFINAL=.*/IPFINAL=$FINAL_T/" "$0"
	sed -i "s/^GATEWAY=.*/GATEWAY=$GATEWAY_T/" "$0"
	sed -i "s/^DNS=.*/DNS=$DNS_T/" "$0"
	sed -i "s/^DNS2=.*/DNS2=$DNS2_T/" "$0"
	sed -i "s/^LEASE=.*/LEASE=$LEASE_T/" "$0"
	sed -i "s/^MASCARA=.*/MASCARA=$MASCARA_T/" "$0"
}

ver_parametros(){
	clear
	if [ "$SCOPE" = "X" ] || [ "$IPINICIAL" = "X" ] || [ "$IPFINAL" = "X" ] || [ "$LEASE" = "X" ]; then
		echo ""
		echo "Parametros no asignados..."
		echo ""
	else
		echo "========== PARAMETROS CONFIGURADOS =========="
		echo "SCOPE = $SCOPE"
		echo "IP INICIAL = $IPINICIAL (IP del servidor)"
		
		local ip_reparto=$(incrementar_ip "$IPINICIAL")
		echo "IP REPARTO = $ip_reparto (Primera IP a repartir)"
		echo "IP FINAL = $IPFINAL"
		
		[[ "$GATEWAY" != "X" ]] && echo "GATEWAY = $GATEWAY"
		[[ "$DNS" != "X" ]] && echo "DNS = $DNS"
		[[ "$DNS2" != "X" ]] && echo "DNS 2 = $DNS2"
		echo "LEASE = $LEASE"
		[[ "$MASCARA" != "X" ]] && echo "MASCARA = $MASCARA"
		[[ "$INTERFAZ" != "X" ]] && echo "INTERFAZ = $INTERFAZ"
		echo ""
	fi
}

iniciar_servidor(){
	clear
	
	if ! zypper se -i dhcp-server > /dev/null 2>&1; then
		echo ""
		echo "ERROR: DHCP-SERVER no esta instalado"
		echo "Ejecute el comando 'verificar' primero"
		echo ""
		return 1
	fi
	
	if [ "$SCOPE" = "X" ] || [ "$IPINICIAL" = "X" ] || [ "$IPFINAL" = "X" ] || [ "$LEASE" = "X" ] || [ "$MASCARA" = "X" ]; then
		echo ""
		echo "ERROR: Los parametros no estan configurados"
		echo "Ejecute el comando 'parametrosconf' primero"
		echo ""
		return 1
	fi
	
	echo "========== INICIAR SERVIDOR DHCP =========="
	echo ""
	
	local interfaz=$(obtener_interfaz "$IPINICIAL")
	
	if [[ -z "$interfaz" ]]; then
		echo "ERROR: No se pudo detectar la interfaz de red"
		return 1
	fi
	
	echo "Interfaz detectada: $interfaz"
	echo ""
	
	if ! configurar_ip_estatica "$IPINICIAL" "$MASCARA" "$interfaz"; then
		return 1
	fi
	
	echo ""
	echo "Generando archivo de configuracion dhcpd.conf..."
	
	local ip_reparto=$(incrementar_ip "$IPINICIAL")
	local red=$(obtener_red "$IPINICIAL")
	local broadcast=$(obtener_broadcast "$IPINICIAL")
	
	sudo tee /etc/dhcpd.conf > /dev/null << EOF
# Configuracion generada automaticamente
ddns-update-style none;
authoritative;
default-lease-time $LEASE;
max-lease-time $LEASE;

subnet $red netmask $MASCARA {
    range $ip_reparto $IPFINAL;
    option subnet-mask $MASCARA;
    option broadcast-address $broadcast;
EOF

	if [[ "$GATEWAY" != "X" ]]; then
		sudo bash -c "echo '    option routers $GATEWAY;' >> /etc/dhcpd.conf"
	fi
	
	if [[ "$DNS" != "X" ]]; then
		if [[ "$DNS2" != "X" ]]; then
			sudo bash -c "echo '    option domain-name-servers $DNS, $DNS2;' >> /etc/dhcpd.conf"
		else
			sudo bash -c "echo '    option domain-name-servers $DNS;' >> /etc/dhcpd.conf"
		fi
	fi
	
	sudo bash -c "echo '}' >> /etc/dhcpd.conf"
	
	echo "Archivo de configuracion creado"
	echo ""
	echo "Iniciando servicio DHCP..."
	
	sudo systemctl stop dhcpd.service 2>/dev/null
	sleep 1
	sudo systemctl start dhcpd.service
	
	if [[ $? -eq 0 ]]; then
		sudo systemctl enable dhcpd.service
		echo ""
		echo "=========================================="
		echo "Servidor DHCP iniciado correctamente"
		echo "=========================================="
		echo "IP del servidor: $IPINICIAL"
		echo "Rango de IPs: $ip_reparto - $IPFINAL"
		echo "Mascara: $MASCARA"
		[[ "$GATEWAY" != "X" ]] && echo "Gateway: $GATEWAY"
		[[ "$DNS" != "X" ]] && echo "DNS: $DNS"
		[[ "$DNS2" != "X" ]] && echo "DNS 2: $DNS2"
		echo "Lease: $LEASE segundos"
		echo "=========================================="
		echo ""
	else
		echo ""
		echo "ERROR: No se pudo iniciar el servidor DHCP"
		echo "Verifique los logs con: journalctl -xeu dhcpd.service"
		echo ""
		return 1
	fi
}

detener_servidor(){
	clear
	
	if ! zypper se -i dhcp-server > /dev/null 2>&1; then
		echo ""
		echo "ERROR: DHCP-SERVER no esta instalado"
		echo ""
		return 1
	fi
	
	echo "========== DETENER SERVIDOR DHCP =========="
	echo ""
	
	sudo systemctl stop dhcpd.service
	
	if [[ $? -eq 0 ]]; then
		echo "Servidor DHCP detenido correctamente"
		echo ""
	else
		echo "Error al detener el servidor DHCP"
		echo ""
	fi
}

monitor(){
	clear
	
	if ! zypper se -i dhcp-server > /dev/null 2>&1; then
		echo ""
		echo "ERROR: DHCP-SERVER no esta instalado"
		echo "Ejecute el comando 'verificar' primero"
		echo ""
		return 1
	fi
	
	if [ "$SCOPE" = "X" ] || [ "$IPINICIAL" = "X" ] || [ "$IPFINAL" = "X" ] || [ "$LEASE" = "X" ]; then
		echo ""
		echo "ERROR: Los parametros no estan configurados"
		echo "Ejecute el comando 'parametrosconf' primero"
		echo ""
		return 1
	fi
	
	if ! systemctl is-active --quiet dhcpd.service; then
		echo ""
		echo "ERROR: El servidor DHCP no esta en ejecucion"
		echo "Ejecute el comando 'iniciar' primero"
		echo ""
		return 1
	fi
	
	trap 'echo ""; echo "Saliendo del monitor..."; exit 0' SIGINT SIGTERM
	
	echo "========== MONITOR DHCP - TIEMPO REAL =========="
	echo "Presione Ctrl+C para salir"
	echo ""
	sleep 2
	
	while true; do
		clear
		echo "========== MONITOR DHCP - TIEMPO REAL =========="
		echo "Servidor: $SCOPE"
		echo "Rango: $(incrementar_ip "$IPINICIAL") - $IPFINAL"
		echo "Actualizando cada 3 segundos... (Ctrl+C para salir)"
		echo ""
		echo "================================================"
		
		if [[ -f /var/lib/dhcp/db/dhcpd.leases ]]; then
			echo ""
			echo "CLIENTES CONECTADOS:"
			echo "================================================"
			
			local lease_file="/var/lib/dhcp/db/dhcpd.leases"
			local ahora=$(date +%s)
			
			awk -v ahora="$ahora" '
			function fecha_a_timestamp(fecha) {
				# Convertir fecha "2025/02/11 10:30:45" a timestamp
				cmd = "date -d \"" fecha "\" +%s 2>/dev/null"
				cmd | getline timestamp
				close(cmd)
				return timestamp
			}
			
			/^lease/ {
				ip = $2
				ends = ""
			}
			/hardware ethernet/ {
				mac = $3
				gsub(";", "", mac)
			}
			/client-hostname/ {
				hostname = $2
				gsub("\"", "", hostname)
				gsub(";", "", hostname)
			}
			/ends/ {
				# Formato: ends 2 2025/02/11 10:30:45;
				if ($2 == "never") {
					ends = "never"
				} else {
					ends = $3 " " $4
					gsub(";", "", ends)
				}
			}
			/binding state active/ {
				if (ip != "" && mac != "") {
					# Verificar si el lease ha expirado
					activo = 0
					if (ends == "never") {
						activo = 1
					} else if (ends != "") {
						timestamp_fin = fecha_a_timestamp(ends)
						if (timestamp_fin > ahora) {
							activo = 1
						}
					}
					
					if (activo == 1) {
						printf "IP: %-15s | MAC: %-17s | Host: %s\n", ip, mac, (hostname != "" ? hostname : "Desconocido")
						clientes_activos++
					}
					
					ip = ""
					mac = ""
					hostname = ""
					ends = ""
				}
			}
			
			END {
				print "" > "/tmp/dhcp_count.tmp"
				print clientes_activos+0 > "/tmp/dhcp_count.tmp"
			}
			' "$lease_file" | sort -u
			
			local count=0
			if [[ -f /tmp/dhcp_count.tmp ]]; then
				count=$(cat /tmp/dhcp_count.tmp)
				rm -f /tmp/dhcp_count.tmp
			fi
			
			echo "================================================"
			echo "Total de clientes activos: $count"
			echo ""
		else
			echo ""
			echo "No se encontro el archivo de leases"
			echo "Ruta esperada: /var/lib/dhcp/db/dhcpd.leases"
			echo ""
		fi
		
		echo "Ultima actualizacion: $(date '+%Y-%m-%d %H:%M:%S')"
		
		sleep 3
	done
}

# ============= COMANDOS ===================================================

if [ "$1" = "help" ]; then
	echo ""
	echo "============ COMANDOS ============"
	echo "verificar       : Verificar si esta instalado DHCP-SERVER"
	echo "parametros      : Ver parametros configurados"
	echo "parametrosconf  : Modificar los parametros"
	echo "iniciar         : Iniciar el servidor DHCP"
	echo "detener         : Detener el servidor DHCP"
	echo "monitor         : Ver clientes conectados en tiempo real"
	echo ""
fi

if [ "$1" = "verificar" ]; then
	verificar
fi

if [ "$1" = "parametros" ]; then
	ver_parametros
fi

if [ "$1" = "parametrosconf" ]; then
	conf_parametros
fi

if [ "$1" = "iniciar" ]; then
	iniciar_servidor
fi

if [ "$1" = "detener" ]; then
	detener_servidor
fi

if [ "$1" = "monitor" ]; then
	monitor
fi
