#!/bin/bash

# --- 1. DETEKCE UŽIVATELE A SUDO PRÁVA ---
REAL_USER=$(ls /home | head -n 1)
echo "Našel jsem složku uživatele: $REAL_USER. Dávám mu sudo práva..."
apt install -y sudo
usermod -aG sudo $REAL_USER

# --- 2. NAČTENÍ KONFIGURACE Z TEXTÁKU ---
PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' setup-config.txt | grep -v '\[.*\]' | grep -v '^#' | grep -v '=' | xargs)
BROWSER_URL=$(grep -i "^BROWSER_URL=" setup-config.txt | cut -d'=' -f2-)

# --- 3. VYNUCENÍ DEFAULTNÍCH HODNOT (Blbovzdornost) ---
echo "Validuji konfiguraci z textáku..."

DESKTOP_ENV=$(grep -i "^DESKTOP_ENV=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$DESKTOP_ENV" != "PLASMA" ] && [ "$DESKTOP_ENV" != "LXQT" ]; then
    echo "Neznámé nebo prázdné DESKTOP_ENV. Vynucuji default: PLASMA"
    DESKTOP_ENV="PLASMA"
fi

BOOT_LOGO=$(grep -i "^BOOT_LOGO=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$BOOT_LOGO" != "FALSE" ]; then BOOT_LOGO="TRUE"; fi

LOW_PC=$(grep -i "^LOW_PC=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$LOW_PC" != "TRUE" ]; then LOW_PC="FALSE"; fi

AUTOLOGIN=$(grep -i "^AUTOLOGIN=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$AUTOLOGIN" != "TRUE" ]; then AUTOLOGIN="FALSE"; fi

RELOGIN=$(grep -i "^RELOGIN=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$RELOGIN" != "TRUE" ]; then RELOGIN="FALSE"; fi

CONFIRM_LOGOUT=$(grep -i "^CONFIRM_LOGOUT=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
if [ "$CONFIRM_LOGOUT" != "TRUE" ]; then CONFIRM_LOGOUT="FALSE"; fi

TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1)
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "Neplatný nebo prázdný GRUB_TIMEOUT. Vynucuji default: 0"
    TIMEOUT="0"
fi

# --- 4. PŘÍPRAVA CORE BALÍČKŮ PODLE DESKTOPU ---
if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    CORE_PACKAGES="plasma-desktop sddm xorg konsole dolphin network-manager plasma-nm"
    SDDM_SESSION="plasma"
elif [ "$DESKTOP_ENV" == "LXQT" ]; then
    # Zadrátovaný nativní network-manager a nm-tray applet
    CORE_PACKAGES="lxqt-core lightdm xorg pcmanfm-qt qterminal arc-theme papirus-icon-theme network-manager nm-tray"
fi

# --- 5. FILTRACE NEEXISTUJÍCÍCH BALÍKŮ ---
echo "Filtruji neexistující balíky..."
ALL_PACKAGES="$CORE_PACKAGES $PACKAGES"
SAFE_PACKAGES=""

for pkg in $ALL_PACKAGES; do
    if apt-cache show "$pkg" > /dev/null 2>&1; then
        SAFE_PACKAGES="$SAFE_PACKAGES $pkg"
    else
        echo "⚠️ VAROVÁNÍ: Balíček '$pkg' neexistuje v repozitářích. Přeskakuji ho!"
    fi
done

if [ -z "$SAFE_PACKAGES" ]; then
    echo "KRITICKÁ CHYBA: Žádný ze zadaných balíků neexistuje. Končím."
    exit 1
fi

# --- 6. INSTALACE SYSTÉMU A APLIKACÍ ---
echo "Instaluji ověřené balíky..."
apt install -y $SAFE_PACKAGES

# --- 7. INSTALACE EXTERNÍHO PROHLÍŽEČE ---
if [ -n "$BROWSER_URL" ]; then
    echo "Stahuji a instaluji prohlížeč z $BROWSER_URL..."
    wget -O /tmp/browser.deb "$BROWSER_URL"
    apt install -y /tmp/browser.deb
    rm /tmp/browser.deb
fi

# --- 8. KONFIGURACE PŘIHLAŠOVÁNÍ (SDDM pro Plasmu, LightDM pro LXQt) ---
echo "Nastavuji přihlašování..."

if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    mkdir -p /etc/sddm.conf.d
    if [ "$AUTOLOGIN" == "TRUE" ] || [ "$RELOGIN" == "TRUE" ]; then
        echo "[Autologin]" > /etc/sddm.conf.d/autologin.conf
        if [ "$AUTOLOGIN" == "TRUE" ]; then
            echo "User=$REAL_USER" >> /etc/sddm.conf.d/autologin.conf
            echo "Session=$SDDM_SESSION" >> /etc/sddm.conf.d/autologin.conf
        fi
        if [ "$RELOGIN" == "TRUE" ]; then
            echo "Relogin=true" >> /etc/sddm.conf.d/autologin.conf
        fi
    else
        rm -f /etc/sddm.conf.d/autologin.conf
    fi
elif [ "$DESKTOP_ENV" == "LXQT" ]; then
    if [ "$AUTOLOGIN" == "TRUE" ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        echo "[Seat:*]" > /etc/lightdm/lightdm.conf.d/autologin.conf
        echo "autologin-user=$REAL_USER" >> /etc/lightdm/lightdm.conf.d/autologin.conf
        echo "autologin-user-timeout=0" >> /etc/lightdm/lightdm.conf.d/autologin.conf
    else
        rm -f /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
fi

# --- 9. VYMRDÁNÍ SÍTĚ ---
echo "Mažu starou síť z interfaces..."
echo -e "auto lo\niface lo inet loopback" > /etc/network/interfaces

# --- 10. ÚPRAVY PRO UŽIVATELE (Podle prostředí) ---
echo "Aplikuji uživatelská nastavení pro $REAL_USER..."

if [ "$DESKTOP_ENV" == "PLASMA" ]; then
    if [ "$LOW_PC" == "TRUE" ]; then
        su - $REAL_USER -c "kwriteconfig6 --file baloofilerc --group 'Basic Settings' --key 'Indexing-Enabled' false"
        su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false"
        su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_shadowEnabled false"
        su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_translucencyEnabled false"
        su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Compositing --key Enabled false"
    fi

    if [ "$CONFIRM_LOGOUT" == "FALSE" ]; then
        su - $REAL_USER -c "kwriteconfig6 --file ksmserverrc --group General --key confirmLogout false"
    fi

elif [ "$DESKTOP_ENV" == "LXQT" ]; then
    echo "Předpřipravuji moderní Arc vzhled a Papirus ikony pro LXQt..."
    mkdir -p /home/$REAL_USER/.config/lxqt
    
    cat <<EOF > /home/$REAL_USER/.config/lxqt/lxqt.conf
[General]
icon_theme=Papirus
theme=frost
EOF

    chown -R $REAL_USER:$REAL_USER /home/$REAL_USER/.config
fi

# --- 11. GRAFICKÝ BOOT LOGO (Plymouth) ---
if [ "$BOOT_LOGO" == "TRUE" ]; then
    echo "Nahazuju Plymouth logo..."
    apt install -y plymouth plymouth-themes
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    plymouth-set-default-theme -R spinner
fi

# --- 12. GRUB A REBOOT ---
echo "Zkracuju GRUB na $TIMEOUT sekund..."
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "Všechno hotovo. Systém je ready out of the script. Restartuju!"
reboot