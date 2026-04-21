#!/usr/bin/env python3
import sys
import glob#!/usr/bin/env python3
import sys
import glob
import os
import subprocess
import shutil
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QTabWidget, QLabel, QLineEdit, 
                             QPushButton, QCheckBox, QComboBox, QFileDialog, 
                             QTableWidget, QTableWidgetItem, QMessageBox, 
                             QGroupBox, QFormLayout, QHeaderView, QAbstractItemView)
from PyQt5.QtCore import Qt, QFileInfo, QSize
from PyQt5.QtGui import QIcon

# --- KONFIGURACE ---
USER_HOME = os.path.expanduser("~")
APPS_DIR = os.path.join(USER_HOME, ".local/share/applications")
SYSTEM_APPS_DIR = "/usr/share/applications"
BUSY_SCRIPT = os.path.join(USER_HOME, ".local/bin/busy-launch.py")

XDG_CATEGORIES = [
    ("🎮 Hry", "Game"), ("🌍 Internet", "Network"), ("🎨 Grafika", "Graphics"),
    ("💼 Kancelář", "Office"), ("🎬 Zvuk a Video", "AudioVideo"),
    ("🛠️  Systémové nástroje", "System;Utility"), ("💻 Vývoj", "Development"),
    ("🎒 Příslušenství", "Qt;Utility")
]

# --- POMOCNÉ FUNKCE ---
def get_app_icon(icon_str):
    if os.path.isabs(icon_str) and os.path.exists(icon_str):
        return QIcon(icon_str)
    icon_base = icon_str.rsplit('.', 1)[0] if icon_str.lower().endswith(('.png', '.svg', '.xpm', '.ico')) else icon_str
    icon = QIcon.fromTheme(icon_base)
    if icon.isNull():
        for d in ["/usr/share/pixmaps", os.path.expanduser("~/.local/share/icons")]:
            for ext in [".png", ".svg"]:
                p = os.path.join(d, icon_base + ext)
                if os.path.exists(p): return QIcon(p)
    return icon if not icon.isNull() else QIcon.fromTheme("application-x-executable")

def parse_desktop_file(filepath):
    """Vrací (Jméno, Ikona, jeVlastní)"""
    name, name_cs, icon, custom = "", "", "application-x-executable", False
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if line.startswith("Name="): name = line.split("=", 1)[1].strip()
                elif line.startswith("Name[cs]="): name_cs = line.split("=", 1)[1].strip()
                elif line.startswith("Icon="): icon = line.split("=", 1)[1].strip()
                elif "X-Debiconf-Custom=true" in line: custom = True
    except: pass
    return (name_cs if name_cs else name), icon, custom

class ShortcutApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Správce Zástupců")
        self.setWindowFlags(Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
        self.resize(800, 600)
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        layout = QVBoxLayout(main_widget)
        
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)
        
        self.init_creator_tab()
        self.init_manager_tab()
        
    def init_creator_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        form_group = QGroupBox("Vytvořit nového zástupce")
        form_layout = QFormLayout(form_group)
        
        self.name_input = QLineEdit()
        self.name_input.textChanged.connect(self.update_auto_comment)
        form_layout.addRow("Název aplikace:", self.name_input)
        
        self.comment_input = QLineEdit()
        self.comment_input.setEnabled(False)
        self.auto_comment_cb = QCheckBox("Automatický")
        self.auto_comment_cb.setChecked(True)
        self.auto_comment_cb.stateChanged.connect(self.toggle_comment_mode)
        
        comment_layout = QHBoxLayout()
        comment_layout.addWidget(self.comment_input); comment_layout.addWidget(self.auto_comment_cb)
        form_layout.addRow("Popis (Komentář):", comment_layout)
        
        self.exec_input = QLineEdit()
        self.exec_input.textChanged.connect(self.validate_exec_intelligence)
        self.exec_btn = QPushButton("Procházet...")
        self.exec_btn.clicked.connect(self.pick_exec_file)
        
        exec_layout = QHBoxLayout()
        exec_layout.addWidget(self.exec_input); exec_layout.addWidget(self.exec_btn)
        form_layout.addRow("Příkaz / Cesta (Povinné):", exec_layout)
        
        self.intel_group = QGroupBox("Inteligentní nastavení")
        intel_layout = QVBoxLayout(self.intel_group)
        self.terminal_cb = QCheckBox("Spustit v terminálu")
        self.wrapper_cb = QCheckBox("Indikace načítání (Wrapper)")
        self.wrapper_cb.setChecked(True)
        intel_layout.addWidget(self.terminal_cb); intel_layout.addWidget(self.wrapper_cb)
        self.intel_group.hide()
        form_layout.addRow(self.intel_group)
        
        self.category_input = QComboBox()
        for friendly_name, xdg_name in XDG_CATEGORIES: self.category_input.addItem(friendly_name, xdg_name)
        form_layout.addRow("Kategorie menu:", self.category_input)
        
        self.icon_input = QLineEdit()
        self.icon_btn = QPushButton("Vybrat...")
        self.icon_btn.clicked.connect(self.pick_icon_file)
        self.extract_btn = QPushButton("Vytáhnout z EXE")
        self.extract_btn.clicked.connect(self.extract_exe_icon)
        self.extract_btn.hide()
        
        icon_layout = QHBoxLayout()
        icon_layout.addWidget(self.icon_input); icon_layout.addWidget(self.icon_btn); icon_layout.addWidget(self.extract_btn)
        form_layout.addRow("Ikona aplikace:", icon_layout)
        
        self.create_btn = QPushButton("Vytvořit zástupce v Menu")
        self.create_btn.setStyleSheet("font-weight: bold; padding: 12px; background-color: #2a7fca; color: white;")
        self.create_btn.clicked.connect(self.create_shortcut)
        
        layout.addWidget(form_group); layout.addStretch(); layout.addWidget(self.create_btn)
        self.tabs.addTab(tab, "Generátor")

    def init_manager_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        
        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("Hledat aplikaci v menu...")
        self.search_bar.textChanged.connect(self.filter_apps)
        layout.addWidget(self.search_bar)
        
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(['Viditelný', 'Aplikace', 'Typ', 'Cesta'])
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.setIconSize(QSize(32, 32))
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Fixed)
        self.table.setColumnWidth(0, 70)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        self.table.setColumnWidth(2, 100)
        self.table.setColumnHidden(3, True) # Skrytá cesta
        
        layout.addWidget(self.table)
        
        button_layout = QHBoxLayout()
        self.save_btn = QPushButton("Uložit viditelnost")
        self.save_btn.setStyleSheet("background-color: #4caf50; color: white; padding: 10px; font-weight: bold;")
        self.save_btn.clicked.connect(self.save_visibility)
        
        self.delete_btn = QPushButton("Trvale smazat")
        # OPRAVA: Definice stylu pro aktivní i deaktivovaný (zašedlý) stav
        self.delete_btn.setStyleSheet("""
            QPushButton { background-color: #f44336; color: white; padding: 10px; font-weight: bold; }
            QPushButton:disabled { background-color: #9e9e9e; color: #e0e0e0; }
        """)
        self.delete_btn.setEnabled(False) # Výchozí stav
        self.delete_btn.clicked.connect(self.delete_shortcut)
        
        button_layout.addWidget(self.save_btn); button_layout.addWidget(self.delete_btn)
        layout.addLayout(button_layout)
        
        self.table.itemSelectionChanged.connect(self.check_delete_permission)
        self.tabs.addTab(tab, "Správce zobrazení")
        self.load_applications()

    def load_applications(self):
        self.table.setRowCount(0)
        apps_dict = {}
        
        for d in [SYSTEM_APPS_DIR, APPS_DIR]:
            if not os.path.exists(d): continue
            for f in os.listdir(d):
                if f.endswith(".desktop"):
                    path = os.path.join(d, f)
                    name, icon, is_custom = parse_desktop_file(path)
                    if name:
                        apps_dict[f] = {"name": name, "icon": icon, "path": path, "custom": is_custom}

        sorted_keys = sorted(apps_dict.keys(), key=lambda x: apps_dict[x]["name"].lower())
        self.table.setRowCount(len(sorted_keys))
        
        for row, key in enumerate(sorted_keys):
            data = apps_dict[key]
            # Checkbox
            ck_widget = QWidget()
            ck_layout = QHBoxLayout(ck_widget)
            cb = QCheckBox()
            with open(data["path"], 'r', errors='ignore') as f: cb.setChecked("NoDisplay=true" not in f.read())
            ck_layout.addWidget(cb); ck_layout.setAlignment(Qt.AlignCenter); ck_layout.setContentsMargins(0,0,0,0)
            self.table.setCellWidget(row, 0, ck_widget)
            
            # Ikona + Jméno
            item = QTableWidgetItem(data["name"])
            item.setIcon(get_app_icon(data["icon"]))
            self.table.setItem(row, 1, item)
            
            # Typ
            typ_item = QTableWidgetItem("Uživatelský" if data["custom"] else "Systémový")
            if data["custom"]: typ_item.setForeground(Qt.blue)
            self.table.setItem(row, 2, typ_item)
            
            # Cesta (skrytá)
            self.table.setItem(row, 3, QTableWidgetItem(data["path"]))

    def check_delete_permission(self):
        row = self.table.currentRow()
        if row < 0:
            self.delete_btn.setEnabled(False)
            return
        is_custom = (self.table.item(row, 2).text() == "Uživatelský")
        self.delete_btn.setEnabled(is_custom)

    def filter_apps(self, text):
        for i in range(self.table.rowCount()):
            name = self.table.item(i, 1).text().lower()
            self.table.setRowHidden(i, text.lower() not in name)

    def save_visibility(self):
        for i in range(self.table.rowCount()):
            path = self.table.item(i, 3).text()
            visible = self.table.cellWidget(i, 0).layout().itemAt(0).widget().isChecked()
            
            target = path
            if path.startswith(SYSTEM_APPS_DIR) and not visible:
                target = os.path.join(APPS_DIR, os.path.basename(path))
                if not os.path.exists(target):
                    if not os.path.exists(APPS_DIR): os.makedirs(APPS_DIR)
                    shutil.copy(path, target)

            try:
                with open(target, 'r', errors='ignore') as f: lines = f.readlines()
                with open(target, 'w') as f:
                    for line in lines:
                        if not line.startswith("NoDisplay="): f.write(line)
                    if not visible: f.write("NoDisplay=true\n")
            except: continue
                    
        self.refresh_system_menu()
        QMessageBox.information(self, "Hotovo", "Změny uloženy.")

    def delete_shortcut(self):
        row = self.table.currentRow()
        path = self.table.item(row, 3).text()
        if QMessageBox.question(self, "Smazat", "Smazat tento zástupce?") == QMessageBox.Yes:
            try:
                os.remove(path)
                self.load_applications()
                self.refresh_system_menu()
            except: pass

    # --- ZBYTEK LOGIKY (Generátor) ---
    def refresh_system_menu(self):
        subprocess.run(["update-desktop-database", APPS_DIR], capture_output=True)
        subprocess.run(["lxqt-panel", "--restart"], capture_output=True)

    def toggle_comment_mode(self):
        self.comment_input.setEnabled(not self.auto_comment_cb.isChecked())
        if self.auto_comment_cb.isChecked(): self.update_auto_comment()

    def update_auto_comment(self):
        if self.auto_comment_cb.isChecked(): self.comment_input.setText(f"Spustit {self.name_input.text()}")

    def pick_exec_file(self):
        fname, _ = QFileDialog.getOpenFileName(self, "Vyber soubor", USER_HOME)
        if fname: self.exec_input.setText(fname)

    def validate_exec_intelligence(self, text):
        path = text.strip()
        if not path: self.intel_group.hide(); self.extract_btn.hide(); return
        self.intel_group.show()
        suffix = QFileInfo(path).suffix().lower()
        if suffix == 'exe':
            self.terminal_cb.setChecked(False); self.terminal_cb.setEnabled(False)
            self.wrapper_cb.setChecked(True); self.extract_btn.show()
        elif suffix == 'sh':
            self.terminal_cb.setChecked(True); self.terminal_cb.setEnabled(True)
            self.wrapper_cb.setChecked(False); self.extract_btn.hide()
        else: self.terminal_cb.setEnabled(True); self.extract_btn.hide()

    def extract_exe_icon(self):
        exe_path = self.exec_input.text()
        if not shutil.which("wrestool"):
            QMessageBox.critical(self, "Chyba", "Nainstaluj icoutils!")
            return
        info = QFileInfo(exe_path)
        tmp_ico = f"/tmp/{info.baseName()}.ico"
        try:
            with open(tmp_ico, "wb") as f: subprocess.run(["wrestool", "-x", "-t", "14", exe_path], stdout=f)
            if os.path.exists(tmp_ico) and os.path.getsize(tmp_ico) > 0:
                out_dir = f"/tmp/{info.baseName()}_png"
                os.makedirs(out_dir, exist_ok=True)
                subprocess.run(["icotool", "-x", tmp_ico, "-o", out_dir])
                pngs = glob.glob(f"{out_dir}/*.png")
                if pngs:
                    best = max(pngs, key=os.path.getsize)
                    target = os.path.join(info.absolutePath(), f"{info.baseName()}.png")
                    shutil.copy(best, target); self.icon_input.setText(target)
                    QMessageBox.information(self, "OK", "Ikona vytažena!")
        except: pass

    def pick_icon_file(self):
        fname, _ = QFileDialog.getOpenFileName(self, "Vyber ikonu", "/usr/share/icons")
        if fname: self.icon_input.setText(fname)

    def create_shortcut(self):
        name, exec_path = self.name_input.text().strip(), self.exec_input.text().strip()
        if not name or not exec_path: return
        final_exec = f"wine \"{exec_path}\"" if exec_path.lower().endswith('.exe') else exec_path
        if self.wrapper_cb.isChecked(): final_exec = f"python3 \"{BUSY_SCRIPT}\" {final_exec}"
        
        safe_name = "".join([c for c in name if c.isalnum() or c==' ']).replace(' ', '-').lower()
        output_file = os.path.join(APPS_DIR, f"{safe_name}.desktop")

        try:
            if not os.path.exists(APPS_DIR): os.makedirs(APPS_DIR)
            
            # Ostrá oprava chybných mezer (backslashů) - bezpečný zápis řádek po řádku
            with open(output_file, 'w') as f:
                f.write("[Desktop Entry]\n")
                f.write("X-Debiconf-Custom=true\n")
                f.write("Type=Application\n")
                f.write(f"Name={name}\n")
                f.write(f"Exec={final_exec}\n")
                f.write(f"Icon={self.icon_input.text() or 'applications-other'}\n")
                f.write(f"Terminal={'true' if self.terminal_cb.isChecked() else 'false'}\n")
                f.write(f"Categories={self.category_input.currentData()};\n")
            
            os.chmod(output_file, 0o755)
            self.load_applications()
            self.refresh_system_menu()
            QMessageBox.information(self, "OK", "Zástupce úspěšně vytvořen!")
            
            # Reset formuláře pro zadání nového
            self.name_input.clear()
            self.exec_input.clear()
            self.icon_input.clear()
            
        except Exception as e: QMessageBox.critical(self, "Chyba", str(e))

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    QIcon.setThemeName("Papirus")
    QIcon.setFallbackThemeName("hicolor")
    window = ShortcutApp()
    window.show()
    sys.exit(app.exec_())
import os
import subprocess
import shutil
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QTabWidget, QLabel, QLineEdit, 
                             QPushButton, QCheckBox, QComboBox, QFileDialog, 
                             QTableWidget, QTableWidgetItem, QMessageBox, 
                             QGroupBox, QFormLayout, QHeaderView, QAbstractItemView)
from PyQt5.QtCore import Qt, QFileInfo, QSize
from PyQt5.QtGui import QIcon

# --- KONFIGURACE ---
USER_HOME = os.path.expanduser("~")
APPS_DIR = os.path.join(USER_HOME, ".local/share/applications")
SYSTEM_APPS_DIR = "/usr/share/applications"
BUSY_SCRIPT = os.path.join(USER_HOME, ".local/bin/busy-launch.py")

XDG_CATEGORIES = [
    ("🎮 Hry", "Game"), ("🌍 Internet", "Network"), ("🎨 Grafika", "Graphics"),
    ("💼 Kancelář", "Office"), ("🎬 Zvuk a Video", "AudioVideo"),
    ("🛠️  Systémové nástroje", "System;Utility"), ("💻 Vývoj", "Development"),
    ("🎒 Příslušenství", "Qt;Utility")
]

# --- POMOCNÉ FUNKCE ---
def get_app_icon(icon_str):
    if os.path.isabs(icon_str) and os.path.exists(icon_str):
        return QIcon(icon_str)
    icon_base = icon_str.rsplit('.', 1)[0] if icon_str.lower().endswith(('.png', '.svg', '.xpm', '.ico')) else icon_str
    icon = QIcon.fromTheme(icon_base)
    if icon.isNull():
        for d in ["/usr/share/pixmaps", os.path.expanduser("~/.local/share/icons")]:
            for ext in [".png", ".svg"]:
                p = os.path.join(d, icon_base + ext)
                if os.path.exists(p): return QIcon(p)
    return icon if not icon.isNull() else QIcon.fromTheme("application-x-executable")

def parse_desktop_file(filepath):
    """Vrací (Jméno, Ikona, jeVlastní)"""
    name, name_cs, icon, custom = "", "", "application-x-executable", False
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if line.startswith("Name="): name = line.split("=", 1)[1].strip()
                elif line.startswith("Name[cs]="): name_cs = line.split("=", 1)[1].strip()
                elif line.startswith("Icon="): icon = line.split("=", 1)[1].strip()
                elif "X-Debiconf-Custom=true" in line: custom = True
    except: pass
    return (name_cs if name_cs else name), icon, custom

class ShortcutApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Správce Zástupců (Debiconf LXQt)")
        self.resize(800, 600)
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        layout = QVBoxLayout(main_widget)
        
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)
        
        self.init_creator_tab()
        self.init_manager_tab()
        
    def init_creator_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        form_group = QGroupBox("Vytvořit nového zástupce")
        form_layout = QFormLayout(form_group)
        
        self.name_input = QLineEdit()
        self.name_input.textChanged.connect(self.update_auto_comment)
        form_layout.addRow("Název aplikace:", self.name_input)
        
        self.comment_input = QLineEdit()
        self.comment_input.setEnabled(False)
        self.auto_comment_cb = QCheckBox("Automatický")
        self.auto_comment_cb.setChecked(True)
        self.auto_comment_cb.stateChanged.connect(self.toggle_comment_mode)
        
        comment_layout = QHBoxLayout()
        comment_layout.addWidget(self.comment_input); comment_layout.addWidget(self.auto_comment_cb)
        form_layout.addRow("Popis (Komentář):", comment_layout)
        
        self.exec_input = QLineEdit()
        self.exec_input.textChanged.connect(self.validate_exec_intelligence)
        self.exec_btn = QPushButton("Procházet...")
        self.exec_btn.clicked.connect(self.pick_exec_file)
        
        exec_layout = QHBoxLayout()
        exec_layout.addWidget(self.exec_input); exec_layout.addWidget(self.exec_btn)
        form_layout.addRow("Příkaz / Cesta (Povinné):", exec_layout)
        
        self.intel_group = QGroupBox("Inteligentní nastavení")
        intel_layout = QVBoxLayout(self.intel_group)
        self.terminal_cb = QCheckBox("Spustit v terminálu")
        self.wrapper_cb = QCheckBox("Indikace načítání (Wrapper)")
        self.wrapper_cb.setChecked(True)
        intel_layout.addWidget(self.terminal_cb); intel_layout.addWidget(self.wrapper_cb)
        self.intel_group.hide()
        form_layout.addRow(self.intel_group)
        
        self.category_input = QComboBox()
        for friendly_name, xdg_name in XDG_CATEGORIES: self.category_input.addItem(friendly_name, xdg_name)
        form_layout.addRow("Kategorie menu:", self.category_input)
        
        self.icon_input = QLineEdit()
        self.icon_btn = QPushButton("Vybrat...")
        self.icon_btn.clicked.connect(self.pick_icon_file)
        self.extract_btn = QPushButton("Vytáhnout z EXE")
        self.extract_btn.clicked.connect(self.extract_exe_icon)
        self.extract_btn.hide()
        
        icon_layout = QHBoxLayout()
        icon_layout.addWidget(self.icon_input); icon_layout.addWidget(self.icon_btn); icon_layout.addWidget(self.extract_btn)
        form_layout.addRow("Ikona aplikace:", icon_layout)
        
        self.create_btn = QPushButton("Vytvořit zástupce v Menu")
        self.create_btn.setStyleSheet("font-weight: bold; padding: 12px; background-color: #2a7fca; color: white;")
        self.create_btn.clicked.connect(self.create_shortcut)
        
        layout.addWidget(form_group); layout.addStretch(); layout.addWidget(self.create_btn)
        self.tabs.addTab(tab, "Generátor")

    def init_manager_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        
        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("Hledat aplikaci v menu...")
        self.search_bar.textChanged.connect(self.filter_apps)
        layout.addWidget(self.search_bar)
        
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(['Viditelný', 'Aplikace', 'Typ', 'Cesta'])
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.setIconSize(QSize(32, 32))
        
        header = self.table.horizontalHeader()
        self.table.setColumnWidth(0, 70)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        self.table.setColumnWidth(2, 100)
        self.table.setColumnHidden(3, True) # Skrytá cesta
        
        layout.addWidget(self.table)
        
        button_layout = QHBoxLayout()
        self.save_btn = QPushButton("Uložit viditelnost")
        self.save_btn.setStyleSheet("background-color: #4caf50; color: white; padding: 10px; font-weight: bold;")
        self.save_btn.clicked.connect(self.save_visibility)
        
        self.delete_btn = QPushButton("Trvale smazat")
        self.delete_btn.setStyleSheet("background-color: #f44336; color: white; padding: 10px; font-weight: bold;")
        self.delete_btn.setEnabled(False) # Výchozí stav
        self.delete_btn.clicked.connect(self.delete_shortcut)
        
        button_layout.addWidget(self.save_btn); button_layout.addWidget(self.delete_btn)
        layout.addLayout(button_layout)
        
        self.table.itemSelectionChanged.connect(self.check_delete_permission)
        self.tabs.addTab(tab, "Správce zobrazení")
        self.load_applications()

    def load_applications(self):
        self.table.setRowCount(0)
        apps_dict = {} # Deduplikace podle názvu souboru
        
        for d in [SYSTEM_APPS_DIR, APPS_DIR]:
            if not os.path.exists(d): continue
            for f in os.listdir(d):
                if f.endswith(".desktop"):
                    path = os.path.join(d, f)
                    name, icon, is_custom = parse_desktop_file(path)
                    if name:
                        apps_dict[f] = {"name": name, "icon": icon, "path": path, "custom": is_custom}

        sorted_keys = sorted(apps_dict.keys(), key=lambda x: apps_dict[x]["name"].lower())
        self.table.setRowCount(len(sorted_keys))
        
        for row, key in enumerate(sorted_keys):
            data = apps_dict[key]
            # Checkbox
            ck_widget = QWidget()
            ck_layout = QHBoxLayout(ck_widget)
            cb = QCheckBox()
            with open(data["path"], 'r', errors='ignore') as f: cb.setChecked("NoDisplay=true" not in f.read())
            ck_layout.addWidget(cb); ck_layout.setAlignment(Qt.AlignCenter); ck_layout.setContentsMargins(0,0,0,0)
            self.table.setCellWidget(row, 0, ck_widget)
            
            # Ikona + Jméno
            item = QTableWidgetItem(data["name"])
            item.setIcon(get_app_icon(data["icon"]))
            self.table.setItem(row, 1, item)
            
            # Typ
            typ_item = QTableWidgetItem("Uživatelský" if data["custom"] else "Systémový")
            if data["custom"]: typ_item.setForeground(Qt.blue)
            self.table.setItem(row, 2, typ_item)
            
            # Cesta (skrytá)
            self.table.setItem(row, 3, QTableWidgetItem(data["path"]))

    def check_delete_permission(self):
        row = self.table.currentRow()
        if row < 0:
            self.delete_btn.setEnabled(False)
            return
        is_custom = (self.table.item(row, 2).text() == "Uživatelský")
        self.delete_btn.setEnabled(is_custom)

    def filter_apps(self, text):
        for i in range(self.table.rowCount()):
            name = self.table.item(i, 1).text().lower()
            self.table.setRowHidden(i, text.lower() not in name)

    def save_visibility(self):
        for i in range(self.table.rowCount()):
            path = self.table.item(i, 3).text()
            visible = self.table.cellWidget(i, 0).layout().itemAt(0).widget().isChecked()
            
            target = path
            if path.startswith(SYSTEM_APPS_DIR) and not visible:
                target = os.path.join(APPS_DIR, os.path.basename(path))
                if not os.path.exists(target):
                    if not os.path.exists(APPS_DIR): os.makedirs(APPS_DIR)
                    shutil.copy(path, target)

            try:
                with open(target, 'r', errors='ignore') as f: lines = f.readlines()
                with open(target, 'w') as f:
                    for line in lines:
                        if not line.startswith("NoDisplay="): f.write(line)
                    if not visible: f.write("NoDisplay=true\n")
            except: continue
                    
        self.refresh_system_menu()
        QMessageBox.information(self, "Hotovo", "Změny uloženy.")

    def delete_shortcut(self):
        row = self.table.currentRow()
        path = self.table.item(row, 3).text()
        typ = self.table.item(row, 2).text()
        
        msg = "Opravdu trvale smazat tohoto zástupce?"
        if typ == "Lokální úprava":
            msg = "Smazáním této lokální úpravy se obnoví původní skrytý systémový zástupce. Pokračovat?"
            
        if QMessageBox.question(self, "Smazat", msg) == QMessageBox.Yes:
            try:
                os.remove(path)
                self.load_applications()
                self.refresh_system_menu()
            except: pass

    def refresh_system_menu(self):
        subprocess.run(["update-desktop-database", APPS_DIR], capture_output=True)
        subprocess.run(["lxqt-panel", "--restart"], capture_output=True)

    def toggle_comment_mode(self):
        self.comment_input.setEnabled(not self.auto_comment_cb.isChecked())
        if self.auto_comment_cb.isChecked(): self.update_auto_comment()

    def update_auto_comment(self):
        if self.auto_comment_cb.isChecked(): self.comment_input.setText(f"Spustit {self.name_input.text()}")

    def pick_exec_file(self):
        fname, _ = QFileDialog.getOpenFileName(self, "Vyber soubor", USER_HOME)
        if fname: self.exec_input.setText(fname)

    def validate_exec_intelligence(self, text):
        path = text.strip()
        if not path: self.intel_group.hide(); self.extract_btn.hide(); return
        self.intel_group.show()
        suffix = QFileInfo(path).suffix().lower()
        if suffix == 'exe':
            self.terminal_cb.setChecked(False); self.terminal_cb.setEnabled(False)
            self.wrapper_cb.setChecked(True); self.extract_btn.show()
        elif suffix == 'sh':
            self.terminal_cb.setChecked(True); self.terminal_cb.setEnabled(True)
            self.wrapper_cb.setChecked(False); self.extract_btn.hide()
        else: self.terminal_cb.setEnabled(True); self.extract_btn.hide()

    def extract_exe_icon(self):
        exe_path = self.exec_input.text()
        if not shutil.which("wrestool"):
            QMessageBox.critical(self, "Chyba", "Nainstaluj icoutils!")
            return
        info = QFileInfo(exe_path)
        tmp_ico = f"/tmp/{info.baseName()}.ico"
        try:
            with open(tmp_ico, "wb") as f: subprocess.run(["wrestool", "-x", "-t", "14", exe_path], stdout=f)
            if os.path.exists(tmp_ico) and os.path.getsize(tmp_ico) > 0:
                out_dir = f"/tmp/{info.baseName()}_png"
                os.makedirs(out_dir, exist_ok=True)
                subprocess.run(["icotool", "-x", tmp_ico, "-o", out_dir])
                pngs = glob.glob(f"{out_dir}/*.png")
                if pngs:
                    best = max(pngs, key=os.path.getsize)
                    target = os.path.join(info.absolutePath(), f"{info.baseName()}.png")
                    shutil.copy(best, target); self.icon_input.setText(target)
                    QMessageBox.information(self, "OK", "Ikona vytažena!")
        except: pass

    def pick_icon_file(self):
        fname, _ = QFileDialog.getOpenFileName(self, "Vyber ikonu", "/usr/share/icons")
        if fname: self.icon_input.setText(fname)

    def create_shortcut(self):
        name, exec_path = self.name_input.text().strip(), self.exec_input.text().strip()
        if not name or not exec_path: return
        final_exec = f"wine \"{exec_path}\"" if exec_path.lower().endswith('.exe') else exec_path
        if self.wrapper_cb.isChecked(): final_exec = f"python3 \"{BUSY_SCRIPT}\" {final_exec}"
        
        safe_name = "".join([c for c in name if c.isalnum() or c==' ']).replace(' ', '-').lower()
        output_file = os.path.join(APPS_DIR, f"{safe_name}.desktop")

        try:
            if not os.path.exists(APPS_DIR): os.makedirs(APPS_DIR)
            with open(output_file, 'w') as f:
                f.write(f"[Desktop Entry]\nX-Debiconf-Custom=true\\nType=Application\\nName={name}\\nExec={final_exec}\\nIcon={self.icon_input.text() or 'applications-other'}\\nTerminal={'true' if self.terminal_cb.isChecked() else 'false'}\\nCategories={self.category_input.currentData()};\\n")
            os.chmod(output_file, 0o755)
            self.load_applications(); self.refresh_system_menu()
            QMessageBox.information(self, "OK", "Vytvořeno!")
        except Exception as e: QMessageBox.critical(self, "Chyba", str(e))

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    QIcon.setThemeName("Papirus")
    QIcon.setFallbackThemeName("hicolor")
    window = ShortcutApp()
    window.show()
    sys.exit(app.exec_())
