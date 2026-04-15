#!/bin/bash
# ULTIMÁTNÍ SPOTLIGHT DÉMON PRO ALBERTA
MEDIA_DIR="/media/$USER"
MNT_DIR="/mnt"
mkdir -p "$MEDIA_DIR" "$MNT_DIR"

while true; do
    # 1. HLAVNÍ KOUZLO: Parametr -r zapne to, na co se vývojář Alberta vysral (REKURZIVNÍ sledování).
    # Démon se zavrtá do úplně každé složky i podsložky. 
    # 2. IGNORACE BALASTU: --exclude '/\.' ignoruje skryté soubory a složky (.cache, .config), 
    # takže se to neaktivuje, když ti na pozadí prohlížeč zapíše historii.
    inotifywait -r -e create -e moved_to --exclude '/\.' "$HOME" "$MEDIA_DIR" "$MNT_DIR" 2>/dev/null
    
    # Když inotifywait detekuje nový soubor (nebo složku), smyčka pokračuje sem.
    # Dáme 1 vteřinu pauzu. Je to "debounce" – pokud rozbaluješ archiv se 100 soubory, 
    # skript počká 1 vteřinu, než se všechny zapíšou, aby Alberta nerestartoval stokrát.
    sleep 1
    
    # Blesková, nemilosrdná vražda a okamžitý restart. Albert naběhne za 0.1s a okamžitě ví o novém souboru.
    killall -9 albert 2>/dev/null
    albert &
done