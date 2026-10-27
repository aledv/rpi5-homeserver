#!/bin/sh
# Avvisi UPS: legge lo stato da apcupsd (NIS) e manda i cambi di stato al notifier del Pi
# (Telegram + email). Se il notifier non risponde (es. blackout: Pi senza UPS), i messaggi restano in coda
# e partono appena torna raggiungibile.
NIS="${NIS:-192.168.1.101:3551}"
NOTIFY="${NOTIFY_URL:-http://192.168.1.100:5000/notify}"
POLL="${POLL:-15}"
WARN_MIN="${WARN_MIN:-12}"         # preavviso: autonomia residua sotto questi minuti
SHUT_MIN="${SHUT_MIN:-8}"          # soglia di spegnimento (minuti di autonomia)
TIMEOUT_MIN="${TIMEOUT_MIN:-0}"    # se >0: apcupsd spegne comunque dopo questi minuti a batteria
QUEUE=/tmp/ups-queue; : > "$QUEUE"; [ -n "${START_MSG:-}" ] && printf '%s\n' "$START_MSG" >> "$QUEUE"
NAME="${NAME:-UPS DELL3080mini (DELL + router + allarme)}"
HOST="${HOST:-il DELL}"            # cosa viene spento

ts() { date '+%d/%m %H:%M'; }
queue() { printf '%s\n' "$1" >> "$QUEUE"; }
flush() {
    [ -s "$QUEUE" ] || return
    tmp="$QUEUE.new"; : > "$tmp"
    while IFS= read -r msg; do
        curl -s -m 10 -o /dev/null -f -X POST "$NOTIFY" -F "message=$msg" || printf '%s\n' "$msg" >> "$tmp"
    done < "$QUEUE"
    mv "$tmp" "$QUEUE"
}
field() { printf '%s\n' "$STATUS_TXT" | sed -n "s/^$1 *: *//p" | awk '{print $1}'; }

state=""; since=0; warned=0; commfail=0
while true; do
    if STATUS_TXT=$(apcaccess -h "$NIS" status 2>/dev/null) && [ -n "$STATUS_TXT" ]; then
        if [ "$commfail" -ge 4 ]; then queue "✅ $NAME: di nuovo raggiungibile ($(ts))"; fi
        commfail=0
        st=$(field STATUS); left=$(field TIMELEFT); charge=$(field BCHARGE)
        left_i=${left%.*}; charge_i=${charge%.*}
        case "$st" in
            *ONBATT*)
                if [ "$state" != onbatt ]; then
                    since=$(date +%s); warned=0; state=onbatt
                    extra=""; [ "$TIMEOUT_MIN" -gt 0 ] && extra=" Se non torna entro ${TIMEOUT_MIN} min, $HOST viene spento in modo pulito."
                    queue "⚡ $NAME: corrente mancata alle $(ts), a batteria. Carica ${charge_i}%, autonomia stimata ${left_i} min.$extra"
                fi
                if [ "$warned" = 0 ] && [ -n "$left_i" ] && [ "$left_i" -le "$WARN_MIN" ]; then
                    warned=1
                    queue "🔋 $NAME: autonomia residua ${left_i} min (carica ${charge_i}%). Sotto ${SHUT_MIN} min $HOST viene spento."
                fi ;;
            *ONLINE*)
                if [ "$state" = onbatt ]; then
                    dur=$(( ($(date +%s) - since) )); m=$((dur / 60)); s=$((dur % 60))
                    queue "✅ $NAME: corrente tornata alle $(ts), dopo ${m} min ${s} s a batteria. Carica ${charge_i}%."
                fi
                state=online ;;
            *LOWBATT*)
                [ "$state" = lowbatt ] || queue "🪫 $NAME: BATTERIA SCARICA alle $(ts) (carica ${charge_i}%, ${left_i} min)."
                state=lowbatt ;;
            *COMMLOST*)
                commfail=$((commfail + 1)) ;;
        esac
    else
        commfail=$((commfail + 1))
        [ "$commfail" -eq 4 ] && queue "⚠️ $NAME: apcupsd non risponde da un minuto ($(ts)): UPS scollegato o servizio fermo?"
    fi
    flush
    sleep "$POLL"
done
