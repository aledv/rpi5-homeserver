#!/bin/bash

# Quando attivi set -e, lo script si interrompe immediatamente se un comando restituisce un codice di uscita diverso da zero (cioè se il comando fallisce).
set -e

# Percorso della directory principale
main_folder="."

# Modalità solo verifica: ./install_containers.sh --check
# Non copia nulla e non riavvia nulla: mostra quali file sono diversi da quelli installati
# e quali container verrebbero ricreati (confronto dell'hash della configurazione compose).
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Controllo preliminare: i segreti non sono su git. Ogni servizio con .env.sample
# deve avere il suo .env compilato, altrimenti i container partirebbero con password vuote.
check_secrets() {
    local missing=()
    for sample in "$main_folder"/*/.env.sample; do
        [ -f "$sample" ] || continue
        local env="${sample%.sample}"
        if [ ! -f "$env" ]; then
            missing+=("$env (manca: crealo da $(basename "$sample"))")
        elif grep -q "<DA_COMPILARE>" "$env" || grep -qE '^[A-Z_]+=\s*$' "$env"; then
            missing+=("$env (ci sono valori da compilare)")
        fi
    done
    for f in ddclient/ddclient.conf mailserver/mailserver.env scripts/rclone.conf; do
        [ -f "$f" ] || missing+=("$f (manca: crealo da $f.sample)")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERRORE: segreti mancanti (non sono su git, recuperali da Vaultwarden/backup):"
        printf '  - %s\n' "${missing[@]}"
        [ "$CHECK" = 1 ] && return 0
        exit 1
    fi
    echo "Controllo segreti: tutti i .env e i file di configurazione sono presenti."
}

# Copia dei file richiesti nelle destinazioni specifiche
copy_files() {
    echo "Copia dei file richiesti..."


    # Copia ddclient.conf sotto /mnt/external_drive/ddclient
    if [ -f "ddclient/ddclient.conf" ]; then
        sudo mkdir -p /mnt/external_drive/ddclient && sudo cp "ddclient/ddclient.conf" /mnt/external_drive/ddclient
        echo "File ddclient.conf copiato in /mnt/external_drive/ddclient."
    else
        echo "File ddclient.conf non trovato: crealo da ddclient/ddclient.conf.sample (non è su git)."
    fi

    # Copia glances.conf sotto /mnt/external_drive/glances
    if [ -f "glances/glances.conf" ]; then
        sudo mkdir -p /mnt/external_drive/glances && sudo cp "glances/glances.conf" /mnt/external_drive/glances
        echo "File glances.conf copiato in /mnt/external_drive/glances."
    else
        echo "File glances.conf non trovato."
    fi

    # Copia smb.conf sotto /mnt/external_drive/samba
    if [ -f "samba/smb.conf" ]; then
        sudo mkdir -p /mnt/external_drive/samba && sudo cp "samba/smb.conf" /mnt/external_drive/samba
        echo "File smb.conf copiato in /mnt/external_drive/samba."
    else
        echo "File smb.conf non trovato."
    fi

    # Copia la config di homepage sotto /mnt/external_drive/homepage
    if [ -d "homepage/config" ] && [ "$(ls -A homepage/config)" ]; then
        sudo mkdir -p /mnt/external_drive/homepage && sudo cp -r homepage/config/* /mnt/external_drive/homepage
        echo "File copiati in /mnt/external_drive/homepage."
    else
        echo "Cartella homepage/config vuota o non trovata."
    fi

    # Creo /mnt/external_drive/utility se non esiste
    sudo mkdir -p /mnt/external_drive/utility
    sudo chmod 775 /mnt/external_drive/utility

    # Copia daily_backup.sh sotto /mnt/external_drive/utility
    if [ -f "scripts/daily_backup.sh" ]; then
        sudo cp "scripts/daily_backup.sh" /mnt/external_drive/utility/
        sudo chmod +x /mnt/external_drive/utility/daily_backup.sh
        [ -f "scripts/.env" ] && sudo install -m 600 "scripts/.env" /mnt/external_drive/utility/.env || echo "ATTENZIONE: crea scripts/.env da scripts/.env.sample (PLEX_TOKEN)"
        echo "File daily_backup.sh copiato in /mnt/external_drive/utility."
    else
        echo "File daily_backup.sh non trovato."
    fi
    
    # Copia renew_cert.sh sotto /mnt/external_drive/utility
    if [ -f "scripts/renew_cert.sh" ]; then
        sudo cp "scripts/renew_cert.sh" /mnt/external_drive/utility/
        sudo chmod +x /mnt/external_drive/utility/renew_cert.sh
        echo "File renew_cert.sh copiato in /mnt/external_drive/utility."
    else
        echo "File renew_cert.sh non trovato."
    fi


    # Copia mosquitto.conf sotto /mnt/external_drive/mosquitto/config
    if [ -f "mosquitto/mosquitto.conf" ]; then
        sudo mkdir -p /mnt/external_drive/mosquitto/config && sudo cp "mosquitto/mosquitto.conf" /mnt/external_drive/mosquitto/config
        echo "File mosquitto.conf copiato in /mnt/external_drive/mosquitto/config."
    else
        echo "File mosquitto.conf non trovato."
    fi


    # Copia mailserver.env sotto /mnt/external_drive/mailserver
    if [ -f "mailserver/mailserver.env" ]; then
        sudo mkdir -p /mnt/external_drive/mailserver && sudo cp "mailserver/mailserver.env" /mnt/external_drive/mailserver
        echo "File mailserver.env copiato in /mnt/external_drive/mailserver"
    else
        echo "File mailserver.env non trovato: crealo da mailserver/mailserver.env.sample (non è su git)."
    fi

    # Copia .env sotto /mnt/external_drive/wireguard
    if [ -f "wireguard/.env" ]; then
        sudo mkdir -p /mnt/external_drive/wireguard && sudo cp "wireguard/.env" /mnt/external_drive/wireguard
        echo "File .env copiato in /mnt/external_drive/wireguard"
    else
        echo "File .env non trovato."
    fi

    # Copia collector.yaml sotto /mnt/external_drive/scrutiny/config
    if [ -f "scrutiny/config/collector.yaml" ]; then
        sudo mkdir -p /mnt/external_drive/scrutiny/config && sudo cp "scrutiny/config/collector.yaml" /mnt/external_drive/scrutiny/config
        echo "File collector.yaml copiato in /mnt/external_drive/scrutiny/config"
    else
        echo "File collector.yaml non trovato."
    fi



}

copy_ssh_key_code_server() { 

# Percorsi delle chiavi
KEY_PATH="/mnt/external_drive/code-server/config/.ssh/id_rsa.pub"
AUTHORIZED_KEYS_PATH="/home/pi/.ssh/authorized_keys"

# Verifica se la chiave pubblica esiste
if [ ! -f "$KEY_PATH" ]; then
    echo "Errore: il file della chiave pubblica non esiste in $KEY_PATH"
    exit 1
fi

# Assicurati che la directory .ssh esista
mkdir -p "home/pi/.ssh"

# Controlla se la chiave è già presente in authorized_keys
if grep -q -f "$KEY_PATH" "$AUTHORIZED_KEYS_PATH"; then
    echo "La chiave è già presente in $AUTHORIZED_KEYS_PATH"
else
    # Aggiungi la chiave al file authorized_keys
    cat "$KEY_PATH" >> "$AUTHORIZED_KEYS_PATH"
    echo "Chiave aggiunta a $AUTHORIZED_KEYS_PATH"
fi

# Imposta i permessi corretti
chmod 700 "/home/pi/.ssh"
chmod 600 "$AUTHORIZED_KEYS_PATH"

echo "Configurazione SSH completata."
}

# File installati da copy_files: sorgente nel repo|file installato (da tenere allineato a copy_files)
INSTALLED_FILES=(
    "ddclient/ddclient.conf|/mnt/external_drive/ddclient/ddclient.conf"
    "glances/glances.conf|/mnt/external_drive/glances/glances.conf"
    "samba/smb.conf|/mnt/external_drive/samba/smb.conf"
    "scripts/daily_backup.sh|/mnt/external_drive/utility/daily_backup.sh"
    "scripts/.env|/mnt/external_drive/utility/.env"
    "scripts/renew_cert.sh|/mnt/external_drive/utility/renew_cert.sh"
    "mosquitto/mosquitto.conf|/mnt/external_drive/mosquitto/config/mosquitto.conf"
    "mailserver/mailserver.env|/mnt/external_drive/mailserver/mailserver.env"
    "wireguard/.env|/mnt/external_drive/wireguard/.env"
    "scrutiny/config/collector.yaml|/mnt/external_drive/scrutiny/config/collector.yaml"
    "scripts/daemon.json|/etc/docker/daemon.json"
)

check_only() {
    local item src dst f
    echo "== File di configurazione (repo -> installato)"
    for item in "${INSTALLED_FILES[@]}"; do
        src="${item%%|*}"; dst="${item#*|}"
        if [ ! -f "$src" ]; then printf '  %-11s %s\n' "assente" "$src (non è nel repo)"
        elif ! sudo test -f "$dst"; then printf '  %-11s %s\n' "NUOVO" "$dst"
        elif sudo cmp -s "$src" "$dst"; then printf '  %-11s %s\n' "uguale" "$dst"
        else printf '  %-11s %s\n' "DIVERSO" "$dst"; fi
    done
    if [ -d homepage/config ]; then
        for f in homepage/config/*; do
            dst="/mnt/external_drive/homepage/$(basename "$f")"
            if ! sudo test -f "$dst"; then printf '  %-11s %s\n' "NUOVO" "$dst"
            elif sudo cmp -s "$f" "$dst"; then printf '  %-11s %s\n' "uguale" "$dst"
            else printf '  %-11s %s\n' "DIVERSO" "$dst"; fi
        done
    fi
    echo
    if docker network ls --format '{{.Name}}' | grep -qx "shared_network"; then
        echo "== Rete shared_network: presente"
    else
        echo "== Rete shared_network: DA CREARE"
    fi
    echo
    echo "== Container: configurazione compose confrontata con quella in esecuzione"
    local dir proj svc want have name n_ok=0 n_diff=0
    for dir in "$main_folder"/*/; do
        dir="${dir%/}"
        [ -f "$dir/docker-compose.yml" ] || continue
        proj=$(cd "$dir" && docker compose config --format json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))' 2>/dev/null)
        for svc in $(cd "$dir" && docker compose config --services 2>/dev/null); do
            want=$(cd "$dir" && docker compose config --hash "$svc" 2>/dev/null | awk '{print $2}')
            name=$(docker ps -a --filter "label=com.docker.compose.project=$proj" --filter "label=com.docker.compose.service=$svc" --format '{{.Names}}' | head -1)
            if [ -z "$name" ]; then
                printf '  %-13s %s\n' "NON AVVIATO" "$dir/$svc"; n_diff=$((n_diff+1)); continue
            fi
            have=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.config-hash"}}' "$name")
            if [ "$want" = "$have" ]; then n_ok=$((n_ok+1))
            else printf '  %-13s %s (container %s)\n' "DA RICREARE" "$dir/$svc" "$name"; n_diff=$((n_diff+1)); fi
        done
        [ -f "$dir/build.sh" ] && printf '  %-13s %s\n' "(build)" "$dir: build.sh verrebbe rieseguito"
    done
    echo "  invariati: $n_ok · da ricreare o avviare: $n_diff"
    echo
    echo "== Pi-hole"
    ./pihole/apply_local_dns.sh --check | sed "s/^/  /"
    echo
    echo "Solo verifica: nessuna modifica fatta."
}

if [ "$CHECK" = 1 ]; then
    check_secrets
    check_only
    exit 0
fi

# Verifica che i segreti (esclusi da git) siano presenti
check_secrets

# Copia i file richiesti
copy_files
copy_ssh_key_code_server

# Creo la shared_network con subnet IPv4 172.20.0.0/16
NETWORK_NAME="shared_network"
SUBNET="172.20.0.0/16"
GATEWAY="172.20.0.1"

# Controlla se la rete esiste già
if docker network ls | grep -q "$NETWORK_NAME"; then
    echo "La rete '$NETWORK_NAME' esiste già. Nessuna azione necessaria."
else
    echo "Creazione della rete '$NETWORK_NAME'..."
    docker network create \
        --driver bridge \
        --subnet="$SUBNET" \
        --gateway="$GATEWAY" \
        "$NETWORK_NAME"

    if [ $? -eq 0 ]; then
        echo "Rete '$NETWORK_NAME' creata con successo."
    else
        echo "Errore durante la creazione della rete '$NETWORK_NAME'."
        exit 1
    fi
fi

# Loop sulle subfolder
for dir in "$main_folder"/*; do
    if [ -d "$dir" ]; then
        # Verifica se sia presente il file build.sh e docker-compose.yml
        if [ -f "$dir/build.sh" ] && [ -f "$dir/docker-compose.yml" ]; then
            echo "Trovato build.sh e docker-compose.yml in $dir. Eseguo build.sh e docker-compose..."
            # Esegui build.sh
            (cd "$dir" && sudo chmod +x build.sh && sudo ./build.sh)
            # Esegui docker-compose
            (cd "$dir" && sudo docker compose down && sudo docker compose up -d --force-recreate)
        elif [ -f "$dir/docker-compose.yml" ]; then
            echo "Trovato solo docker-compose.yml in $dir. Eseguo docker-compose..."
            # Esegui solo docker-compose
            (cd "$dir" && sudo docker compose down && sudo docker compose up -d --force-recreate)
        fi
    fi
done

# Nomi locali di Pi-hole (xxx.example.com -> server da casa/VPN): pihole/local_dns_hosts.txt
./pihole/apply_local_dns.sh
