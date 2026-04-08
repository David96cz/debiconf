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
    # Přidáno || true, aby selhání D-Bus nezabilo instalaci
    su - "$REAL_USER" -c "dbus-launch $1" 2>/dev/null || true
}

get_setting() {
    local key="$1"
    if [ -f "$GLOBAL_CONFIG" ]; then
        # Přidáno || true, jinak grep zabije skript, když klíč nenajde
        grep -i "^${key}=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | tr -d '[:space:]' || true
    fi
}

get_section() {
    local file="$1"
    local section="$2"
    if [ -f "$file" ]; then
        # Přidáno || true pro ochranu proti prázdným sekcím
        sed -n "/^\[$section\]/,/^\[/p" "$file" | grep -v '^\[.*\]' | grep -vE '^\s*(#|$)' | xargs || true
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
    
    usermod -aG sudo,audio,video,plugdev "$REAL_USER" || true

    apt-get purge -y ifupdown || true
    rm -rf /etc/network/interfaces.d/* || true
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
        1) wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt-get install -y /tmp/chrome.deb || true ;;
        2) apt-get install -y chromium chromium-l10n || true ;;
        3) curl -fsS https://dl.brave.com/install.sh | sh || true ;;
        4) apt-get install -y firefox-esr firefox-esr-l10n-cs || true ;;
    esac

    log "Přidávám repozitář a instaluji AnyDesk..."
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor -o /usr/share/keyrings/anydesk.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list || true
    apt-get update -qq && apt-get install -y anydesk || true
}

setup_auto_updates() {
    log "Konfiguruji automatické aktualizace (unattended-upgrades)..."
    echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades

    local UPGRADES_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [ -f "$UPGRADES_CONF" ]; then
        sed -i 's/\/\/      "o=Debian,a=${distro_codename}-updates";/"o=Debian,a=${distro_codename}-updates";/' "$UPGRADES_CONF" || true
        if ! grep -q "Unattended-Upgrade::Package-Blacklist" "$UPGRADES_CONF"; then
            echo 'Unattended-Upgrade::Origins-Pattern { "o=*"; };' >> "/etc/apt/apt.conf.d/20auto-upgrades" || true
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
    FILE_NAME=$(wget -qO- http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/ | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1) || true
    if [ -n "$FILE_NAME" ]; then
        wget "http://archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb || true
        dpkg-deb -x lubuntu-artwork.deb root_dir || true
        mkdir -p "$USER_HOME/.local/share/lxqt/themes"
        # Ošetřeno || true proti pádu z důvodu chybějících souborů uvnitř deb balíčku
        cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/" 2>/dev/null || true
    fi
    cd ~ && rm -rf /tmp/lubuntu-rip || true

    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null || true
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null || true

    if [ -f "$CONF_SRC/lxqt-panel_amd64_no_about" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_amd64_no_about" /usr/bin/lxqt-panel || true
        chmod +x /usr/bin/lxqt-panel || true
    fi

    local SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    mkdir -p "$USER_HOME/.local/bin"
    if [ -d "$SCRIPTS_SRC" ]; then
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null || true
    fi

    chmod +s $(which brightnessctl 2>/dev/null) 2>/dev/null || true
    rm -f "/tmp/jas_notif_id" || true
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
        cp "$TOUCHPAD_SRC" /etc/X11/xorg.conf.d/40-libinput-touchpad.conf || true
    fi

    local SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
    if [ ! -f "$SESSION_CONF" ]; then
        echo -e "[General]\nwindow_manager=xfwm4" > "$SESSION_CONF"
    else
        sed -i 's/^window_manager=.*/window_manager=xfwm4/' "$SESSION_CONF" || true
        grep -q "^window_manager=" "$SESSION_CONF" || sed -i '/^\[General\]/a window_manager=xfwm4' "$SESSION_CONF" || true
    fi

    if [ -f "$XFWM_SRC" ]; then
        log "Aplikuji nastavení XFWM4..."
        local TMP_XFWM="/tmp/xfwm_setup.sh"
        echo "#!/bin/bash" > "$TMP_XFWM"
        cat "$XFWM_SRC" >> "$TMP_XFWM"
        chmod +x "$TMP_XFWM"
        run_as_user "$TMP_XFWM"
        rm -f "$TMP_XFWM" || true
    fi

    local LXQT_CONF="$USER_HOME/.config/lxqt/lxqt.conf"
    if [ -f "$LXQT_CONF" ]; then
        sed -i "s/^ask_before_logout=.*/ask_before_logout=$CONF_OUT/" "$LXQT_CONF" || true
        sed -i "s/^theme=.*/theme=Lubuntu Arc/" "$LXQT_CONF" || true
        if grep -q "^language=" "$LXQT_CONF"; then
            sed -i "s/^language=.*/language=$SYS_LANG_CODE/" "$LXQT_CONF" || true
        else
            sed -i "/^\[General\]/a language=$SYS_LANG_CODE" "$LXQT_CONF" || true
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
        cp "$app" "$LOCAL_APPS/" || true
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$LOCAL_APPS/$app_name" || true
    done

    for app in "${APPS_TO_HIDE[@]}"; do
        [ -f "$LOCAL_APPS/$app" ] && sed -i '/^NoDisplay=/d; $ a NoDisplay=true' "$LOCAL_APPS/$app" || true
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
        sed -i "s/^BROWSER=.*/BROWSER=$B_EXEC/" "$SESSION_CONF" || true
    fi

    if [ -f "$PANEL_CONF" ]; then
        sed -i '/^apps\\/d' "$PANEL_CONF" || true
        if [ -n "$B_NAME" ]; then
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\2\\\\desktop=$LOCAL_APPS/$B_NAME\napps\\\\size=2" "$PANEL_CONF" || true
        else
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\size=1" "$PANEL_CONF" || true
        fi
    fi

    local Q_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$Q_CONF")"
    [ ! -f "$Q_CONF" ] && echo -e "[General]\nshowTerminalSizeHint=false" > "$Q_CONF" || sed -i '/showTerminalSizeHint/d; /\[General\]/a showTerminalSizeHint=false' "$Q_CONF" || true

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

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local" || true
}

configure_plasma() {
    log "Aplikuji specifické nastavení pro Plasmu (Čisté zkratky a GTK Fix)..."
    
    mkdir -p "$USER_HOME/.config"

    # 1. Základní chování (Odhlášení a Klíčenka)
    echo -e "[General]\nconfirmLogout=$CONF_OUT" > "$USER_HOME/.config/ksmserverrc" || true
    echo -e "[Wallet]\nEnabled=false" > "$USER_HOME/.config/kwalletrc" || true

    # 2. GTK Fix pro Chrome (aby okno mělo všechna tlačítka)
    mkdir -p "$USER_HOME/.config/gtk-3.0"
    echo -e "[Settings]\ngtk-decoration-layout=icon:minimize,maximize,close" > "$USER_HOME/.config/gtk-3.0/settings.ini" || true

    # 3. ÚKLID: Smažeme ty zbytečné zástupce z minula, pokud tam zůstali
    rm -f "$USER_HOME/.local/share/applications/htop.desktop" || true
    rm -f "$USER_HOME/.local/share/applications/custom-htop.desktop" || true

    # 4. ZKRATKY: Nabindujeme to přímo na systémové .desktop soubory
    local SHORTCUTS_CONF="$USER_HOME/.config/kglobalshortcutsrc"
    touch "$SHORTCUTS_CONF"
    
    # Zkratka pro Htop (Ctrl+Shift+Esc) - Plasma si to sama najde v /usr/share/applications/htop.desktop
    if ! grep -q "^\[htop.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[htop.desktop]\n_launch=Ctrl+Shift+Esc,none,htop" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[htop.desktop\]/,/^\[/ s/^_launch=.*/_launch=Ctrl+Shift+Esc,none,htop/' "$SHORTCUTS_CONF" || true
    fi

    # Zkratka pro Výstřižky (Meta+Shift+S) - Využije systémový org.kde.spectacle.desktop
    if ! grep -q "^\[org.kde.spectacle.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[org.kde.spectacle.desktop]\nRectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[org.kde.spectacle.desktop\]/,/^\[/ s/^RectangularRegionScreenShot=.*/RectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot/' "$SHORTCUTS_CONF" || true
    fi

    # 5. Vizuál (Twilight motiv a tmavý panel)
    run_as_user "lookandfeeltool -a org.kde.plasma.twilight"
    
    local PLASMARC="$USER_HOME/.config/plasmarc"
    if [ ! -f "$PLASMARC" ]; then
        echo -e "[Theme]\nname=breeze-dark" > "$PLASMARC"
    else
        if grep -q "^\[Theme\]" "$PLASMARC"; then
            sed -i '/^\[Theme\]/,/^\[/ s/^name=.*/name=breeze-dark/' "$PLASMARC" || true
        else
            echo -e "\n[Theme]\nname=breeze-dark" >> "$PLASMARC"
        fi
    fi

    # Nastavení práv, aby na to mohl user i systém
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" || true
}

# === 4. SYSTÉMOVÉ SLUŽBY A BOOT ===

setup_display_manager() {
    log "Nastavuji Display Manager a Autologin..."
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        echo "/usr/bin/sddm" > /etc/X11/default-display-manager 2>/dev/null || true
        # Násilné vnucení SDDM přes systemd
        systemctl disable lightdm 2>/dev/null || true
        systemctl enable sddm 2>/dev/null || true
        dpkg-reconfigure -f noninteractive sddm 2>/dev/null || true
        
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/sddm.conf.d
            cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$REAL_USER
Session=plasma
EOF
        fi
    else
        echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
        # Násilné vnucení LightDM přes systemd
        systemctl disable sddm 2>/dev/null || true
        systemctl enable lightdm 2>/dev/null || true
        dpkg-reconfigure -f noninteractive lightdm 2>/dev/null || true
        
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/lightdm/lightdm.conf.d
            echo -e "[Seat:*]\nautologin-user=$REAL_USER\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/autologin.conf
            sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' /etc/lightdm/lightdm.conf 2>/dev/null || true
        fi
    fi
}

setup_boot() {
    log "Nastavuji GRUB a Boot Logo..."
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub || true

    if [ "$BOOT_LOGO" == "TRUE" ]; then
        log "Aplikuji grafický start (Plymouth)..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub || true
        # Pojistka || true aby nespadl skript, když selže rebuild initramfs
        plymouth-set-default-theme -R bgrt 2>/dev/null || plymouth-set-default-theme -R spinner 2>/dev/null || true
    else
        log "Ponechávám textový start..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub || true
    fi

    update-grub || true
    systemctl set-default graphical.target || true
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