#!/bin/bash

# Nastavení jasu podle parametru (up/down)
if [ "$1" == "-i" ]; then
    brightnessctl set +5%
elif [ "$1" == "-d" ]; then
    brightnessctl set 5%-
fi

# Vytažení aktuální procentuální hodnoty
JAS=$(brightnessctl -m | awk -F, '{print $4}')

# Soubor pro paměť ID
ID_FILE="/tmp/jas_notif_id"

# Přidán parametr -a "Jas" pro zamaskování hlavičky
if [ -f "$ID_FILE" ]; then
    NOTIF_ID=$(cat "$ID_FILE")
    NEW_ID=$(notify-send -a "Jas monitoru" -p -r "$NOTIF_ID" "Aktuální úroveň: $JAS" -t 1500 -i video-display)
else
    NEW_ID=$(notify-send -a "Jas monitoru" -p  "Aktuální úroveň: $JAS" -t 1500 -i video-display)
fi

echo "$NEW_ID" > "$ID_FILE"
