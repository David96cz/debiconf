#!/bin/bash

# ==============================================================================
# DEBICONF - ULTIMATE REFACTORED VERSION (S FIXEM PRO MOTIV A ZKRATKY)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Nutno spustit jako root (sudo)"
    exit 1
fi

# --- DEFINICE CEST ---
REAL_USER=$(ls /home | head -n 1)
USER_HOME="/home/$REAL_USER"
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$CONTENTS_DIR/setup-config.txt"
SHORTCUTS_SRC="$CONTENTS_DIR/lxqt/shortcuts.conf"

# --- 1. INTERAKTIVNÍ DOTAZY ---
echo "--------------------------------------------------"
echo "KONFIGURACE INSTALACE"
echo "--------------------------------------------------"

read -p "1) KDE Plasma | 2) LXQT (Ready out of the box): " DISTRO_ANS
case $DISTRO_ANS in
    1) DESKTOP_ENV="PLASMA" ;;
    *) DESKTOP_ENV="LXQT" ;;
esac

echo "--------------------------------------------------"
echo "VÝBĚR PROHLÍŽEČE:"
echo "1) Chrome | 2) Chromium | 3) Brave | 4) Firefox | 5) Žádný"
read -p "Vyber číslo: " BROWSER_CHOICE

echo "--------------------------------------------------"
echo "Chceš nastavit automatické přihlašování?" 
read -p "(1 = ANO, 2 = NE): " AUTO_ANS
[[ "$AUTO_ANS" == "1" ]] && { AUTOLOGIN_REQ="TRUE"; RELOGIN_REQ="TRUE"; } || { AUTOLOGIN_REQ="FALSE"; RELOGIN_REQ="FALSE"; }

echo "--------------------------------------------------"
echo "STARTUJI INSTALACI: $DESKTOP_ENV"
echo "--------------------------------------------------"

# --- 2. NAČTENÍ KONFIGURÁKŮ A ZÁKLADNÍ INSTALACE ---
apt update && apt install -y sudo curl wget dpkg-dev git dbus-x11 numlockx
usermod -aG sudo $REAL_USER

# Čtení globálních proměnných
BOOT_LOGO=$(grep -i "^BOOT_LOGO=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]')
CONFIRM_LOGOUT=$(grep -i "^CONFIRM_LOGOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
[[ "$CONFIRM_LOGOUT" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"

# Načtení balíčků
GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)
LOCAL_CONFIG="$CONTENTS_DIR/$(echo $DESKTOP_ENV | tr '[:upper:]' '[:lower:]')/config.txt"

if [ ! -f "$LOCAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Konfigurace prostředí $LOCAL_CONFIG chybí!"
    exit 1
fi

CORE_PACKAGES=$(sed -n '/^\[CORE_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
EXTRA_PACKAGES=$(sed -n '/^\[EXTRA_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
ALL_PACKAGES="$CORE_PACKAGES $EXTRA_PACKAGES $GLOBAL_PACKAGES"

# --- 3. INSTALACE BALÍKŮ (FOR CYKLUS) ---
echo "Instaluji balíky jeden po druhém..."
for pkg in $ALL_PACKAGES; do
    apt install -y --no-install-recommends "$pkg" || echo "⚠️ SELHALO: $pkg (přeskakuji)"
done

# Prohlížeč
case $BROWSER_CHOICE in
    1) wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt install -y /tmp/chrome.deb ;;
    2) apt install -y chromium chromium-l10n ;;
    3) curl -fsS https://dl.brave.com/install.sh | sh ;;
    4) apt install -y firefox-esr firefox-esr-l10n-cs ;;
esac

# --- 4. LXQT TÉMA A KONFIGY (Source of Truth) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # Instalace Lubuntu Artwork (Motiv)
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip
    
    # Kopírování TVÝCH konfigů (Zde se nahrají tvoje zálohy)
    CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null

    # Panel Patch
    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi

    # Skripty
    SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    mkdir -p "$USER_HOME/.local/bin"
    if [ -d "$SCRIPTS_SRC" ]; then
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null
    fi
fi

# --- 5. SYSTÉMOVÉ FINÁLE (LOCALE, TOUCHPAD, PATH) ---
# Locale
sed -i 's/^# cs_CZ.UTF-8 UTF-8/cs_CZ.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=cs_CZ.UTF-8 LC_ALL=cs_CZ.UTF-8
localectl set-locale LANG=cs_CZ.UTF-8

usermod -aG audio,pulse,pulse-access,video,plugdev $REAL_USER

# Fix PATH v .bashrc
if ! grep -q ".local/bin" "$USER_HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
fi

# Automount (Polkit)
mkdir -p /etc/polkit-1/rules.d
echo 'polkit.addRule(function(action, subject) { if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" || action.id == "org.freedesktop.udisks2.filesystem-mount") && subject.isInGroup("sudo")) { return polkit.Result.YES; } });' > /etc/polkit-1/rules.d/50-udisks2-automount.rules

# Touchpad (X11) - načtení z externího konfigu
TOUCHPAD_SRC="$CONTENTS_DIR/lxqt/config/touchpad.conf"
mkdir -p /etc/X11/xorg.conf.d

if [ -f "$TOUCHPAD_SRC" ]; then
    echo ">> Kopíruji nastavení touchpadu..."
    cp "$TOUCHPAD_SRC" /etc/X11/xorg.conf.d/40-libinput-touchpad.conf
else
    echo ">> VAROVÁNÍ: $TOUCHPAD_SRC nenalezen, touchpad zůstane ve výchozím stavu."
fi

# --- 6. LXQT TWEAKY (REFACTORED) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # 1. FIX LXQT.CONF (Už žádné cat > !)
    # Měníme jen nezbytné, zbytek motivu Lubuntu Arc zůstane zachován.
    LXQT_CONF="$USER_HOME/.config/lxqt/lxqt.conf"
    if [ -f "$LXQT_CONF" ]; then
        sed -i "s/^ask_before_logout=.*/ask_before_logout=$CONF_OUT/" "$LXQT_CONF"
        sed -i "s/^language=.*/language=cs_CZ/" "$LXQT_CONF"
        sed -i "s/^theme=.*/theme=Lubuntu Arc/" "$LXQT_CONF"
    fi

    # 2. DYNAMICKÉ ZKRATKY Z TEXTÁKU
    SHORTCUTS_CONF="$USER_HOME/.config/lxqt/globalkeyshortcuts.conf"
    if [ -f "$SHORTCUTS_SRC" ]; then
        # Vymažeme staré zkratky se suffixem .99, ať se nedublují
        sed -i '/\.99\]/,+3d' "$SHORTCUTS_CONF" 2>/dev/null
        
        while IFS='|' read -r label shortcut cmd || [[ -n "$label" ]]; do
            [[ "$label" =~ ^#.*$ || -z "$label" ]] && continue
            # Přidání zkratky s absolutní cestou pro brightness.sh
            FINAL_CMD=$(echo "$cmd" | sed "s|brightness.sh|$USER_HOME/.local/bin/brightness.sh|g")
            echo -e "\n[${shortcut}.99]\nComment=$label\nEnabled=true\nExec=$FINAL_CMD" >> "$SHORTCUTS_CONF"
        done < "$SHORTCUTS_SRC"
    fi
    chmod +s $(which brightnessctl) 2>/dev/null

    # 3. BUSY LAUNCH & IKONY PANELU
    WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    LOCAL_APPS="$USER_HOME/.local/share/applications"
    mkdir -p "$LOCAL_APPS"
    
    # Wrappery pro všechny aplikace
    for app in /usr/share/applications/*.desktop; do
        app_name=$(basename "$app")
        cp "$app" "$LOCAL_APPS/"
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$LOCAL_APPS/$app_name"
    done

    # Skrývání aplikací
    for app in "${APPS_TO_HIDE[@]}"; do
        [ -f "$LOCAL_APPS/$app" ] && sed -i '/^NoDisplay=/d; $ a NoDisplay=true' "$LOCAL_APPS/$app"
    done

    # Panel Quicklaunch
    PANEL_CONF="$USER_HOME/.config/lxqt/panel.conf"
    case $BROWSER_CHOICE in
        1) B_NAME="google-chrome.desktop" ;;
        2) B_NAME="chromium.desktop" ;;
        3) B_NAME="brave-browser.desktop" ;;
        4) B_NAME="firefox-esr.desktop" ;;
        *) B_NAME="" ;;
    esac

    if [ -f "$PANEL_CONF" ]; then
        sed -i '/^apps\\/d' "$PANEL_CONF"
        if [ -n "$B_NAME" ]; then
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\2\\\\desktop=$LOCAL_APPS/$B_NAME\napps\\\\size=2" "$PANEL_CONF"
        else
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\size=1" "$PANEL_CONF"
        fi
    fi

    # 4. OSTATNÍ (QTerminal, Tisk, Autostart)
    # QTerminal
    Q_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$Q_CONF")"
    [ ! -f "$Q_CONF" ] && echo -e "[General]\nshowTerminalSizeHint=false" > "$Q_CONF" || sed -i '/showTerminalSizeHint/d; /\[General\]/a showTerminalSizeHint=false' "$Q_CONF"

    # --- KONTEXTOVÉ MENU (Akce pro správce souborů) ---
    CONTEXT_CONF="$CONTENTS_DIR/lxqt/config/contextmenu.conf"
    ACTION_DIR="$USER_HOME/.local/share/file-manager/actions"

    if [ -s "$CONTEXT_CONF" ]; then
        echo ">> Generuji akce kontextového menu z $CONTEXT_CONF..."
        mkdir -p "$ACTION_DIR"
        CURRENT_FILE=""

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Detekce nového bloku (řádek začínající FILE:)
            if [[ "$line" =~ ^FILE:\ (.*\.desktop)$ ]]; then
                CURRENT_FILE="${BASH_REMATCH[1]}"
                # Vytvoření prázdného souboru pro novou akci
                > "$ACTION_DIR/$CURRENT_FILE"
            # Zápis do souboru (pokud už nějaký čteme a řádek není prázdný zbytečně)
            elif [ -n "$CURRENT_FILE" ]; then
                echo "$line" >> "$ACTION_DIR/$CURRENT_FILE"
            fi
        done < "$CONTEXT_CONF"
    else
        echo ">> VAROVÁNÍ: $CONTEXT_CONF je prázdný nebo chybí, akce v menu se negenerují."
    fi

    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config" "$USER_HOME/.local"
fi

# --- 7. LIGHTDM, GRUB A RESTART ---
if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
    # Numlock pro LightDM
    sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' /etc/lightdm/lightdm.conf 2>/dev/null
fi

# Grub
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub
systemctl set-default graphical.target

echo "=================================================="
echo " HOTOVO. Motiv zůstal, zkratky jsou vymlácený."
echo " REBOOT ZA 5 SEKUND."
echo "=================================================="
sleep 5
reboot
