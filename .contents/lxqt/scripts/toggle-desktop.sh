#!/bin/bash
# Zjistí, jestli už je plocha zobrazená (okna jsou dole).
# Pokud ano, vytáhne je zpět. Pokud ne, skryje je.
if wmctrl -m | grep -q "mode: ON"; then
    wmctrl -k off
else
    wmctrl -k on
fi