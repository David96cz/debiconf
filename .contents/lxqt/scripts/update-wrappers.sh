#!/bin/bash

# --- NASTAVENÍ ---
SCRIPT_DIR="$HOME/.local/bin"
SCRIPT_PATH="$SCRIPT_DIR/busy-launch.py"

# Příkaz wrapperu
WRAPPER="python3 $SCRIPT_PATH"

LOCAL_APPS="$HOME/.local/share/applications"
SYSTEM_APPS="/usr/share/applications"

# --- BLACKLIST ---
BLACKLIST="flameshot|syncthing|nextcloud|kdeconnect|spectacle"

echo "🔧 Startuji inteligentní úpravu pro LXQt..."
echo "📂 Skripty jsou v: $SCRIPT_DIR"

mkdir -p "$LOCAL_APPS"

# --- ÚKLID MRTVOL PO ODINSTALACI ---
echo "🧹 Kontroluji a čistím smazané aplikace..."
for local_app in "$LOCAL_APPS"/*.desktop; do
    [ -e "$local_app" ] || continue
    
    # NOVÁ POJISTKA: Pokud je tam naše značka, nesahat!
    if grep -q "X-Debiconf-Custom=true" "$local_app"; then
        continue
    fi

    filename=$(basename "$local_app")
    system_app="$SYSTEM_APPS/$filename"

    if [ ! -f "$system_app" ]; then
        if grep -q "$SCRIPT_PATH" "$local_app"; then
            rm -f "$local_app"
        fi
    fi
done
# -----------------------------------

# Projdeme systémové aplikace
for app in "$SYSTEM_APPS"/*.desktop; do
    filename=$(basename "$app")
    local_file="$LOCAL_APPS/$filename"

    # --- FILTR 0: Je aplikace skrytá už v systému? ---
    # Pokud má zdrojový soubor NoDisplay=true, vůbec ho neřešíme.
    if grep -q "^NoDisplay=true" "$app"; then
        continue
    fi

    # --- FILTR 1 (KRITICKÝ): Máš ji skrytou lokálně? ---
    # Pokud soubor u tebe existuje A má NoDisplay=true, NESMÍME ho přepsat.
    if [ -f "$local_file" ]; then
        if grep -q "^NoDisplay=true" "$local_file"; then
            # echo "🙈 Ignoruji skrytou aplikaci: $filename"
            continue
        fi
    fi

    # 1. Teď už můžeme bezpečně zkopírovat (přepíšeme jen viditelné)
    cp -f "$app" "$local_file"
    chmod +x "$local_file"

    # --- FILTR 2: Blacklist (podle názvu) ---
    if echo "$filename" | grep -qE "$BLACKLIST"; then
        continue
    fi

    # --- FILTR 3: Terminál ---
    if grep -q "Terminal=true" "$local_file"; then
        continue
    fi

    # 3. Injektáž Wrapperu
    if ! grep -q "$SCRIPT_PATH" "$local_file"; then
        sed -i "s~^Exec=~Exec=$WRAPPER ~" "$local_file"
        
        # Úklid
        sed -i "/^TryExec=/d" "$local_file"
        sed -i "s/^DBusActivatable=true/DBusActivatable=false/" "$local_file"
    fi
done

# --- ZOBRAZENÉ APLIKACE (seznam uložený instalátorem debiconf) ---
SHOW_LIST="$HOME/.config/debiconf/apps-show.list"
if [ -f "$SHOW_LIST" ]; then
    while IFS= read -r show_app; do
        show_app="${show_app%$'\r'}"
        [ -n "$show_app" ] || continue
        [ -f "$LOCAL_APPS/$show_app" ] && sed -i '/^OnlyShowIn=/d; /^NotShowIn=/d; /^NoDisplay=/d; /^X-XfceSettingsManagerHidden=/d' "$LOCAL_APPS/$show_app"
    done < "$SHOW_LIST"
fi

# 4. Aktualizace databáze
update-desktop-database "$LOCAL_APPS"

echo "✅ Hotovo. Tvé skryté aplikace zůstaly nedotčeny."
