#!/usr/bin/env python3
import sys
import os
import subprocess
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout,
                             QLineEdit, QPushButton, QMessageBox, QListWidget, 
                             QListWidgetItem, QLabel)
from PyQt5.QtCore import Qt, QSize, QThread, pyqtSignal
from PyQt5.QtGui import QIcon

# --- VLÁKNO PRO ODINSTALACI NA POZADÍ ---
class UninstallWorker(QThread):
    finished = pyqtSignal(int, str, str, str)

    def __init__(self, filepath, app_name, filename):
        super().__init__()
        self.filepath = filepath
        self.app_name = app_name
        self.filename = filename

    def run(self):
        if self.filepath.startswith("/usr/share/applications"):
            dpkg_result = subprocess.run(["dpkg", "-S", self.filepath], capture_output=True, text=True)
            if dpkg_result.returncode == 0:
                pkg_name = dpkg_result.stdout.split(":")[0].strip()
                cmd = f"apt-get remove --purge -y {pkg_name} && apt-get autoremove -y"
                result = subprocess.run(["lxqt-sudo", "bash", "-c", cmd])
                self.finished.emit(result.returncode, self.filepath, self.app_name, self.filename)
            else:
                self.remove_local()
        else:
            self.remove_local()

    def remove_local(self):
        try:
            os.remove(self.filepath)
            self.finished.emit(0, self.filepath, self.app_name, self.filename)
        except:
            self.finished.emit(1, self.filepath, self.app_name, self.filename)


class AppUninstaller(QWidget):
    def __init__(self):
        super().__init__()
        self.unremovable_file = "/etc/debiconf-unremovable.txt"
        self.unremovable_list = self.load_blacklist()
        self.worker = None
        self.initUI()
        self.load_apps()

    def load_blacklist(self):
        blacklist = []
        if os.path.exists(self.unremovable_file):
            with open(self.unremovable_file, 'r') as f:
                blacklist = [line.strip().lower() for line in f if line.strip()]
        return blacklist

    def initUI(self):
        self.setWindowTitle('Odinstalovat programy')
        self.setFixedSize(550, 650) # Zvětšeno pro nové tlačítko
        self.setWindowFlags(Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
        
        self.setStyleSheet("""
            QWidget { background-color: #f5f5f5; font-family: sans-serif; }
            QLabel { color: #333; }
            QLineEdit { padding: 10px; border: 1px solid #ccc; border-radius: 5px; background-color: white; font-size: 11pt; }
            QListWidget { background-color: white; border: 1px solid #ccc; border-radius: 5px; outline: 0; }
            QListWidget::item { border-bottom: 1px solid #e0e0e0; padding: 10px; color: #222; }
            QListWidget::item:last { border-bottom: none; }
            QListWidget::item:hover { background-color: #e3f2fd; }
            QListWidget::item:selected { background-color: #2a7fca; color: white; border-radius: 3px; }
            
            QPushButton#btnUninstall {
                background-color: #d32f2f; color: white; padding: 15px; font-weight: bold; border-radius: 5px; font-size: 12pt;
            }
            QPushButton#btnUninstall:hover { background-color: #b71c1c; }
            QPushButton#btnUninstall:disabled { background-color: #9e9e9e; color: #e0e0e0; }
            
            /* Tlačítko pro WINE */
            QPushButton#btnWine {
                background-color: #7b1fa2; color: white; padding: 12px; font-weight: bold; border-radius: 5px; font-size: 11pt; margin-top: 10px;
            }
            QPushButton#btnWine:hover { background-color: #4a148c; }
        """)

        layout = QVBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)
        
        lbl_info = QLabel("<b>Správce aplikací (Linux)</b><br>Vyberte linuxový program pro trvalé odstranění.")
        lbl_info.setStyleSheet("font-size: 12pt;")
        layout.addWidget(lbl_info)

        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("Hledat aplikaci (např. Chrome)...")
        self.search_bar.textChanged.connect(self.filter_apps)
        layout.addWidget(self.search_bar)
        
        self.app_list = QListWidget()
        self.app_list.setIconSize(QSize(32, 32))
        self.app_list.setStyleSheet("font-size: 12pt;")
        layout.addWidget(self.app_list)
        
        self.btn_uninstall = QPushButton('Odinstalovat vybranou linuxovou aplikaci')
        self.btn_uninstall.setObjectName("btnUninstall")
        self.btn_uninstall.setCursor(Qt.PointingHandCursor)
        self.btn_uninstall.clicked.connect(self.handle_uninstall)
        layout.addWidget(self.btn_uninstall)
        
        # --- NOVÉ TLAČÍTKO PRO WINE ---
        self.btn_wine = QPushButton('Odinstalovat Windows hry a programy (Wine)')
        self.btn_wine.setObjectName("btnWine")
        self.btn_wine.setCursor(Qt.PointingHandCursor)
        self.btn_wine.clicked.connect(self.run_wine_uninstaller)
        layout.addWidget(self.btn_wine)
        
        self.setLayout(layout)

    def load_apps(self):
        self.app_list.clear()
        
        dirs_to_scan = [
            "/usr/share/applications",
            os.path.expanduser("~/.local/share/applications")
        ]
        
        apps_data = {}

        for directory in dirs_to_scan:
            if not os.path.exists(directory):
                continue
                
            for filename in os.listdir(directory):
                if not filename.endswith(".desktop"):
                    continue
                    
                if filename.lower() in self.unremovable_list:
                    continue
                    
                filepath = os.path.join(directory, filename)
                
                try:
                    with open(filepath, 'r', errors='ignore') as f:
                        content = f.read()
                        
                    # IGNOROVÁNÍ SKRYTÝCH A CUSTOM ZÁSTUPCŮ (Z Generátoru)
                    if "NoDisplay=true" in content or "X-Debiconf-Custom=true" in content:
                        continue
                        
                    temp_name = ""
                    temp_name_cs = ""
                    icon_name = "application-x-executable"
                    categories = ""
                    
                    in_main_section = False
                    
                    for line in content.splitlines():
                        line = line.strip()
                        if line.startswith("["):
                            in_main_section = (line == "[Desktop Entry]")
                            continue
                            
                        if not in_main_section:
                            continue
                            
                        if line.startswith("Name="): temp_name = line.split("=", 1)[1].strip()
                        elif line.startswith("Name[cs]="): temp_name_cs = line.split("=", 1)[1].strip()
                        elif line.startswith("Icon="): icon_name = line.split("=", 1)[1].strip()
                        elif line.startswith("Categories="): categories = line.split("=", 1)[1].strip()

                    name = temp_name_cs if temp_name_cs else (temp_name if temp_name else filename)

                    cat_lower = categories.lower()
                    if "settings" in cat_lower or "system" in cat_lower or "desktopsettings" in cat_lower:
                        continue
                    
                    if name not in apps_data:
                        apps_data[name] = {"filepath": filepath, "filename": filename, "icon": icon_name}
                        
                except Exception:
                    continue

        for name in sorted(apps_data.keys()):
            item_data = apps_data[name]
            item = QListWidgetItem(name)
            
            icon_str = item_data["icon"]
            icon = QIcon()
            
            if os.path.isabs(icon_str) and os.path.exists(icon_str):
                icon = QIcon(icon_str)
            else:
                icon_base = icon_str.rsplit('.', 1)[0] if icon_str.lower().endswith(('.png', '.svg', '.xpm', '.ico')) else icon_str
                icon = QIcon.fromTheme(icon_base)
                
                if icon.isNull():
                    for path in [f"/usr/share/pixmaps/{icon_base}.png", f"/usr/share/pixmaps/{icon_base}.svg",
                                 f"{os.path.expanduser('~')}/.local/share/icons/{icon_base}.png", f"{os.path.expanduser('~')}/.local/share/icons/{icon_base}.svg"]:
                        if os.path.exists(path):
                            icon = QIcon(path)
                            break
                            
                if icon.isNull(): icon = QIcon.fromTheme("application-x-executable")
                    
            item.setIcon(icon)
            item.setData(Qt.UserRole, item_data["filepath"])
            item.setData(Qt.UserRole + 1, item_data["filename"])
            self.app_list.addItem(item)

    def filter_apps(self, text):
        for i in range(self.app_list.count()):
            item = self.app_list.item(i)
            item.setHidden(text.lower() not in item.text().lower())

    def handle_uninstall(self):
        current_item = self.app_list.currentItem()
        if not current_item:
            QMessageBox.warning(self, "Chyba", "Musíte nejprve vybrat aplikaci ze seznamu.")
            return
            
        self.app_name = current_item.text()
        filepath = current_item.data(Qt.UserRole)
        filename = current_item.data(Qt.UserRole + 1)
        
        reply = QMessageBox.question(self, 'Potvrzení odinstalace', 
                                     f"Opravdu chcete trvale odstranit program <b>{self.app_name}</b>?",
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
                                     
        if reply != QMessageBox.Yes: return

        self.btn_uninstall.setEnabled(False)
        self.btn_uninstall.setText("Probíhá odinstalace...")
        self.app_list.setEnabled(False)
        current_item.setText(f"{self.app_name}  (Zpracovávám...)")

        self.worker = UninstallWorker(filepath, self.app_name, filename)
        self.worker.finished.connect(self.on_uninstall_finished)
        self.worker.start()

    def on_uninstall_finished(self, returncode, filepath, app_name, filename):
        self.btn_uninstall.setEnabled(True)
        self.btn_uninstall.setText('Odinstalovat vybranou linuxovou aplikaci')
        self.app_list.setEnabled(True)

        if returncode == 0:
            self.post_uninstall_cleanup(filename)
            QMessageBox.information(self, "Hotovo", f"Program {app_name} byl úspěšně odstraněn.")
            self.load_apps()
            self.search_bar.clear()
        else:
            QMessageBox.warning(self, "Zrušeno", "Odinstalace byla zrušena nebo se nezdařila.")
            self.load_apps()

    def post_uninstall_cleanup(self, filename):
        local_path = os.path.expanduser(f"~/.local/share/applications/{filename}")
        if os.path.exists(local_path):
            try: os.remove(local_path)
            except: pass
        subprocess.run(["update-desktop-database", os.path.expanduser("~/.local/share/applications")], capture_output=True)

    # --- SPUŠTĚNÍ NATIVNÍHO WINE ODINSTALÁTORU ---
    def run_wine_uninstaller(self):
        try:
            # Pustíme wine uninstaller jako proces na pozadí, ať to nezasekne Python okno
            subprocess.Popen(["wine", "uninstaller"])
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Nepodařilo se spustit Wine uninstaller.\n{str(e)}")

if __name__ == '__main__':
    app = QApplication(sys.argv)
    QIcon.setThemeName("Papirus")
    QIcon.setFallbackThemeName("hicolor")
    window = AppUninstaller()
    window.show()
    sys.exit(app.exec_())