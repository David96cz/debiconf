#!/usr/bin/env python3
import sys
import os
import subprocess
import pexpect
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QFormLayout, 
                             QLineEdit, QPushButton, QMessageBox)
from PyQt5.QtCore import Qt

class PasswordChanger(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        self.setWindowTitle('Změna systémového hesla')
        self.resize(420, 250)
        
        layout = QVBoxLayout()
        form_layout = QFormLayout()
        
        # 1. Stávající heslo
        self.old_pass = QLineEdit()
        self.old_pass.setEchoMode(QLineEdit.Password)
        self.old_pass.setPlaceholderText("Pokud heslo není nastaveno, nechte prázdné")
        
        # 2. Nové heslo
        self.new_pass = QLineEdit()
        self.new_pass.setEchoMode(QLineEdit.Password)
        self.new_pass.setPlaceholderText("Nechte prázdné pro zrušení hesla")
        
        # 3. Potvrzení nového
        self.new_pass_confirm = QLineEdit()
        self.new_pass_confirm.setEchoMode(QLineEdit.Password)

        form_layout.addRow('Stávající heslo:', self.old_pass)
        form_layout.addRow('Nové heslo:', self.new_pass)
        form_layout.addRow('Potvrdit nové heslo:', self.new_pass_confirm)

        layout.addLayout(form_layout)

        self.btn_save = QPushButton('Uložit a nastavit')
        self.btn_save.setStyleSheet("background-color: #2a7fca; color: white; padding: 10px; font-weight: bold; border-radius: 5px;")
        self.btn_save.setCursor(Qt.PointingHandCursor)
        self.btn_save.clicked.connect(self.handle_change)
        
        layout.addSpacing(10)
        layout.addWidget(self.btn_save)
        self.setLayout(layout)

    def verify_current_password(self, old_p):
        """Tiše ověří, jestli je zadané staré heslo správné."""
        try:
            # Zavoláme standardní passwd v angličtině
            child = pexpect.spawn('env LANG=C passwd')
            
            # Zjistíme, na co se systém zeptá (pokud uživatel nemá heslo, přeskočí to rovnou na New password)
            idx = child.expect(['Current password:', 'New password:', pexpect.EOF], timeout=3)
            
            if idx == 0:
                # Systém chce staré heslo
                if not old_p:
                    child.close()
                    return False # Bylo potřeba heslo, ale uživatel zadal prázdné
                
                child.sendline(old_p)
                idx2 = child.expect(['New password:', 'Authentication token manipulation error', 'incorrect password', 'Authentication failure', pexpect.EOF], timeout=3)
                child.close()
                
                # Pokud po zadání starého hesla následuje dotaz na nové, staré bylo SPRÁVNĚ
                return idx2 == 0 
                
            elif idx == 1:
                # Systém rovnou chce nové heslo (uživatel momentálně ŽÁDNÉ heslo NEMÁ)
                child.close()
                return old_p == "" # Vrátí True, jen pokud uživatel správně nechal políčko prázdné
                
            else:
                child.close()
                return False
                
        except pexpect.ExceptionPexpect:
            return False

    def handle_change(self):
        old_p = self.old_pass.text()
        new_p = self.new_pass.text()
        conf_p = self.new_pass_confirm.text()
        user = os.getlogin()

        # 1. Kontrola shody nových hesel
        if new_p != conf_p:
            QMessageBox.warning(self, "Chyba", "Nová hesla se neshodují!")
            return

        # 2. Ověření stávajícího hesla (Kritická bezpečnostní oprava)
        if not self.verify_current_password(old_p):
            QMessageBox.critical(self, "Chyba ověření", "Stávající heslo je nesprávné.")
            return

        # 3. Logika pro nastavení PRÁZDNÉHO hesla
        if not new_p:
            reply = QMessageBox.question(self, 'Varování', 
                "Opravdu chcete ZRUŠIT heslo? Počítač bude nezabezpečený a při přihlášení či instalaci programů nebudete zadávat heslo.",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            
            if reply == QMessageBox.Yes:
                try:
                    subprocess.run(['sudo', 'passwd', '-d', user], check=True)
                    QMessageBox.information(self, "Hotovo", "Heslo bylo úspěšně odstraněno.")
                    self.close()
                except:
                    QMessageBox.critical(self, "Chyba", "Nepodařilo se smazat heslo.")
            return

        # 4. Logika pro JEDNODUCHÉ heslo (obejití linuxové buzerace přes sudo)
        try:
            process = subprocess.Popen(['sudo', 'passwd', user], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            process.communicate(input=f"{new_p}\n{new_p}\n")
            
            if process.returncode == 0:
                QMessageBox.information(self, "Úspěch", "Vaše nové heslo bylo úspěšně nastaveno.")
                self.close()
            else:
                QMessageBox.warning(self, "Chyba", "Systém odmítl heslo nastavit.")
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Došlo k chybě: {str(e)}")

if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = PasswordChanger()
    window.show()
    sys.exit(app.exec_())