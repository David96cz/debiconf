#!/bin/bash

# Počkáme chvilku, než po startu plně naběhne udisks2 a prostředí
sleep 2

# Najde všechny oddíly, které mají filesystém, nejsou swap/EFI a nejsou připojené
for dev in $(lsblk -p -r -n -o NAME,FSTYPE,MOUNTPOINT | awk '$2 != "" && $2 != "swap" && $2 != "vfat" && $3 == "" {print $1}'); do
    udisksctl mount -b "$dev" >/dev/null 2>&1 || true
done