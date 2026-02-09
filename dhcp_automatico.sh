#!/bin/bash

clear
echo "Verificando si esta instalado DHCP..."

if zypper se -i dhcp-server | grep -q dhcp-server
then
	echo ""
	echo "El servidor ya esta instalado :D"
else
	echo ""
	echo "El servidor no esta instalado"
	echo "Instalando..."
	sudo zypper install dhcp-server
fi

sleep 2

clear
echo "========= CONFIGURACION DHCP ========="
read -p "Nombre del ambito: " SCOPE


# cosa para validar la IP	
validar_ip(){
local ip=$1
local verificar=1
		
	if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]];
	then

	# Dividir la ip en partes
		IFS='.' read -r p1 p2 p3 p4 <<< "$ip"
	
	# Que los numeros esten maximo hasta 255
		if [[ $p1 -le 255 && $p2 -le 255 && $p3 -le 255 && $p4 -le 255 ]]
		then
			verificar=0
		fi
	fi

return $verificar
}

while true
do
	read -p "IP inicial del rango: " IPinicial
	if validar_ip $IPinicial
	then
		break
	else
		echo "IP no valida"
		sleep 1
	fi
done

while true
do
	read -p "IP final del rango: " IPfinal
	if validar_ip $IPfinal
	then
		break
	else
		echo "IP no valida"
		sleep 1
	fi
done

while true
do
	read -p "Puerta de enlace (Gateway): " GATEWAY
	if validar_ip $GATEWAY
	then
		break
	else
		echo "Gateway no valido"
		sleep 1
	fi
done

while true
do
	read -p "Servidor DNS: " DNS
	if validar_ip $DNS
	then
		break
	else
		echo "DNS no valido"
		sleep 1
	fi
done

while true
do
	read -p "Tiempo de concesion en segundos: " LEASE
	if [[ $LEASE =~ ^([0-9]+)$ ]]
	then
		break
	else
		echo "Debe ser un numero valido para los segundos"
		sleep 1
	fi
done
clear

echo "Configurando archivo DHCP..."


red = "${IPinicial%.*}.0"
mascara =  "255.255.255.0"

sudo bash -c "cat /etc/dhcp/dhcp.conf" << EOF
authoritative;

default-lease-time $LEASE;
max-lease-time $LEASE;

subnet $red netmask $mascara {
	range $IPinicial $IPfinal;
	option routers $GATEWAY;
	option domain-name-servers $DNS;
}
EOF
sleep 1


clear
ip -o link show

echo "----------------------------------------------"
read -p "Digite la interfaz de red: " INTERFAZ

sudo sed -i "s/^DHCPD_INTERFACE=.*/DHCPD_INTERFACE=\"%INTERFAZ\"/" /etc/sysconfig/dhcpd






























