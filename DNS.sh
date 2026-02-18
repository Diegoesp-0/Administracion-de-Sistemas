#!/bin/bash

DOMINIO="reprobados.com"

#==================== FUNCIONES ====================
verificar(){
	if rpm -q bind > /dev/null 2>&1
	then
		echo ""
		echo "BIND ya esta instalado :D"
		echo ""
		sleep 2
	else
		echo ""
		echo "BIND no esta instalado"
		echo ""
		read -p "Desea descargar BIND? (S/s): " OPC
	
		if [ "$OPC" = "S" ] || [ "$OPC" = "s" ]
		then
			clear
			echo ""
			echo "Descargando BIND..."
			sudo zypper install -y bind bind-utils bind-doc
		fi
	fi
}
iniciar(){
	if systemctl is-active --quiet named
	then
		clear
		echo ""
		echo "El servidor ya esta corriendo..."
		echo ""
		sleep 2
	else
		clear
		sudo systemctl enable named
		sudo systemctl start named
		echo ""
		echo "Iniciando servicio..."
		echo ""
		if systemctl is-active --quiet named
		then
			echo "Servicio inciado correctamente..."
		else
			echo "Error al iniciar el servicio..."
			exit 1
		fi
	fi
}
configurar_zona(){
	clear
	IP_SERVER=$(ip -4 addr show | grep "192.168" | awk '{print $2}' | cut -d/ -f1)
	
while true; do
	echo "=============== IP CLIENTE =============="
	echo ""
	read -p "Ingrese la IP a la que apuntara el Dominio: " IP_CLIENTE
	
	if ! validar_ip "$IP_CLIENTE"
	then
		clear
		echo ""
		echo "La IP del cliente no es valida..."
		echo ""
		sleep 2
		continue
	else
		break
	fi
done
	if grep -q "$DOMINIO" /etc/named.conf
	then
		clear
		
	else
		clear
cat >> /etc/named.conf <<EOF
zone "$DOMINIO" {
	type master;
	file "/var/lib/named/db.$DOMINIO";
};
EOF
	fi
cat > /var/lib/named/db.$DOMINIO <<EOF	
\$TTL 604800
@	IN	SOA ns1.$DOMINIO. admin.$DOMINIO. (
	2024010101 ; Serial
	604800	   ; Refresh
	86400	   ; Retry
	2419200	   ; Expire
	604800)	   ; Negative TTL
@	IN	NS	ns1.$DOMINIO.
ns1	IN	A	$IP_SERVER
@	IN 	A	$IP_CLIENTE	
www	IN	CNAME	@
EOF
	sudo systemctl restart named
	sudo firewall-cmd --add-service=dns --permanent
	sudo firewall-cmd --reload
	echo ""
	echo "Zona configurada y servicio reiniciado..."
}
validar(){
	clear
	echo "Verificando la sintaxis..."
	named-checkconf
	named-checkzone $DOMINIO /var/lib/named/db.$DOMINIO
	
	echo "Probando resolucion DNS..."
	nslookup $DOMINIO 127.0.0.1
	echo "Probando ping..."
	ping -c 3 www.$DOMINIO
}
validar_ip(){
	local ip=$1
	if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
	then
		return 1
	fi
	IFS='.' read -r p1 p2 p3 p4 <<< "$ip"
	
	for p in $p1 $p2 $p3 $p4
	do
		[[ $p -le 255 ]] || return 1
	done
	[[ $p1 -eq 0 && $p2 -eq 0 && $p3 -eq 0 && $p4 -eq 0 ]] && return 1	
	[[ $p1 -eq 255 && $p2 -eq 255 && $p3 -eq 255 && $p4 -eq 255 ]] && return 1
	[[ $p1 -eq 127 ]] && return 1
	
return 0
}
validar_ip_fija(){
	INTERFAZ="enp0s8"
	CONEXION=$(nmcli -t -f NAME,DEVICE connection show --active | grep "$INTERFAZ" | cut -d: -f1)
	METODO=$(nmcli -g ipv4.method connection show "$CONEXION")
	if [ "$METODO" = "auto" ]
	then
		clear
		echo ""
		echo "La interfaz es dinamica..."
		echo ""
		
		while true; do
			read -p "Ingrese la IP fija: " IP_FIJA
			
			if ! validar_ip "$IP_FIJA"
			then
				clear
				echo ""
				echo "IP invalida..."
				echo ""
				sleep 2
				continue
			else
				break
			fi
		done
	PREFIJO="24"
	GATEWAY=$(ip route | grep default | awk '{print $3}')
	DNS=$(nmcli -g ipv4.dns connection show "$CONEXION")
	
	sudo nmcli connection modify "$CONEXION" ipv4.method manual
	sudo nmcli connection modify "$CONEXION" ipv4.addresses "$IP_FIJA/$PREFIJO"
	sudo nmcli connection modify "$CONEXION" ipv4.gateway "$GATEWAY"
	sudo nmcli connection modify "$CONEXION" ipv4.dns "$DNS"
	sudo nmcli connection down "$CONEXION"
	sudo nmcli connection up "$CONEXION"
	else
		clear
		echo ""
		echo "La interfaz ya tiene IP fija..."
		echo ""
		sleep 2
	fi
}
arroz(){
	local -n _ARR=$1
	local NUEVA_LISTA="	local DOMINIOS=("
	for d in "${_ARR[@]}"; do
		NUEVA_LISTA+="\"$d\" "
	done
	NUEVA_LISTA="${NUEVA_LISTA% })"
	sed -i "s|^\tlocal DOMINIOS=(.*|${NUEVA_LISTA}|" "$(realpath "$0")"
}
menu(){
	local DOMINIOS=("reprobados.com")

	while true; do
		clear
		echo "========================================="
		echo "         SELECCIONAR DOMINIO"
		echo "========================================="
		echo ""
		echo "  Dominio activo: $DOMINIO"
		echo ""
		for i in "${!DOMINIOS[@]}"
		do
			echo "  $((i+1)). ${DOMINIOS[$i]}"
		done
		echo ""
		echo "  A. Agregar dominio"
		echo "  0. Salir"
		echo ""
		read -p "Seleccione una opcion: " OPC_DOM

		if [ "$OPC_DOM" = "0" ]; then
			break

		elif [ "$OPC_DOM" = "A" ] || [ "$OPC_DOM" = "a" ]; then
			echo ""
			read -p "Ingrese el nuevo dominio (ej: midominio.com): " NUEVO_DOM
			if [ -z "$NUEVO_DOM" ]; then
				echo "El dominio no puede estar vacio..."
				sleep 2
				continue
			fi
			local DUPLICADO=0
			for d in "${DOMINIOS[@]}"; do
				if [ "$d" = "$NUEVO_DOM" ]; then
					DUPLICADO=1
					break
				fi
			done
			if [ "$DUPLICADO" -eq 1 ]; then
				echo "El dominio [$NUEVO_DOM] ya existe en la lista..."
				sleep 2
			else
				DOMINIOS+=("$NUEVO_DOM")
				arroz DOMINIOS
				echo "Dominio [$NUEVO_DOM] agregado..."
				sleep 2
			fi

		elif [[ "$OPC_DOM" =~ ^[0-9]+$ ]] && [ "$OPC_DOM" -ge 1 ] && [ "$OPC_DOM" -le "${#DOMINIOS[@]}" ]; then
			DOMINIO="${DOMINIOS[$((OPC_DOM-1))]}"
			sed -i "s/^DOMINIO=.*/DOMINIO=\"$DOMINIO\"/" "$(realpath "$0")"
			echo ""
			echo "Dominio seleccionado: $DOMINIO"
			sleep 2
			break

		else
			echo "Opcion invalida..."
			sleep 2
		fi
	done
}

#==================== COMANDOS ====================
if [ "$1" = "verificar" ]; then
	verificar
fi
if [ "$1" = "iniciar" ]; then
	iniciar
fi
if [ "$1" = "configurar" ]; then
	configurar_zona
fi
if [ "$1" = "validar" ]; then
	validar
fi
if [ "$1" = "ipfija" ]; then
	validar_ip_fija
fi
if [ "$1" = "menu" ]; then
	menu
fi
if [ "$1" = "todo" ]; then
	verificar
	validar_ip_fija
	iniciar
	configurar_zona
	validar
fi
