#!/bin/bash

# ==============================================================================
# DEBIAN ULTIMATE SETUP SCRIPT (PLASMA / LXQT)
# ==============================================================================

# --- 1. DETEKCE UŽIVATELE A SUDO PRÁVA ---
if [ "$EUID" -ne 0 ]; then
    echo "Prosím, spusťte skript s právy root (sudo)."
    exit 1
fi

REAL_USER=$(ls /home | head -n 1)
USER_HOME="/home/$REAL_USER"
echo "Našel jsem složku uživatele: $REAL_USER. Dávám mu sudo práva..."
apt update && apt install -y sudo curl wget dpkg-dev git
usermod -aG sudo $REAL_USER

# --- 2. DEFINICE ABSOLUTNÍCH CEST ---
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$BASE_DIR/setup-config.txt"

# --- 3. NAČTENÍ GLOBÁLNÍ KONFIGURACE A VOLBA PROSTŘEDÍ ---
echo "Validuji globální konfiguraci ze setup-config.txt..."

if [ ! -f "$GLOBAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Globální konfigurace $GLOBAL_CONFIG chybí!"
    exit 1
fi

# --- INTERAKTIVNÍ VOLBA PROSTŘEDÍ ---
echo "--------------------------------------------------"
echo "VOLBA DESKTOPOVÉHO PROSTŘEDÍ"
echo "1) KDE Plasma
echo "2) LXQT (Ready out of the box)"
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

# Dočtení zbytku hodnot z texťáku (už bez DESKTOP_ENV)
BROWSER_URL=$(grep -i "^BROWSER_URL=" "$GLOBAL_CONFIG" | cut -d'=' -f2-)
BOOT_LOGO=$(grep -i "^BOOT_LOGO=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
LOW_PC=$(grep -i "^LOW_PC=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
AUTOLOGIN=$(grep -i "^AUTOLOGIN=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d' ' -f1)

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then TIMEOUT="0"; fi

# Načtení globálních balíčků (ignoruje řádky s '=' jako BROWSER_URL)
GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)

# --- 4. NAČTENÍ SPECIFIK PROSTŘEDÍ (Z LOKÁLNÍHO CONFIGU) ---
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

# --- 5. INSTALACE BALÍKŮ (S FILTRACÍ CHYBĚJÍCÍCH) ---
echo "Filtruji neexistující balíky..."
SAFE_PACKAGES=""
for pkg in $ALL_PACKAGES; do
    if apt-cache show "$pkg" > /dev/null 2>&1; then
        SAFE_PACKAGES="$SAFE_PACKAGES $pkg"
    else
        echo " ⚠️ VAROVÁNÍ: Balíček '$pkg' neexistuje. Přeskakuji!"
    fi
done

echo "Instaluji ověřené balíky..."
apt install -y --no-install-recommends $SAFE_PACKAGES

if [ -n "$BROWSER_URL" ]; then
    echo "Stahuji a instaluji prohlížeč..."
    wget -qO /tmp/browser.deb "$BROWSER_URL"
    apt install -y /tmp/browser.deb
    rm /tmp/browser.deb
fi

# --- 6. EXTRAKCE LUBUNTU-ARC TÉMATU (POUZE LXQT) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Stahuji originální Lubuntu Arc téma přímo z Ubuntu serverů..."
    cd /tmp
    rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        
        THEMES_DIR="$USER_HOME/.local/share/lxqt/themes"
        mkdir -p "$THEMES_DIR"
        cp -r root_dir/usr/share/lxqt/themes/* "$THEMES_DIR/"
        chown -R $REAL_USER:$REAL_USER "$USER_HOME/.local"
        echo "   [OK] Lubuntu Arc téma úspěšně aplikováno."
    else
        echo "   [!] CHYBA: Nepodařilo se stáhnout Lubuntu téma."
    fi
    cd ~
    rm -rf /tmp/lubuntu-rip
fi

# --- 7. NASAZENÍ KONFIGURACÍ A SKRIPTŮ (POUZE LXQT) ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Kopíruji lokální .config a .scripts..."
    
    CONF_SRC="$LOCAL_CONFIG_DIR/.config"
    SCRIPTS_SRC="$LOCAL_CONFIG_DIR/.scripts"
    LXQT_DEST="$USER_HOME/.config/lxqt"
    PCMANFM_DEST="$USER_HOME/.config/pcmanfm-qt/lxqt"
    
    if [ -d "$CONF_SRC" ]; then
        mkdir -p "$LXQT_DEST" "$PCMANFM_DEST"
        cp "$CONF_SRC/notifications.conf" "$LXQT_DEST/" 2>/dev/null
        cp "$CONF_SRC/pcmanfm-qt.conf" "$PCMANFM_DEST/settings.conf" 2>/dev/null
        cp "$CONF_SRC/panel-26.conf" "$LXQT_DEST/panel.conf" 2>/dev/null
        cp "$CONF_SRC/panel.conf" "$LXQT_DEST/panel.conf" 2>/dev/null # Fallback
        cp "$CONF_SRC/session.conf" "$LXQT_DEST/" 2>/dev/null
        chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config"
    fi

    if [ -d "$SCRIPTS_SRC" ]; then
        LOCAL_BIN="$USER_HOME/.local/bin"
        mkdir -p "$LOCAL_BIN"
        cp -u "$SCRIPTS_SRC/"*.sh "$LOCAL_BIN/" 2>/dev/null
        cp -u "$SCRIPTS_SRC/"*.py "$LOCAL_BIN/" 2>/dev/null
        chmod +x "$LOCAL_BIN/"* 2>/dev/null
        chown -R $REAL_USER:$REAL_USER "$LOCAL_BIN"
    fi

    # Binární patch pro panel bez ptáka (pokud existuje)
    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
        echo "   [OK] Panel binárně patchován."
    fi
fi

# --- 8. KONFIGURACE PŘIHLAŠOVÁNÍ ---
echo "Nastavuji přihlašování..."
if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    if [ "$AUTOLOGIN" == "TRUE" ]; then
        mkdir -p /etc/sddm.conf.d
        echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma" > /etc/sddm.conf.d/autologin.conf
    fi
elif [ "$DESKTOP_ENV" == "LXQT" ]; then
    if [ "$AUTOLOGIN" == "TRUE" ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
fi

# --- 9. UŽIVATELSKÁ NASTAVENÍ A TWEAKY ---
echo "Aplikuji uživatelská nastavení..."

# Vyčištění interfaces
echo -e "auto lo\niface lo inet loopback" > /etc/network/interfaces

# Automount disků
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

# Touchpad pravidla
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-libinput-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "ClickMethod" "clickfinger"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
    Option "AccelProfile" "adaptive"
    Option "AccelSpeed" "0.0"
EndSection
EOF

# Specifika pro LXQt
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    USER_APPS_DIR="$USER_HOME/.local/share/applications"
    mkdir -p "$USER_APPS_DIR"
    
    # Skrytí aplikací
    for app in "${APPS_TO_HIDE[@]}"; do
        if [ -f "/usr/share/applications/$app" ]; then
            cp "/usr/share/applications/$app" "$USER_APPS_DIR/$app"
            if grep -q "^NoDisplay=" "$USER_APPS_DIR/$app"; then
                sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$USER_APPS_DIR/$app"
            else
                echo "NoDisplay=true" >> "$USER_APPS_DIR/$app"
            fi
        fi
    done
    
    # QTerminal úprava
    QTERM_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$QTERM_CONF")"
    if [ ! -f "$QTERM_CONF" ] || ! grep -q "^\[General\]" "$QTERM_CONF"; then echo -e "\n[General]" >> "$QTERM_CONF"; fi
    sed -i '/^[sS]howTerminalSizeHint/d' "$QTERM_CONF"
    sed -i '/^\[General\]/a showTerminalSizeHint=false' "$QTERM_CONF"

    # Zastavení popupů prohlížečů
    for policy_dir in /etc/opt/chrome/policies/managed /etc/chromium/policies/managed; do
        mkdir -p "$policy_dir"
        echo '{"DefaultBrowserSettingEnabled": false}' > "$policy_dir/stop-otravovat.json"
    done

    # =========================================================
    # TVOJE TVRDÉ LXQT A XFWM4 NASTAVENÍ
    # =========================================================

    # XFWM4 nastavení (layout a chování)
    echo "Aplikuji tvůj XFWM4 layout..."
    XFWM4_XML="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    mkdir -p "$(dirname "$XFWM4_XML")"
    cat <<EOF > "$XFWM4_XML"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="tile_on_move" type="bool" value="true"/>
    <property name="wrap_pointer" type="bool" value="false"/>
    <property name="wrap_windows" type="bool" value="false"/>
  </property>
</channel>
EOF
    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config/xfce4"

    # Zápis lxqt.conf a session.conf
    LXQT_CONF="$USER_HOME/.config/lxqt/lxqt.conf"
    mkdir -p "$(dirname "$LXQT_CONF")"
    if [ ! -f "$LXQT_CONF" ] || ! grep -q "icon_theme=" "$LXQT_CONF"; then
        echo "Zapisuji pevný lxqt.conf..."
        cat <<EOF > "$LXQT_CONF"
[General]
icon_theme=Papirus
theme=Lubuntu-Arc
themeOverridesWallpaper=false
EOF
    fi

    SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
    if [ ! -f "$SESSION_CONF" ]; then
        echo -e "[General]\nwindow_manager=xfwm4" > "$SESSION_CONF"
    else
        sed -i 's/^window_manager=.*/window_manager=xfwm4/' "$SESSION_CONF"
    fi
    
    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.local" "$USER_HOME/.config"
fi

# --- 10. PLYMOUTH, GRUB A REBOOT ---
if [ "$BOOT_LOGO" == "TRUE" ]; then
    echo "Nahazuju Plymouth logo..."
    apt install -y plymouth plymouth-themes
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    plymouth-set-default-theme -R spinner
fi

echo "Zkracuju GRUB na $TIMEOUT sekund..."
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "=================================================="
echo " VŠECHNO HOTOVO! Systém se restartuje za 5 sekund."
echo "=================================================="
sleep 5
reboot