#!/bin/bash
# Cancella le registrazioni delle telecamere più vecchie di KEEP_DAYS giorni (richiesta dell utente, 2026-10-01)
# e le cartelle orarie rimaste vuote. Lanciato ogni notte dal crontab di root (scripts/crontab.copy).
# La cartella è esclusa dal backup notturno (rsync --exclude pure-ftpd/data/test).
REC_DIR="${REC_DIR:-/mnt/external_drive/pure-ftpd/data/test}"
KEEP_DAYS="${KEEP_DAYS:-7}"
[ -d "$REC_DIR" ] || { echo "cartella $REC_DIR non trovata"; exit 1; }
n=$(find "$REC_DIR" -type f \( -name "*.mp4" -o -name "*.jpg" \) -mtime +"$KEEP_DAYS" -print -delete | wc -l)
find "$REC_DIR" -mindepth 2 -type d -empty -delete
echo "$(date "+%F %T") registrazioni cancellate (> $KEEP_DAYS giorni): $n file; spazio usato ora: $(du -sh "$REC_DIR" | cut -f1)"
