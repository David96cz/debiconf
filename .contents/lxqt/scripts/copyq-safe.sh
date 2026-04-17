#!/bin/bash
# Přinutíme CopyQ pracovat v /tmp. Jakýkoliv odpad se smaže při restartu.
cd /tmp
exec copyq "$@"