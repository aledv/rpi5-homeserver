#!/bin/bash
# Aggiorna l indice di Nextcloud quando un servizio ha salvato un file direttamente nella cartella dati, così il file
# compare subito su Mac e iPhone. Ogni servizio lascia un file flag; cron di root ogni minuto (scripts/crontab.copy).
#   scanner-buttons (tasto PDF)        -> cartella Scansioni
# NEXTCLOUD_USER dal .env accanto allo script (copia di scripts/.env in utility/)
NEXTCLOUD_USER=$(grep -h "^NEXTCLOUD_USER=" "$(dirname "$0")/.env" 2>/dev/null | tail -1 | cut -d= -f2-)
[ -n "$NEXTCLOUD_USER" ] || exit 0
rescan() {  # <file flag> <cartella Nextcloud>
    [ -f "$1" ] || return 0
    rm -f "$1"
    docker exec -u www-data nextcloud php occ files:scan --path="$NEXTCLOUD_USER/files/$2" -q
}
rescan /mnt/external_drive/scanner-buttons/flags/nextcloud-rescan Scansioni
