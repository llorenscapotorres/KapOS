#!/bin/bash
set -e

# Solo instalar si falta algo
if ! command -v nasm &> /dev/null || ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "Instalando dependencias..."
    make install-deps
else
    echo "Bless God!"
fi

# Execute OS

make --no-print-directory -s

qemu-system-x86_64 -M pc-i440fx-8.2 -drive file=build/main_disk.img,format=raw,if=ide -boot c
