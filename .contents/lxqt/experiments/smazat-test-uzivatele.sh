# Odstřelí všechny procesy uživatele (pro jistotu)
sudo pkill -u test

# Smaže uživatele i s jeho domovskou složkou
sudo userdel -r test

# Vytvoří ho znovu (tady zadej heslo)
sudo adduser test

# Přidá ho do skupiny sudo (aby mohl instalovat věci)
sudo usermod -aG sudo test
