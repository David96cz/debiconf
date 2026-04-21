#!/usr/bin/env python3
import sys
import os
import subprocess
import glob      # PŘIDÁNO
import shutil    # PŘIDÁNO
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, 
                             QLineEdit, QPushButton, QMessageBox, QListWidget, 
                             QListWidgetItem, QLabel)
from PyQt5.QtCore import Qt, QSize, QThread, pyqtSignal
from PyQt5.QtGui import QIcon

# --- VLÁKNO PRO ODINSTALACI NA POZADÍ ---
class UninstallWorker(QThread):
    finished = pyqtSignal(int, str, str, str, bool)

    def __init__(self, filepath, app_name, filename, is_wine=False):
        super().__init__()
        self.filepath = filepath # U Wine aplikací to obsahuje ID klíče
        self.app_name = app_name
        self.filename = filename
        self.is_wine = is_wine

    def run(self):
        if self.is_wine:
            # 1. Spustíme nativní Windows odinstalátor
            subprocess.run(["wine", "uninstaller", "--remove", self.filepath])
            
            # 2. DONUTÍME WINE OKAMŽITĚ ZAPSAT ZMĚNY NA DISK!
            subprocess.run(["wineserver", "-w"])
            
            # 3. Zkontrolujeme pravdu: Zmizel ten klíč z registrů?
            still_exists = False
            for reg_file in ["system.reg", "user.reg"]:
                reg_path = os.path.expanduser(f"~/.wine/{reg_file}")
                if os.path.exists(reg_path):
                    with open(reg_path, 'r', errors='ignore') as f:
                        if self.filepath in f.read():
                            still_exists = True
                            break
            
            # Návratové kódy: 0 = úspěch, 2 = zrušeno uživatelem
            if still_exists:
                self.finished.emit(2, self.filepath, self.app_name, self.filename, True)
            else:
                self.finished.emit(0, self.filepath, self.app_name, self.filename, True)
            
        elif self.filepath.startswith("/usr/share/applications"):
            dpkg_result = subprocess.run(["dpkg", "-S", self.filepath], capture_output=True, text=True)
            if dpkg_result.returncode == 0:
                pkg_name = dpkg_result.stdout.split(":")[0].strip()
                cmd = f"apt-get remove --purge -y {pkg_name} && apt-get autoremove -y"
                result = subprocess.run(["lxqt-sudo", "bash", "-c", cmd])
                self.finished.emit(result.returncode, self.filepath, self.app_name, self.filename, False)
            else:
                self.remove_local()
        else:
            self.remove_local()

    def remove_local(self):
        try:
            os.remove(self.filepath)
            self.finished.emit(0, self.filepath, self.app_name, self.filename, False)
        except:
            self.finished.emit(1, self.filepath, self.app_name, self.filename, False)


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
        self.setWindowTitle('Odinstalovat programy (Sjednocený Správce)')
        self.setFixedSize(550, 600)
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
        """)

        layout = QVBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)
        
        lbl_info = QLabel("<b>Správce aplikací</b><br>Vyberte program nebo hru pro trvalé odstranění.")
        lbl_info.setStyleSheet("font-size: 12pt;")
        layout.addWidget(lbl_info)

        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("Hledat (např. Chrome nebo Call of Duty)...")
        self.search_bar.textChanged.connect(self.filter_apps)
        layout.addWidget(self.search_bar)
        
        self.app_list = QListWidget()
        self.app_list.setIconSize(QSize(32, 32))
        self.app_list.setStyleSheet("font-size: 12pt;")
        layout.addWidget(self.app_list)
        
        self.btn_uninstall = QPushButton('Odinstalovat vybraný program')
        self.btn_uninstall.setObjectName("btnUninstall")
        self.btn_uninstall.setCursor(Qt.PointingHandCursor)
        self.btn_uninstall.clicked.connect(self.handle_uninstall)
        layout.addWidget(self.btn_uninstall)
        
        self.setLayout(layout)

    def load_apps(self):
        self.app_list.clear()
        apps_data = {}

        # 1. NAČTENÍ LINUXOVÝCH APLIKACÍ (Jako předtím)
        dirs_to_scan = ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]
        for directory in dirs_to_scan:
            if not os.path.exists(directory): continue
            for filename in os.listdir(directory):
                if not filename.endswith(".desktop") or filename.lower() in self.unremovable_list: continue
                filepath = os.path.join(directory, filename)
                try:
                    with open(filepath, 'r', errors='ignore') as f: content = f.read()
                    if "NoDisplay=true" in content or "X-Debiconf-Custom=true" in content: continue
                    
                    temp_name, temp_name_cs, icon_name, categories, in_main = "", "", "application-x-executable", "", False
                    for line in content.splitlines():
                        line = line.strip()
                        if line.startswith("["): in_main = (line == "[Desktop Entry]"); continue
                        if not in_main: continue
                        if line.startswith("Name="): temp_name = line.split("=", 1)[1].strip()
                        elif line.startswith("Name[cs]="): temp_name_cs = line.split("=", 1)[1].strip()
                        elif line.startswith("Icon="): icon_name = line.split("=", 1)[1].strip()
                        elif line.startswith("Categories="): categories = line.split("=", 1)[1].strip()

                    name = temp_name_cs if temp_name_cs else (temp_name if temp_name else filename)
                    cat_lower = categories.lower()
                    if "settings" in cat_lower or "system" in cat_lower or "desktopsettings" in cat_lower: continue
                    
                    if name not in apps_data:
                        apps_data[name] = {"filepath": filepath, "filename": filename, "icon": icon_name, "is_wine": False}
                except: continue

       # 2. RYCHLÉ A SPOLEHLIVÉ NAČTENÍ Z WINE REGISTRŮ BEZ VOLÁNÍ WINE
        wine_apps = {}
        for reg_file in ["system.reg", "user.reg"]:
            reg_path = os.path.expanduser(f"~/.wine/{reg_file}")
            if not os.path.exists(reg_path): continue

            try:
                with open(reg_path, 'r', errors='ignore') as f:
                    lines = f.readlines()

                current_key = None
                display_name = None
                display_icon = None

                for line in lines:
                    line = line.strip()
                    
                    if line.startswith("[") and "\\Uninstall\\" in line:
                        # Uložení předchozí nalezéné hry, než přejdeme na další klíč
                        if current_key and display_name:
                            if "Wine" not in display_name and "Gecko" not in display_name and "Mono" not in display_name:
                                wine_apps[display_name] = {"uuid": current_key, "icon": display_icon}
                        
                        raw_key = line.split("\\")[-1]
                        current_key = raw_key.split("]")[0]
                        display_name = None
                        display_icon = None
                        
                    elif line.startswith("["):
                        if current_key and display_name:
                            if "Wine" not in display_name and "Gecko" not in display_name and "Mono" not in display_name:
                                wine_apps[display_name] = {"uuid": current_key, "icon": display_icon}
                        current_key = None
                        display_name = None
                        display_icon = None
                        
                    elif current_key:
                        if line.startswith('"DisplayName"='):
                            display_name = line.split("=", 1)[1].strip('"')
                        elif line.startswith('"DisplayIcon"='):
                            display_icon = line.split("=", 1)[1].strip('"')

                # Zachycení úplně poslední hry v souboru
                if current_key and display_name:
                    if "Wine" not in display_name and "Gecko" not in display_name and "Mono" not in display_name:
                        wine_apps[display_name] = {"uuid": current_key, "icon": display_icon}
            except Exception:
                pass

        # Naplnění do hlavní tabulky pro vykreslení
        for app_name, data in wine_apps.items():
            display_name = f"{app_name} (Windows Program)"
            if display_name not in apps_data:
                # TADY SE DĚJE TA MAGIE S IKONOU!
                real_icon = extract_wine_icon(data["icon"], app_name) or "wine"
                apps_data[display_name] = {"filepath": data["uuid"], "filename": "wine_app", "icon": real_icon, "is_wine": True}
            display_name = f"{app_name} (Windows Program)"
            if display_name not in apps_data:
                apps_data[display_name] = {"filepath": app_uuid, "filename": "wine_app", "icon": "wine", "is_wine": True}

        # 3. VYKRESLENÍ VŠEHO DO JEDNOHO SEZNAMU
        for name in sorted(apps_data.keys()):
            item_data = apps_data[name]
            item = QListWidgetItem(name)
            
            icon_str = item_data["icon"]
            icon = QIcon()
            
            # Nastavení ikon
            if item_data["is_wine"]:
                # Pro Windows hry to natvrdo nastaví Wine ikonu
                icon = QIcon.fromTheme("wine")
                if icon.isNull(): icon = QIcon.fromTheme("application-x-ms-dos-executable")
            else:
                # Běžné linuxové ikony
                if os.path.isabs(icon_str) and os.path.exists(icon_str):
                    icon = QIcon(icon_str)
                else:
                    icon_base = icon_str.rsplit('.', 1)[0] if icon_str.lower().endswith(('.png', '.svg', '.xpm', '.ico')) else icon_str
                    icon = QIcon.fromTheme(icon_base)
                    if icon.isNull():
                        for path in [f"/usr/share/pixmaps/{icon_base}.png", f"/usr/share/pixmaps/{icon_base}.svg",
                                     f"{os.path.expanduser('~')}/.local/share/icons/{icon_base}.png", f"{os.path.expanduser('~')}/.local/share/icons/{icon_base}.svg"]:
                            if os.path.exists(path): icon = QIcon(path); break
                    if icon.isNull(): icon = QIcon.fromTheme("application-x-executable")
                    
            item.setIcon(icon)
            item.setData(Qt.UserRole, item_data["filepath"])
            item.setData(Qt.UserRole + 1, item_data["filename"])
            item.setData(Qt.UserRole + 2, item_data["is_wine"]) # Uložení informace, že jde o hru
            
            # Wine aplikace zbarvíme trochu odlišně (volitelné, pro lepší přehlednost)
            if item_data["is_wine"]:
                item.setForeground(Qt.darkMagenta)
                
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
        is_wine = current_item.data(Qt.UserRole + 2)
        
        reply = QMessageBox.question(self, 'Potvrzení odinstalace', 
                                     f"Opravdu chcete trvale odstranit program <b>{self.app_name}</b>?",
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
                                     
        if reply != QMessageBox.Yes: return

        self.btn_uninstall.setEnabled(False)
        self.btn_uninstall.setText("Probíhá odinstalace..." if not is_wine else "Spouštím odinstalátor...")
        self.app_list.setEnabled(False)
        current_item.setText(f"{self.app_name}  (Zpracovávám...)")

        self.worker = UninstallWorker(filepath, self.app_name, filename, is_wine)
        self.worker.finished.connect(self.on_uninstall_finished)
        self.worker.start()

    def on_uninstall_finished(self, returncode, filepath, app_name, filename, is_wine):
        self.btn_uninstall.setEnabled(True)
        self.btn_uninstall.setText('Odinstalovat vybraný program')
        self.app_list.setEnabled(True)

        if returncode == 0:
            if not is_wine:
                self.post_uninstall_cleanup(filename)
            QMessageBox.information(self, "Hotovo", f"Program {app_name} byl úspěšně odstraněn.")
            self.search_bar.clear()
        elif returncode == 2:
            # Tohle zachytí ten moment, kdy to uživatel v okně Wine zruší
            QMessageBox.information(self, "Zrušeno", f"Odinstalace programu {app_name} byla přerušena.")
        else:
            if not is_wine:
                QMessageBox.warning(self, "Zrušeno", "Odinstalace byla zrušena nebo se nezdařila.")
        
        # Načteme seznam znova v KAŽDÉM PŘÍPADĚ (teď už i pro Wine bez problému)
        self.load_apps()
        self.btn_uninstall.setEnabled(True)
        self.btn_uninstall.setText('Odinstalovat vybraný program')
        self.app_list.setEnabled(True)

        if returncode == 0:
            if not is_wine:
                self.post_uninstall_cleanup(filename)
            QMessageBox.information(self, "Hotovo", f"Program {app_name} byl úspěšně odstraněn.")
            self.load_apps()
            self.search_bar.clear()
        else:
            # U wine to nevyhodí chybu, pokud to uživatel prostě jen zrušil v tom Windows okně
            if not is_wine:
                QMessageBox.warning(self, "Zrušeno", "Odinstalace byla zrušena nebo se nezdařila.")
            self.load_apps()

    def post_uninstall_cleanup(self, filename):
        local_path = os.path.expanduser(f"~/.local/share/applications/{filename}")
        if os.path.exists(local_path):
            try: os.remove(local_path)
            except: pass
        subprocess.run(["update-desktop-database", os.path.expanduser("~/.local/share/applications")], capture_output=True)

    # --- POMOCNÁ FUNKCE PRO EXTRAKCI IKON Z WINDOWS EXE SOUBORŮ ---
    def extract_wine_icon(win_path, app_name):
        if not win_path: return None
        # Odstraní uvozovky a index ikony (např. C:\hra.exe,0)
        win_path = win_path.split(',')[0].strip('"\'') 
        if not win_path.lower().startswith("c:\\"): return None
        
        # Převod Windows cesty na Linuxovou (C:\ -> ~/.wine/drive_c/)
        linux_path = os.path.expanduser("~/.wine/drive_c/" + win_path[3:].replace("\\", "/"))
        if not os.path.exists(linux_path): return None

        # PyQt nativně podporuje .ico soubory
        if linux_path.lower().endswith(".ico"): return linux_path

        # Cache složka, aby to při dalším spuštění nelagovalo
        cache_dir = os.path.expanduser("~/.cache/wine-icons")
        os.makedirs(cache_dir, exist_ok=True)
        safe_name = "".join(c for c in app_name if c.isalnum()).lower()
        cached_icon = os.path.join(cache_dir, f"{safe_name}.png")
        
        if os.path.exists(cached_icon): return cached_icon

        # Vytažení ikony z EXE souboru
        if linux_path.lower().endswith(".exe") and shutil.which("wrestool"):
            tmp_ico = f"/tmp/{safe_name}.ico"
            try:
                with open(tmp_ico, "wb") as f:
                    subprocess.run(["wrestool", "-x", "-t", "14", linux_path], stdout=f, stderr=subprocess.DEVNULL)
                if os.path.exists(tmp_ico) and os.path.getsize(tmp_ico) > 0:
                    out_dir = f"/tmp/{safe_name}_png"
                    os.makedirs(out_dir, exist_ok=True)
                    subprocess.run(["icotool", "-x", tmp_ico, "-o", out_dir], stderr=subprocess.DEVNULL)
                    pngs = glob.glob(f"{out_dir}/*.png")
                    if pngs:
                        best = max(pngs, key=os.path.getsize) # Vybere ikonu s nejvyšším rozlišením
                        shutil.copy(best, cached_icon)
                        return cached_icon
            except: pass
        return None
    
if __name__ == '__main__':
    app = QApplication(sys.argv)
    QIcon.setThemeName("Papirus")
    QIcon.setFallbackThemeName("hicolor")
    window = AppUninstaller()
    window.show()
    sys.exit(app.exec_())