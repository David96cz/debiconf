#!/bin/bash

# ==============================================================================
# DEBICONF
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Nutno spustit jako root (sudo)"
    exit 1
fi

REAL_USER=$(ls /home | head -n 1)
USER_HOME="/home/$REAL_USER"
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$BASE_DIR/setup-config.txt"

# --- 1. INTERAKTIVNÍ DOTAZY (Hned na začátku) ---
echo "--------------------------------------------------"
echo "KONFIGURACE INSTALACE"
echo "--------------------------------------------------"

# Volba Distra
read -p "1) KDE Plasma | 2) LXQT (Ready out of the box): " DISTRO_ANS
case $DISTRO_ANS in
    1) DESKTOP_ENV="PLASMA" ;;
    *) DESKTOP_ENV="LXQT" ;;
esac

# Volba Prohlížeče
echo "--------------------------------------------------"
echo "VÝBĚR PROHLÍŽEČE:"
echo "1) Chrome | 2) Chromium | 3) Brave | 4) Firefox | 5) Žádný"
read -p "Vyber číslo: " BROWSER_CHOICE

# Volba Autologinu
read -p "Chceš nastavit AUTOLOGIN? (y/n): " AUTO_ANS
if [[ "$AUTO_ANS" =~ ^[Yy]$ ]]; then
    AUTOLOGIN_REQ="TRUE"
    read -p "Povolit i RELOGIN (automatické přihlášení po odhlášení)? (y/n): " RELO_ANS
    [[ "$RELO_ANS" =~ ^[Yy]$ ]] && RELOGIN_REQ="TRUE" || RELOGIN_REQ="FALSE"
else
    AUTOLOGIN_REQ="FALSE"
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

# Balíčky z configu
GLOBAL_PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' "$GLOBAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | grep -v '=' | xargs)

# Balíčky z prostředí
LOCAL_CONFIG="$CONTENTS_DIR/$(echo $DESKTOP_ENV | tr '[:upper:]' '[:lower:]')/config.txt"
CORE_PACKAGES=$(sed -n '/^\[CORE_PACKAGES\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
ALL_PACKAGES="$CORE_PACKAGES $GLOBAL_PACKAGES"

# Načtení aplikací ke skrytí
APPS_TO_HIDE_STR=$(sed -n '/^\[APPS_TO_HIDE\]/,/^\[/p' "$LOCAL_CONFIG" | grep -v '^\[.*\]' | grep -vE '^\s*#|^\s*$' | xargs)
read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"

# --- 3. INSTALACE BALÍKŮ (HROMADNÁ - OPRAVA GUI) ---
echo "Filtruji neplatné balíčky..."
VALID_PKGS=""
for pkg in $ALL_PACKAGES; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        VALID_PKGS="$VALID_PKGS $pkg"
    else
        echo "⚠️ Přeskakuji neexistující balík: $pkg"
    fi
done

echo "Instaluji vše najednou pro zachování závislostí GUI..."
apt install -y --no-install-recommends $VALID_PKGS

case $BROWSER_CHOICE in
    1) wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt install -y /tmp/chrome.deb ;;
    2) apt install -y chromium chromium-l10n ;;
    3) curl -fsS https://dl.brave.com/install.sh | sh ;;
    4) apt install -y firefox-esr firefox-esr-l10n-cs ;;
esac

# --- 4. LXQT TÉMA A KONFIGY ---
if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # Téma Lubuntu Arc
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip
    
    # Konfigy
    CONF_SRC="$CONTENTS_DIR/lxqt/.config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null

    # Panel Patch
    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi

    # Kopírování vlastních skriptů do .local/bin
    SCRIPTS_SRC="$CONTENTS_DIR/lxqt/.scripts"
    if [ -d "$SCRIPTS_SRC" ]; then
        mkdir -p "$USER_HOME/.local/bin"
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null
    fi
fi

# --- 5. AUTOLOGIN A POVOLENÍ GUI SLUŽEB ---
# Tohle natvrdo donutí Debian najet do grafiky
systemctl set-default graphical.target

if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    systemctl enable sddm 2>/dev/null
    if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
        mkdir -p /etc/sddm.conf.d
        echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma\nRelogin=$RELOGIN_REQ" > /etc/sddm.conf.d/autologin.conf
    fi
else
    systemctl enable lightdm 2>/dev/null
    if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
fi

# --- 6. SYSTÉMOVÉ FINÁLE ---
# Vynucení češtiny
sed -i 's/^# cs_CZ.UTF-8 UTF-8/cs_CZ.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=cs_CZ.UTF-8 LC_ALL=cs_CZ.UTF-8
localectl set-locale LANG=cs_CZ.UTF-8 LC_ALL=cs_CZ.UTF-8

usermod -aG audio,pulse,pulse-access,video,plugdev $REAL_USER

# Automount a Touchpad
mkdir -p /etc/polkit-1/rules.d /etc/X11/xorg.conf.d
echo 'polkit.addRule(function(action, subject) { if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" || action.id == "org.freedesktop.udisks2.filesystem-mount") && subject.isInGroup("sudo")) { return polkit.Result.YES; } });' > /etc/polkit-1/rules.d/50-udisks2-automount.rules
echo -e 'Section "InputClass"\n Identifier "touchpad"\n MatchIsTouchpad "on"\n Driver "libinput"\n Option "Tapping" "on"\n Option "NaturalScrolling" "true"\nEndSection' > /etc/X11/xorg.conf.d/40-libinput-touchpad.conf

if [ "$DESKTOP_ENV" == "LXQT" ]; then
    # XFWM4 Layout
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    echo '<?xml version="1.0" encoding="UTF-8"?><channel name="xfwm4" version="1.0"><property name="general" type="empty"><property name="theme" type="string" value="Default"/><property name="button_layout" type="string" value="O|HMC"/><property name="title_alignment" type="string" value="center"/><property name="tile_on_move" type="bool" value="true"/></property></channel>' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    
    # LXQT.CONF
    [[ "$CONFIRM_LOGOUT" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    cat <<EOF > "$USER_HOME/.config/lxqt/lxqt.conf"
[General]
__userfile__=true
icon_theme=Papirus
theme=Lubuntu Arc
ask_before_logout=$CONF_OUT

[Qt]
style=Breeze
EOF

    # Busy-Launch (Python wrapper) & Skrývání aplikací
    WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    mkdir -p "$USER_HOME/.local/share/applications"
    
    # Nejdřív obalíme aplikace kolečkem
    for app in /usr/share/applications/*.desktop; do
        app_name=$(basename "$app")
        if [ ! -f "$USER_HOME/.local/share/applications/$app_name" ]; then
            cp "$app" "$USER_HOME/.local/share/applications/"
        fi
        if ! grep -q "python3 $WRAPPER_BIN" "$USER_HOME/.local/share/applications/$app_name"; then
            sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$USER_HOME/.local/share/applications/$app_name"
        fi
    done

    # Potom skryjeme aplikace přes NoDisplay
    for app in "${APPS_TO_HIDE[@]}"; do
        if [ -f "$USER_HOME/.local/share/applications/$app" ]; then
            if grep -q "^NoDisplay=" "$USER_HOME/.local/share/applications/$app"; then
                sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$USER_HOME/.local/share/applications/$app"
            else
                echo "NoDisplay=true" >> "$USER_HOME/.local/share/applications/$app"
            fi
        fi
    done

    chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config" "$USER_HOME/.local"
fi

# Grub & Reboot
if [ "$BOOT_LOGO" == "TRUE" ]; then
    apt install -y plymouth plymouth-themes
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    plymouth-set-default-theme -R spinner
fi
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "HOTOVO. Restart za 5s."
sleep 5
reboot
