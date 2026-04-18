#!/bin/bash

# 1. Zjistíme aktuální nativní rozlišení monitoru
NATIVE_RES=$(xrandr 2>/dev/null | grep '\*' | awk '{print $1}' | head -n 1)
# Pokud xrandr selže (třeba hned po startu), končíme, ať nic nerozbijeme
[ -z "$NATIVE_RES" ] && exit 0

# 2. Definujeme cestu k registru Wine (HKCU se ukládá do user.reg)
USER_REG="$HOME/.wine/user.reg"

# Pokud teta ještě nemá vytvořený Wine prefix, nemá cenu nic syncovat
[ ! -f "$USER_REG" ] && exit 0

# 3. SILENT CHECK: Koukneme se přímo do souboru registru bez buzení Wine
# Hledáme, jestli v registrech už JE zapsané tohle konkrétní rozlišení
if ! grep -Fq "\"Default\"=\"$NATIVE_RES\"" "$USER_REG"; then
    # POUZE POKUD SE LIŠÍ, provedeme zápis (tady to jednou problikne, ale jen při změně monitoru)
    wine reg add "HKCU\Software\Wine\Explorer" /v "Desktop" /t REG_SZ /d "Default" /f >/dev/null 2>&1
    wine reg add "HKCU\Software\Wine\Explorer\Desktops" /v "Default" /t REG_SZ /d "$NATIVE_RES" /f >/dev/null 2>&1
    
    # Volitelně: Můžeme killnout explorer, aby si to Wine hned přebral, 
    # ale po startu PC je to jedno
    wineboot -u >/dev/null 2>&1
fi