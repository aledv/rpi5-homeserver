#!/bin/bash

set -e

sudo find /etc/NetworkManager/system-connections/ -type f -name "*.nmconnection" ! -name "preconfigured.nmconnection" -delete

# Nome della connessione NetworkManager
CONNECTION_NAME="eth0"

# Nome della scheda Ethernet
INTERFACE="eth0"

# Configurazione IP statico
STATIC_IP="192.168.1.100/24"
GATEWAY="192.168.1.1"
DNS="1.1.1.1;"
UUID=$(uuidgen)
TIMESTAMP=$(date +%s)

# Directory per i file di configurazione di NetworkManager
CONNECTION_DIR="/etc/NetworkManager/system-connections"
CONNECTION_FILE="${CONNECTION_DIR}/${CONNECTION_NAME}.nmconnection"

echo "Creazione della configurazione per la connessione Ethernet..."

# Crea il file di configurazione per NetworkManager
sudo tee "${CONNECTION_FILE}" > /dev/null <<EOF
[connection]
id=${CONNECTION_NAME}
uuid=${UUID}
type=ethernet
interface-name=${INTERFACE}
timestamp=${TIMESTAMP}

[ethernet]

[ipv4]
address1=${STATIC_IP},${GATEWAY}
dns=${DNS}
dns-search=${DNS}
method=manual

[ipv6]
addr-gen-mode=stable-privacy
method=ignore

[proxy]
EOF

# Imposta i permessi corretti per il file
sudo chmod 600 "${CONNECTION_FILE}"

# Riavvia NetworkManager per applicare le modifiche
echo "Riavvio di NetworkManager per applicare la nuova configurazione..."
sudo systemctl restart NetworkManager

echo "Configurazione completata:"
echo "- Interfaccia: ${INTERFACE}"
echo "- IP statico: ${STATIC_IP}"
echo "- Gateway: ${GATEWAY}"
echo "- DNS: ${DNS}"
echo "- UUID generato: ${UUID}"