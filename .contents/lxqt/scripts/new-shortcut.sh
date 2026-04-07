#!/bin/bash

# --- KONFIGURACE ---
BUSY_SCRIPT="$HOME/.local/bin/busy-launch.py"
APPS_DIR="$HOME/.local/share/applications"

# Barvičky
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- HLAVNÍ SMYČKA ---
while true; do

    clear
    echo -e "${CYAN}--- GENERÁTOR ZÁSTUPCŮ (verze 9.3 - Loop Mode) ---${NC}"

    # 1. NÁZEV
    echo ""
    read -e -p "Zadej název aplikace: " APP_NAME
    if [ -z "$APP_NAME" ]; then 
        echo -e "${RED}Chyba: Název je povinný!${NC}"
        # Pokud uživatel nic nezadá, zeptáme se, jestli chce skončit nebo zkusit znovu
        read -p "Chceš to zkusit znovu? (y/N): " RETRY
        if [[ "$RETRY" =~ ^[yY]$ ]]; then continue; else exit 1; fi
    fi

    APP_COMMENT="Spustit $APP_NAME"
    SAFE_NAME=$(echo "$APP_NAME" | iconv -f utf8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    FILE_NAME="${SAFE_NAME}.desktop"

    # 2. KATEGORIE
    echo ""
    echo "Vyber kategorii:"
    echo "1) 🎮 Hry"
    echo "2) 🌍 Internet"
    echo "3) 🎨 Grafika"
    echo "4) 💼 Kancelář"
    echo "5) 🎬 Zvuk a Video"
    echo "6) 🛠️  Systémové nástroje"
    echo "7) 💻 Vývoj"
    echo "8) 🎒 Příslušenství"

    read -p "Zadej číslo (1-8): " CAT_NUM
    case $CAT_NUM in
        1) CATEGORY="Game";;
        2) CATEGORY="Network";;
        3) CATEGORY="Graphics";;
        4) CATEGORY="Office";;
        5) CATEGORY="AudioVideo";;
        6) CATEGORY="System;Utility";;
        7) CATEGORY="Development";;
        8) CATEGORY="Qt;Utility";;
        *) CATEGORY="Utility";;
    esac

    # 3. PŘÍKAZ & DETEKCE TYPU
    echo ""
    echo -e "${CYAN}Zadej příkaz nebo cestu k souboru.${NC}"
    echo "(Můžeš zadat i celý příkaz s parametry, např: pcmanfm 'cesta')"
    read -e -p "Příkaz: " RAW_INPUT

    if [ -z "$RAW_INPUT" ]; then 
        echo -e "${RED}Chyba: Příkaz je povinný!${NC}"
        read -p "Chceš to zkusit znovu? (y/N): " RETRY
        if [[ "$RETRY" =~ ^[yY]$ ]]; then continue; else exit 1; fi
    fi

    # --- PARSOVÁNÍ VSTUPU ---
    IS_WINE_MANUAL=0
    if [[ "$RAW_INPUT" == wine* ]]; then
        IS_WINE_MANUAL=1
        TEMP_INPUT=${RAW_INPUT#wine }
    else
        TEMP_INPUT="$RAW_INPUT"
    fi

    # Získání čisté cesty
    REAL_PATH=$(eval echo "$TEMP_INPUT")
    DETECTED_DIR=$(dirname "$REAL_PATH")
    BASENAME=$(basename "$REAL_PATH")
    NAME_NO_EXT="${BASENAME%.*}"

    # --- INTELIGENTNÍ ROZHODOVÁNÍ ---
    USE_WRAPPER=1      
    USE_TERMINAL="false" 
    IS_EXE=0

    # A) Je to Shell Skript (.sh)?
    if [[ "$REAL_PATH" =~ \.[sS][hH]$ ]]; then
        echo -e "${GREEN}ℹ️  Detekován Shell skript (.sh)${NC}"
        echo -e "   -> Vypínám python wrapper (zamezení timeoutu)"
        echo -e "   -> Zapínám terminál"
        USE_WRAPPER=0
        USE_TERMINAL="true"
        FINAL_APP_EXEC="\"$REAL_PATH\""

    # B) Je to Windows Executable (.exe)?
    elif [[ "$REAL_PATH" =~ \.[eE][xX][eE]$ ]]; then
        IS_EXE=1
        if [ "$IS_WINE_MANUAL" -eq 0 ]; then
            echo -e "${GREEN}ℹ️  Detekován .exe soubor bez 'wine'${NC}"
            echo -e "   -> Automaticky přidávám prefix 'wine'"
        fi
        FINAL_APP_EXEC="wine \"$REAL_PATH\""
        
    # C) Ostatní
    else
        if [ "$IS_WINE_MANUAL" -eq 1 ]; then
            FINAL_APP_EXEC="wine \"$REAL_PATH\""
        else
            if [ -f "$REAL_PATH" ]; then
                 FINAL_APP_EXEC="\"$REAL_PATH\""
            else
                 FINAL_APP_EXEC="$TEMP_INPUT"
            fi
        fi
    fi

    # Path (Pracovní adresář)
    if [ -d "$DETECTED_DIR" ] && [ "$DETECTED_DIR" != "." ]; then
        PATH_ENTRY="Path=$DETECTED_DIR"
    else
        PATH_ENTRY=""
    fi

    # 4. IKONA
    echo ""
    APP_ICON=""

    # Logika extrakce (jen pro EXE)
    if [ "$IS_EXE" -eq 1 ]; then
        read -p "Chceš zkusit vytáhnout ikonu z .exe souboru? (y/N): " EXTRACT_CHOICE
        if [[ "$EXTRACT_CHOICE" =~ ^[yY]$ ]]; then
            # KONTROLA BALÍKU ICOUTILS
            if ! command -v wrestool &> /dev/null; then
                echo ""
                echo -e "${RED}❌ CHYBA: Chybí balík 'icoutils'!${NC}"
                echo "Možnosti:"
                echo " y) Pokračovat ve vytváření (zadat ikonu ručně)"
                echo " n) Ukončit skript a jít instalovat"
                echo ""
                read -p "Volba (y/N): " CONTINUE_CHOICE
                
                if [[ "$CONTINUE_CHOICE" =~ ^[yY]$ ]]; then
                    echo -e "${YELLOW}⚠️  Pokračuji k ručnímu výběru ikony...${NC}"
                else
                    echo ""
                    echo -e "${CYAN}Pro instalaci spusť:${NC}"
                    echo -e "${YELLOW}sudo apt install icoutils${NC}"
                    echo ""
                    exit 1
                fi
            else
                # MÁME ICOUTILS
                echo "🔍 Kuchám ikonu..."
                wrestool -x -t 14 "$REAL_PATH" > "/tmp/${NAME_NO_EXT}.ico" 2>/dev/null
                if [ -s "/tmp/${NAME_NO_EXT}.ico" ]; then
                    mkdir -p "/tmp/${NAME_NO_EXT}_icons"
                    icotool -x "/tmp/${NAME_NO_EXT}.ico" -o "/tmp/${NAME_NO_EXT}_icons"
                    BIGGEST_ICON=$(ls -S "/tmp/${NAME_NO_EXT}_icons"/*.png 2>/dev/null | head -n 1)
                    if [ ! -z "$BIGGEST_ICON" ]; then
                        TARGET_ICON="$DETECTED_DIR/$NAME_NO_EXT.png"
                        cp "$BIGGEST_ICON" "$TARGET_ICON"
                        APP_ICON="$TARGET_ICON"
                        echo -e "${GREEN}✅ Ikona uložena: $TARGET_ICON${NC}"
                    fi
                    rm "/tmp/${NAME_NO_EXT}.ico"
                    rm -rf "/tmp/${NAME_NO_EXT}_icons"
                else
                    echo -e "${RED}❌ Ikonu se nepodařilo najít.${NC}"
                fi
            fi
        fi
    fi

    # Hledání existující ikony
    if [ -z "$APP_ICON" ]; then
        POTENTIAL_ICON="$DETECTED_DIR/$NAME_NO_EXT.png"
        if [ -f "$POTENTIAL_ICON" ]; then
            echo -e "${GREEN}✨ Nalezena existující ikona: $NAME_NO_EXT.png${NC}"
            APP_ICON="$POTENTIAL_ICON"
        fi
    fi

    # Ruční zadání
    if [ -z "$APP_ICON" ]; then
        echo -e "${YELLOW}⚠️  Ikona nenalezena.${NC}"
        echo -e "${CYAN}Zadej cestu k ikoně:${NC}"
        read -e -p "Ikona: " RAW_ICON_INPUT
        APP_ICON=$(eval echo "$RAW_ICON_INPUT")
    fi

    # 5. SESTAVENÍ FINAL EXEC
    if [ "$USE_WRAPPER" -eq 1 ]; then
        FINAL_EXEC_LINE="python3 \"$BUSY_SCRIPT\" $FINAL_APP_EXEC"
    else
        FINAL_EXEC_LINE="$FINAL_APP_EXEC"
    fi

    # 6. ZÁPIS SOUBORU
    OUTPUT_FILE="$APPS_DIR/$FILE_NAME"

    cat > "$OUTPUT_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=$APP_COMMENT
Exec=$FINAL_EXEC_LINE
Icon=${APP_ICON:-applications-other}
$PATH_ENTRY
Categories=$CATEGORY;
Terminal=$USE_TERMINAL
StartupNotify=false
EOF

    # 7. DOKONČENÍ
    chmod +x "$OUTPUT_FILE"
    update-desktop-database "$APPS_DIR"

    echo ""
    echo -e "${GREEN}✅ HOTOVO!${NC}"
    echo -e "Zástupce vytvořen: $OUTPUT_FILE"
    if [ "$USE_TERMINAL" == "true" ]; then
        echo -e "(Režim terminálu aktivní)"
    fi

    # --- SMYČKA NEBO KONEC ---
    echo ""
    echo "----------------------------------------"
    echo -e "${CYAN}Chceš vytvořit dalšího zástupce? (y/N)${NC}"
    read -p "> " AGAIN
    
    if [[ "$AGAIN" =~ ^[yY]$ ]]; then
        echo "Restartuji..."
        sleep 0.5
        continue
    else
        echo "Končím. Měj se!"
        break
    fi

done
