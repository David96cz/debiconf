#!/bin/bash
# Připravíme si cesty pro flashky i pro pevné disky
MEDIA_DIR="/media/$USER"
MNT_DIR="/mnt"

mkdir -p "$MEDIA_DIR"
mkdir -p "$MNT_DIR"

while true; do
    # inotifywait teď hlídá OBĚ složky současně.
    # Vzbudí se, jakmile se v /media nebo v /mnt objeví nový disk.
    inotifywait -e create -e delete "$MEDIA_DIR" "$MNT_DIR" 2>/dev/null
    
    # Dáme systému 2 sekundy na bezpečné připojení disku
    sleep 2
    
    # Bleskový restart Alberta pro okamžité načtení
    killall albert 2>/dev/null
    albert &
done