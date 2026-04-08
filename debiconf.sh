#!/bin/bash
# ==============================================================================
# DEBICONF - ČISTÝ DEBIAN S DESKTOPOVÝM PROSTŘEDÍM (PROFI REFACTOR - FIXED)
# ==============================================================================

set -e # Ukončí skript při první vážné chybě

# === GLOBÁLNÍ PROMĚNNÉ A CESTY ===
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$CONTENTS_DIR/setup-config.txt"

# Bezpečnější detekce původního uživatele
REAL_USER=$(logname 2>/dev/null || who am i | awk '{print $1}')
if [ -z "$REAL_USER" ]; then
    REAL_USER=$(ls /home | head -n 1)
fi
USER_HOME="/home/$REAL_USER"

# Detekce jazyka
SYS_LOCALE=$(grep "^LANG=" /etc/default/locale | cut -d'=' -f2 | tr -d '"' || echo "en_US.UTF-8")
SYS_LANG_CODE="${SYS_LOCALE%%.*}"

# === POMOCNÉ FUNKCE ===

log() {
    echo -e "\n\033[1;34m>> $1\033[0m"
}

error() {
    echo -e "\n\033[1;31mCHYBA: $1\033[0m" >&2
    exit 1
}

run_as_user() {
    su - "$REAL_USER" -c "dbus-launch $1" 2>/dev/null
}

get_setting() {
    local key="$1"
    if [ -f "$GLOBAL_CONFIG" ]; then
        grep -i "^${key}=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]'
    fi
}

get_section() {
    local file="$1"
    local section="$2"
    if [ -f "$file" ]; then
        sed -n "/^\[$section\]/,/^\[/p" "$file" | grep -v '^\[.*\]' | grep -vE '^\s*(#|$)' | xargs
    fi
}

# === 1. PŘÍPRAVA A INTERAKTIVNÍ DOTAZY ===

init_setup() {
    [ "$EUID" -ne 0 ] && error "Nutno spustit jako root (sudo)"
    
    log "Detekován systémový jazyk instalace: $SYS_LANG_CODE"

    echo "--------------------------------------------------"
    echo "Vyber desktopové prostředí"
    read -p "1) KDE Plasma | 2) LXQT (Ready out of the box): " DISTRO_ANS
    [[ "$DISTRO_ANS" == "1" ]] && DESKTOP_ENV="PLASMA" || DESKTOP_ENV="LXQT"

    # Definice lokálního konfiguráku hned po výběru prostředí
    LOCAL_CONFIG="$CONTENTS_DIR/$(echo "$DESKTOP_ENV" | tr '[:upper:]' '[:lower:]')/config.txt"

    echo "--------------------------------------------------"
    echo "Vyber prohlížeč"
    read -p "1) Chrome | 2) Chromium | 3) Brave | 4) Firefox | 5) Nic: " BROWSER_CHOICE

    echo "--------------------------------------------------"
    echo "Chceš nastavit automatické přihlašování?"
    read -p "1) ANO | 2) NE: " AUTO_ANS
    [[ "$AUTO_ANS" == "1" ]] && AUTOLOGIN_REQ="TRUE" || AUTOLOGIN_REQ="FALSE"

    # Načtení globálních nastavení
    TIMEOUT=$(get_setting "GRUB_TIMEOUT")
    TIMEOUT=${TIMEOUT:-0}
    
    CONF_OUT_RAW=$(get_setting "CONFIRM_LOGOUT" | tr '[:lower:]' '[:upper:]')
    [[ "$CONF_OUT_RAW" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    
    BOOT_LOGO=$(get_setting "BOOT_LOGO" | tr '[:lower:]' '[:upper:]')
}

prepare_system() {
    log "Základní příprava systému a sítě..."
    apt-get update -qq
    apt-get install -y sudo curl wget dpkg-dev git dbus-x11 numlockx
    usermod -aG sudo,audio,pulse,pulse-access,video,plugdev "$REAL_USER"

    apt-get purge -y ifupdown || true
    rm -rf /etc/network/interfaces.d/*
    cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback 
EOF
}

# === 2. INSTALACE BALÍČKŮ A PROHLÍŽEČŮ ===

install_packages() {
    log "Načítám konfigurace a instaluji balíčky..."
    
    local ALL_PKGS=$(get_section "$GLOBAL_CONFIG" "INSTALL")
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "CORE_PACKAGES")"
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "EXTRA_PACKAGES")"
    
    read -r -a PKG_ARRAY <<< "$ALL_PKGS"
    
    # Bezpečnostní pojistka proti prázdnému poli
    if [ ${#PKG_ARRAY[@]} -gt 0 ]; then
        apt-get install -y --no-install-recommends "${PKG_ARRAY[@]}"
    fi

    log "Instaluji prohlížeč..."
    case $BROWSER_CHOICE in
        1) wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt-get install -y /tmp/chrome.deb ;;
        2) apt-get install -y chromium chromium-l10n ;;
        3) curl -fsS https://dl.brave.com/install.sh | sh ;;
        4) apt-get install -y firefox-esr firefox-esr-l10n-cs ;;
    esac

    log "Přidávám repozitář a instaluji AnyDesk..."
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor -o /usr/share/keyrings/anydesk.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
    apt-get update -qq && apt-get install -y anydesk
}

setup_auto_updates() {
    log "Konfiguruji automatické aktualizace (unattended-upgrades)..."
    echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades

    local UPGRADES_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [ -f "$UPGRADES_CONF" ]; then
        sed -i 's/\/\/      "o=Debian,a=${distro_codename}-updates";/"o=Debian,a=${distro_codename}-updates";/' "$UPGRADES_CONF"
        if ! grep -q "Unattended-Upgrade::Package-Blacklist" "$UPGRADES_CONF"; then
            echo 'Unattended-Upgrade::Origins-Pattern { "o=*"; };' >> "/etc/apt/apt.conf.d/20auto-upgrades"
        fi
    fi

    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
}

# === 3. KONFIGURACE DESKTOPOVÝCH PROSTŘEDÍ ===

configure_lxqt() {
    log "Aplikuji specifické nastavení pro LXQt..."
    
    [ -f "$CONTENTS_DIR/lxqt/config/Shortcuts.conf" ] && mv "$CONTENTS_DIR/lxqt/config/Shortcuts.conf" "$CONTENTS_DIR/lxqt/config/shortcuts.conf" 2>/dev/null || true
    [ -f "$CONTENTS_DIR/lxqt/config/shortcuts.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/shortcuts.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/xfwm.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/xfwm.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/contextmenu.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/contextmenu.conf" || true

    local SHORTCUTS_SRC="$CONTENTS_DIR/lxqt/config/shortcuts.conf"
    local XFWM_SRC="$CONTENTS_DIR/lxqt/config/xfwm.conf"
    local APPS_TO_HIDE_STR=$(get_section "$LOCAL_CONFIG" "APPS_TO_HIDE")
    read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"

    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1)
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb
        dpkg-deb -x lubuntu-artwork.deb root_dir
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/"
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip

    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null || true
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null || true

    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel
        chmod +x /usr/bin/lxqt-panel
    fi

    local SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    mkdir -p "$USER_HOME/.local/bin"
    if [ -d "$SCRIPTS_SRC" ]; then
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null || true
    fi

    chmod +s $(which brightnessctl 2>/dev/null) 2>/dev/null || true
    rm -f "/tmp/jas_notif_id"
    if ! grep -q ".local/bin" "$USER_HOME/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
    fi

    echo "export LANG=$SYS_LOCALE" > /etc/profile.d/00-locale.sh
    echo "export LC_ALL=$SYS_LOCALE" >> /etc/profile.d/00-locale.sh

    mkdir -p /etc/polkit-1/rules.d
    echo 'polkit.addRule(function(action, subject) { if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" || action.id == "org.freedesktop.udisks2.filesystem-mount") && subject.isInGroup("sudo")) { return polkit.Result.YES; } });' > /etc/polkit-1/rules.d/50-udisks2-automount.rules

    local TOUCHPAD_SRC="$CONTENTS_DIR/lxqt/config/touchpad.conf"
    mkdir -p /etc/X11/xorg.conf.d
    if [ -f "$TOUCHPAD_SRC" ]; then
        cp "$TOUCHPAD_SRC" /etc/X11/xorg.conf.d/40-libinput-touchpad.conf
    fi

    local SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
    if [ ! -f "$SESSION_CONF" ]; then
        echo -e "[General]\nwindow_manager=xfwm4" > "$SESSION_CONF"
    else
        sed -i 's/^window_manager=.*/window_manager=xfwm4/' "$SESSION_CONF"
        grep -q "^window_manager=" "$SESSION_CONF" || sed -i '/^\[General\]/a window_manager=xfwm4' "$SESSION_CONF"
    fi

    if [ -f "$XFWM_SRC" ]; then
        log "Aplikuji nastavení XFWM4..."
        local TMP_XFWM="/tmp/xfwm_setup.sh"
        echo "#!/bin/bash" > "$TMP_XFWM"
        cat "$XFWM_SRC" >> "$TMP_XFWM"
        chmod +x "$TMP_XFWM"
        run_as_user "$TMP_XFWM"
        rm -f "$TMP_XFWM"
    fi

    local LXQT_CONF="$USER_HOME/.config/lxqt/lxqt.conf"
    if [ -f "$LXQT_CONF" ]; then
        sed -i "s/^ask_before_logout=.*/ask_before_logout=$CONF_OUT/" "$LXQT_CONF"
        sed -i "s/^theme=.*/theme=Lubuntu Arc/" "$LXQT_CONF"
        if grep -q "^language=" "$LXQT_CONF"; then
            sed -i "s/^language=.*/language=$SYS_LANG_CODE/" "$LXQT_CONF"
        else
            sed -i "/^\[General\]/a language=$SYS_LANG_CODE" "$LXQT_CONF"
        fi
    fi

    local SHORTCUTS_CONF="$USER_HOME/.config/lxqt/globalkeyshortcuts.conf"
    if [ -f "$SHORTCUTS_SRC" ]; then
        sed -i '/\.99\]/,+3d' "$SHORTCUTS_CONF" 2>/dev/null || true
        while IFS='|' read -r label shortcut cmd || [[ -n "$label" ]]; do
            [[ "$label" =~ ^#.*$ || -z "$label" ]] && continue
            safe_shortcut="${shortcut//+/%2B}"
            FINAL_CMD=$(echo "$cmd" | sed "s|brightness.sh|$USER_HOME/.local/bin/brightness.sh|g")
            echo -e "\n[${safe_shortcut}.99]\nComment=$label\nEnabled=true\nExec=$FINAL_CMD" >> "$SHORTCUTS_CONF"
        done < "$SHORTCUTS_SRC"
    fi

    local WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    mkdir -p "$LOCAL_APPS"
    
    for app in /usr/share/applications/*.desktop; do
        [ -e "$app" ] || continue
        app_name=$(basename "$app")
        cp "$app" "$LOCAL_APPS/"
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$LOCAL_APPS/$app_name"
    done

    for app in "${APPS_TO_HIDE[@]}"; do
        [ -f "$LOCAL_APPS/$app" ] && sed -i '/^NoDisplay=/d; $ a NoDisplay=true' "$LOCAL_APPS/$app"
    done

    local PANEL_CONF="$USER_HOME/.config/lxqt/panel.conf"
    case $BROWSER_CHOICE in
        1) B_NAME="google-chrome.desktop"; B_EXEC="google-chrome-stable" ;;
        2) B_NAME="chromium.desktop"; B_EXEC="chromium" ;;
        3) B_NAME="brave-browser.desktop"; B_EXEC="brave-browser" ;;
        4) B_NAME="firefox-esr.desktop"; B_EXEC="firefox-esr" ;;
        *) B_NAME=""; B_EXEC="" ;;
    esac

    if [ -f "$SESSION_CONF" ] && [ -n "$B_EXEC" ]; then
        sed -i "s/^BROWSER=.*/BROWSER=$B_EXEC/" "$SESSION_CONF"
    fi

    if [ -f "$PANEL_CONF" ]; then
        sed -i '/^apps\\/d' "$PANEL_CONF"
        if [ -n "$B_NAME" ]; then
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\2\\\\desktop=$LOCAL_APPS/$B_NAME\napps\\\\size=2" "$PANEL_CONF"
        else
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\size=1" "$PANEL_CONF"
        fi
    fi

    local Q_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$Q_CONF")"
    [ ! -f "$Q_CONF" ] && echo -e "[General]\nshowTerminalSizeHint=false" > "$Q_CONF" || sed -i '/showTerminalSizeHint/d; /\[General\]/a showTerminalSizeHint=false' "$Q_CONF"

    local CONTEXT_CONF="$CONTENTS_DIR/lxqt/config/contextmenu.conf"
    local ACTION_DIR="$USER_HOME/.local/share/file-manager/actions"

    if [ -s "$CONTEXT_CONF" ]; then
        mkdir -p "$ACTION_DIR"
        CURRENT_FILE=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^FILE:\ (.*\.desktop)$ ]]; then
                CURRENT_FILE="${BASH_REMATCH[1]}"
                > "$ACTION_DIR/$CURRENT_FILE"
            elif [ -n "$CURRENT_FILE" ]; then
                echo "$line" >> "$ACTION_DIR/$CURRENT_FILE"
            fi
        done < "$CONTEXT_CONF"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local"
}

configure_plasma() {
    log "Aplikuji specifické nastavení pro Plasmu (Motiv, Klíčenka)..."
    mkdir -p "$USER_HOME/.config"

    echo -e "[General]\nconfirmLogout=$CONF_OUT" > "$USER_HOME/.config/ksmserverrc"
    echo -e "[Wallet]\nEnabled=false" > "$USER_HOME/.config/kwalletrc"

    run_as_user "lookandfeeltool -a org.kde.plasma.twilight"
    
    local PLASMARC="$USER_HOME/.config/plasmarc"
    if [ ! -f "$PLASMARC" ]; then
        echo -e "[Theme]\nname=breeze-dark" > "$PLASMARC"
    else
        if grep -q "^\[Theme\]" "$PLASMARC"; then
            sed -i '/^\[Theme\]/,/^\[/ s/^name=.*/name=breeze-dark/' "$PLASMARC"
        else
            echo -e "\n[Theme]\nname=breeze-dark" >> "$PLASMARC"
        fi
    fi

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config"
}

# === 4. SYSTÉMOVÉ SLUŽBY A BOOT ===

setup_display_manager() {
    log "Nastavuji Display Manager a Autologin..."
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        echo "/usr/bin/sddm" > /etc/X11/default-display-manager 2>/dev/null
        dpkg-reconfigure -f noninteractive sddm 2>/dev/null
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/sddm.conf.d
            cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$REAL_USER
Session=plasma
EOF
        fi
    else
        echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null
        dpkg-reconfigure -f noninteractive lightdm 2>/dev/null
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/lightdm/lightdm.conf.d
            echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
            sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' /etc/lightdm/lightdm.conf 2>/dev/null
        fi
    fi
}

setup_boot() {
    log "Nastavuji GRUB a Boot Logo..."
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub

    if [ "$BOOT_LOGO" == "TRUE" ]; then
        log "Aplikuji grafický start (Plymouth)..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
        plymouth-set-default-theme -R bgrt 2>/dev/null || plymouth-set-default-theme -R spinner 2>/dev/null
    else
        log "Ponechávám textový start..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub
    fi

    update-grub
    systemctl set-default graphical.target
}

# ==============================================================================
# BĚH PROGRAMU (MAIN)
# ==============================================================================

init_setup
prepare_system
install_packages
setup_auto_updates

if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    configure_plasma
else
    configure_lxqt
fi

setup_display_manager
setup_boot

echo "=================================================="
echo " HOTOVO"
echo " RESTART ZA 5 SEKUND."
echo "=================================================="
sleep 5
reboot