#!/bin/bash

# ==============================================================================
# DEBICONF - DEBIAN ULTIMATE SETUP SCRIPT
# ==============================================================================

# --- 1. DETEKCE UŽIVATELE A SUDO PRÁVA ---
if [ "$EUID" -ne 0 ]; then
    echo "Prosím, spusťte skript s právy root (sudo)."
    exit 1
fi

REAL_USER=$(ls /home | head -n 1)
USER_HOME="/home/$REAL_USER"
echo "Našel jsem uživatele: $REAL_USER. Dávám mu sudo práva..."
apt update && apt install -y sudo curl wget dpkg-dev git
usermod -aG sudo $REAL_USER

# --- 2. DEFINICE ABSOLUTNÍCH CEST ---
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$BASE_DIR/setup-config.txt"

# --- 3. VOLBA PROSTŘEDÍ A NAČTENÍ GLOBÁLNÍ KONFIGURACE ---
echo "Validuji globální konfiguraci ze setup-config.txt..."

if [ ! -f "$GLOBAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Globální konfigurace $GLOBAL_CONFIG chybí!"
    exit 1
fi

# --- INTERAKTIVNÍ VOLBA PROSTŘEDÍ ---
echo "--------------------------------------------------"
echo "VOLBA DESKTOPOVÉHO PROSTŘEDÍ"
echo "1) KDE Plasma"
echo "2) LXQT (Moderní Lubuntu-style)"
echo "--------------------------------------------------"
read -p "Vyber číslo (default 2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        DESKTOP_ENV="PLASMA"
        ;;
    2|*)
        DESKTOP_ENV="LXQT"
        ;;
esac

echo "Vybráno prostředí: $DESKTOP_ENV"

# Dočtení hodnot z texťáku
BROWSER_URL=$(grep -i "^BROWSER_URL=" "$GLOBAL_CONFIG" | cut -d'=' -f2-)
BOOT_LOGO=$(grep -i "^BOOT_LOGO=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
AUTOLOGIN=$(grep -i "^AUTOLOGIN=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1)

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then TIMEOUT="0"; fi

# Načtení globálních balíčků
GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)

# --- 4. NAČTENÍ SPECIFIK PROSTŘEDÍ ---
LOCAL_CONFIG_DIR="$CONTENTS_DIR/$(echo $DESKTOP_ENV | tr '[:upper:]' '[:lower:]')"
LOCAL_CONFIG="$LOCAL_CONFIG_DIR/config.txt"

if [ ! -f "$LOCAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Konfigurace prostředí $LOCAL_CONFIG chybí!"
    exit 1
fi

echo "Načítám specifikace pro $DESKTOP_ENV..."
CORE_PACKAGES=$(sed -n '/^\[CORE_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
EXTRA_PACKAGES=$(sed -n '/^\[EXTRA_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
APPS_TO_HIDE_STR=$(sed -n '/^\[APPS_TO_HIDE\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"

ALL_PACKAGES="$CORE_PACKAGES $EXTRA_PACKAGES $GLOBAL_PACKAGES"

# --- 5. INSTALACE BALÍKŮ ---
echo "Instaluji balíky..."
apt install -y --no-install-recommends $ALL_PACKAGES

if [ -n "$BROWSER_URL" ]; then
    wget -qO /tmp/browser.deb "$BROWSER_URL"
    apt install -y /tmp/browser.deb
    rm /tmp/browser.deb
fi

# --- 6. EXTRAKCE LUBUNTU-ARC TÉMATU (POUZE LXQT) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Tahám Lubuntu Arc téma z Ubuntu serverů..."
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
    dpkg-deb -x lubuntu-artwork.deb root_dir
    mkdir -p "$USER_HOME/.local/share/lxqt/themes"
    cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.local"
    cd ~ && rm -rf /tmp/lubuntu-rip
fi

# --- 7. NASAZENÍ KONFIGURACÍ (POUZE LXQT) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Kopíruji konfigurace..."
    CONF_SRC="$LOCAL_CONFIG_DIR/.config"
    if [ -d "$CONF_SRC" ]; then
        mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
        cp "$CONF_SRC/notifications.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
        cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null
        cp "$CONF_SRC/panel.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
        cp "$CONF_SRC/session.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
    fi
    # Patch panelu (pokud existuje tvůj zkompilovaný bez ptáka)
    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi
fi

# --- 8. KONFIGURACE PŘIHLAŠOVÁNÍ ---
if [ "$DESKTOP_ENV" == "PLASMA" ] && [ "$AUTOLOGIN" == "TRUE" ]; then
    mkdir -p /etc/sddm.conf.d
    echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma" > /etc/sddm.conf.d/autologin.conf
elif [ "$DESKTOP_ENV" == "LXQT" ] && [ "$AUTOLOGIN" == "TRUE" ]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
fi

# --- 9. UŽIVATELSKÁ NASTAVENÍ A TWEAKY ---
echo "Dolaďuji systém..."
echo -e "auto lo\niface lo inet loopback" > /etc/network/interfaces

# Automount a Touchpad (globální pravidla)
mkdir -p /etc/polkit-1/rules.d /etc/X11/xorg.conf.d
# ... (tvoje polkit a libinput pravidla z předchozích verzí) ...

if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # Zvuk, Čeština, XFWM4, lxqt.conf a Busy-Launch wrapper
    # ... (Vložit kompletní Sekci 9 z předchozího turnu) ...
fi

# --- 10. GRUB A REBOOT ---
if [ "$BOOT_LOGO" == "TRUE" ]; then
    apt install -y plymouth plymouth-themes
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    plymouth-set-default-theme -R spinner
fi
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "HOTOVO! Restart za 5s."
sleep 5
reboot