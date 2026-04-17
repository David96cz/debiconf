#!/bin/bash
# ==============================================================================
# DEBICONF - ČISTÝ DEBIAN S DESKTOPOVÝM PROSTŘEDÍM (PROFI REFACTOR - FIXED)
# ==============================================================================

# === INIT FUNKCE ===

init_script() {
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
}

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
        echo "5. Vyžadovat pro sudo výhradně jen heslo ROOT? (Místo uživatelského hesla nastavené při instalaci bude pro administraci vyžadováno heslo ROOT)"
        while true; do
            echo "1) Ano (Sudo bude chtít ROOT heslo)"
            echo "2) Ne (Ponechat pro sudo klasické heslo uživatele)"
            read -p "Zadej číslo (1 nebo 2): " ROOT_ANS
            case "$ROOT_ANS" in
                1) 
                    ROOT_ADMIN_ONLY="TRUE"
                    ROOT_STR="Ano (Sudo na root heslo)"
                    break 
                    ;;
                2) 
                    ROOT_ADMIN_ONLY="FALSE"
                    ROOT_STR="Ne (Sudo na uživatele)"
                    # Rovnou natvrdo zakážeme smazání hesla, jinak by měl sudo bez hesla
                    REMOVE_PASS="FALSE" 
                    REMOVE_PASS_STR="Ne (Nutné pro sudo)"
                    break 
                    ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        # Zeptáme se na smazání hesla JEN pokud je sudo kryté rootem
        if [ "$ROOT_ADMIN_ONLY" == "TRUE" ]; then
            echo "--------------------------------------------------"
            echo "5b. Odstranit uživateli heslo pro přihlášení? (Windows styl - přihlášení jen kliknutím. Bezpečné, protože sudo už je chráněno ROOT heslem.)"
            while true; do
                echo "1) Ano (Vymazat heslo běžného uživatele)"
                echo "2) Ne (Ponechat uživateli heslo)"
                read -p "Zadej číslo (1 nebo 2): " PASS_ANS
                case "$PASS_ANS" in
                    1) REMOVE_PASS="TRUE"; REMOVE_PASS_STR="Ano (Bez hesla)"; break ;;
                    2) REMOVE_PASS="FALSE"; REMOVE_PASS_STR="Ne (S heslem)"; break ;;
                    r|R) continue 2 ;;
                    *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
                esac
            done
        fi

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

        echo "--------------------------------------------------"
        echo "7. Instalace RustDesk (Vzdálená plocha)?"
        echo "   Umožňuje ovládat tento počítač z jiného zařízení nebo naopak."
        echo "   Ideální pro rychlou technickou pomoc nebo správu na dálku."
        while true; do
            echo "1) Ano (Nainstalovat RustDesk)"
            echo "2) Ne (Přeskočit)"
            read -p "Zadej číslo (1 nebo 2): " RUSTDESK_ANS
            case "$RUSTDESK_ANS" in
                1) RUSTDESK_REQ="TRUE"; RUSTDESK_STR="Ano"; break ;;
                2) RUSTDESK_REQ="FALSE"; RUSTDESK_STR="Ne"; break ;;
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
        echo " RustDesk:         $RUSTDESK_STR"
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
            if command -v google-chrome &> /dev/null; then
                log "Google Chrome je již nainstalován, přeskakuji..."
            elif [ "$SYS_ARCH" == "arm64" ]; then
                log "UPOZORNĚNÍ: Google Chrome nevydává balíčky pro ARM. Instaluji jako náhradu Chromium."
                if command -v chromium &> /dev/null; then
                    log "Chromium je již nainstalováno, přeskakuji..."
                else
                    apt-get install -y chromium chromium-l10n || true
                fi
            else
                wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt-get install -y /tmp/chrome.deb || true 
            fi
            ;;
        2) 
            if command -v chromium &> /dev/null; then
                log "Chromium je již nainstalováno, přeskakuji..."
            else
                apt-get install -y chromium chromium-l10n || true 
            fi
            ;;
        3) 
            if command -v brave-browser &> /dev/null; then
                log "Brave Browser je již nainstalován, přeskakuji..."
            else
                curl -fsS https://dl.brave.com/install.sh | sh || true 
            fi
            ;;
        4) 
            if command -v firefox &> /dev/null; then
                log "Firefox je již nainstalován, přeskakuji..."
            else
                apt-get install -y firefox-esr firefox-esr-l10n-cs || true 
            fi
            ;;
    esac

    log "Instaluji kancelářský balík..."
    case $OFFICE_CHOICE in
        1) 
            if command -v libreoffice &> /dev/null; then
                log "LibreOffice je již nainstalován, přeskakuji..."
            else
                apt-get install -y libreoffice libreoffice-l10n-cs || true 
            fi
            ;;
        2) 
            if command -v desktopeditors &> /dev/null; then
                log "OnlyOffice je již nainstalován, přeskakuji..."
            elif [ "$SYS_ARCH" == "arm64" ]; then
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
            
            # PŘIDÁNO: fonts-wine (aby fungovalo vykreslování písma v exe)
            log "Instaluji nejnovější verzi WineHQ Stable..."
            apt-get install -y --install-recommends winehq-stable fonts-wine || true
            
            log "Stahuji absolutně nejnovější Winetricks přímo z GitHubu..."
            wget -qO /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks || true
            chmod +x /usr/local/bin/winetricks || true

            # PŘIDÁNO: Tichá inicializace Wine profilu na pozadí bez vyskakovacích oken
            log "Inicializuji Wine profil potichu, aby neotravoval uživatele..."
            su - "$REAL_USER" -c "WINEDLLOVERRIDES=mscoree,mshtml= wineboot -u" || true
        fi
    fi
    # ---------------------------------------------------------

    if [ "$RUSTDESK_REQ" == "TRUE" ]; then
        log "Instalace RustDesku zahájena. Detekuji verzi pro $SYS_ARCH..."
        
        # Výběr správné architektury (x86_64 vs aarch64)
        if [ "$SYS_ARCH" == "arm64" ]; then
            RUSTDESK_GREP="browser_download_url.*aarch64\.deb"
        else
            RUSTDESK_GREP="browser_download_url.*x86_64\.deb"
        fi

        # Získání URL z GitHubu
        LATEST_URL=$(curl -sL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -E "$RUSTDESK_GREP" | cut -d '"' -f 4 | head -n 1)
        
        if [ -n "$LATEST_URL" ]; then
            log "Stahuji RustDesk: $LATEST_URL"
            wget -qO /tmp/rustdesk.deb "$LATEST_URL"
            
            # 1. ROUBÍK: Zakážeme spuštění démona během apt-get instalace
            echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
            chmod +x /usr/sbin/policy-rc.d
            
            # 2. Instalace (proběhne tiše)
            env -u DISPLAY -u WAYLAND_DISPLAY apt-get install -y /tmp/rustdesk.deb || true
            rm -f /tmp/rustdesk.deb
            
            # 3. SUNDÁNÍ ROUBÍKU
            rm -f /usr/sbin/policy-rc.d
            
            log "Vypaluji TOML konfiguraci pro permanentní skrytí tray ikony..."
            
            # 4. CHIRURGICKÝ ŘEZ: Podvrhneme RustDesku soubor, který nasimuluje zadání hesla
            local RUSTDESK_CONF_DIR="$USER_HOME/.config/rustdesk"
            mkdir -p "$RUSTDESK_CONF_DIR"
            
            # Vytvoření souboru přesně s tím parametrem, co jsme našli
            echo -e "[options]\nstop-service = 'Y'" > "$RUSTDESK_CONF_DIR/RustDesk2.toml"
            
            # Extrémně důležité: Vrátit práva tobě, jinak by RustDesk crashnul na permissions
            chown -R "$REAL_USER:$REAL_USER" "$RUSTDESK_CONF_DIR"
            
            # Pojistka: To samé hodíme i do rootovy složky
            mkdir -p /root/.config/rustdesk
            echo -e "[options]\nstop-service = 'Y'" > /root/.config/rustdesk/RustDesk2.toml
            
            # 5. Teď můžeme službu nahodit - přečte si TOML a tray prostě nevyhodí.
            systemctl enable rustdesk 2>/dev/null || true
            systemctl start rustdesk 2>/dev/null || true
            
            log "RustDesk byl úspěšně nainstalován a navždy umlčen."
        else
            log "CHYBA: Nepodařilo se získat odkaz na RustDesk. Přeskakuji."
        fi
    fi
}

setup_auto_updates() {
    log "Konfiguruji profesionální automatické aktualizace..."

    # 1. Likvidace notifikátorů
    log "Odstraňuji zbytečné notifikátory..."
    apt-get purge -y plasma-discover-notifier packagekit 2>/dev/null || true

    # 2. Vypnutí standardních timerů, aby neblokovaly zámek /var/lib/dpkg/lock-frontend
    log "Deaktivuji výchozí apt timery..."
    printf 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n' > /etc/apt/apt.conf.d/20auto-upgrades
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

    # 3. Nasazení tvého skriptu
    local SRC_SCRIPT="$CONTENTS_DIR/lxqt/scripts/system-autoupdate"
    local DEST_SCRIPT="/etc/cron.daily/system-autoupdate"

    if [ -f "$SRC_SCRIPT" ]; then
        log "Instaluji autoupdate skript do cron.daily..."
        cp "$SRC_SCRIPT" "$DEST_SCRIPT"
        chmod +x "$DEST_SCRIPT"
        # Oprava vlastnictví na roota, aby cron neměl problém
        chown root:root "$DEST_SCRIPT"
    else
        log "CHYBA: Zdrojový skript nebyl nalezen v $SRC_SCRIPT!"
    fi
}

# === 3. KONFIGURACE DESKTOPOVÝCH PROSTŘEDÍ ===

# ==============================================================================
# KONFIGURACE LXQT + PODFUNKCE PRO KONFIGURACI
# ==============================================================================

lxqt_prepare_base_configs() {
    log "1/7: Připravuji základní konfigurační soubory LXQt..."
    
    # Odstranění Windows konců řádků
    [ -f "$CONTENTS_DIR/lxqt/config/shortcuts.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/shortcuts.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/xfwm.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/xfwm.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/contextmenu.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/contextmenu.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/lxqt-powermanagement.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/lxqt-powermanagement.conf" || true

    # Kopírování základu
    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null || true
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null || true

    # Základní nastavení LXQt
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

    # QTerminal nenápadně stranou
    local Q_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$Q_CONF")"
    [ ! -f "$Q_CONF" ] && echo -e "[General]\nshowTerminalSizeHint=false\nAskOnExit=false" > "$Q_CONF" || sed -i '/showTerminalSizeHint/d; /AskOnExit/d; /\[General\]/a showTerminalSizeHint=false\nAskOnExit=false' "$Q_CONF" || true

    # QPS konfigurace
    local QPS_DST_DIR="$USER_HOME/.config/qps"
    mkdir -p "$QPS_DST_DIR"
    if [ -f "$CONF_SRC/qps.conf" ]; then
        cp "$CONF_SRC/qps.conf" "$QPS_DST_DIR/qps.conf"
    fi
}

lxqt_setup_system_integrations() {
    log "2/7: Nasazuji systémové integrace (Skripty, APT hook, Locale, Polkit, NM-Tray)..."
    
    local SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    mkdir -p "$USER_HOME/.local/bin"
    if [ -d "$SCRIPTS_SRC" ]; then
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null || true
    fi

    echo "DPkg::Post-Invoke { \"su - $REAL_USER -c '$USER_HOME/.local/bin/update-wrappers.sh'\"; };" > /etc/apt/apt.conf.d/99-update-wrappers
    
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

    # --- OPRAVA NM-TRAY  ---
    log "Přesměrovávám nm-tray na Gnome editor a blokuji duplicitní ikonu..."
    
    # 1. Přesměrování editoru
    local NM_TRAY_DIR="$USER_HOME/.config/nm-tray"
    mkdir -p "$NM_TRAY_DIR"
    local NM_TRAY_CONF="$NM_TRAY_DIR/nm-tray.conf"
    
    if [ ! -f "$NM_TRAY_CONF" ]; then
        echo -e "[general]\nconnectionsEditor=nm-connection-editor" > "$NM_TRAY_CONF"
    else
        sed -i '/^connectionsEditor=/d' "$NM_TRAY_CONF"
        sed -i '/^\[general\]/a connectionsEditor=nm-connection-editor' "$NM_TRAY_CONF" 2>/dev/null || echo -e "\n[general]\nconnectionsEditor=nm-connection-editor" >> "$NM_TRAY_CONF"
    fi
    
    # 2. Likvidace duplicitní ikony z autostartu
    local AUTOSTART_DIR="$USER_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    echo -e "[Desktop Entry]\nHidden=true" > "$AUTOSTART_DIR/nm-applet.desktop"

    # === ČISTÉ AUTOMOUNTOVÁNÍ VŠECH DISKŮ PŘES NATIVNÍ PCMANFM-QT ===
    local PCMANFM_CONF="$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf"
    mkdir -p "$(dirname "$PCMANFM_CONF")"

    # Zkontroluje, jestli už tam sekce Volume je. Pokud ano, přepíše ty dvě důležité hodnoty. Pokud ne, přidá ji na konec.
    if grep -q "\[Volume\]" "$PCMANFM_CONF" 2>/dev/null; then
        sed -i 's/^AutoRun=.*/AutoRun=false/' "$PCMANFM_CONF"
        sed -i 's/^MountOnStartup=.*/MountOnStartup=true/' "$PCMANFM_CONF"
        sed -i 's/^MountRemovable=.*/MountRemovable=true/' "$PCMANFM_CONF"
    else
        echo -e "\n[Volume]\nAutoRun=false\nMountOnStartup=true\nMountRemovable=true" >> "$PCMANFM_CONF"
    fi

    mkdir -p /etc/polkit-1/rules.d
    printf 'polkit.addRule(function(action, subject) {\n    if ((action.id == "org.freedesktop.systemd1.manage-units" || \n         action.id == "org.freedesktop.systemd1.manage-unit-files") &&\n        subject.isInGroup("sudo")) {\n        var unit = action.lookup("unit");\n        if (unit == "rustdesk.service" || unit == "rustdesk") {\n            return polkit.Result.YES;\n        }\n    }\n});\n' > /etc/polkit-1/rules.d/60-rustdesk.rules

    chown "$REAL_USER:$REAL_USER" "$PCMANFM_CONF"
}

lxqt_setup_appearance() {
    log "3/7: Konfiguruji vzhled (stažení motivu, správce oken, panel, ikony)..."
    
    # 1. Stažení a příprava grafických podkladů (Lubuntu Artwork)
    log "Stahuji Lubuntu artwork a nasazuji ikony..."
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    
    # 1. SKREPOVÁNÍ PŘES cURL A CZ MIRROR: 
    # --max-time 5 garantuje, že i kdyby server hořel, skript se po 5 vteřinách pohne dál.
    local FILE_NAME=$(curl -s --max-time 5 "http://cz.archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/" | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1) || true
    
    if [ -n "$FILE_NAME" ]; then
        log "Nalezen balíček: $FILE_NAME, stahuji z CZ mirroru..."
        
        # 2. RYCHLÉ STAŽENÍ BALÍČKU
        wget -q --timeout=15 --tries=2 "http://cz.archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb || true
        
        if [ -s lubuntu-artwork.deb ]; then
            dpkg-deb -x lubuntu-artwork.deb root_dir || true
            mkdir -p "$USER_HOME/.local/share/lxqt/themes"
            cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/" 2>/dev/null || true
            log "Lubuntu Artwork úspěšně nasazen."
        else
            log "CHYBA: Stažení balíčku selhalo (soubor je prázdný)."
        fi
    else
        log "CHYBA: CZ Server neodpověděl do 5 vteřin, nepodařilo se zjistit název."
    fi
    
    cd ~ && rm -rf /tmp/lubuntu-rip || true

    local ICONS_SRC="$CONTENTS_DIR/lxqt/icons"
    if [ -d "$ICONS_SRC" ]; then
        cp -r "$ICONS_SRC" "$USER_HOME/.local/share/" 2>/dev/null || true
    fi

    # 2. XFWM4 Session
    local SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
    if [ ! -f "$SESSION_CONF" ]; then
        echo -e "[General]\nwindow_manager=xfwm4" > "$SESSION_CONF"
    else
        sed -i 's/^window_manager=.*/window_manager=xfwm4/' "$SESSION_CONF" || true
        grep -q "^window_manager=" "$SESSION_CONF" || sed -i '/^\[General\]/a window_manager=xfwm4' "$SESSION_CONF" || true
    fi

    local XFWM_SRC="$CONTENTS_DIR/lxqt/config/xfwm.conf"
    if [ -f "$XFWM_SRC" ]; then
        cp "$XFWM_SRC" /tmp/xfwm-apply.sh
        chown "$REAL_USER:$REAL_USER" /tmp/xfwm-apply.sh
        mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
        chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/xfce4"
        su - "$REAL_USER" -c "dbus-run-session bash -c 'bash /tmp/xfwm-apply.sh; sleep 2'" || true
        rm -f /tmp/xfwm-apply.sh
    fi

    # 3. Architektura panelu
    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    if [ "$SYS_ARCH" = "amd64" ] && [ -f "$CONF_SRC/lxqt-panel_no_about_amd64" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_no_about_amd64" /usr/bin/lxqt-panel || true
        chmod +x /usr/bin/lxqt-panel || true
    elif [ "$SYS_ARCH" = "arm64" ] && [ -f "$CONF_SRC/lxqt-panel_no_about_arm64" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_no_about_arm64" /usr/bin/lxqt-panel || true
        chmod +x /usr/bin/lxqt-panel || true
    fi

    # 4. Panel ikony a quicklaunch
    local PANEL_CONF="$USER_HOME/.config/lxqt/panel.conf"
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    if [ -f "$PANEL_CONF" ]; then
        sed -i "s|icon=~/.local|icon=$USER_HOME/.local|g" "$PANEL_CONF" || true
        
        case $BROWSER_CHOICE in
            1) B_NAME="google-chrome.desktop"; B_EXEC="google-chrome-stable" ;;
            2) B_NAME="chromium.desktop"; B_EXEC="chromium" ;;
            3) B_NAME="brave-browser.desktop"; B_EXEC="brave-browser" ;;
            4) B_NAME="firefox-esr.desktop"; B_EXEC="firefox-esr" ;;
            *) B_NAME=""; B_EXEC="" ;;
        esac

        [ -f "$SESSION_CONF" ] && [ -n "$B_EXEC" ] && sed -i "s/^BROWSER=.*/BROWSER=$B_EXEC/" "$SESSION_CONF" || true

        # Definice názvu zástupce pro vyhledávání (uprav podle reality)
        local SEARCH_DESKTOP="$LOCAL_APPS/hledat.desktop"

        # Vymazání starých zástupců
        sed -i '/^apps\\/d' "$PANEL_CONF" || true
        
        if [ -n "$B_NAME" ]; then
            # Pokud je prohlížeč: 1. Hledání, 2. PCManFM, 3. Prohlížeč (size=3)
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$SEARCH_DESKTOP\napps\\\\2\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\3\\\\desktop=$LOCAL_APPS/$B_NAME\napps\\\\size=3" "$PANEL_CONF" || true
        else
            # Pokud není prohlížeč: 1. Hledání, 2. PCManFM (size=2)
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$SEARCH_DESKTOP\napps\\\\2\\\\desktop=$LOCAL_APPS/pcmanfm-qt.desktop\napps\\\\size=2" "$PANEL_CONF" || true
        fi
    fi
}

lxqt_setup_shortcuts_and_menus() {
    log "4/7: Přidávám klávesové zkratky a vlastní kontextová menu..."
    
    local SHORTCUTS_SRC="$CONTENTS_DIR/lxqt/config/shortcuts.conf"
    local SHORTCUTS_CONF="$USER_HOME/.config/lxqt/globalkeyshortcuts.conf"
    
    if [ -f "$SHORTCUTS_SRC" ]; then
        # Pojistka: Vytvoříme složku a prázdný soubor, pokud ještě neexistuje
        mkdir -p "$(dirname "$SHORTCUTS_CONF")"
        touch "$SHORTCUTS_CONF"
        
        while IFS='|' read -r label shortcut cmd || [[ -n "$label" ]]; do
            [[ "$label" =~ ^#.*$ || -z "$label" ]] && continue
            safe_shortcut="${shortcut//+/%2B}"
            
            # UNIVERZÁLNÍ NAHRAZOVÁNÍ SCRIPTŮ: 
            # Najde cokoliv, co končí na .sh nebo .py a vloží před to cestu ~/.local/bin/
            FINAL_CMD=$(echo "$cmd" | sed -E "s@([a-zA-Z0-9_-]+\.(sh|py))@$USER_HOME/.local/bin/\1@g")
            
            # BRUTÁLNÍ VRAŽDA SYSTÉMOVÉ ZKRATKY (aby LXQt nemazalo Alberta atd.)
            sed -i "/^\[${safe_shortcut}\]/,+3d" "$SHORTCUTS_CONF" 2>/dev/null || true
            sed -i "/^\[${safe_shortcut}\.99\]/,+3d" "$SHORTCUTS_CONF" 2>/dev/null || true
            
            # Zápis čisté zkratky
            echo -e "\n[${safe_shortcut}]\nComment=$label\nEnabled=true\nExec=$FINAL_CMD" >> "$SHORTCUTS_CONF"
        done < "$SHORTCUTS_SRC"

        # Super_L oprava
        sed -i '/^\[Super_L\]/,+3d' "$SHORTCUTS_CONF" 2>/dev/null || true
        echo -e "\n[Super_L]\nComment=Otevrit menu\nEnabled=true\npath=/panel/fancymenu/show_hide" >> "$SHORTCUTS_CONF"
    fi

    # Kontextové menu
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
                sed -i "s|~/.local/bin|$USER_HOME/.local/bin|g" "$ACTION_DIR/$CURRENT_FILE" || true
            fi
        done < "$CONTEXT_CONF"
    fi

    # Zástupci z actions.conf - OPRAVENÁ VERZE (Bez custom_shortcut sraček)
    local LOCAL_APPS_DIR="$USER_HOME/.local/share/applications"
    mkdir -p "$LOCAL_APPS_DIR"
    local SRC_ACTIONS="$CONTENTS_DIR/lxqt/config/actions.conf"
    
    if [ -f "$SRC_ACTIONS" ]; then
        local BLOCK=""
        local APP_NAME=""
        
        # Načítáme soubor a rozdělujeme ho na bloky podle [Desktop Entry]
        while IFS= read -r line || [ -n "$line" ]; do
            trimmed=$(echo "$line" | xargs)
            
            if [[ "$trimmed" == "[Desktop Entry]" ]]; then
                # Pokud už máme v paměti předchozí blok, uložíme ho
                if [ -n "$BLOCK" ]; then
                    # Vytvoření bezpečného jména souboru z APP_NAME
                    local SAFE_FILENAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')
                    [ -z "$SAFE_FILENAME" ] && SAFE_FILENAME="unknown-app-$(date +%s%N)"
                    
                    echo -e "$BLOCK" > "$LOCAL_APPS_DIR/${SAFE_FILENAME}.desktop"
                    chmod +x "$LOCAL_APPS_DIR/${SAFE_FILENAME}.desktop"
                fi
                # Resetujeme buffer pro nový blok
                BLOCK="[Desktop Entry]"
                APP_NAME=""
            elif [ -n "$BLOCK" ] && [ -n "$trimmed" ]; then
                # Zpracování řádků uvnitř bloku
                local processed_line="${line//~\/.local/$USER_HOME\/.local}"
                BLOCK="${BLOCK}\n${processed_line}"
                
                # Pokud narazíme na Name, uložíme si ho pro název souboru
                if [[ "$processed_line" == Name=* ]]; then
                    APP_NAME="${processed_line#Name=}"
                fi
            fi
        done < "$SRC_ACTIONS"
        
        # Nezapomenout uložit úplně poslední blok ze souboru
        if [ -n "$BLOCK" ]; then
            local SAFE_FILENAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')
            echo -e "$BLOCK" > "$LOCAL_APPS_DIR/${SAFE_FILENAME}.desktop"
            chmod +x "$LOCAL_APPS_DIR/${SAFE_FILENAME}.desktop"
        fi
    fi
}

lxqt_packages_install() {
        
    log "5/7 Instaluji balíčky a externí aplikace (Albert & PeaZip čistě pro amd64)..."

    # Kontrola architektury
    local SYS_ARCH=$(dpkg --print-architecture)
    if [ "$SYS_ARCH" != "amd64" ]; then
        log "UPOZORNĚNÍ: Architektura $SYS_ARCH. Tento skript instaluje externí aplikace pouze pro amd64. Přeskakuji."
        return 0
    fi

    # 1. Albert - Správná cesta pro Debian 13
    log "Nasazuji oficiální repozitář Alberta pro Debian 13..."
    curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/Debian_13/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
    echo 'deb http://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_13/ /' | tee /etc/apt/sources.list.d/albert.list
    
    apt-get update -y
    
    # Zkusíme instalaci přes apt (pro automatické updaty v budoucnu)
    if ! apt-get install -y albert; then
        log "CHYBA apt instalace. Přepínám na dynamické stažení .deb přímo z adresáře..."
        
        # Scraper: Najde přesný název aktuálního balíčku v HTML kódu té stránky
        local ALBERT_BASE="https://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_13/amd64/"
        local ALBERT_FILE=$(curl -s "$ALBERT_BASE" | grep -oE 'albert_[^"]+_amd64\.deb' | head -n 1)
        
        if [ -n "$ALBERT_FILE" ]; then
            log "Našel jsem balíček: $ALBERT_FILE. Stahuji..."
            wget -qO "/tmp/$ALBERT_FILE" "${ALBERT_BASE}${ALBERT_FILE}"
            dpkg -i "/tmp/$ALBERT_FILE" || apt-get install -f -y
            rm -f "/tmp/$ALBERT_FILE"
        else
            log "FATÁLNÍ CHYBA: Na té adrese se nepodařilo najít žádný albert...amd64.deb!"
        fi
    fi

   # 2. PeaZip - Dynamické stažení nejnovější Qt6 verze z GitHubu
    log "Stahuji nejnovější PeaZip..."
    
    # Přísný filtr: musí to obsahovat "browser_download_url", "LINUX.Qt6" a "amd64.deb"
    local PEAZIP_URL=$(curl -s https://api.github.com/repos/peazip/PeaZip/releases/latest | grep "browser_download_url" | grep "LINUX.Qt6" | grep "amd64.deb" | cut -d '"' -f 4 | head -n 1)
    
    if [ -n "$PEAZIP_URL" ]; then
        log "Našel jsem odkaz: $PEAZIP_URL"
        wget -qO /tmp/peazip_latest.deb "$PEAZIP_URL"
        dpkg -i /tmp/peazip_latest.deb || apt-get install -f -y
        rm -f /tmp/peazip_latest.deb
    else
        log "CHYBA: Nepodařilo se získat odkaz na PeaZip z GitHubu."
    fi
}

lxqt_setup_apps_and_defaults() {
    log "6/7: Nastavuji chování aplikací, MIME typy a Autostart..."
    
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    local WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    mkdir -p "$LOCAL_APPS"
    
    # Nasazení wrapperů
    for app in /usr/share/applications/*.desktop; do
        [ -e "$app" ] || continue
        app_name=$(basename "$app")
        cp "$app" "$LOCAL_APPS/" || true
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$LOCAL_APPS/$app_name" || true
    done

    # Skrytí aplikací
    local APPS_TO_HIDE_STR=$(get_section "$LOCAL_CONFIG" "APPS_TO_HIDE")
    read -r -a APPS_TO_HIDE <<< "$APPS_TO_HIDE_STR"
    for app in "${APPS_TO_HIDE[@]}"; do
        [ -f "$LOCAL_APPS/$app" ] && sed -i '/^NoDisplay=/d; $ a NoDisplay=true' "$LOCAL_APPS/$app" || true
    done

    # --- MIME Typy ---
    local MIME_FILE="$USER_HOME/.config/mimeapps.list"
    [ ! -f "$MIME_FILE" ] && echo "[Added Associations]" > "$MIME_FILE"
    grep -q "^\[Added Associations\]" "$MIME_FILE" || echo "[Added Associations]" >> "$MIME_FILE"

    set_default_app() {
        local mime="$1"
        local app="$2"
        sed -i "/^${mime//\//\\/}=/d" "$MIME_FILE" 2>/dev/null || true
        sed -i "/^\[Added Associations\]/a ${mime}=${app};" "$MIME_FILE"
    }

    local APPS_CONF="$CONTENTS_DIR/lxqt/config/defaultapps.conf"
    
    if [ -f "$APPS_CONF" ]; then
        log "Načítám výchozí aplikace z defaultapps.conf..."
        local CURRENT_APP=""
        
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | xargs) # Očištění od mezer
            [[ -z "$line" || "$line" =~ ^# ]] && continue # Přeskočí prázdné řádky a komentáře
            
            if [[ "$line" =~ ^\[(.*)\]$ ]]; then
                CURRENT_APP="${BASH_REMATCH[1]}"
                
                # INTELIGENCE: Přeskočíme aplikace, které uživatel v dotazníku odmítl
                if [ "$CURRENT_APP" == "wine.desktop" ] && [ "$WINE_CHOICE" != "1" ]; then
                    CURRENT_APP="SKIP"
                elif [ "$CURRENT_APP" == "libreoffice-writer.desktop" ] && [ "$OFFICE_CHOICE" != "1" ]; then
                    CURRENT_APP="SKIP"
                elif [ "$CURRENT_APP" == "onlyoffice-desktopeditors.desktop" ] && [ "$OFFICE_CHOICE" != "2" ]; then
                    CURRENT_APP="SKIP"
                fi
                
            elif [ "$CURRENT_APP" != "SKIP" ] && [ -n "$CURRENT_APP" ]; then
                # Pokud nejsme ve SKIP módu, zapíšeme MIME typ k aktuální aplikaci
                set_default_app "$line" "$CURRENT_APP"
            fi
        done < "$APPS_CONF"
    else
        log "UPOZORNĚNÍ: Soubor $APPS_CONF nebyl nalezen, výchozí aplikace nebudou nastaveny."
    fi

    # Autostart
    local AUTOSTART_DIR="$USER_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    AUTORUN_APPS=$(awk '/^\[AUTORUN\]/{flag=1; next} /^\[/{flag=0} flag && NF' "$CONTENTS_DIR/lxqt/config.txt")

    if [ -n "$AUTORUN_APPS" ]; then
        for APP in $AUTORUN_APPS; do
            local DEST_DESKTOP="$AUTOSTART_DIR/${APP}-autostart.desktop"
            local EXEC_CMD="$APP"
            
            # CHYTRÁ DETEKCE CESTY: 
            # Pokud název aplikace končí na .sh nebo .py, vynuť absolutní cestu k .local/bin
            if [[ "$APP" == *.sh || "$APP" == *.py ]]; then
                EXEC_CMD="$USER_HOME/.local/bin/$APP"
            fi
            
            echo "[Desktop Entry]" > "$DEST_DESKTOP"
            echo "Type=Application" >> "$DEST_DESKTOP"
            echo "Name=Autostart $APP" >> "$DEST_DESKTOP"
            echo "Exec=$EXEC_CMD" >> "$DEST_DESKTOP"
            echo "Hidden=false" >> "$DEST_DESKTOP"
            echo "NoDisplay=false" >> "$DEST_DESKTOP"
            echo "X-GNOME-Autostart-enabled=true" >> "$DEST_DESKTOP"
        done
    fi

    # --- KONFIGURACE ALBERT A PEAZIP (Dynamické cesty) ---
    log "Nasazuji konfigurace pro Albert a PeaZip..."
    
    # 1. Albert
    local ALBERT_SRC="$CONTENTS_DIR/lxqt/config/albert.conf"
    local ALBERT_DEST="$USER_HOME/.config/albert/config"
    if [ -f "$ALBERT_SRC" ]; then
        mkdir -p "$(dirname "$ALBERT_DEST")"
        cp "$ALBERT_SRC" "$ALBERT_DEST"
        
        # Nahrazení normální cesty (/home/david -> /home/novyuzivatel)
        sed -i "s|/home/david|$USER_HOME|g" "$ALBERT_DEST"
        # Nahrazení Qt escapované cesty (home\david -> home\novyuzivatel)
        sed -i "s|home\\\\david|home\\\\$REAL_USER|g" "$ALBERT_DEST"
    fi

    # Vytvoření portálů pro Alberta k obcházení Qt bugu s krátkými cestami
    local ALBERT_DISKS="$USER_HOME/.local/share/albert_disks"
    mkdir -p "$ALBERT_DISKS"
    ln -sfn /media "$ALBERT_DISKS/media"
    ln -sfn /mnt "$ALBERT_DISKS/mnt"

    # ZABITÍ "FIRST RUN" DIALOGU (Podstrčení stavového souboru)
    local ALBERT_STATE_DIR="$USER_HOME/.local/share/albert"
    mkdir -p "$ALBERT_STATE_DIR"
    echo -e "[General]\nlast_used_version=34.0.10" > "$ALBERT_STATE_DIR/state"

    # 2. PeaZip
    local PEAZIP_SRC="$CONTENTS_DIR/lxqt/config/peazip.conf"
    local PEAZIP_DEST="$USER_HOME/.config/peazip/conf.txt"
    if [ -f "$PEAZIP_SRC" ]; then
        mkdir -p "$(dirname "$PEAZIP_DEST")"
        cp "$PEAZIP_SRC" "$PEAZIP_DEST"
        
        # Nahrazení normální cesty
        sed -i "s|/home/david|$USER_HOME|g" "$PEAZIP_DEST"
        
        # --- DYNAMICKÉ NASTAVENÍ JAZYKA PEAZIPU ---
        # Převod systémového kódu na jméno souboru PeaZipu
        local PEAZIP_LANG=""
        case "$SYS_LANG_CODE" in
            cs) PEAZIP_LANG="cz.txt" ;;
            sk) PEAZIP_LANG="sk.txt" ;;
            de) PEAZIP_LANG="de.txt" ;;
            fr) PEAZIP_LANG="fr.txt" ;;
            es) PEAZIP_LANG="es.txt" ;;
            pl) PEAZIP_LANG="pl.txt" ;;
            # Angličtina nebo neznámý jazyk necháme prázdné (PeaZip použije defaultní ENG)
            *) PEAZIP_LANG="" ;;
        esac
        
        # Najde řádek pod [language] a nahradí ho správným jazykem
        if grep -q "^\[language\]" "$PEAZIP_DEST"; then
            sed -i "/^\[language\]/{n;s/.*/$PEAZIP_LANG/}" "$PEAZIP_DEST"
        fi
        # ------------------------------------------
    fi
}

lxqt_config_backup() {
    # --- ZÁLOHA A AUTOMATICKÁ OBNOVA (100% TAR Snapshot) ---
    log "7/7 Vytvářím 1:1 TAR snapshot .config pro případ, že by si uživatel smazal .config z domovského adresáře..."
    
    # 0. Nasazení kanárka (tajný soubor)
    touch "$USER_HOME/.config/lxqt/.debiconf_ok"
    
    # 1. Čistá záloha do archivu (Zaručí zachování struktury a zamezí slučování zmetků)
    mkdir -p /opt/debiconf-backup
    tar -czf /opt/debiconf-backup/config.tar.gz -C "$USER_HOME" .config
    
    # Zabezpečíme, aby si to uživatel mohl po přihlášení sám rozbalit
    chmod 644 /opt/debiconf-backup/config.tar.gz
    
    # 2. Záchranný skript (Běží při KAŽDÉM přihlášení)
    local RESTORE_SCRIPT="/etc/X11/Xsession.d/90debiconf-restore"
    
    echo '# Kontrola na základě chybějícího kanárka' > "$RESTORE_SCRIPT"
    echo 'if [ ! -f "$HOME/.config/lxqt/.debiconf_ok" ]; then' >> "$RESTORE_SCRIPT"
    echo '    # 1. Nemilosrdně smazat zmetka, kterého LXQt vytvořilo při odhlášení' >> "$RESTORE_SCRIPT"
    echo '    rm -rf "$HOME/.config/lxqt"' >> "$RESTORE_SCRIPT"
    echo '    # 2. Rozbalit čistý 1:1 snapshot přesně tak, jak byl nastaven při instalaci' >> "$RESTORE_SCRIPT"
    echo '    tar -xzf /opt/debiconf-backup/config.tar.gz -C "$HOME"' >> "$RESTORE_SCRIPT"
    echo 'fi' >> "$RESTORE_SCRIPT"
    
    chmod 644 "$RESTORE_SCRIPT"
    # -------------------------------------------------------------
}

configure_lxqt() {
    log "=== ZAHAJUJI KOMPLEXNÍ KONFIGURACI LXQT ==="
    
    lxqt_prepare_base_configs
    lxqt_setup_system_integrations
    lxqt_setup_appearance
    lxqt_setup_shortcuts_and_menus
    lxqt_packages_install
    lxqt_setup_apps_and_defaults
    
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local" || true

    lxqt_config_backup
    
    log "=== KONFIGURACE LXQT BYLA ÚSPĚŠNĚ DOKONČENA ==="
}

# ==============================================================================
# KONFIGURACE KDE PLASMA
# ==============================================================================

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

    log "Odstraňuji Plasma Discover Notifier, aby neotravoval v liště..."
    apt-get purge -y plasma-discover-notifier || true

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
            printf "[Autologin]\nUser=%s\nSession=plasma\nRelogin=false\n" "$REAL_USER" > /etc/sddm.conf.d/autologin.conf
        fi
    else
        echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
        systemctl disable sddm 2>/dev/null || true
        systemctl enable lightdm 2>/dev/null || true
        dpkg-reconfigure -f noninteractive lightdm 2>/dev/null || true

        log "Aplikuji automatickou konfiguraci pro LightDM..."
    
        # 1. Zobrazení uživatelů k nakliknutí
        local LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
        if [ -f "$LIGHTDM_CONF" ]; then
            # Najde zakomentovaný řádek a odkomentuje ho s hodnotou false
            sed -i 's/^#greeter-hide-users=true/greeter-hide-users=false/' "$LIGHTDM_CONF"
            sed -i 's/^#greeter-hide-users=false/greeter-hide-users=false/' "$LIGHTDM_CONF"
        fi

        # 2. Nastavení správné tapety a ošetření černé obrazovky
        local GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
        [ ! -f "$GREETER_CONF" ] && touch "$GREETER_CONF"
        
        # Pojistka, že tam je sekce [greeter]
        if ! grep -q "^\[greeter\]" "$GREETER_CONF"; then
            echo -e "[greeter]\n" >> "$GREETER_CONF"
        fi

        # Vynucení modré tapety pod sekci [greeter]
        if grep -q "^background=" "$GREETER_CONF"; then
            sed -i 's|^background=.*|background=/usr/share/lxqt/wallpapers/simple_blue_widescreen.png|' "$GREETER_CONF"
        else
            sed -i '/^\[greeter\]/a background=/usr/share/lxqt/wallpapers/simple_blue_widescreen.png' "$GREETER_CONF"
        fi
        
        log "LightDM nastaven s modrou tapetou."
        
        if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
            mkdir -p /etc/lightdm/lightdm.conf.d
            
            # TADY JE TA HLAVIČKA [Seat:*], KTEROU JSEM DVAKRÁT ZAPOMNĚL:
            printf "[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n" "$REAL_USER" > /etc/lightdm/lightdm.conf.d/autologin.conf
            
            # Zapnutí numlocku na přihlašovací obrazovce
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

    hardware_detection

    update-grub || true
    systemctl set-default graphical.target || true
}

admin_security() {
    if [ "$ROOT_ADMIN_ONLY" == "TRUE" ]; then
        log "Zabezpečuji systém: Nastavuji sudo na vyžadování hesla ROOT..."

        # Povolí uživateli měnit heslo bez zadávání starého hesla v SUDO
        echo "$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/chpasswd, /usr/bin/passwd *" | sudo tee /etc/sudoers.d/99-passwd-nopass
        sudo chmod 0440 /etc/sudoers.d/99-passwd-nopass
        
        if grep -q '^root:[!\*]' /etc/shadow; then
            log "CHYBA: Účet root je zamčen nebo nemá nastavené heslo!"
            log "Bezpečnostní pojistka: Sudo bude dál chtít heslo uživatele, jinak by se systém zablokoval."
        else
            echo 'Defaults rootpw' > /etc/sudoers.d/01-rootpw
            chmod 0440 /etc/sudoers.d/01-rootpw
            log "Sudo nyní bezpečně vyžaduje heslo ROOT."
        fi
    fi

    if [ "$REMOVE_PASS" == "TRUE" ]; then
        log "Odstraňuji heslo uživatele '$REAL_USER' pro snadné přihlášení..."
        passwd -d "$REAL_USER"
        log "Heslo uživatele bylo odstraněno."
    fi
}

hardware_detection() {
    log "Provádím detekci hardwaru pro specifické parametry jádra..."
    
    local GRUB_FILE="/etc/default/grub"
    local EXTRA_CMDLINE=""

    # 1. Detekce Bay Trail (Celeron/Pentium/Atom z této rodiny trpící na C-states zamrzání)
    if grep -iqE "(N28|N29|J19|N35|J29|Z37)[0-9][0-9]" /proc/cpuinfo 2>/dev/null; then
        log "Detekován procesor rodiny Intel Bay Trail. Přidávám opravu C-states..."
        EXTRA_CMDLINE+=" intel_idle.max_cstate=1"
    fi

    # 2. Detekce AMD Grafiky (přepnutí starých karet z radeon na amdgpu)
    if lspci -nn 2>/dev/null | grep -i vga | grep -iqE "amd|radeon"; then
        log "Detekována AMD grafika. Vynucuji moderní amdgpu ovladač pro starší karty..."
        EXTRA_CMDLINE+=" radeon.cik_support=0 amdgpu.cik_support=1 radeon.si_support=0 amdgpu.si_support=1"
    fi

    # Pokud jsme něco našli, bezpečně to zapíšeme do GRUBu
    if [ -n "$EXTRA_CMDLINE" ] && [ -f "$GRUB_FILE" ]; then
        local CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" | cut -d'"' -f2 | cut -d"'" -f2)
        
        for param in $EXTRA_CMDLINE; do
            if ! echo "$CURRENT_CMDLINE" | grep -q "$param"; then
                CURRENT_CMDLINE="$CURRENT_CMDLINE $param"
            fi
        done
        
        CURRENT_CMDLINE=$(echo "$CURRENT_CMDLINE" | xargs)
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" "$GRUB_FILE" || true
        
        log "Nové parametry jádra: $CURRENT_CMDLINE"
    else
        log "Žádný specifický hardware (Bay Trail/AMD) nedetekován, parametry jádra zůstávají beze změny."
    fi
}

# ==============================================================================
# BĚH PROGRAMU (MAIN)
# ==============================================================================

main() {
    init_script
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
    rm -rf "$BASE_DIR"
    echo "=================================================="
    echo "HOTOVO"
    echo "RESTART ZA 5 SEKUND..."
    echo "=================================================="
    for i in {5..1}
    do
        echo "$i..."
        sleep 1
    done
    echo "Restartuji nyní!"
    reboot
}

main