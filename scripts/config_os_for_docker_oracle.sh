#!/bin/bash

CONFIG_FILE="/boot/firmware/config.txt"
CMDLINE_FILE="/boot/firmware/cmdline.txt"

# Aggiunge 'kernel=kernel8.img' a config.txt se non presente
grep -q "^kernel=kernel8.img" "$CONFIG_FILE" || echo "kernel=kernel8.img" >> "$CONFIG_FILE"

# Aggiunge 'cgroup_enable=memory' a cmdline.txt se non presente
if ! grep -q " cgroup_enable=memory" "$CMDLINE_FILE"; then
    echo -n " cgroup_enable=memory" >> "$CMDLINE_FILE"
fi

sudo mkdir -p /mnt/external_drive/oracle/oracle-data
sudo mkdir -p /mnt/external_drive/oracle/ext-tables
sudo chown -R 54321:54321 /mnt/external_drive/oracle
sudo chmod 777 /mnt/external_drive/oracle/ext-tables

echo "Configurazione completata."
