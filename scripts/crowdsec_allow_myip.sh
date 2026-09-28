#!/bin/bash
# Tiene l'IP pubblico di casa nell'allowlist "casa" di CrowdSec, così non verrà mai bloccato.
# L'IP cambia (DDNS): gira ogni 5 minuti da crontab (utente pi) e aggiorna solo se è cambiato.
set -u
LIST=casa
ip=$(curl -s -m 10 https://api.ipify.org)
[[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip=$(getent ahostsv4 "${DDNS_HOST:-example.com}" | awk 'NR==1{print $1}')
[[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "IP pubblico non trovato"; exit 1; }

cs() { docker exec crowdsec cscli "$@"; }
cs allowlists inspect "$LIST" >/dev/null 2>&1 || cs allowlists create "$LIST" -d "IP pubblico di casa (aggiornato da crowdsec_allow_myip.sh)" >/dev/null
current=$(cs allowlists inspect "$LIST" -o json | python3 -c 'import json,sys; print(" ".join(i["value"] for i in (json.load(sys.stdin).get("items") or [])))')

[[ " $current " == *" $ip "* ]] && exit 0
for old in $current; do cs allowlists remove "$LIST" "$old" >/dev/null; done
cs allowlists add "$LIST" "$ip" -d "IP pubblico casa dal $(date +%F)" >/dev/null
cs decisions delete --ip "$ip" >/dev/null 2>&1
echo "$(date '+%F %T') allowlist $LIST: ${current:-vuota} -> $ip"
