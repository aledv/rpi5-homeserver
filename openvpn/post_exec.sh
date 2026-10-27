# Password dell admin letta da openvpn/.env (escluso da git), vedi .env.sample
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
docker exec -it openvpn-as sacli --user "openvpn" --new_pass "${OPENVPN_ADMIN_PASSWORD:?imposta OPENVPN_ADMIN_PASSWORD in openvpn/.env}" SetLocalPassword