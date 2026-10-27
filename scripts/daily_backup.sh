#!/bin/bash
# Backup notturno di rpi5 (lanciato dal crontab di root alle 02:00 (spostato dalle 00:00 il 26/09/2026 per non sovrapporsi ai report automatici di Oracle)).
# Segreti e parametri (PLEX_TOKEN, NEXTCLOUD_USER, KUMA_PUSH_URL, PAPERLESS_TOKEN) da .env nella stessa cartella, escluso da git: vedi scripts/.env.sample
# Codice di uscita: 0 = tutto ok · 1 = backup ok ma qualche passo di manutenzione è fallito · 2 = backup Backrest fallito
# Dal 14/10/2026 il backup è uno snapshot restic fatto da Backrest (my_rpi_scripts/backrest) verso un rest-server in LAN
# (backup server), al posto dello specchio rsync: storico 14 giorni + 8 settimane + 6 mesi, esclusioni in backrest/setup_config.py.
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"

declare -a SUMMARY=()
MAINT_FAILED=0
# Report con i soli errori (allegato alla notifica solo se qualcosa è fallito); il log completo resta in logs/
ERR_REPORT="${ERR_REPORT:-/mnt/external_drive/utility/logs/daily_backup_errors.txt}"
: > "$ERR_REPORT"
STEP_OUT=$(mktemp); trap 'rm -f "$STEP_OUT"' EXIT

report_error() {  # $1 = titolo, $2 = file con l'output del passo fallito (ultime 40 righe)
    { echo "=== $1"; tail -n 40 "$2"; echo; } >> "$ERR_REPORT"
}

log_time() {
    echo "Current time : $(date +"%T")"
}

# Esegue un passo di manutenzione e ne registra l'esito (un errore qui non blocca il backup)
step() {
    local name="$1"; shift
    echo; echo "=== $name"
    "$@" 2>&1 | tee "$STEP_OUT"; local rc=${PIPESTATUS[0]}
    if [ $rc -eq 0 ]; then SUMMARY+=("OK      $name"); else SUMMARY+=("ERRORE  $name (codice $rc)"); MAINT_FAILED=1; report_error "$name (codice $rc)" "$STEP_OUT"; fi
    log_time
}

log_time

for folder in Movies Music Photo "Serie TV"; do
    step "Nextcloud: scansione Media/$folder" docker exec -u www-data nextcloud php occ files:scan --path="${NEXTCLOUD_USER}/files/Media/$folder"
done

# full-upgrade (non solo upgrade): installa anche kernel e pacchetti Raspberry Pi che richiedono nuove dipendenze
step "Sistema: apt update/full-upgrade" bash -c 'export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -qq update && sudo -E apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade && sudo apt-get -y autoclean && sudo apt-get -y autoremove'
step "Sistema: snap refresh" sudo snap refresh
step "PhotoPrism: indicizzazione" docker exec photoprism photoprism index --cleanup
# Paperless: documenti nuovi/modificati/cancellati in Nextcloud → Paperless, poi dump del database (i file di
# Postgres copiati "a caldo" non sono affidabili; con il dump il ripristino è sicuro)
step "Paperless: sincronizzazione da Nextcloud" env NEXTCLOUD_USER="$NEXTCLOUD_USER" PAPERLESS_TOKEN="$PAPERLESS_TOKEN" python3 "$(dirname "$0")/paperless_sync.py"
step "Paperless: dump del database" bash -c 'mkdir -p /mnt/external_drive/paperless/export && docker exec paperless-db pg_dump -U paperless paperless | gzip > /mnt/external_drive/paperless/export/paperless-db.sql.gz.tmp && mv /mnt/external_drive/paperless/export/paperless-db.sql.gz.tmp /mnt/external_drive/paperless/export/paperless-db.sql.gz'
# Dump di tutti gli altri database (14/10/2026): i file copiati "a caldo" non sono affidabili, il dump sì.
# Un file per database in /mnt/external_drive/db_dumps (sovrascritto ogni notte: lo storico lo tiene il backup restic).
dump_one() {  # $1 = container, $2 = comando di dump dentro il container
    local out="/mnt/external_drive/db_dumps/$1.sql.gz"
    if docker exec "$1" sh -c "$2" | gzip > "$out.tmp" && [ "${PIPESTATUS[0]}" -eq 0 ]; then
        mv "$out.tmp" "$out" && echo "$1: ok ($(du -h "$out" | cut -f1))"
    else
        echo "$1: FALLITO"; return 1
    fi
}
dump_databases() {
    local rc=0 c
    mkdir -p /mnt/external_drive/db_dumps && chmod 700 /mnt/external_drive/db_dumps
    for c in nextcloud_db photoprism_db nginx-proxy-manager_db; do
        dump_one "$c" 'mariadb-dump -uroot -p"${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}" --all-databases --single-transaction --routines --events' || rc=1
    done
    dump_one umami-db 'pg_dumpall -U "$POSTGRES_USER"' || rc=1
    return $rc
}
step "Database: dump di Nextcloud, PhotoPrism, NPM, Umami" dump_databases
# Copie coerenti dei database SQLite (14/10/2026): il file vivo copiato mentre l'app scrive può essere incoerente.
# API di backup di SQLite (legge in sola lettura, gestisce il WAL) verso /mnt/external_drive/db_dumps/sqlite/<servizio>_<file>.
SQLITE_DBS=(
    vaultwarden/db.sqlite3
    uptime-kuma/kuma.db
    homeassistant/config/home-assistant_v2.db
    homeassistant/config/zigbee.db
    "plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    roundcube/db/sqlite.db
    beszel/beszel_data/data.db
    camera_dashboard/data/recordings.db
    speedtest-tracker/database.sqlite
    paperless/data/llm_index/llmindex.db
)
sqlite_copies() {
    local rc=0 f out
    mkdir -p /mnt/external_drive/db_dumps/sqlite && chmod 700 /mnt/external_drive/db_dumps/sqlite
    for f in "${SQLITE_DBS[@]}"; do
        [ -f "/mnt/external_drive/$f" ] || { echo "$f: non trovato"; continue; }
        out="/mnt/external_drive/db_dumps/sqlite/$(echo "${f%%/*}_$(basename "$f")" | tr ' ' '_')"
        if python3 -c "import sqlite3,sys; s=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro',uri=True,timeout=60); d=sqlite3.connect(sys.argv[2]); s.backup(d); d.close(); s.close()" "/mnt/external_drive/$f" "$out.tmp"; then
            mv "$out.tmp" "$out" && echo "$f: ok ($(du -h "$out" | cut -f1))"
        else
            echo "$f: FALLITO"; rc=1
        fi
    done
    return $rc
}
step "Database: copie coerenti dei database SQLite" sqlite_copies
step "Plex: refresh librerie" curl -sf "http://192.168.1.100:32400/library/sections/all/refresh?X-Plex-Token=${PLEX_TOKEN}"

# Serve un riavvio? (kernel nuovo installato o file /run/reboot-required): messaggio dedicato, ogni notte finché non si riavvia
reboot_reason() {
    # Kernel avviato dal firmware: quello indicato in config.txt (kernel8.img, impostato a suo tempo per Oracle), altrimenti kernel_2712.img.
    # Se il file è più recente dell'avvio, un aggiornamento ha installato un kernel che non è ancora in uso.
    local kimg boot
    kimg=/boot/firmware/$(sed -n 's/^kernel=//p' /boot/firmware/config.txt | tail -1)
    [ "$kimg" = /boot/firmware/ ] && kimg=/boot/firmware/kernel_2712.img
    boot=$(date -d "$(uptime -s)" +%s)
    if [ -f /run/reboot-required ]; then echo "richiesto dagli aggiornamenti ($(tr '\n' ' ' < /run/reboot-required.pkgs 2>/dev/null))"
    elif [ -f "$kimg" ] && [ "$(stat -c %Y "$kimg")" -gt "$boot" ]; then echo "kernel aggiornato il $(date -r "$kimg" '+%d/%m %H:%M') (in uso: $(uname -r))"
    fi
}
REBOOT_REASON=$(reboot_reason)
if [ -n "$REBOOT_REASON" ]; then
    SUMMARY+=("AVVISO  Serve un riavvio: $REBOOT_REASON")
    curl -s -X POST http://localhost:5000/notify -F "message=Message from RPi5: serve un riavvio - $REBOOT_REASON" > /dev/null
fi

echo; echo "=== Backup disco (Backrest -> rest-server)"
# Avvia il piano "tr-004" via API e aspetta la fine (snapshot, poi pulizia secondo la conservazione)
BR_ENV=/mnt/external_drive/my_rpi_scripts/backrest/.env
BR_PASS=$(sed -n 's/^BACKREST_API_PASSWORD=//p' "$BR_ENV")
HTTP=$(curl -sS -o "$STEP_OUT" -w '%{http_code}' -u "daily-backup:$BR_PASS" -X POST -H 'Content-Type: application/json' \
    -d '{"value":"tr-004"}' http://localhost:9898/v1.Backrest/Backup 2>&1)
if [ "$HTTP" = 200 ]; then BACKUP_RC=0; else BACKUP_RC=2; fi
cat "$STEP_OUT"; echo
# Ultimi snapshot nel repository (data, dimensione)
( set -a; . "$BR_ENV"; set +a
  docker exec -e RESTIC_REPOSITORY=rest:http://192.168.1.101:8000/pi/ -e RESTIC_PASSWORD -e RESTIC_REST_USERNAME=pi -e RESTIC_REST_PASSWORD \
      backrest restic snapshots --latest 3 --compact ) 2>&1 | tail -n 8
log_time
if [ $BACKUP_RC -eq 0 ]; then SUMMARY+=("OK      Backup Backrest (restic)")
else SUMMARY+=("ERRORE  Backup Backrest (HTTP $HTTP)"); report_error "Backup Backrest (HTTP $HTTP)" "$STEP_OUT"; fi

echo; echo "=== RIEPILOGO"
printf '%s\n' "${SUMMARY[@]}"
if [ -s "$ERR_REPORT" ]; then
    { echo "Backup RPi5 del $(date '+%d/%m/%Y'): solo gli errori (log completo in /mnt/external_drive/utility/logs)"; echo
      printf '%s\n' "${SUMMARY[@]}" | grep -v '^OK'; echo; cat "$ERR_REPORT"; } > "$ERR_REPORT.tmp" && mv "$ERR_REPORT.tmp" "$ERR_REPORT"
fi

# Uptime Kuma (monitor push "daily-backup"): up se il backup Backrest è andato, down altrimenti; senza push per 26 ore Kuma avvisa
if [ -n "${KUMA_PUSH_URL:-}" ]; then
    [ $BACKUP_RC -eq 0 ] && KUMA_STATUS=up || KUMA_STATUS=down
    curl -fsS -m 10 -G "$KUMA_PUSH_URL" --data-urlencode "status=$KUMA_STATUS" --data-urlencode "msg=backrest $BACKUP_RC, manutenzione $([ $MAINT_FAILED -eq 0 ] && echo ok || echo con errori)" >/dev/null || echo "Push a Uptime Kuma non riuscito"
fi

if [ $BACKUP_RC -ne 0 ]; then exit $BACKUP_RC; fi
if [ $MAINT_FAILED -ne 0 ]; then exit 1; fi
exit 0
