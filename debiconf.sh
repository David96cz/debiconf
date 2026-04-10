#!/bin/bash
# ==============================================================================
# DEBICONF - ČISTÝ DEBIAN S DESKTOPOVÝM PROSTŘEDÍM (PROFI REFACTOR - FIXED)
# ==============================================================================

set -e # Ukončí skript při první vážné chybě

# === GLOBÁLNÍ PROMĚNNÉ A CESTY ===
BASE_DIR="$(dirname "$(realpath "$0")")"
CONTENTS_DIR="$BASE_DIR/.contents"
GLOBAL_CONFIG="$CONTENTS_DIR/setup-config.txt"

# Bezpečnější detekce původního uživatele (hledá UID 1000+)
REAL_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' | head -n 1)
if [ -z "$REAL_USER" ]; then
    echo -e "\033[1;31mCHYBA: Nepodařilo se najít žádného běžného uživatele (UID 1000+).\033[0m" >&2
    exit 1
fi
# Přesná detekce home složky podle databáze uživatelů
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Detekce jazyka
SYS_LOCALE=$(grep "^LANG=" /etc/default/locale | cut -d'=' -f2 | tr -d '"' || echo "en_US.UTF-8")
SYS_LANG_CODE="${SYS_LOCALE%%.*}"

# Přidána detekce architektury (amd64 nebo arm64)
SYS_ARCH=$(dpkg --print-architecture)

# === POMOCNÉ FUNKCE ===

log() {
    echo -e "\n\033[1;34m>> $1\033[0m"
}

error() {
    echo -e "\n\033[1;31mCHYBA: $1\033[0m" >&2
    exit 1
}

run_as_user() {
    su - "$REAL_USER" -c "dbus-launch $1" 2>/dev/null || true
}

get_setting() {
    local key="$1"
    if [ -f "$GLOBAL_CONFIG" ]; then
        grep -i "^${key}=" "$GLOBAL_CONFIG" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d '[:space:]' || true
    fi
}

get_section() {
    local file="$1"
    local section="$2"
    if [ -f "$file" ]; then
        sed -n "/^\[$section\]/,/^\[/p" "$file" | grep -v '^\[.*\]' | grep -vE '^\s*(#|$)' | xargs || true
    fi
}

# === 1. PŘÍPRAVA A INTERAKTIVNÍ DOTAZY ===

init_setup() {
    [ "$EUID" -ne 0 ] && error "Nutno spustit jako root (sudo)"
    
    log "Detekován systémový jazyk instalace: $SYS_LANG_CODE"
    log "Instalace bude provedena pro uživatele: $REAL_USER"
    sleep 1

    # HLAVNÍ INTERAKTIVNÍ SMYČKA
    while true; do
        clear
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e "\033[1;36m                 DEBIAN SETUP                     \033[0m"
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e " \033[1;33m(Kdykoliv zadej 'R' pro reset a návrat na začátek)\033[0m"
        echo -e "\033[1;36m--------------------------------------------------\033[0m"
        echo ""

        echo "1. Vyber desktopové prostředí"
        while true; do
            echo "1) KDE Plasma"
            echo "2) LXQT"
            read -p "Zadej číslo (1 nebo 2): " DISTRO_ANS
            case "$DISTRO_ANS" in
                1) DESKTOP_ENV="PLASMA"; DESKTOP_STR="KDE Plasma"; break ;;
                2) DESKTOP_ENV="LXQT"; DESKTOP_STR="LXQt"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "2. Vyber prohlížeč"
        while true; do
            echo "1) Chrome"
            echo "2) Chromium"
            echo "3) Brave"
            echo "4) Firefox"
            echo "5) Nic"
            read -p "Zadej číslo (1 až 5): " BROWSER_CHOICE
            case "$BROWSER_CHOICE" in
                1) BROWSER_STR="Google Chrome"; break ;;
                2) BROWSER_STR="Chromium"; break ;;
                3) BROWSER_STR="Brave"; break ;;
                4) BROWSER_STR="Firefox"; break ;;
                5) BROWSER_STR="Žádný"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej číslo 1 až 5 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "3. Vyber kancelářský balík"
        while true; do
            echo "1) LibreOffice"
            echo "2) OnlyOffice"
            echo "3) Nic"
            read -p "Zadej číslo (1 až 3): " OFFICE_CHOICE
            case "$OFFICE_CHOICE" in
                1) OFFICE_STR="LibreOffice"; break ;;
                2) OFFICE_STR="OnlyOffice"; break ;;
                3) OFFICE_STR="Žádný"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej číslo 1 až 3 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "4. Chceš nastavit automatické přihlašování?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "Zadej číslo (1 nebo 2): " AUTO_ANS
            case "$AUTO_ANS" in
                1) AUTOLOGIN_REQ="TRUE"; AUTOLOGIN_STR="Ano"; break ;;
                2) AUTOLOGIN_REQ="FALSE"; AUTOLOGIN_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "5. Omezit sudo pouze na heslo ROOT? (Běžný uživatel ztratí administrátorská práva)"
        while true; do
            echo "1) Ano (Max. zabezpečení)"
            echo "2) Ne (Ponechat sudo běžnému uživateli)"
            read -p "Zadej číslo (1 nebo 2): " ROOT_ANS
            case "$ROOT_ANS" in
                1) ROOT_ADMIN_ONLY="TRUE"; ROOT_STR="Ano (Odebrat sudo)"; break ;;
                2) ROOT_ADMIN_ONLY="FALSE"; ROOT_STR="Ne (Ponechat sudo)"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "6. Chceš nainstalovat Wine a Winetricks pro Windows aplikace?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "Zadej číslo (1 nebo 2): " WINE_ANS
            case "$WINE_ANS" in
                1) WINE_REQ="TRUE"; WINE_STR="Ano"; break ;;
                2) WINE_REQ="FALSE"; WINE_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        # SOUHRN A POTVRZENÍ
        clear
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e "\033[1;36m                 SOUHRN NASTAVENÍ                 \033[0m"
        echo -e "\033[1;36m==================================================\033[0m"
        echo " Cílový uživatel:  $REAL_USER"
        echo " Prostředí:        $DESKTOP_STR"
        echo " Prohlížeč:        $BROWSER_STR"
        echo " Office:           $OFFICE_STR"
        echo " Autologin:        $AUTOLOGIN_STR"
        echo " Zámek Sudo:       $ROOT_STR"
        echo " Wine podpora:     $WINE_STR"
        echo -e "\033[1;36m==================================================\033[0m"
        echo "Je toto nastavení správné?"
        while true; do
            echo "1) Ano (Spustit instalaci)"
            echo "2) Ne (Začít znovu)"
            read -p "Zadej číslo (1 nebo 2, případně R pro restart): " CONFIRM_ANS
            case "$CONFIRM_ANS" in
                1) break 2 ;; 
                2|r|R) continue 2 ;; 
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done
    done

    # Definice lokálního konfiguráku
    LOCAL_CONFIG="$CONTENTS_DIR/$(echo "$DESKTOP_ENV" | tr '[:upper:]' '[:lower:]')/config.txt"

    # Načtení zbytku globálních nastavení
    TIMEOUT=$(get_setting "GRUB_TIMEOUT")
    TIMEOUT=${TIMEOUT:-0}
    
    CONF_OUT_RAW=$(get_setting "CONFIRM_LOGOUT" | tr '[:lower:]' '[:upper:]')
    [[ "$CONF_OUT_RAW" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    
    BOOT_LOGO=$(get_setting "BOOT_LOGO" | tr '[:lower:]' '[:upper:]')
}

prepare_system() {
    log "Základní příprava systému a sítě..."
    apt-get update -qq
    # Přidán plymouth a plymouth-themes
    apt-get install -y sudo curl wget dpkg-dev git dbus-x11 numlockx plymouth plymouth-themes
    
    usermod -aG sudo,audio,video,plugdev "$REAL_USER" || true

    apt-get purge -y ifupdown || true
    rm -rf /etc/network/interfaces.d/* || true
    
    printf "auto lo\niface lo inet loopback\n" > /etc/network/interfaces
}

# === 2. INSTALACE BALÍČKŮ A PROHLÍŽEČŮ ===

install_packages() {
    log "Načítám konfigurace a instaluji balíčky pro architekturu: $SYS_ARCH..."
    
    local ALL_PKGS=$(get_section "$GLOBAL_CONFIG" "INSTALL")
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "CORE_PACKAGES")"
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "EXTRA_PACKAGES")"
    
    read -r -a PKG_ARRAY <<< "$ALL_PKGS"
    
    if [ ${#PKG_ARRAY[@]} -gt 0 ]; then
        apt-get install -y --no-install-recommends "${PKG_ARRAY[@]}"
    fi

    log "Instaluji prohlížeč..."
    case $BROWSER_CHOICE in
        1) 
            if [ "$SYS_ARCH" == "arm64" ]; then
                log "UPOZORNĚNÍ: Google Chrome nevydává balíčky pro ARM. Instaluji jako náhradu Chromium."
                apt-get install -y chromium chromium-l10n || true
            else
                wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt-get install -y /tmp/chrome.deb || true 
            fi
            ;;
        2) apt-get install -y chromium chromium-l10n || true ;;
        3) curl -fsS https://dl.brave.com/install.sh | sh || true ;;
        4) apt-get install -y firefox-esr firefox-esr-l10n-cs || true ;;
    esac

    log "Instaluji kancelářský balík..."
    case $OFFICE_CHOICE in
        1) apt-get install -y libreoffice libreoffice-l10n-cs || true ;;
        2) 
            if [ "$SYS_ARCH" == "arm64" ]; then
                wget -qO /tmp/onlyoffice.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_arm64.deb && apt-get install -y /tmp/onlyoffice.deb || true
            else
                wget -qO /tmp/onlyoffice.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb && apt-get install -y /tmp/onlyoffice.deb || true
            fi
            ;;
    esac

    # -- NOVÝ BLOK PRO NEJNOVĚJŠÍ WINE (WINEHQ) A WINETRICKS --
    if [ "$WINE_REQ" == "TRUE" ]; then
        log "Zpracovávám požadavek na instalaci Wine..."
        if [ "$SYS_ARCH" == "arm64" ]; then
            log "UPOZORNĚNÍ: Architektura ARM64 nepodporuje nativní spouštění x86 Windows aplikací bez emulátoru. Instalaci Wine přeskakuji z důvodu kompatibility."
        else
            log "Povoluji 32bitovou architekturu (i386)..."
            dpkg --add-architecture i386 || true
            
            log "Přidávám oficiální WineHQ repozitář (bezpečně pro tuto verzi Debianu)..."
            mkdir -p /etc/apt/keyrings
            wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || true
            
            # Dynamické načtení kódového jména (např. trixie), aby nedošlo k přidání cizích repozitářů
            source /etc/os-release
            wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/debian/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" || true
            
            apt-get update -qq || true
            
            log "Instaluji nejnovější verzi WineHQ Stable..."
            apt-get install -y --install-recommends winehq-stable || true
            
            log "Stahuji absolutně nejnovější Winetricks přímo z GitHubu..."
            wget -qO /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks || true
            chmod +x /usr/local/bin/winetricks || true
        fi
    fi
    # ---------------------------------------------------------

    if grep -iq "^INSTALL_RUSTDESK=TRUE" "$GLOBAL_CONFIG" || grep -iq "^INSTALL_RUSTDESK=TRUE" "$LOCAL_CONFIG"; then
        log "Instalace RustDesku povolena. Zjišťuji nejnovější verzi..."
        
        # Filtr pro GitHub API dynamicky podle architektury (x86_64 vs aarch64)
        if [ "$SYS_ARCH" == "arm64" ]; then
            RUSTDESK_GREP="browser_download_url.*aarch64\.deb"
        else
            RUSTDESK_GREP="browser_download_url.*x86_64\.deb"
        fi

        LATEST_URL=$(curl -sL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -E "$RUSTDESK_GREP" | cut -d '"' -f 4 | head -n 1)
        
        if [ -n "$LATEST_URL" ]; then
            log "Stahuji RustDesk pro $SYS_ARCH z: $LATEST_URL"
            wget -qO /tmp/rustdesk.deb "$LATEST_URL"
            apt-get install -y /tmp/rustdesk.deb || true
            rm -f /tmp/rustdesk.deb
        else
            log "CHYBA: Nepodařilo se získat odkaz na nejnovější RustDesk. Přeskakuji."
        fi
    fi
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

    printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Download-Upgradeable-Packages "1";\nAPT::Periodic::AutocleanInterval "7";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
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
        log "Aplikuji externí konfiguraci XFWM4..."
        sed -i 's/\r$//' "$XFWM_SRC"
        
        cp "$XFWM_SRC" /tmp/xfwm-apply.sh
        chown "$REAL_USER:$REAL_USER" /tmp/xfwm-apply.sh
        
        # Vytvoří to root, práva se automaticky opraví na konci celého skriptu
        mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
        
        su - "$REAL_USER" -c "dbus-run-session bash /tmp/xfwm-apply.sh" || true
        rm -f /tmp/xfwm-apply.sh
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
    # Překlad vlnovky u vlastní ikony menu na absolutní cestu
    if [ -f "$PANEL_CONF" ]; then
        sed -i "s|icon=~/.local|icon=$USER_HOME/.local|g" "$PANEL_CONF" || true
    fi
    
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

    # --- VÝCHOZÍ APLIKACE (MIME TYPES) ---
    log "Nastavuji výchozí aplikace (FeatherPad, GDebi, Office)..."
    local MIME_FILE="$USER_HOME/.config/mimeapps.list"
    
    # Vytvoření souboru a základní sekce, pokud neexistuje
    [ ! -f "$MIME_FILE" ] && echo "[Default Applications]" > "$MIME_FILE"
    grep -q "^\[Default Applications\]" "$MIME_FILE" || echo "[Default Applications]" >> "$MIME_FILE"

    # Pomocná lokální funkce pro bezpečný zápis/přepis
    set_default_app() {
        local mime="$1"
        local app="$2"
        # Smaže starý záznam (pokud existuje) a vloží nový hned pod hlavičku
        sed -i "/^${mime//\//\\/}=/d" "$MIME_FILE" 2>/dev/null || true
        sed -i "/^\[Default Applications\]/a ${mime}=${app};" "$MIME_FILE"
    }

    # TXT -> FeatherPad
    set_default_app "text/plain" "featherpad.desktop"
    
    # DEB balíčky -> GDebi
    set_default_app "application/vnd.debian.binary-package" "gdebi.desktop"

    # DOCX -> Podle výběru v dotazníku
    if [ "$OFFICE_CHOICE" == "1" ]; then
        set_default_app "application/vnd.openxmlformats-officedocument.wordprocessingml.document" "libreoffice-writer.desktop"
    elif [ "$OFFICE_CHOICE" == "2" ]; then
        set_default_app "application/vnd.openxmlformats-officedocument.wordprocessingml.document" "onlyoffice-desktopeditors.desktop"
    fi
    # -------------------------------------

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local" || true
}

configure_plasma() {
    log "Aplikuji specifické nastavení pro Plasmu..."
    
    mkdir -p "$USER_HOME/.config"

    echo -e "[General]\nconfirmLogout=$CONF_OUT" > "$USER_HOME/.config/ksmserverrc" || true
    echo -e "[Wallet]\nEnabled=false" > "$USER_HOME/.config/kwalletrc" || true

    mkdir -p "$USER_HOME/.config/gtk-3.0"
    echo -e "[Settings]\ngtk-decoration-layout=icon:minimize,maximize,close" > "$USER_HOME/.config/gtk-3.0/settings.ini" || true

    rm -f "$USER_HOME/.local/share/applications/htop.desktop" || true
    rm -f "$USER_HOME/.local/share/applications/custom-htop.desktop" || true

    local SHORTCUTS_CONF="$USER_HOME/.config/kglobalshortcutsrc"
    touch "$SHORTCUTS_CONF"
    
    if ! grep -q "^\[htop.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[htop.desktop]\n_launch=Ctrl+Shift+Esc,none,htop" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[htop.desktop\]/,/^\[/ s/^_launch=.*/_launch=Ctrl+Shift+Esc,none,htop/' "$SHORTCUTS_CONF" || true
    fi

    if ! grep -q "^\[org.kde.spectacle.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[org.kde.spectacle.desktop]\nRectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[org.kde.spectacle.desktop\]/,/^\[/ s/^RectangularRegionScreenShot=.*/RectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot/' "$SHORTCUTS_CONF" || true
    fi

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

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" || true
}

# === 4. SYSTÉMOVÉ SLUŽBY A BOOT ===

setup_display_manager() {
    log "Nastavuji Display Manager a Autologin..."
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        echo "/usr/bin/sddm" > /etc/X11/default-display-manager 2>/dev/null || true
        systemctl disable lightdm 2>/dev/null || true
        systemctl enable sddm 2>/dev/null || true
        dpkg-reconfigure -f noninteractive sddm 2>/dev/null || true
        
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/sddm.conf.d
            printf "[Autologin]\nUser=%s\nSession=plasma\nRelogin=true\n" "$REAL_USER" > /etc/sddm.conf.d/autologin.conf
        fi
    else
        echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
        systemctl disable sddm 2>/dev/null || true
        systemctl enable lightdm 2>/dev/null || true
        dpkg-reconfigure -f noninteractive lightdm 2>/dev/null || true
        
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/lightdm/lightdm.conf.d
            printf "[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n" "$REAL_USER" > /etc/lightdm/lightdm.conf.d/autologin.conf
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
        plymouth-set-default-theme -R bgrt 2>/dev/null || plymouth-set-default-theme -R spinner 2>/dev/null || true
    else
        log "Ponechávám textový start..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub || true
    fi

    update-grub || true
    systemctl set-default graphical.target || true
}

admin_security() {
    # === 5. FINÁLNÍ ZABEZPEČENÍ ===
    if [ "$ROOT_ADMIN_ONLY" == "TRUE" ]; then
        log "Zabezpečuji systém: Pokus o odebrání uživatele '$REAL_USER' ze skupiny sudo..."
        
        # Ochranný mechanismus: Ověření, zda je účet root vůbec aktivní (nemá zamčené heslo '!*' v /etc/shadow)
        if grep -q '^root:[!\*]' /etc/shadow; then
            log "CHYBA: Účet root je zamčen nebo nemá nastavené heslo!"
            log "Bezpečnostní pojistka: Ponechávám uživateli '$REAL_USER' práva sudo, jinak by se systém zcela zablokoval."
        else
            deluser "$REAL_USER" sudo 2>/dev/null || true
            rm -f "/etc/sudoers.d/$REAL_USER" 2>/dev/null || true
            log "Uživatel '$REAL_USER' byl úspěšně degradován. Pro správu systému bude nyní vyžadováno heslo ROOT."
        fi
    fi
}

# ==============================================================================
# BĚH PROGRAMU (MAIN)
# ==============================================================================

main() {
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
    admin_security

    echo "=================================================="
    echo " HOTOVO"
    echo " RESTART ZA 5 SEKUND."
    echo "=================================================="
    sleep 5
    reboot
}

main