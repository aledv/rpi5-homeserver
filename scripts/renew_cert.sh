#!/bin/bash
# Rinnovo del certificato Let's Encrypt di mailserver.example.com (certbot standalone sulla porta 80).
# Crontab di root, ogni lunedì alle 04:00 (dal 01/11/2026; prima il giorno 1 del mese).
# - Se mancano più di RENEW_DAYS giorni alla scadenza esce subito: niente stop di NPM, niente notifica.
# - Altrimenti ferma NPM (libera la porta 80), rinnova con un timeout, riavvia sempre NPM e,
#   solo se il certificato è cambiato, il mailserver. Notifica l'esito vero (rinnovato / FALLITO).
# Uso: renew_cert.sh [--check]   (--check: stampa solo i giorni rimasti, non tocca nulla)

set -u

NGINX_PROXY_MANAGER="nginx-proxy-manager"
MAILSERVER="mailserver"
DOMAIN="mailserver.example.com"
CERTBOT_DIR="/mnt/external_drive/mailserver/docker-data/certbot"
CERT="$CERTBOT_DIR/certs/live/$DOMAIN/cert.pem"
CERTBOT_IMAGE="certbot/certbot:v5.9.0@sha256:bc93cb710b413e6b456d622f9b0133b3e109c0a78c2ed9976af43d209b0a1805"
RENEW_DAYS=29          # certbot rinnova sotto i 30 giorni: 29 evita il caso limite "not yet due"
CERTBOT_TIMEOUT=300    # secondi massimi con NPM spento
LOG="/mnt/external_drive/utility/logs/renew_cert_latest.txt"
NOTIFY_URL="http://localhost:5000/notify"

days_left() {
    local end
    end=$(openssl x509 -noout -enddate -in "$CERT" 2>/dev/null | cut -d= -f2) || return 1
    [ -n "$end" ] || return 1
    echo $(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
}

fingerprint() {
    openssl x509 -noout -fingerprint -sha256 -in "$CERT" 2>/dev/null
}

notify() {
    curl -s -m 30 -X POST "$NOTIFY_URL" -F "message=$1" -F "file=@$LOG" > /dev/null
}

if ! DAYS=$(days_left); then
    DAYS=-1  # certificato illeggibile: prova comunque a rinnovare
fi

if [ "${1:-}" = "--check" ]; then
    echo "$DOMAIN: $DAYS giorni alla scadenza (rinnovo sotto i $RENEW_DAYS)"
    exit 0
fi

if [ "$DAYS" -gt "$RENEW_DAYS" ]; then
    exit 0
fi

mkdir -p "$(dirname "$LOG")"
exec > "$LOG" 2>&1
echo "$(date '+%F %T') $DOMAIN: $DAYS giorni alla scadenza, rinnovo"
BEFORE=$(fingerprint)

# Immagine scaricata prima di fermare NPM: il fermo dura solo il rinnovo
docker pull -q "$CERTBOT_IMAGE"

# NPM torna su in ogni caso, anche se lo script si interrompe
trap 'docker start "$NGINX_PROXY_MANAGER" > /dev/null' EXIT

echo "Arresto di $NGINX_PROXY_MANAGER..."
docker stop "$NGINX_PROXY_MANAGER"

echo "Esecuzione di Certbot..."
timeout "$CERTBOT_TIMEOUT" docker run --rm --name certbot-renew \
    -v "$CERTBOT_DIR/certs/:/etc/letsencrypt/" \
    -v "$CERTBOT_DIR/logs/:/var/log/letsencrypt/" \
    -p 80:80 "$CERTBOT_IMAGE" renew --non-interactive
RC=$?
if [ "$RC" -eq 124 ]; then
    echo "Certbot oltre ${CERTBOT_TIMEOUT}s: interrotto"
    docker rm -f certbot-renew > /dev/null 2>&1
fi

echo "Riavvio di $NGINX_PROXY_MANAGER..."
docker start "$NGINX_PROXY_MANAGER"
trap - EXIT

AFTER=$(fingerprint)
if [ "$RC" -eq 0 ] && [ -n "$AFTER" ] && [ "$AFTER" != "$BEFORE" ]; then
    echo "Certificato nuovo, riavvio di $MAILSERVER..."
    docker restart "$MAILSERVER"
    notify "🔐 Certificato $DOMAIN rinnovato, scade tra $(days_left) giorni. Mailserver riavviato."
else
    notify "❌ Rinnovo certificato $DOMAIN FALLITO (certbot exit $RC, $DAYS giorni alla scadenza). Log allegato."
    exit 1
fi
