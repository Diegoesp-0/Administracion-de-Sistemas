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

#  =============== FUNCIONES =============================================
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
	[[ "Slease" -gt 0 ]] || return 1
}

verificar(){
clear
	if zypper se -i dhcp-server > /dev/null 2>&1
	then
		echo ""
		echo "SHCP-SERVER esta instalado :D"
		echo ""
	else
		echo ""
		echo "El paquete SHCP-SERVER no esta instalado"
		echo ""
		read -p "Desea descargar DHCP-SERVER? (S/s): " OPC

		if [ "$OPC" = "S" ] || [ "$OPC" = "s" ]
		then
			echo "Descargando..."
			sudo zypper install dhcp-server
		fi		 
	fi
}

conf_parametros(){
clear
	echo "========== CONFIGURAR PARAMETROS ========== "
	read -p "Nombre del ambito: " SCOPE_T
	
	while true
	do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		read -p "IP inicial del rango: " INICIAL_T
		
		if ! validar_ip "$INICIAL_T"
		then	
			clear
			echo "La IP inicial no es valida"
			sleep 2
			continue
		fi

		read -p "IP final del rango: " FINAL_T
		
		if ! validar_ip "$FINAL_T"
		then
			clear
			echo "La IP final no es valida"
			sleep 2
			continue
		fi

		if ! validar_rango "$INICIAL_T" "$FINAL_T"	
		then 
			clear
			echo "La IP inicial debe ser menor a la IP final"
			sleep 2
			continue
		fi	
		break
	done		
	
	while true
	do 
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		read -p "Gateway: " GATEWAY_T
		
		if validar_gateway "$GATEWAY_T" "$INICIAL_T" >/dev/null 2>&1
		then
			break
		else
			clear
			echo "Gateway invalido..."
			sleep 2			
		fi
	done		
clear
	
	while true
	do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		echo "Gateway: $GATEWAY_T"
		read -p "DNS primario: " DNS_T

		if ! validar_dns "$DNS_T"
		then
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
		echo "Gateway: $GATEWAY_T"
		echo "DNS primario: $DNS_T"
		read -p "DNS secundario (Enter para omitir): " DNS2_T

		if [[ -z "$DNS2_T" ]]
		then
			DNS2_T="X"
			break
		fi

		if ! validar_dns "$DNS2_T"
		then
			clear
			echo "DNS secundario invalido..."
			sleep 2
			continue
		fi
		
		if [[ "$DNS_T" == "$DNS2_T" ]]
		then
			clear
			echo " El DNS secundario no puede ser igual al primario..."
			sleep 2
			continue
		fi

		break
	done

	while true
	do
		clear
		echo "========== CONFIGURAR PARAMETROS =========="
		echo "Nombre del ambito: $SCOPE_T"
		echo "IP inicial del rango: $INICIAL_T"
		echo "IP final del rango: $FINAL_T"
		echo "Gateway: $GATEWAY_T"
		echo "DNS primario: $DNS_T"
		[[ "$DNS2_T" != "X" ]] && echo "DNS secundario: $DNS2_T"
		
		read -p "Lease (en segundos): " LEASE_T
		
		if ! validar_lease "$LEASE_T"
		then
			clear
			echo "Lease invalido..."
			sleep 2
			continue
		fi
	done

	
	clear
	echo "========== CONFIGURAR PARAMETROS =========="
	echo "Nombre del ambito: $SCOPE_T"
	echo "IP inicial del rango: $INICIAL_T"
	echo "IP final del rango: $FINAL_T"
	echo "Gateway: $GATEWAY_T"
	echo "DNS primario: $DNS_T"
	[[ "$DNS2_T" != "X" ]] && echo "DNS secundario: $DNS2_T"
	echo "Lease (en segundos): $LEASE_T"
	echo "---------------------------------------------
	read -p "Datos capturados, precione enter para continuar..."

	sed -i "s/^SCOPE=.*/SCOPE=$SCOPE_T/" "$0"
	sed -i "s/^IPINICIAL=.*/IPINICIAL=$INICIAL_T/" "$0"
	sed -i "s/^IPFINAL=.*/IPFINAL=$FINAL_T/" "$0"
	sed -i "s/^GATEWAY=.*/GATEWAY=$GATEWAY_T/" "$0"
	sed -i "s/^DNS=.*/DNS=$DNS_T/" "$0"
	sed -i "s/^DNS2=.*/DNS2=$DNS2_T/" "$0"
	sed -i "s/^LEASE=.*/LEASE=$LEASE_T/" "$0"

}


ver_parametros(){
clear
	if [ "$SCOPE" = "X" ] && [ "$IPINICIAL" = "X" ] && [ "$IPFINAL" = "X" ] && [ "$GATEWAY" = "X" ] && [ "$DNS" = "X"  ] && [ "$LEASE" = "X" ]
	then	
		echo ""
		echo "Parametros no asignados..."
		echo ""
	else
		echo "========== PARAMETROS CONFIGURADOS =========="
		echo "SCOPE = $SCOPE"	
		echo "IP INICIAL = $IPINICIAL"
		echo "IP FINAL = $IPFINAL"
		echo "GATEWAY = $GATEWAY"
		echo "DNS = $DNS"
		echo "DNS 2= $DNS2"
		echo "LEASE = $LEASE"
		echo ""
	fi
	
}

# ============= COMANDOS ===================================================


if [ "$1" = "help" ]
then
	echo ""
	echo "============ COMANDOS ============"
	echo "verificar : Verificar si esta instalado DHCP-SERVER"
	echo "parametros : Ver parametros"
	echo "parametrosconf : Modificar los parametros"
	echo ""
fi

if [ "$1" = "verificar" ]
then
	verificar
fi 

if [ "$1" = "parametros" ]
then
	ver_parametros
fi

if [ "$1" = "parametrosconf" ]
then
	conf_parametros
fi
