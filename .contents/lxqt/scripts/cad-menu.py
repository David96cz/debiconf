#!/usr/bin/env python3
import sys
import os
import fcntl
import subprocess
from PyQt5.QtWidgets import QApplication, QWidget, QVBoxLayout, QPushButton, QDesktopWidget
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QColor, QPainter

class CADMenu(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        # Okno bez okrajů, které zůstává vždy navrchu
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        # Nastavení průhlednosti pozadí
        self.setAttribute(Qt.WA_TranslucentBackground)
        
        # Roztáhnutí přes celou obrazovku
        screen = QDesktopWidget().screenGeometry()
        self.setGeometry(0, 0, screen.width(), screen.height())

        # Hlavní layout (vycentrování tlačítek doprostřed)
        layout = QVBoxLayout()
        layout.setAlignment(Qt.AlignCenter)
        layout.setSpacing(15) # Zmenšené mezery z 20 na 15

        # Stylování tlačítek (Zmenšené písmo a padding)
        button_style = """
            QPushButton {
                background-color: rgba(255, 255, 255, 15); /* Permanentní jemné pozadí */
                color: white;
                font-size: 18px; /* Zmenšeno z 22px */
                font-weight: 500;
                border: 1px solid rgba(255, 255, 255, 40); /* Viditelný tenký okraj */
                border-radius: 8px; /* Jemné zakulacení rohů */
                padding: 12px 40px; /* Zmenšeno z 15px */
                min-width: 350px;
            }
            QPushButton:hover {
                background-color: rgba(255, 255, 255, 40);
                border: 1px solid rgba(255, 255, 255, 150);
            }
            QPushButton:pressed {
                background-color: rgba(255, 255, 255, 60);
                border: 1px solid white;
            }
        """

        # Tlačítko: Zamknout
        btn_lock = QPushButton('Zamknout')
        btn_lock.setStyleSheet(button_style)
        btn_lock.setCursor(Qt.PointingHandCursor)
        btn_lock.clicked.connect(self.action_lock)

        # Tlačítko: Odhlásit se
        btn_logout = QPushButton('Odhlásit se')
        btn_logout.setStyleSheet(button_style)
        btn_logout.setCursor(Qt.PointingHandCursor)
        btn_logout.clicked.connect(self.action_logout)

        # Tlačítko: Změnit heslo (Nová volba)
        btn_passwd = QPushButton('Změnit heslo')
        btn_passwd.setStyleSheet(button_style)
        btn_passwd.setCursor(Qt.PointingHandCursor)
        btn_passwd.clicked.connect(self.action_passwd)

        # Tlačítko: Správce úloh
        btn_taskmgr = QPushButton('Správce úloh')
        btn_taskmgr.setStyleSheet(button_style)
        btn_taskmgr.setCursor(Qt.PointingHandCursor)
        btn_taskmgr.clicked.connect(self.action_taskmgr)

        # Tlačítko: Zrušit
        btn_cancel = QPushButton('Zrušit')
        btn_cancel.setStyleSheet(button_style)
        btn_cancel.setCursor(Qt.PointingHandCursor)
        btn_cancel.clicked.connect(self.close)

        # Přidání do layoutu
        layout.addWidget(btn_lock)
        layout.addWidget(btn_logout)
        layout.addWidget(btn_passwd) # Vloženo pod správce úloh
        layout.addWidget(btn_taskmgr)
        layout.addSpacing(30) # Zmenšená mezera před Zrušit z 40 na 30
        layout.addWidget(btn_cancel)

        self.setLayout(layout)

    # Vykreslení toho průsvitného tmavého pozadí
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(0, 0, 0, 220))

    # Reakce na klávesu Escape (zavře menu)
    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.close()

    # --- AKCE TLAČÍTEK ---
    def action_lock(self):
        subprocess.Popen(['lxqt-leave', '--lockscreen'])
        self.close()

    def action_logout(self):
        subprocess.Popen(['lxqt-leave', '--logout'])
        self.close()

    def action_taskmgr(self):
        subprocess.Popen(['qps'])
        self.close()

    def action_passwd(self):
        # Spustí izolovaný skript na změnu hesla a zavře toto CAD menu
        script_path = os.path.expanduser('~/.local/bin/change-password.py')
        subprocess.Popen(['python3', script_path])
        self.close()

if __name__ == '__main__':
    # 1. Zajištění, že běží jen jedna instance
    lock_file_path = '/tmp/cad_menu.lock'
    lock_file = open(lock_file_path, 'w')
    
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)

    # 2. Spuštění samotné aplikace
    app = QApplication(sys.argv)
    menu = CADMenu()
    menu.show()
    sys.exit(app.exec_())