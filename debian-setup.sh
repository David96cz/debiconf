#!/bin/bash

# --- 1. DETEKCE UŽIVATELE A SUDO PRÁVA ---
REAL_USER=$(ls /home | head -n 1)
echo "Našel jsem složku uživatele: $REAL_USER. Dávám mu sudo práva..."
apt install -y sudo
usermod -aG sudo $REAL_USER

# --- 2. NAČTENÍ KONFIGURACE Z TEXTÁKU ---
PACKAGES=$(sed -n '/^\[INSTALL\]/,/^\[/p' setup-config.txt | grep -v '\[.*\]' | grep -v '^#' | grep -v '=' | xargs)

LOW_PC=$(grep -i "^LOW_PC=" setup-config.txt | cut -d'=' -f2 | tr '[:lower:]' '[:upper:]')
TIMEOUT=$(grep -i "^GRUB_TIMEOUT=" setup-config.txt | cut -d'=' -f2)
BOOT_LOGO=$(grep -i "^BOOT_LOGO=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
BROWSER_URL=$(grep -i "^BROWSER_URL=" setup-config.txt | cut -d'=' -f2-)

AUTOLOGIN=$(grep -i "^AUTOLOGIN=" setup-config.txt | cut -d'=' -f2 | tr '[:lower:]' '[:upper:]')
RELOGIN=$(grep -i "^RELOGIN=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
CONFIRM_LOGOUT=$(grep -i "^CONFIRM_LOGOUT=" setup-config.txt | cut -d'=' -f2 | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')

# --- 3. INSTALACE VŠEHO BALASTU ---
echo "Instaluji systémové balíky: $PACKAGES"
apt install -y $PACKAGES

# --- 4. INSTALACE EXTERNÍHO PROHLÍŽEČE ---
if [ -n "$BROWSER_URL" ]; then
    echo "Stahuji a instaluji prohlížeč z $BROWSER_URL..."
    wget -O /tmp/browser.deb "$BROWSER_URL"
    apt install -y /tmp/browser.deb
    rm /tmp/browser.deb
else
    echo "BROWSER_URL je prázdné, instalaci prohlížeče přeskakuji."
fi

# --- 5. KONFIGURACE SDDM (PŘIHLAŠOVÁNÍ) ---
echo "Nastavuji SDDM..."
mkdir -p /etc/sddm.conf.d
if [ "$AUTOLOGIN" == "TRUE" ] || [ "$RELOGIN" == "TRUE" ]; then
    echo "[Autologin]" > /etc/sddm.conf.d/autologin.conf
    if [ "$AUTOLOGIN" == "TRUE" ]; then
        echo "User=$REAL_USER" >> /etc/sddm.conf.d/autologin.conf
        echo "Session=plasma" >> /etc/sddm.conf.d/autologin.conf
    fi
    if [ "$RELOGIN" == "TRUE" ]; then
        echo "Relogin=true" >> /etc/sddm.conf.d/autologin.conf
    fi
else
    echo "Autologin vypnut v configu. Mažu případná stará nastavení."
    rm -f /etc/sddm.conf.d/autologin.conf
fi

# --- 6. VYMRDÁNÍ SÍTĚ ---
echo "Mažu starou síť z interfaces, ať to sežere NetworkManager v Plasmě..."
echo -e "auto lo\niface lo inet loopback" > /etc/network/interfaces

# --- 7. ÚPRAVY PLASMY PRO UŽIVATELE ---
echo "Aplikuji uživatelská nastavení Plasmy pro $REAL_USER..."

if [ "$LOW_PC" == "TRUE" ]; then
    echo "Aplikuji hardcore ořezání Plasmy..."
    su - $REAL_USER -c "kwriteconfig6 --file baloofilerc --group 'Basic Settings' --key 'Indexing-Enabled' false"
    su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false"
    su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_shadowEnabled false"
    su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_translucencyEnabled false"
    su - $REAL_USER -c "kwriteconfig6 --file kwinrc --group Compositing --key Enabled false"
fi

if [ "$CONFIRM_LOGOUT" == "FALSE" ]; then
    echo "Vypínám potvrzovací dialog při odhlášení/restartu..."
    su - $REAL_USER -c "kwriteconfig6 --file ksmserverrc --group General --key confirmLogout false"
fi

# --- 8. GRAFICKÝ BOOT LOGO (Plymouth) ---
if [ "$BOOT_LOGO" == "TRUE" ]; then
    echo "Skrývám terminál při startu a nahazuju Plymouth logo..."
    apt install -y plymouth plymouth-themes
    # Změní parametr jádra z "quiet" na "quiet splash" (splash zapne grafiku)
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    # Aplikuje moderní výchozí motiv (spinner) a přebuduje startovací obraz (initramfs)
    plymouth-set-default-theme -R spinner
fi

# --- 9. GRUB A REBOOT ---
echo "Zkracuju GRUB na $TIMEOUT sekund..."
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub
update-grub

echo "Všechno hotovo. Systém je ready out of the script. Restartuju!"
reboot