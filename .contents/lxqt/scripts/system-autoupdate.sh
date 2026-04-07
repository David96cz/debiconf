#!/bin/bash

# true = Zablokuje aktualizace jádra | false = Povolí (Doporučuji FALSE pro Debian)
BLOCK_KERNEL_UPDATES=false

sleep 120
export DEBIAN_FRONTEND=noninteractive

# Správné názvy pro Debian
KERNEL_PACKAGES="linux-image-amd64 linux-headers-amd64"

if [ "$BLOCK_KERNEL_UPDATES" = true ]; then
    apt-mark hold $KERNEL_PACKAGES > /dev/null
else
    apt-mark unhold $KERNEL_PACKAGES > /dev/null
fi

apt-get update -qq

# full-upgrade je na Debianu Stable v pohodě, ale 'dist-upgrade' je v cronu jistota
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

apt-get autoremove -y -qq
apt-get autoclean -qq