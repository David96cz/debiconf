#!/bin/bash
# ULTIMÁTNÍ SPOTLIGHT DÉMON PRO ALBERTA
MEDIA_DIR="/media/$USER"
MNT_DIR="/mnt"
mkdir -p "$MEDIA_DIR" "$MNT_DIR"

inotifywait -m -r -e create -e moved_to --format '%w%f' "$HOME" "$MEDIA_DIR" "$MNT_DIR" 2>/dev/null |
while read -r FILE; do
    
    # 1. BASHOVÁ ZEĎ (Absolutní filtr skrytých souborů)
    if [[ "$FILE" == */.* ]]; then
        continue
    fi
    
    # 2. AGRESIVNÍ DEBOUNCE (Požírač událostí z kopírování)
    # Tento vnitřní cyklus přečte a zahodí všechny další soubory, které
    # přijdou do roury. Skončí až ve chvíli, kdy 2 vteřiny nepřijde žádný nový soubor.
    while read -t 2 -r EXTRA_FILE; do
        continue
    done
    
    # 3. KOPÍROVÁNÍ SKONČILO (2 vteřiny ticha). Můžeme restartovat Alberta.
    if pgrep -x "albert" > /dev/null; then
        # POZOR: Vyhoď tu -9! Albert si ukládá data do SQLite databáze. 
        # Kill -9 (SIGKILL) nedovolí databázi uzavřít zápis a za týden se ti ten index rozjebe a koruptne.
        # Normální killall (SIGTERM) ho bezpečně a rychle ukončí.
        killall albert 2>/dev/null
        
        # Dáme mu chvilku, aby stihl zapsat indexy před smrtí, a zapneme ho
        sleep 0.5
        albert &
    fi
done