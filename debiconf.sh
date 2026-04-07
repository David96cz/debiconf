#!/bin/bash

# ==============================================================================
# DEBICONF - ULTIMATE DEBIAN SETUP (S LXQT TWEAKY Z LUBUNTU)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Nutno spustit jako root (sudo)"
    exit 1
fi

REAL_USER=$(ls /home | head -n 1)
USER_HOME="/home/$REAL_USER"
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$CONTENTS_DIR/setup-config.txt"

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

# Volba Autologinu a Reloginu
echo "--------------------------------------------------"
echo "Chceš nastavit automatické přihlašování?" 
read -p "(1 = ANO, 2 = NE): " AUTO_ANS
if [ "$AUTO_ANS" == "1" ]; then
    AUTOLOGIN_REQ="TRUE"
    RELOGIN_REQ="TRUE"
else
    AUTOLOGIN_REQ="FALSE"
    RELOGIN_REQ="FALSE"
fi

echo "--------------------------------------------------"
echo "STARTUJI INSTALACI: $DESKTOP_ENV"
echo "--------------------------------------------------"

# --- 2. NAČTENÍ KONFIGURÁKU ---
apt update && apt install -y sudo curl wget dpkg-dev git
usermod -aG sudo $REAL_USER

BOOT_LOGO=$(grep -i "^BOOT_LOGO=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]')
CONFIRM_LOGOUT=$(grep -i "^CONFIRM_LOGOUT=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)

LOCAL_CONFIG="$CONTENTS_DIR/$(echo $DESKTOP_ENV | tr '[:upper:]' '[:lower:]')/config.txt"

if [ ! -f "$LOCAL_CONFIG" ]; then
    echo "KRITICKÁ CHYBA: Konfigurace prostředí $LOCAL_CONFIG chybí!"
    exit 1
fi

CORE_PACKAGES=$(sed -n '/^\[CORE_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
EXTRA_PACKAGES=$(sed -n '/^\[EXTRA_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
ALL_PACKAGES="$CORE_PACKAGES $EXTRA_PACKAGES $GLOBAL_PACKAGES"

APPS_TO_HIDE_STR=$(sed -n '/^\[APPS_TO_HIDE\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"

# --- 3. INSTALACE BALÍKŮ (TVŮJ FOR CYKLUS) ---
echo "Instaluji balíky jeden po druhém..."
for pkg in $ALL_PACKAGES; do
    apt install -y --no-install-recommends "$pkg" || echo "⚠️ SELHALO: $pkg (přeskakuji a jedu dál)"
done

case $BROWSER_CHOICE in
    1) wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt install -y /tmp/chrome.deb ;;
    2) apt install -y chromium chromium-l10n ;;
    3) curl -fsS https://dl.brave.com/install.sh | sh ;;
    4) apt install -y firefox-esr firefox-esr-l10n-cs ;;
esac

# --- 4. LXQT TÉMA A KONFIGY ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip
    
    CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null

    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi

    SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    if [ -d "$SCRIPTS_SRC" ]; then
        mkdir -p "$USER_HOME/.local/bin"
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null
    fi
fi

# --- 5. AUTOLOGIN LOGIKA ---
if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        mkdir -p /etc/sddm.conf.d
        echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma\nRelogin=$RELOGIN_REQ" > /etc/sddm.conf.d/autologin.conf
    else
        mkdir -p /etc/lightdm/lightdm.conf.d
        echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
fi

# --- 6. SYSTÉMOVÉ FINÁLE A TWEAKY (SPOJENO) ---
sed -i 's/^# cs_CZ.UTF-8 UTF-8/cs_CZ.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=cs_CZ.UTF-8 LC_ALL=cs_CZ.UTF-8
localectl set-locale LANG=cs_CZ.UTF-8

usermod -aG audio,pulse,pulse-access,video,plugdev $REAL_USER

# Automount (Polkit)
mkdir -p /etc/polkit-1/rules.d
echo 'polkit.addRule(function(action, subject) { if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" || action.id == "org.freedesktop.udisks2.filesystem-mount") && subject.isInGroup("sudo")) { return polkit.Result.YES; } });' > /etc/polkit-1/rules.d/50-udisks2-automount.rules

# Touchpad (X11)
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

if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # --- XFWM4 ---
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    echo '<?xml version="1.0" encoding="UTF-8"?><channel name="xfwm4" version="1.0"><property name="general" type="empty"><property name="theme" type="string" value="Default"/><property name="button_layout" type="string" value="O|HMC"/><property name="title_alignment" type="string" value="center"/><property name="tile_on_move" type="bool" value="true"/></property></channel>' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    
    # --- LXQT.CONF (ČEŠTINA A LOGOUT) ---
    [[ "$CONFIRM_LOGOUT" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    cat <<EOF > "$USER_HOME/.config/lxqt/lxqt.conf"
[General]
__userfile__=true
icon_theme=Papirus
theme=Lubuntu Arc
ask_before_logout=$CONF_OUT
language=cs_CZ

[Qt]
style=Breeze
EOF

    # --- KLÁVESOVÉ ZKRATKY ---
    SHORTCUTS_CONF="$USER_HOME/.config/lxqt/globalkeyshortcuts.conf"
    mkdir -p "$(dirname "$SHORTCUTS_CONF")"
    
    if [ ! -s "$SHORTCUTS_CONF" ]; then
        cp /usr/share/lxqt/globalkeyshortcuts.conf "$SHORTCUTS_CONF" 2>/dev/null || touch "$SHORTCUTS_CONF"
    fi

    if ! grep -q "flameshot" "$SHORTCUTS_CONF" 2>/dev/null; then
        cat >> "$SHORTCUTS_CONF" << 'EOF'

[Meta%2BShift%2BS.99]
Comment=Výstřižky (Flameshot)
Enabled=true
Exec=flameshot, gui
EOF
    fi

    if ! grep -q "htop" "$SHORTCUTS_CONF" 2>/dev/null; then
        cat >> "$SHORTCUTS_CONF" << 'EOF'

[Control%2BShift%2BEscape.99]
Comment=Správce úloh (Htop)
Enabled=true
Exec=qterminal, -e, htop
EOF
    fi

    if ! grep -q "copyq show" "$SHORTCUTS_CONF" 2>/dev/null; then
        cat >> "$SHORTCUTS_CONF" << 'EOF'

[Meta%2BV.99]
Comment=CopyQ show
Enabled=true
Exec=copyq, show
EOF
    fi

    # Jas
    sed -i 's/lxqt-config-brightness/brightness.sh/g' "$SHORTCUTS_CONF"
    chmod +s $(which brightnessctl) 2>/dev/null

    # --- QTERMINAL (Velikost okna) ---
    QTERM_DIR="$USER_HOME/.config/qterminal.org"
    mkdir -p "$QTERM_DIR"
    QTERM_CONF="$QTERM_DIR/qterminal.ini"

    if [ ! -f "$QTERM_CONF" ] || ! grep -q "^\[General\]" "$QTERM_CONF"; then
        echo -e "\n[General]" >> "$QTERM_CONF"
    fi
    sed -i '/^[sS]howTerminalSizeHint/d' "$QTERM_CONF"
    sed -i '/^\[General\]/a showTerminalSizeHint=false' "$QTERM_CONF"

    # --- TISK V MENU ---
    ACTION_DIR="$USER_HOME/.local/share/file-manager/actions"
    mkdir -p "$ACTION_DIR"
    cat > "$ACTION_DIR/tisk.desktop" << 'EOF'
[Desktop Entry]
Type=Action
Name=Vytisknout...
Icon=printer
Profiles=profile-zero;
[X-Action-Profile profile-zero]
MimeTypes=image/*;application/pdf;text/plain;
Exec=/usr/local/bin/tisk-cz %f
EOF

    # --- BUSY LAUNCH & SKRÝVÁNÍ APLIKACÍ ---
    WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    mkdir -p "$USER_HOME/.local/share/applications"
    
    for app in /usr/share/applications/*.desktop; do
        app_name=$(basename "$app")
        if [ ! -f "$USER_HOME/.local/share/applications/$app_name" ]; then
            cp "$app" "$USER_HOME/.local/share/applications/"
        fi
        if ! grep -q "python3 $WRAPPER_BIN" "$USER_HOME/.local/share/applications/$app_name"; then
            sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$USER_HOME/.local/share/applications/$app_name"
        fi
    done

    for app in "${APPS_TO_HIDE[@]}"; do
        if [ -f "$USER_HOME/.local/share/applications/$app" ]; then
            if grep -q "^NoDisplay=" "$USER_HOME/.local/share/applications/$app"; then
                sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$USER_HOME/.local/share/applications/$app"
            else
                echo "NoDisplay=true" >> "$USER_HOME/.local/share/applications/$app"
            fi
        fi
    done

    # --- IKONY DO PANELU ---
    PANEL_CONF="$USER_HOME/.config/lxqt/panel.conf"
    case $BROWSER_CHOICE in
        1) BROWSER_APP="google-chrome.desktop" ;;
        2) BROWSER_APP="chromium.desktop" ;;
        3) BROWSER_APP="brave-browser.desktop" ;;
        4) BROWSER_APP="firefox-esr.desktop" ;;
        *) BROWSER_APP="" ;;
    esac

    if [ -f "$PANEL_CONF" ]; then
        sed -i '/^apps\\/d' "$PANEL_CONF"
        if grep -q "^\[quicklaunch\]" "$PANEL_CONF"; then
            if [ -n "$BROWSER_APP" ]; then
                sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=/usr/share/applications/pcmanfm-qt.desktop\napps\\\\2\\\\desktop=/usr/share/applications/$BROWSER_APP\napps\\\\size=2" "$PANEL_CONF"
            else
                sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=/usr/share/applications/pcmanfm-qt.desktop\napps\\\\size=1" "$PANEL_CONF"
            fi
        fi
    fi

    # Aplikování práv na vytvořené konfigy
    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config" "$USER_HOME/.local"
fi

# --- NUMLOCK PRO LIGHTDM ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # Instalace greeter settings (pokud není) a zapnutí numlocku
    apt install -y numlockx lightdm-gtk-greeter-settings >/dev/null 2>&1
    sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' /etc/lightdm/lightdm.conf 2>/dev/null
fi

# --- 7. POJISTKA PRO GUI ---
echo "Zapínám grafický režim..."
systemctl set-default graphical.target
if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    systemctl enable sddm 2>/dev/null
else
    systemctl enable lightdm 2>/dev/null
fi

# Grub & Reboot
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