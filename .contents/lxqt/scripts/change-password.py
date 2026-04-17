#!/usr/bin/env python3
import sys
import os
import subprocess
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QFormLayout, 
                             QLineEdit, QPushButton, QMessageBox)
from PyQt5.QtCore import Qt

class PasswordChanger(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        self.setWindowTitle('Změna systémového hesla')
        self.resize(380, 220)
        
        layout = QVBoxLayout()
        form_layout = QFormLayout()
        
        self.new_pass = QLineEdit()
        self.new_pass.setEchoMode(QLineEdit.Password)
        self.new_pass.setPlaceholderText("Nechte prázdné pro zrušení hesla")
        
        self.new_pass_confirm = QLineEdit()
        self.new_pass_confirm.setEchoMode(QLineEdit.Password)

        form_layout.addRow('Nové heslo:', self.new_pass)
        form_layout.addRow('Potvrdit heslo:', self.new_pass_confirm)

        layout.addLayout(form_layout)

        self.btn_save = QPushButton('Uložit a nastavit')
        self.btn_save.setStyleSheet("background-color: #2a7fca; color: white; padding: 10px; font-weight: bold; border-radius: 5px;")
        self.btn_save.setCursor(Qt.PointingHandCursor)
        self.btn_save.clicked.connect(self.handle_change)
        
        layout.addSpacing(10)
        layout.addWidget(self.btn_save)
        self.setLayout(layout)

    def handle_change(self):
        new_p = self.new_pass.text()
        conf_p = self.new_pass_confirm.text()
        user = os.getlogin()

        # 1. Kontrola shody
        if new_p != conf_p:
            QMessageBox.warning(self, "Chyba", "Hesla se neshodují!")
            return

        # 2. Logika pro PRÁZDNÉ heslo
        if not new_p:
            reply = QMessageBox.question(self, 'Varování', 
                "Nezadali jste žádné heslo. Počítač bude nezabezpečený a nebudete ho muset při přihlášení zadávat. Chcete opravdu pokračovat?",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            
            if reply == QMessageBox.Yes:
                try:
                    # Smaže heslo uživatele (-d = delete)
                    subprocess.run(['sudo', 'passwd', '-d', user], check=True)
                    QMessageBox.information(self, "Hotovo", "Heslo bylo odstraněno. Nyní se můžete přihlašovat bez hesla.")
                    self.close()
                except:
                    QMessageBox.critical(self, "Chyba", "Nepodařilo se smazat heslo. Máte práva sudo?")
            return

        # 3. Logika pro JEDNODUCHÉ heslo (přes sudo to projde vždy)
        try:
            # Použijeme echo pro předání hesla do sudo passwd, aby nás to neobtěžovalo dotazy
            process = subprocess.Popen(['sudo', 'passwd', user], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            process.communicate(input=f"{new_p}\n{new_p}\n")
            
            if process.returncode == 0:
                QMessageBox.information(self, "Úspěch", "Heslo bylo úspěšně nastaveno (i přes případnou jednoduchost).")
                self.close()
            else:
                QMessageBox.warning(self, "Chyba", "Systém odmítl heslo nastavit. Zkuste to znovu přes terminál.")
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Došlo k chybě: {str(e)}")

if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = PasswordChanger()
    window.show()
    sys.exit(app.exec_())