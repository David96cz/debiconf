# ---------------------------------------------------------
# XX. VYKASTROVÁNÍ FANCY MENU (Odstranění tlačítka O LXQt)
# ---------------------------------------------------------
echo ">> Kastruji Fancy Menu a odstraňuji tlačítko 'O LXQt'..."

# 1. Instalace vývojářských nástrojů (pokud ještě nejsou)
sudo apt update
sudo apt install -y dpkg-dev build-essential cmake
sudo apt build-dep -y lxqt-panel

# 2. Vytvoření dočasné pracovní složky
mkdir -p /tmp/lxqt-hack && cd /tmp/lxqt-hack

# 3. Stažení zdrojáků (apt source nevyžaduje sudo)
apt source lxqt-panel
cd lxqt-panel-*/plugin-fancymenu

# 4. Automatická úprava C++ kódu (magie se sed)
# Najde addWidget a zakomentuje ho
sed -i 's/mButtonsLayout->addWidget(mAboutButton);/\/\/ mButtonsLayout->addWidget(mAboutButton);/g' lxqtfancymenuwindow.cpp
# Najde connect a hned pod něj vloží hide() a setFixedSize(0,0)
sed -i '/connect(mAboutButton.*runAboutgDialog);/a \    mAboutButton->hide();\n    mAboutButton->setFixedSize(0, 0);' lxqtfancymenuwindow.cpp

# 5. Rychlá kompilace a instalace
cd ..
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr ..
make -j$(nproc)
sudo make install

# 6. Úklid a restart panelu
cd ~
rm -rf /tmp/lxqt-hack
killall lxqt-panel && lxqt-panel &

echo ">> Fancy Menu úspěšně upraveno!"
