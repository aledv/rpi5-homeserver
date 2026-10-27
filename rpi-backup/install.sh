#!/usr/bin/env bash
# Setup del RPi4 "rpi-backup" (Raspberry Pi OS Lite 64 bit, utente pi) da un'installazione pulita. Idempotente.
# Uso, da un host con accesso ssh a entrambi (DELL):  scp -r rpi-backup pi@<ip>:   poi
#   ssh pi@<ip-del-pi5> "grep -oP '^RESTIC_REST_PASSWORD=\\K.*' /mnt/external_drive/my_rpi_scripts/backrest/.env" | ssh pi@<ip> bash rpi-backup/install.sh
# (la password del rest-server, RESTIC_REST_PASSWORD del .env di backrest sul .30, serve su stdin solo se htpasswd manca)
set -euo pipefail
cd "$(dirname "$0")"

echo "== 1. Aggiornamenti e pacchetti"
sudo apt-get -qq update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install git curl ca-certificates smartmontools unattended-upgrades apache2-utils wireguard-tools fastfetch >/dev/null
# fastfetch al login SSH (solo shell interattive, non dentro tmux), come DELL e .30
grep -q "fastfetch --logo" ~/.bashrc || printf '\n%s\n' 'if [[ $- == *i* && -n "$SSH_TTY" && -z "$TMUX" ]] && command -v fastfetch >/dev/null; then fastfetch --logo raspbian; fi' >> ~/.bashrc
# aggiornamenti automatici completi (Debian, Raspberry Pi, Docker) con riavvio alle 05:00 se serve, come DELL e .30
sudo install -m 644 52unattended-rpi-backup /etc/apt/apt.conf.d/52unattended-rpi-backup

echo "== 2. Docker"
command -v docker >/dev/null || { curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && sudo sh /tmp/get-docker.sh >/dev/null; }
sudo usermod -aG docker "$USER"
echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' | sudo tee /etc/docker/daemon.json.new >/dev/null
if ! sudo cmp -s /etc/docker/daemon.json.new /etc/docker/daemon.json; then sudo mv /etc/docker/daemon.json.new /etc/docker/daemon.json; sudo systemctl restart docker; else sudo rm /etc/docker/daemon.json.new; fi

echo "== 3. Quirk USB del bridge Seagate (SMART leggibile, niente UAS): attiva dal prossimo riavvio"
CMD=/boot/firmware/cmdline.txt
grep -q 'usb-storage.quirks=0bc2:331a:u' "$CMD" || sudo sed -i '1 s/$/ usb-storage.quirks=0bc2:331a:u/' "$CMD"
# memoria dei container per Beszel/Portainer (cgroup memory, spenta di default sul kernel del Raspberry): attiva dal prossimo riavvio
grep -q 'cgroup_memory=1' "$CMD" || sudo sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' "$CMD"

echo "== 4. Disco Seagate (LABEL=offsite) su /mnt/offsite, nofail; mountpoint immutabile se il disco manca"
sudo mkdir -p /mnt/offsite
mountpoint -q /mnt/offsite || sudo chattr +i /mnt/offsite
grep -q 'LABEL=offsite' /etc/fstab || echo 'LABEL=offsite /mnt/offsite ext4 defaults,nofail,x-systemd.device-timeout=15s 0 2' | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
blkid -L offsite >/dev/null 2>&1 && { mountpoint -q /mnt/offsite || sudo mount /mnt/offsite; }

echo "== 5. Utente del rest-server (/opt/rpi-backup/htpasswd)"
sudo mkdir -p /opt/rpi-backup
if [ ! -s /opt/rpi-backup/htpasswd ]; then
    read -r PW || { echo "   manca la password su stdin (vedi intestazione)"; exit 1; }
    printf '%s\n' "$PW" | sudo htpasswd -B -i -c /opt/rpi-backup/htpasswd pi 2>/dev/null
    sudo chmod 644 /opt/rpi-backup/htpasswd
fi

echo "== 6. VPN WireGuard verso casa (client RPi-Backup di wg-easy; configurazione con wg-config.py, vedi sua intestazione)"
if sudo test -s /etc/wireguard/wg0.conf; then sudo systemctl enable --now wg-quick@wg0
else echo "   manca /etc/wireguard/wg0.conf: generala con rpi-backup/wg-config.py sul .30, poi rilancia"; fi

echo "== 7. Tunnel inverso verso il .30 (utente offsite, chiave /root/.ssh/id_offsite: la pubblica va in my_rpi_scripts/scripts/offsite_authorized_keys)"
sudo test -f /root/.ssh/id_offsite || sudo ssh-keygen -q -t ed25519 -N "" -C rpi-backup-tunnel -f /root/.ssh/id_offsite
sudo install -m 644 offsite-tunnel.service /etc/systemd/system/offsite-tunnel.service
sudo systemctl daemon-reload && sudo systemctl enable --now offsite-tunnel.service

echo "== 8. Container (scrutiny-collector solo se il disco è collegato, beszel-agent solo con .env)"
PROFILE=(); [ -e /dev/disk/by-id/ata-<MODELLO>_<SERIALE> ] && PROFILE=(--profile disco)
grep -qs "^BESZEL_TOKEN=." .env && PROFILE+=(--profile beszel)   # agent Beszel solo con il token in .env
sudo docker compose "${PROFILE[@]}" up -d

echo "FATTO"
