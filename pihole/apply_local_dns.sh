#!/bin/bash
# Allinea i nomi locali di Pi-hole (dns.hosts) al file local_dns_hosts.txt.
# Uso: ./apply_local_dns.sh          applica (il file è la fonte: le voci non presenti nel file vengono tolte)
#      ./apply_local_dns.sh --check  mostra solo le differenze
cd "$(dirname "$0")"
FILE=local_dns_hosts.txt

# Pi-hole appena avviato: aspetta che FTL risponda (max 2 minuti)
for i in $(seq 24); do docker exec pihole pihole-FTL --config dns.hosts >/dev/null 2>&1 && break; sleep 5; done
current=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null) || { echo "Pi-hole non raggiungibile: nomi locali non applicati"; exit 1; }

want=$(grep -vE "^\s*(#|$)" "$FILE" | sed "s/[[:space:]]\+/ /g; s/ *$//" | sort -u)
have=$(echo "$current" | tr -d "[]" | tr "," "\n" | sed "s/^ *//; s/ *$//" | grep -v "^$" | sort -u)

if [ "$want" = "$have" ]; then echo "Nomi locali di Pi-hole: allineati ($(echo "$want" | wc -l) voci)"; exit 0; fi
echo "Nomi locali di Pi-hole: differenze (+ da aggiungere, - da togliere)"
diff <(echo "$have") <(echo "$want") | grep -E "^[<>]" | sed "s/^>/  +/; s/^</  -/"
[ "${1:-}" = "--check" ] && exit 0

json=$(echo "$want" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
docker exec pihole pihole-FTL --config dns.hosts "$json" >/dev/null && docker exec pihole pihole reloaddns >/dev/null && echo "Nomi locali di Pi-hole applicati"
