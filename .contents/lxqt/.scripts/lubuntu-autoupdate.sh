#!/bin/bash

# --- KONFIGURACE ---
# true = Zablokuje aktualizace jádra (pro stabilitu starších PC s AMD/NVIDIA)
# false = Povolí aktualizace jádra
BLOCK_KERNEL_UPDATES=true
# -------------------

# Pockame 120 sekund (2 minuty) po startu anacronu
sleep 120

# Vypne jakékoliv interaktivní dotazy (aby to v cronu nečekalo na Enter)
export DEBIAN_FRONTEND=noninteractive

# Seznam hlavních metabalíčků jádra, které do systému tahají nové verze
KERNEL_PACKAGES="linux-generic linux-image-generic linux-headers-generic"

# Aplikace logiky pro blokování jádra před samotným updatem
if [ "$BLOCK_KERNEL_UPDATES" = true ]; then
    # Zablokuje změny v jádře
    apt-mark hold $KERNEL_PACKAGES > /dev/null
else
    # Odblokuje změny (pokud bys to někdy v budoucnu chtěl povolit)
    apt-mark unhold $KERNEL_PACKAGES > /dev/null
fi

# Stáhne čerstvé seznamy balíků
apt-get update -qq

# Provede tvrdý full-upgrade přesně jako tvůj manuální příkaz.
# Ty "Dpkg" parametry zajistí, že pokud se systém zeptá, jestli přepsat konfigurační soubor,
# automaticky zvolí výchozí/starou možnost a nezasekne se.
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade

# Uklidí po sobě staré a nepotřebné balíky
apt-get autoremove -y -qq
apt-get autoclean -qq