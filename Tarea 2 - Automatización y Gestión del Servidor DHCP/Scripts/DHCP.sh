#!/bin/bash

# =============== VARIABLES ==============================================

SCOPE=Conexion
IPINICIAL=192.168.100.30
IPFINAL=192.168.100.60
GATEWAY=192.168.100.1
DNS=8.8.8.8
DNS2=4.4.4.4
LEASE=5000
MASCARA=X

#  =============== FUNCIONES =============================================

calcular_mascara(){
   local ipInicial="$1"
   local ipFinal="$2"
   
   echo "Calculando mascara de subred para el rango $ipInicial - $ipFinal..."
   
   # Convertir IPs a números
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
      echo "ERROR: IP final menor que IP inicial"
      return 1
   fi
   
   local diferencia=$((ip2_dec - ip1_dec + 1))
   echo "IPs en el rango: $diferencia"
   
   local hosts_necesarios=$((diferencia + 2))
   echo "Hosts necesarios: $hosts_necesarios"
   
   #Calcular CIDR por hosts necesarios
   local cidr_hosts=32
   while [[ $cidr_hosts -ge 8 ]]; do
      # Calcular 2^(32-cidr) sin operadores <<
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
   
   #Calcular CIDR por misma subred
   local cidr_subred=32
   while [[ $cidr_subred -ge 8 ]]; do
      # Calcular máscara sin operadores <<
      local mascara_tmp=0
      # Poner 1's en los primeros cidr_subred bits
      for ((i=0; i<cidr_subred; i++)); do
         mascara_tmp=$(( (mascara_tmp * 2) + 1 ))
      done
      # Poner 0's en los bits restantes
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
   
   #Elegir el CIDR que cumpla AMBAS condiciones
   local cidr_final=$(( cidr_hosts < cidr_subred ? cidr_hosts : cidr_subred ))
   
   echo "CIDR necesario por hosts: /$cidr_hosts"
   echo "CIDR necesario por subred: /$cidr_subred"
   echo "CIDR final seleccionado: /$cidr_final"
   
   local mascara_dec=0
   # Poner 1's en los primeros cidr_final bits
   for ((i=0; i<cidr_final; i++)); do
      mascara_dec=$(( (mascara_dec * 2) + 1 ))
   done
   # Poner 0's en los bits restantes
   for ((i=cidr_final; i<32; i++)); do
      mascara_dec=$((mascara_dec * 2))
   done
   
   mascara=$(_dec2ip "$mascara_dec")
   
   # Calcular hosts disponibles sin operadores <<
   local bits_final=$((32 - cidr_final))
   local hosts_potencia=1
   for ((i=0; i<bits_final; i++)); do
      hosts_potencia=$((hosts_potencia * 2))
   done
   local hosts_finales=$((hosts_potencia - 2))
   
   echo "Máscara calculada: $mascara (CIDR: /$cidr_final)"
   echo "Hosts disponibles: $hosts_finales"
   
   # Verificar si el rango cabe en la subred
   local red_base=$(( ip1_dec & mascara_dec ))
   
   # Calcular broadcast sin operadores <<
   local broadcast=$(( (~mascara_dec) & 0x7FFFFFFF ))
   # Ajustar para 32 bits
   if [[ $mascara_dec -gt 0 ]]; then
      broadcast=$(( red_base | (0xFFFFFFFF & ~mascara_dec) ))
   else
      broadcast=0xFFFFFFFF
   fi
   
   if [[ $ip1_dec -lt $red_base || $ip2_dec -gt $broadcast ]]; then
      echo "  ERROR: El rango no cabe en la subred $(_dec2ip "$red_base")/$cidr_final"
      echo "  - Broadcast de la subred: $(_dec2ip "$broadcast")"
    return 1
   fi
   
   echo "Mascara de subred determinada: $mascara"
   return 0
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

verificar(){
clear
	if zypper se -i dhcp-server > /dev/null 2>&1
	then
		echo ""
		echo "DHCP-SERVER esta instalado :D"
		echo ""
	else
		echo ""
		echo "El paquete DHCP-SERVER no esta instalado"
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
		break
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
	echo "---------------------------------------------"
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
