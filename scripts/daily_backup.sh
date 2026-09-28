#!/bin/bash
# Backup notturno di rpi5 (lanciato dal crontab di root alle 02:00 (spostato dalle 00:00 il 26/09/2026 per non sovrapporsi ai report automatici di Oracle)).
# Segreti e parametri (PLEX_TOKEN, NEXTCLOUD_USER, BACKUP_TARGET) da .env nella stessa cartella, escluso da git: vedi scripts/.env.sample
# Codice di uscita: 0 = tutto ok · 1 = backup ok ma qualche passo di manutenzione è fallito · altro = rsync fallito (codice di rsync)
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"

declare -a SUMMARY=()
MAINT_FAILED=0

log_time() {
    echo "Current time : $(date +"%T")"
}

# Esegue un passo di manutenzione e ne registra l'esito (un errore qui non blocca il backup)
step() {
    local name="$1"; shift
    echo; echo "=== $name"
    "$@"; local rc=$?
    if [ $rc -eq 0 ]; then SUMMARY+=("OK      $name"); else SUMMARY+=("ERRORE  $name (codice $rc)"); MAINT_FAILED=1; fi
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
step "Plex: refresh librerie" curl -sf "http://192.168.1.100:32400/library/sections/all/refresh?X-Plex-Token=${PLEX_TOKEN}"

# Serve un riavvio? (kernel nuovo installato o file /run/reboot-required): messaggio dedicato, ogni notte finché non si riavvia
reboot_reason() {
    # Kernel avviato dal firmware: quello indicato in config.txt (kernel8.img per Oracle), altrimenti kernel_2712.img.
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

echo; echo "=== Backup disco"
sudo rsync -aAXHv --no-specials --no-devices --delete --stats --exclude="downloads" --exclude="pure-ftpd/data/test" --exclude=".Trash-1000" --exclude="time_machine_bck" --exclude=".trash_folder" /mnt/external_drive/ ${BACKUP_TARGET}
RSYNC_RC=$?
log_time
case $RSYNC_RC in
    0)  SUMMARY+=("OK      Backup rsync verso ${BACKUP_TARGET}") ;;
    24) SUMMARY+=("AVVISO  Backup rsync: alcuni file sono spariti durante la copia (codice 24, normale per file temporanei)"); RSYNC_RC=0 ;;
    *)  SUMMARY+=("ERRORE  Backup rsync (codice $RSYNC_RC)") ;;
esac

echo; echo "=== RIEPILOGO"
printf '%s\n' "${SUMMARY[@]}"

if [ $RSYNC_RC -ne 0 ]; then exit $RSYNC_RC; fi
if [ $MAINT_FAILED -ne 0 ]; then exit 1; fi
exit 0
