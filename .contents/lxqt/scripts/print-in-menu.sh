#!/bin/bash
SOUBOR="$1"
NAZEV=$(basename "$SOUBOR")
RAW_PRINTERS=$(lpstat -p 2>/dev/null | awk '{print $2}')

if [ -z "$RAW_PRINTERS" ]; then
    yad --error --title="Chyba" --text="V systému není žádná nainstalovaná tiskárna!" \
        --button="OK:0" --center --width=300 --window-icon="printer"
    exit 1
fi

PRINTER_LIST=$(echo "$RAW_PRINTERS" | tr '\n' '!')
DEFAULT_PRINTER=$(lpstat -d 2>/dev/null | awk '{print $4}')

VYSTUP=$(yad --form --title="Tisk souboru" \
    --text="<big><b>Tisk dokumentu</b></big>\n\nSoubor: $NAZEV" \
    --window-icon="printer" --center --width=450 \
    --field="Výběr tiskárny:CB" "$DEFAULT_PRINTER!$PRINTER_LIST" \
    --field="Počet kopií:NUM" "1!1..20!1" \
    --field="Kvalita tisku:CB" "Normální!Rychlá (Koncept)!Vysoká (Foto)" \
    --button="Zrušit:1" \
    --button="Tisk:0" \
    --separator="|")

if [ $? -ne 0 ]; then exit 0; fi

TISKARNA=$(echo "$VYSTUP" | cut -d'|' -f1)
KOPIE=$(echo "$VYSTUP" | cut -d'|' -f2)
KVALITA_TXT=$(echo "$VYSTUP" | cut -d'|' -f3)

case "$KVALITA_TXT" in
  "Rychlá (Koncept)") MOJE_OPTS="-o print-quality=3" ;;
  "Vysoká (Foto)")    MOJE_OPTS="-o print-quality=5" ;;
  *)                  MOJE_OPTS="-o print-quality=4" ;;
esac

lp -d "$TISKARNA" -n "$KOPIE" $MOJE_OPTS "$SOUBOR"

if [ $? -eq 0 ]; then
    notify-send -i printer "Tisk odeslán" "Tiskárna: $TISKARNA"
else
    yad --error --text="Chyba při odesílání na tiskárnu."
fi