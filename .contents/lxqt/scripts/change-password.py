#!/usr/bin/env python3
import sys
import os
import subprocess
import pexpect
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QFormLayout, 
                             QLineEdit, QPushButton, QMessageBox, QCheckBox)
from PyQt5.QtCore import Qt

class PasswordChanger(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        self.setWindowTitle('Změna systémového hesla')
        self.resize(420, 270)
        
        layout = QVBoxLayout()
        form_layout = QFormLayout()
        
        self.old_pass = QLineEdit()
        self.old_pass.setEchoMode(QLineEdit.Password)
        self.old_pass.setPlaceholderText("Pokud heslo není nastaveno, nechte prázdné")
        
        self.new_pass = QLineEdit()
        self.new_pass.setEchoMode(QLineEdit.Password)
        self.new_pass.setPlaceholderText("Nechte prázdné pro zrušení hesla")
        
        self.new_pass_confirm = QLineEdit()
        self.new_pass_confirm.setEchoMode(QLineEdit.Password)

        form_layout.addRow('Stávající heslo:', self.old_pass)
        form_layout.addRow('Nové heslo:', self.new_pass)
        form_layout.addRow('Potvrdit nové heslo:', self.new_pass_confirm)

        layout.addLayout(form_layout)

        # CHECKBOX: Zobrazit nová hesla
        self.cb_show_pass = QCheckBox('Zobrazit nová hesla')
        self.cb_show_pass.stateChanged.connect(self.toggle_echo_mode)
        layout.addWidget(self.cb_show_pass)

        self.btn_save = QPushButton('Uložit a nastavit')
        self.btn_save.setStyleSheet("background-color: #2a7fca; color: white; padding: 10px; font-weight: bold; border-radius: 5px;")
        self.btn_save.setCursor(Qt.PointingHandCursor)
        self.btn_save.clicked.connect(self.handle_change)
        
        layout.addSpacing(10)
        layout.addWidget(self.btn_save)
        self.setLayout(layout)

    def toggle_echo_mode(self, state):
        if state == Qt.Checked:
            self.new_pass.setEchoMode(QLineEdit.Normal)
            self.new_pass_confirm.setEchoMode(QLineEdit.Normal)
        else:
            self.new_pass.setEchoMode(QLineEdit.Password)
            self.new_pass_confirm.setEchoMode(QLineEdit.Password)

    def verify_current_password(self, old_p):
        try:
            child = pexpect.spawn('env LANG=C passwd')
            idx = child.expect(['Current password:', 'New password:', pexpect.EOF], timeout=3)
            
            if idx == 0:
                if not old_p:
                    child.close()
                    return False
                child.sendline(old_p)
                idx2 = child.expect(['New password:', 'Authentication token manipulation error', 'incorrect password', 'Authentication failure', pexpect.EOF], timeout=3)
                child.close()
                return idx2 == 0 
            elif idx == 1:
                child.close()
                return old_p == ""
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

        if new_p != conf_p:
            QMessageBox.warning(self, "Chyba", "Nová hesla se neshodují!")
            return

        if not self.verify_current_password(old_p):
            QMessageBox.critical(self, "Chyba ověření", "Stávající heslo je nesprávné.")
            return

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
        try:
            process = subprocess.Popen(['sudo', '/usr/sbin/chpasswd'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            out, err = process.communicate(input=f"{user}:{new_p}\n")
            
            if process.returncode == 0:
                QMessageBox.information(self, "Úspěch", "Vaše nové heslo bylo úspěšně nastaveno.")
                self.close()
            else:
                QMessageBox.warning(self, "Chyba Systému", f"Systém odmítl heslo nastavit.\n\nTechnický důvod:\n{err}")
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Došlo ke kritické chybě: {str(e)}")

if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = PasswordChanger()
    window.show()
    sys.exit(app.exec_())