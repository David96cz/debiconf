#!/usr/bin/env python3
import sys
import time
import subprocess
import ctypes

# --- NASTAVENÍ ---
TIMEOUT = 10           # Maximální čas čekání (pojistka)
POLL_INTERVAL = 0.25   # Jak často kontrolovat (vteřiny)

# Kurzor: left_ptr_watch (šipka s hodinkami)
CURSOR_NAME = b"watch" 

def get_window_count():
    """Získá aktuální počet oken v systému."""
    try:
        output = subprocess.check_output(
            ["xprop", "-root", "_NET_CLIENT_LIST"], 
            stderr=subprocess.DEVNULL
        ).decode("utf-8").strip()
        
        if "window id #" in output:
            content = output.split("window id #")[1]
            windows = content.split(",")
            return len([w for w in windows if w.strip()])
        return 0
    except Exception:
        return 0

def get_active_window():
    """Získá ID aktuálně aktivního okna."""
    try:
        output = subprocess.check_output(
            ["xprop", "-root", "_NET_ACTIVE_WINDOW"], 
            stderr=subprocess.DEVNULL
        ).decode("utf-8").strip()
        
        # Výstup vypadá např.: _NET_ACTIVE_WINDOW(WINDOW): window id # 0x2400005
        if "window id #" in output:
            return output.split("window id #")[1].strip()
        return None
    except Exception:
        return None

def main():
    display = None
    x11 = None
    
    try:
        # --- 1. PŘÍPRAVA X11 ---
        x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
        xcursor = ctypes.cdll.LoadLibrary("libXcursor.so.1")

        x11.XOpenDisplay.restype = ctypes.c_void_p
        xcursor.XcursorLibraryLoadCursor.restype = ctypes.c_ulong
        
        display = x11.XOpenDisplay(None)
        if not display:
            if len(sys.argv) > 1:
                subprocess.Popen(sys.argv[1:])
            return

        screen_id = x11.XDefaultScreen(display)
        root = x11.XRootWindow(display, screen_id)
        
        # Načteme kurzor
        cursor = xcursor.XcursorLibraryLoadCursor(display, CURSOR_NAME)

        # --- 2. ZJIŠTĚNÍ STAVU PŘED SPUŠTĚNÍM ---
        initial_count = get_window_count()
        initial_active = get_active_window()

        # --- 3. GRAB POINTER (BLOKUJÍCÍ) ---
        x11.XGrabPointer(display, root, True, 0, 1, 1, 0, cursor, 0)
        x11.XFlush(display)
        
        # --- 4. SPUŠTĚNÍ APLIKACE ---
        if len(sys.argv) > 1:
            subprocess.Popen(sys.argv[1:], start_new_session=True)
        else:
            return

        # --- 5. SMYČKA ČEKÁNÍ ---
        start_time = time.time()
        
        while time.time() - start_time < TIMEOUT:
            # A) Zkontrolujeme, jestli přibylo okno (nová appka)
            current_count = get_window_count()
            if current_count > initial_count:
                break
            
            # B) Zkontrolujeme, jestli se změnilo aktivní okno (tab v prohlížeči)
            # Pokud se focus změnil (např. ze správce souborů na Chrome), končíme.
            current_active = get_active_window()
            if current_active != initial_active and current_active is not None:
                break
            
            time.sleep(POLL_INTERVAL)

    except Exception as e:
        # Tichý error handling, aby to uživatele neobtěžovalo
        pass

    finally:
        # --- 6. ÚKLID (UNGRAB) ---
        if x11 and display:
            x11.XUngrabPointer(display, 0)
            x11.XFlush(display)
            x11.XCloseDisplay(display)

if __name__ == "__main__":
    main()
