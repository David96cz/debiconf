#!/bin/bash

# ==============================================================================
# DEBICONF - DEBIAN ULTIMATE SETUP SCRIPT (COMPLETE VERSION)
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
if [ ! -f "$GLOBAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Globální konfigurace $GLOBAL_CONFIG chybí!"
    exit 1
fi

echo "--------------------------------------------------"
echo "VOLBA DESKTOPOVÉHO PROSTŘEDÍ"
echo "1) KDE Plasma"
echo "2) LXQT (Moderní Lubuntu-style)"
echo "--------------------------------------------------"
read -p "Vyber číslo (default 2): " ENV_CHOICE

case $ENV_CHOICE in
    1) DESKTOP_ENV="PLASMA" ;;
    2|*) DESKTOP_ENV="LXQT" ;;
esac

echo "Vybráno prostředí: $DESKTOP_ENV"

# Načtení hodnot z texťáku
BROWSER_URL=$(grep -i "^BROWSER_URL=" "$GLOBAL_CONFIG" | cut -d'=' -f2-)
BOOT_LOGO=$(grep -i "^BOOT_LOGO=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
AUTOLOGIN=$(grep -i "^AUTOLOGIN=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1)
[ -z "$TIMEOUT" ] && TIMEOUT="0"

# Globální balíčky
GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)

# --- 4. NAČTENÍ SPECIFIK PROSTŘEDÍ ---
LOCAL_CONFIG_DIR="$CONTENTS_DIR/$(echo $DESKTOP_ENV | tr '[:upper:]' '[:lower:]')"
LOCAL_CONFIG="$LOCAL_CONFIG_DIR/config.txt"

if [ ! -f "$LOCAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Konfigurace prostředí $LOCAL_CONFIG chybí!"
    exit 1
fi

CORE_PACKAGES=$(sed -n '/^\[CORE_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
EXTRA_PACKAGES=$(sed -n '/^\[EXTRA_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
APPS_TO_HIDE_STR=$(sed -n '/^\[APPS_TO_HIDE\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"

ALL_PACKAGES="$CORE_PACKAGES $EXTRA_PACKAGES $GLOBAL_PACKAGES"

# --- 5. ROBUSTNÍ INSTALACE (NEZÁVISLÁ NA CHYBÁCH) ---
echo "Instaluji balíky (jeden po druhém pro stabilitu)..."
for pkg in $ALL_PACKAGES; do
    echo "--> $pkg"
    apt install -y --no-install-recommends "$pkg" || echo " ⚠️ SELHALO: $pkg (přeskakuji)"
done

if [ -n "$BROWSER_URL" ]; then
    wget -qO /tmp/browser.deb "$BROWSER_URL"
    apt install -y /tmp/browser.deb
    rm /tmp/browser.deb
fi

# --- 6. LUBUNTU-ARC TÉMA (LXQT) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Tahám Lubuntu Arc téma..."
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip
fi

# --- 7. KONFIGURACE A PATCH PANELU ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    CONF_SRC="$LOCAL_CONFIG_DIR/.config"
    if [ -d "$CONF_SRC" ]; then
        mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
        cp "$CONF_SRC/notifications.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
        cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null
        cp "$CONF_SRC/panel.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
        cp "$CONF_SRC/session.conf" "$USER_HOME/.config/lxqt/" 2>/dev/null
    fi
    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi
fi

# --- 8. AUTOLOGIN ---
if [ "$AUTOLOGIN" == "TRUE" ]; then
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        mkdir -p /etc/sddm.conf.d
        echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma" > /etc/sddm.conf.d/autologin.conf
    else
        mkdir -p /etc/lightdm/lightdm.conf.d
        echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
fi

# --- 9. UŽIVATELSKÁ NASTAVENÍ A TWEAKY (FINÁLNÍ SEKCE) ---
echo "Dolaďuji systém..."
echo -e "auto lo\niface lo inet loopback" > /etc/network/interfaces

# Automount Polkit
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-udisks2-automount.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount") &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

# Touchpad
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-libinput-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "ClickMethod" "clickfinger"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
EOF

if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Aplikuji LXQT specifika (Zvuk, CZ, XFWM4)..."
    sed -i 's/^# cs_CZ.UTF-8 UTF-8/cs_CZ.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=cs_CZ.UTF-8 LC_ALL=cs_CZ.UTF-8
    usermod -aG audio,pulse,pulse-access,video,plugdev $REAL_USER

    # XFWM4 XML
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat <<EOF > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="tile_on_move" type="bool" value="true"/>
  </property>
</channel>
EOF

    # LXQT.CONF
    cat <<EOF > "$USER_HOME/.config/lxqt/lxqt.conf"
[General]
__userfile__=true
icon_follow_color_scheme=true
icon_theme=Papirus
theme=Lubuntu Arc
themeOverridesWallpaper=false
tool_bar_icon_size=24

[Qt]
style=Breeze
EOF

    # BUSY LAUNCH WRAPPER
    WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    mkdir -p "$USER_HOME/.local/share/applications"
    for app in /usr/share/applications/*.desktop; do
        app_name=$(basename "$app")
        cp "$app" "$USER_HOME/.local/share/applications/"
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$USER_HOME/.local/share/applications/$app_name"
    done
    
    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config" "$USER_HOME/.local"
fi

# --- 10. GRUB A REBOOT ---
if [ "$BOOT_LOGO" == "TRUE" ]; then
    apt install -y plymouth plymouth-themes
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    plymouth-set-default-theme -R spinner
fi
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "=================================================="
echo " VŠECHNO HOTOVO! Restartuji za 5 sekund."
echo "=================================================="
sleep 5
reboot