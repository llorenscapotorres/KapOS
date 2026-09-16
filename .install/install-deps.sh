#!/bin/bash
set -e

if command -v apt-get $> /dev/null; then
	sudo apt-get update && sudo apt-get install -y nasm qemu-system-x86
elif command -v dnf &> /dev/null; then
    sudo dnf install -y nasm qemu-system-x86
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm nasm qemu-arch-extra
else
    echo "Error: Gestor de paquetes no detectado"
    exit 1
fi

echo "✓ Dependencias instaladas"
