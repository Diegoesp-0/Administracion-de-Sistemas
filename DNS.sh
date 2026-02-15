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

	echo "=============== IP CLIENTE =============="
	echo ""
	read -p "Ingrese la IP del cliente: " IP_CLIENTE

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
	
	echo "Probando resolucion DNS..."
	nslookup reprobados.com 127.0.0.1

	echo "Probando pong..."
	ping -c 3 www.reprobados.com

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
