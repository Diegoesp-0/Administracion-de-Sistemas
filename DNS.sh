#==================== FUNCIONES ====================

verificar(){
	if rpm -q bind > /dev/null 2>&1
	then
		echo ""
		echo "BIND ya esta instalado :D"
		echo ""
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
	read -p "Ingrese la IP del cliente: " IP_CLIENTE
	
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


	if grep -q "reprobados.com" /etc/named.conf
	then
		clear
		
	else
		clear
cat >> /etc/named.conf <<EOF
zone "reprobados.com" {
	type master;
	file "/var/lib/named/db.reprobados.com";
};
EOF
	fi

cat > /var/lib/named/db.reprobados.com <<EOF	
\$TTL 604800
@	IN	SOA ns1.reprobados.com. admin.reprobados.com. (
	2024010101 ; Serial
	604800	   ; Refresh
	86400	   ; Retry
	2419200	   ; Expire
	604800)	   ; Negative TTL


@	IN	NS	ns1.reprobados.com.
ns1	IN	A	$IP_SERVER
@	IN 	A	$IP_CLIENTE	
www	IN	CNAME	@
EOF

	sudo systemctl restart named
	echo ""
	echo "Zona configurada y servicio reiniciado..."

}

validar(){
	clear
	echo "Verificando la sintaxis..."
	named-checkconf
	named-checkzone reprobados.com /var/lib/named/db.reprobados.com
	
	echo "Probando resolucion DNS..."
	nslookup reprobados.com 127.0.0.1

	echo "Probando ping..."
	ping -c 3 www.reprobados.com

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

if [ "$1" = "todo" ]; then
	verificar
	validar_ip_fija
	iniciar
	configurar_zona
	validar
fi
