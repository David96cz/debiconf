#!/bin/bash
# ULTIMÁTNÍ SPOTLIGHT DÉMON PRO ALBERTA (MENGELE-PROOF VERZE)
MEDIA_DIR="/media/$USER"
MNT_DIR="/mnt"
mkdir -p "$MEDIA_DIR" "$MNT_DIR"

# Přidán parametr -m (monitor). Inotify běží trvale na pozadí a posílá čisté cesty (--format '%w%f')
inotifywait -m -r -e create -e moved_to --format '%w%f' "$HOME" "$MEDIA_DIR" "$MNT_DIR" 2>/dev/null |
while read -r FILE; do
    
    # 1. BASHOVÁ ZEĎ (Absolutní filtr)
    # Pokud cesta obsahuje "/." (skrytá složka nebo soubor, např. /.config/ nebo /.local/), přeskoč to!
    if [[ "$FILE" == */.* ]]; then
        continue
    fi
    
    # 2. Reakce pouze na čisté, viditelné soubory
    if pgrep -x "albert" > /dev/null; then
        killall -9 albert 2>/dev/null
        albert &
        
        # Debounce: Uspíme tuhle smyčku na 1,5 vteřiny, aby se Albert nerestartoval 100x
        # když uživatel kopíruje do složky třeba 50 písniček najednou.
        sleep 1.5
    fi
done