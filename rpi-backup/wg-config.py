#!/usr/bin/env python3
"""Stampa la configurazione WireGuard del RPi4 rpi-backup, presa dal client "RPi-Backup" di wg-easy sul .30.
Da lanciare sul .30 e passare direttamente al RPi4 (contiene la chiave privata: non salvarla altrove):
  ssh pi@<ip-del-pi5> sudo python3 /mnt/external_drive/my_rpi_scripts/rpi-backup/wg-config.py | ssh pi@<ip> sudo install -m 600 /dev/stdin /etc/wireguard/wg0.conf
AllowedIPs contiene solo 10.102.0.1, il .30 visto dal container wg-easy (rete "network" di wireguard/docker-compose.yml):
non 192.168.1.100, perché a casa l'endpoint risolve proprio in 192.168.1.100 e si creerebbe un loop di routing.
Endpoint: il nome pubblico; dalla sede remota risolve nell'IP pubblico di casa (aggiornato da ddclient)."""

import sqlite3

DB = "file:/mnt/external_drive/wireguard/config/wg-easy.db?mode=ro"
c = sqlite3.connect(DB, uri=True)
priv, psk, ip = c.execute(
    "select private_key, pre_shared_key, ipv4_address from clients_table where name = ?",
    ("RPi-Backup",),
).fetchone()
(pub,) = c.execute(
    "select public_key from interfaces_table where name = 'wg0'"
).fetchone()
host, port = c.execute(
    "select host, port from user_configs_table where id = 'wg0'"
).fetchone()
print(f"""[Interface]
PrivateKey = {priv}
Address = {ip}/32

[Peer]
PublicKey = {pub}
PresharedKey = {psk}
AllowedIPs = 10.102.0.1/32
Endpoint = {host}:{port}
PersistentKeepalive = 25""")
