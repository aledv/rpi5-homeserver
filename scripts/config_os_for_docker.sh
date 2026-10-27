#!/bin/bash
# Abilita il cgroup della memoria (limiti e statistiche di memoria dei container Docker)
CMDLINE_FILE="/boot/firmware/cmdline.txt"
if ! grep -q " cgroup_enable=memory" "$CMDLINE_FILE"; then
    echo -n " cgroup_enable=memory" >> "$CMDLINE_FILE"
fi
echo "Configurazione completata."
