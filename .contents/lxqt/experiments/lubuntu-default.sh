# 1. Smazání nastavení LXQt (panel, session)
rm -rf ~/.config/lxqt

# 2. Smazání nastavení oken (Openbox i XFWM4)
rm -rf ~/.config/openbox
rm -rf ~/.config/xfce4

# 3. Smazání ikon na ploše a nastavení pcmanfm
rm -rf ~/.config/pcmanfm-qt

# 4. Smazání těch skrytých aplikací (aby se znovu objevily)
rm -rf ~/.local/share/applications

# 5. OKAMŽITÝ KILL (aby se nic neuložilo)
pkill -u "$USER"
