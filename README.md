# Debiconf
Zprovoznění desktopového prostředí bez bloatwaru na čistém Debianu

Debian 13.4.0

AMD64: http://debian-cd.mirror.web4u.cz/13.4.0/amd64/iso-cd/debian-13.4.0-amd64-netinst.iso

ARM64: http://debian-cd.mirror.web4u.cz/13.4.0/arm64/iso-cd/debian-13.4.0-arm64-netinst.iso

--------------------------------------------------
**!! INSTALOVAT VÝHRADNĚ BEZ DESKTOPOVÉHO PROSTŘEDÍ BĚHEM INSTALACE SAMOTNÉHO SYSTÉMU - ZDE PONECHAT POUZE "STANDARDNÍ SYSTÉMOVÉ NÁSTROJE" !!**

![instalace](https://github.com/user-attachments/assets/09b934ce-8d9a-4a8f-863c-f3655eda5185)

--------------------------------------------------

Po dokončení čisté netinst instalace bez prostředí:

  1) su -
  
  2) apt install git -y
  
  3) git clone https://github.com/David96cz/debiconf
  
  4) cd debiconf
  
  5) bash debiconf.sh

---------------------------------------------------

![ukazka](https://github.com/user-attachments/assets/64951e8f-3912-4ba0-9bc4-acdc5192d50c)

---------------------------------------------------

**LXQt** 
- minimální HW požadavky (libovolný 64bitový procesor, 2GB RAM)
- spotřeba RAM po startu cca *600-700MB*
- ready out of the box pro běžného uživatele, customizace je však strohá, méně moderní vzhled, avšak extrémně svižné i na úplném šrotu
- *Klávesové zkratky*
  - Win + V = zobrazení historie schránky
  - Win + E = spuštění průzkumníka
  - Win + D = zobrazení plochy
  - Win + L = uzamčení obrazovky
  - Win + S = hledání nastavení, aplikací, souborů na interním či externím disku
  - Win + Shift + S = pořízení screenshotu
  - Ctrl + Shift + ESC = správce úloh
  - Ctrl + Alt + Delete = kontextová nabídka pro uzamčení, odhlášení, změnu hesla, správce úloh.
  - Alt + Tab = přepínání mezi okny apikací
  - Ctrl + Alt + T = spuštění terminálu
  
![lxqt](https://github.com/user-attachments/assets/ba057bfa-8508-444f-af25-8de0b2706106)

---------------------------------------------------

**KDE Plasma**
- lehce vyšší HW požadavky, avšak díky skvělé optimalizaci stále vhodné i na starší PC (Intel 3. generace a vyšší ideálně, 4GB RAM)
- spotřeba RAM po startu cca *800-1200MB*
- ready out of the box pro běžného uživatele, obrovská možnost customizace, široké nastavení, skoro vše jde vyklikat GUI, moderní vzhled a funkce
  
![plasma](https://github.com/user-attachments/assets/9d313503-b97b-49d1-b5a1-0ae01faade75)


