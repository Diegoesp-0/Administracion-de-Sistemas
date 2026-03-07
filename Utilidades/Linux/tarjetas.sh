#!/bin/bash

clear

echo "====================================="
echo "   Administrador de Interfaces Red"
echo "====================================="
echo ""

echo "Interfaces disponibles:"
echo "-----------------------"

ip -o link show | awk -F': ' '{print $2}'

echo ""
read -p "Escribe el nombre de la interfaz: " interfaz

echo ""
echo "¿Que deseas hacer?"
echo "1) Subir interfaz"
echo "2) Bajar interfaz"
echo ""
read -p "Selecciona una opcion: " opcion

case $opcion in
    1)
        echo "Subiendo interfaz $interfaz..."
        sudo ip link set $interfaz up
        ;;
    2)
        echo "Bajando interfaz $interfaz..."
        sudo ip link set $interfaz down
        ;;
    *)
        echo "Opcion no valida"
        ;;
esac

echo ""
echo "Estado actual de la interfaz:"
ip addr show $interfaz
