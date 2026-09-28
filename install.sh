#!/bin/bash

# Quando attivi set -e, lo script si interrompe immediatamente se un comando restituisce un codice di uscita diverso da zero (cioè se il comando fallisce). 
set -e

# Percorso della directory principale
main_folder="."

echo "Avvio del ridimensionamento della partizione root..."
sudo raspi-config --expand-rootfs

# Abilita SSH (decommentato per permettere l'uso)
#echo "Abilito SSH"
#sudo raspi-config nonint do_ssh 0

echo "Abilito VNC"
sudo raspi-config nonint do_vnc 0

# Funzione per installare Docker
install_docker() {
    echo "Inizio installazione di Docker..."
    sudo apt update
    sudo apt upgrade -y
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    #sudo apt install -y docker-compose 
    echo "Docker installato correttamente!"
}

# Funzione per installare fuse
install_fuse() {
    echo "Inizio installazione di Fuse..."
    sudo apt update
    sudo apt install -y exfat-fuse ntfs-3g
    echo "Fuse installato correttamente!"
}

# Funzione per installare rsync
install_rsync() {
    echo "Inizio installazione di RSync..."
    sudo apt update
    sudo apt install -y rsync
    echo "RSync installato correttamente!"
}

# Funzione per installare Splix
install_splix() {
    echo "Inizio installazione di Splix..."
    sudo apt update
    sudo apt install -y printer-driver-splix
    echo "Splix installato correttamente!"
}

# Funzione per installare uuid-runtime
install_uuid_runtime() {
    echo "Inizio installazione di uuid-runtime..."
    sudo apt update
    sudo apt install -y uuid-runtime
    echo "uuid-runtime installato correttamente!"
}

# Funzione per installare NCDU
install_ncdu() {
    echo "Inizio installazione di NCDU..."
    sudo apt update
    sudo apt install -y ncdu
    echo "NCDU installato correttamente!"
}

# Funzione per installare GParted
install_gparted() {
    echo "Inizio installazione di GParted..."
    sudo apt update
    sudo apt install -y gparted
    echo "GParted installato correttamente!"
}

# Funzione per installare MusicBrainz - Picard
install_musicbrainz_picard() {
    echo "Inizio installazione di MusicBrainz - Picard..."
    if ! command -v snap &> /dev/null; then
        echo "Installazione di snapd..."
        sudo apt install -y snapd
    fi
    sudo snap install picard
    echo "MusicBrainz - Picard installato correttamente!"
}

# Funzione per installare FastFetch
install_fastfetch() {
    echo "Inizio installazione di FastFetch..."
    sudo apt update
    sudo apt install -y fastfetch
    echo -e '\n#fastfetch information\nfastfetch --logo raspbian' >> ~/.bashrc
    echo "FastFetch installato correttamente!"
}

# Funzione per configurare la swappiness a 10
configure_swappiness() {
    echo "Configurazione della swappiness a 10..."
    echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null
    sudo sysctl --system
    echo "Swappiness configurata correttamente a 10!"
}

# Funzione per configurare lo swap di rpi-swap (zram + file di writeback) a 4 GB
# Default di Raspberry Pi OS (trixie): tetto di 2 GB, troppo poco per i container di questo server
configure_swap() {
    if ! dpkg -s rpi-swap &> /dev/null; then
        echo "rpi-swap non installato: salto la configurazione dello swap."
        return 0
    fi
    echo "Configurazione dello swap (zram e file di writeback) a 8 GB..."
    sudo mkdir -p /etc/rpi/swap.conf.d
    printf '[Zram]\nMaxSizeMiB=8192\n\n[File]\nMaxSizeMiB=8192\n' | sudo tee /etc/rpi/swap.conf.d/90-more-swap.conf > /dev/null
    echo "Swap configurato a 8 GB: sarà attivo dal prossimo riavvio."
}

# Funzione per aggiungere file al crontab se non esistono
add_crontab_entry() {
    local crontab_file="scripts/crontab.copy"
    if [ -f "$crontab_file" ]; then
        echo "Aggiungendo contenuto di crontab.copy al crontab di sistema..."
        # Aggiungi solo le voci che non sono già presenti nel crontab di root
        sudo crontab -l -u root | grep -v -f "$crontab_file" | sudo crontab -u root -
        cat "$crontab_file" | sudo crontab -u root -
    else
        echo "File crontab.copy non trovato."
    fi
}

add_fstab_entry() {
    echo "Creo le cartelle per ospitare il DAS sotto /mnt"
    sudo mkdir -p /mnt/external_drive/utility /mnt/external_drive 
    sudo chmod 775 /mnt/external_drive/utility /mnt/external_drive 
    echo "Modifico il file fstab"
    local fstab_file="scripts/fstab.copy"
    if [ -f "$fstab_file" ]; then
        echo "Aggiungendo contenuto di fstab.copy a /etc/fstab..."
        while IFS= read -r line; do
            # Salta righe vuote o commenti
            if [ -z "$line" ] || echo "$line" | grep -q "^#"; then
                continue
            fi

            # Verifica se la riga esiste già in /etc/fstab
            if ! grep -qFx "$line" /etc/fstab; then
                echo "Aggiungendo riga a /etc/fstab: $line"
                echo "$line" | sudo tee -a /etc/fstab > /dev/null

                # Estrai il punto di mount dalla riga e montalo
                mount_point=$(echo "$line" | awk '{print $2}')
                echo "Montando $mount_point..."
                sudo mount "$mount_point"
            else
                echo "Riga già presente in /etc/fstab: $line"
            fi
        done < "$fstab_file"
    else
        echo "File fstab.copy non trovato."
    fi

    sudo systemctl daemon-reload
}

add_daemon_for_docker() {
    # Copia daemon.json sotto /etc/docker
    if [ -f "scripts/daemon.json" ]; then
        sudo cp "scripts/daemon.json" /etc/docker
        echo "File daemon.json copiato in /etc/docker."
        sudo systemctl restart docker
    else
        echo "File daemon.json non trovato."
    fi
}

# Funzione per dare a Docker 4 minuti per fermare i container allo spegnimento
# Default di systemd: 90s, troppo pochi per lo shutdown pulito di Oracle (stop_grace_period 3m)
configure_docker_stop_timeout() {
    echo "Configurazione del timeout di arresto di Docker a 240s..."
    sudo mkdir -p /etc/systemd/system/docker.service.d
    printf '[Service]\nTimeoutStopSec=240\n' | sudo tee /etc/systemd/system/docker.service.d/10-stop-timeout.conf > /dev/null
    sudo systemctl daemon-reload
    echo "Timeout di arresto di Docker configurato a 240s!"
}

# Funzione per installare il bouncer di CrowdSec (blocca nel firewall gli IP decisi dal container crowdsec)
# La chiave è in crowdsec/.env (non su git); il container crowdsec lo avvia install_containers.sh.
install_crowdsec_bouncer() {
    echo "Installazione di crowdsec-firewall-bouncer..."
    sudo apt install -y --no-install-recommends crowdsec-firewall-bouncer
    # rsyslog scrive /var/log/auth.log, che CrowdSec legge per proteggere SSH (su trixie c e solo journald)
    sudo apt install -y rsyslog
    if [ -f crowdsec/.env ]; then
        . crowdsec/.env
        printf 'mode: nftables\napi_url: http://127.0.0.1:8180/\napi_key: %s\n' "$BOUNCER_KEY_FIREWALL" \
            | sudo tee /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local > /dev/null
        sudo chmod 600 /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local
    else
        echo "ATTENZIONE: crowdsec/.env mancante, il bouncer non potrà collegarsi (crealo da crowdsec/.env.sample)."
    fi
    # Il container crowdsec parte dopo Docker: senza restart il bouncer resterebbe fermo dopo un riavvio
    sudo mkdir -p /etc/systemd/system/crowdsec-firewall-bouncer.service.d
    printf '[Unit]\nAfter=docker.service\n\n[Service]\nRestart=always\nRestartSec=30\n' \
        | sudo tee /etc/systemd/system/crowdsec-firewall-bouncer.service.d/10-restart.conf > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable crowdsec-firewall-bouncer
    sudo systemctl restart crowdsec-firewall-bouncer || true
}

# Funzione per limitare sshd (SSH solo da LAN/VPN: la porta 22 non va inoltrata sul router)
configure_sshd_hardening() {
    echo "Configurazione di sshd (root no, 3 tentativi, solo pi)..."
    sudo install -m 644 scripts/sshd_hardening.conf /etc/ssh/sshd_config.d/90-hardening.conf
    sudo sshd -t && sudo systemctl reload ssh
}

# Esegui l'installazione di Docker, se non è già installato
if ! command -v docker &> /dev/null; then
    install_docker
else
    echo "Docker è già installato."
fi

# Esegui l'installazione di Fuse, se non è già installato
if ! dpkg -l | grep -q exfat-fuse; then
    install_fuse
else
    echo "Fuse è già installato."
fi

# Esegui l'installazione di Fuse, se non è già installato
if ! dpkg -l | grep -q rsync; then
    install_rsync
else
    echo "RSync è già installato."
fi

# Esegui l'installazione di Splix, se non è già installato
if ! dpkg -l | grep -q printer-driver-splix; then
    install_splix
else
    echo "Splix è già installato."
fi

# Esegui l'installazione di uuid-runtime, se non è già installato
if ! dpkg -l | grep -q uuid-runtime; then
    install_uuid_runtime
else
    echo "uuid-runtime è già installato."
fi

# Esegui l'installazione di NCDU, se non è già installato
if ! dpkg -l | grep -q ncdu; then
    install_ncdu
else
    echo "NCDU è già installato."
fi

# Esegui l'installazione di GParted, se non è già installato
if ! dpkg -l | grep -q gparted; then
    install_gparted
else
    echo "GParted è già installato."
fi

# Esegui l'installazione di MusicBrainz - Picard, se non è già installato
if ! command -v snap &> /dev/null || ! snap list | grep -q picard; then
    install_musicbrainz_picard
else
    echo "MusicBrainz - Picard è già installato."
fi

# Esegui l'installazione di FastFetch, se non è già installato
if ! dpkg -l | grep -q fastfetch; then
    install_fastfetch
else
    echo "FastFetch è già installato."
fi

# Imposta la swappiness a 10
configure_swappiness

# Imposta lo swap (zram + file) a 4 GB
configure_swap

# Aggiungi entry al crontab di sistema se non esistono
add_crontab_entry

# Aggiungi entry a /etc/fstab se non esistono
add_fstab_entry

# Copia daemon.json sotto /etc/docker
add_daemon_for_docker

# Timeout di arresto di Docker a 240s (shutdown pulito di Oracle)
configure_docker_stop_timeout

# Bouncer di CrowdSec (firewall): configurazione e riavvio automatico
install_crowdsec_bouncer

# sshd: root no, massimo 3 tentativi, solo l utente pi
configure_sshd_hardening

echo "Configuro la eth0"
sudo sh scripts/configure_eth0.sh

echo "Aggiungo pi user to www-data and docker"
sudo usermod -aG www-data pi
sudo usermod -aG docker pi

echo "Modifico OS per eseguire il container di Oracle-XE"
sudo sh scripts/config_os_for_docker_oracle.sh

echo "Configuro l'accesso a GIT"
sh ssh_key_git/setup_ssh.sh || echo "ATTENZIONE: chiave SSH per git non trovata (non è su git). Generane una nuova con ssh-keygen -t ed25519 -f ssh_key_git/id_ed25519 e aggiungi la .pub su GitHub."

echo "Aggiorno il desktop background"
sh scripts/set_wallpaper.sh

echo "Script completato con successo!"