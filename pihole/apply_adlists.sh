#!/bin/bash
# Allinea le liste di blocco di Pi-hole (tabella adlist di gravity.db) al file adlists.txt e aggiorna gravity.
# Uso: ./apply_adlists.sh          applica (il file è la fonte: le liste non presenti vengono tolte)
#      ./apply_adlists.sh --check  mostra solo le differenze
cd "$(dirname "$0")" || exit 1
want=$(grep -vE "^\s*(#|$)" adlists.txt | sed "s/[[:space:]]*$//" | sort -u)
have=$(docker exec pihole pihole-FTL sqlite3 -readonly /etc/pihole/gravity.db "select address from adlist where type=0" | sort -u) \
  || { echo "Pi-hole non raggiungibile"; exit 1; }
if [ "$want" = "$have" ]; then echo "Liste di blocco: allineate ($(echo "$want" | wc -l))"; exit 0; fi
echo "Liste di blocco: differenze (+ da aggiungere, - da togliere)"
diff <(echo "$have") <(echo "$want") | grep -E "^[<>]" | sed "s/^>/  +/; s/^</  -/"
[ "${1:-}" = "--check" ] && exit 0
sql=""
while read -r u; do [ -n "$u" ] && sql+="delete from gravity where adlist_id in (select id from adlist where address='$u'); delete from adlist_by_group where adlist_id in (select id from adlist where address='$u'); delete from adlist where type=0 and address='$u';"; done < <(comm -23 <(echo "$have") <(echo "$want"))
while read -r u; do [ -n "$u" ] && sql+="insert into adlist (address, enabled, comment) values ('$u', 1, 'adlists.txt');"; done < <(comm -13 <(echo "$have") <(echo "$want"))
docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db "$sql" && docker exec pihole pihole -g >/dev/null && echo "Liste di blocco applicate, gravity aggiornata"
