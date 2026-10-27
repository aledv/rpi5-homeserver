#!/bin/bash

#creo la cartella se non esiste
sudo mkdir -p /home/pi/.config/pcmanfm/default/
sudo chmod 700 /home/pi/.config/pcmanfm/default/
sudo chown pi:pi /home/pi/.config/pcmanfm/default/

#copio il file di configurazione
sudo cp scripts/desktop-items-NOOP-1.conf /home/pi/.config/pcmanfm/default/
sudo cp scripts/desktop-items-HDMI-A-1.conf /home/pi/.config/pcmanfm/default/
sudo cp scripts/desktop-items-HDMI-A-2.conf /home/pi/.config/pcmanfm/default/

#ricarico la configurazione
pcmanfm --reconfigure

echo "Wallpaper aggiornato con successo!"
