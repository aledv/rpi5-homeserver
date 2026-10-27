#!/usr/bin/env python3
"""Genera /mnt/external_drive/backrest/config/config.json (repository, piano, esclusioni, utenti) dai segreti in .env.

Così la configurazione di Backrest sta nel repo (questo file) e si ricostruisce da zero con install_containers.sh.
Le modifiche fatte dall interfaccia vanno riportate qui, altrimenti la prossima esecuzione le sovrascrive.
Uso: sudo ./setup_config.py   (poi docker compose restart backrest; con un backup in corso: --api, applica senza riavvio)
"""
import base64
import json
import subprocess
import sys
from pathlib import Path

import bcrypt

HERE = Path(__file__).resolve().parent
CONFIG = Path("/mnt/external_drive/backrest/config/config.json")
# Multihost (14/10/2026): Backrest del DELL (my_dell_scripts/backrest) manda qui lo storico delle sue operazioni, così
# questa interfaccia mostra anche i backup del DELL. keyId = identità dell'istanza del DELL (sync.identity.keyId nella sua
# config.json): se il DELL viene reinstallato da zero cambia, va aggiornata qui (e il keyId del Pi nello script del DELL).
# Notifiche (14/10/2026): qualsiasi operazione fallita (backup, pulizia, controllo) -> notifier (Telegram + email).
# Backrest 1.14 non ha ancora il gestore per actionWebhook: si usa un comando curl (il JSON lo costruisce il template).
NOTIFY_URL = "http://192.168.1.100:5000/notify/json"
HOOK_CMD = (
    'curl -fsS -m 20 -H "Content-Type: application/json" -d "{\\"title\\": '
    '$(printf %s {{ .ShellEscape (.JsonMarshal (printf "[RPi5] Backrest: %s FALLITO" .Task)) }}), '
    '\\"message\\": $(printf %s {{ .ShellEscape (.JsonMarshal .Summary) }})}" ' + NOTIFY_URL)
HOOKS = [{"conditions": ["CONDITION_ANY_ERROR"], "actionCommand": {"command": HOOK_CMD}}]
DELL_PEER = {"instanceId": "dell", "keyId": "ed25519.<KEY_ID_DELL_ALTRA_ISTANZA>",
             "permissions": [{"type": "PERMISSION_READ_OPERATIONS", "scopes": ["*"]}]}
env = dict(ln.split("=", 1) for ln in (HERE / ".env").read_text().splitlines() if "=" in ln and not ln.startswith("#"))

# Esclusioni: solo dati che si rigenerano da soli o che non servono a un ripristino (decise con l utente il 14/10/2026)
EXCLUDES = [
    "/userdata/downloads", "/userdata/time_machine_bck", "/userdata/.trash_folder", "/userdata/.Trash-1000",
    "/userdata/pure-ftpd/data/test",
    "/userdata/backrest/cache", "/userdata/backrest/restore",                # cache di restic e ripristini temporanei
    "/userdata/photoprism/storage/cache",                                    # miniature (si rigenerano)
    "/userdata/nextcloud/nextcloud_data/data/appdata_*/preview",             # anteprime di Nextcloud (si rigenerano)
    "/userdata/nextcloud/nextcloud_data/data/nextcloud.log.*",               # log vecchi di Nextcloud
    "/userdata/plex/Library/Application Support/Plex Media Server/Cache",
    "/userdata/plex/Library/Application Support/Plex Media Server/Logs",
    "/userdata/plex/Library/Application Support/Plex Media Server/Crash Reports",
    "/userdata/plex/Library/Application Support/Plex Media Server/Codecs",
    "*-journal",  # giornali temporanei di SQLite: spariscono durante la lettura e danno STATUS_WARNING (25/10/2026); i -wal restano
]
# JPEG generati da PhotoPrism (conversioni di HEIC/RAW/video); i .yml del sidecar (modifiche dell utente) restano
IEXCLUDES = ["/userdata/photoprism/storage/sidecar/**/*.jpg"]


def bhash(pw):
    return base64.b64encode(bcrypt.hashpw(pw.encode(), bcrypt.gensalt())).decode()


old = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
cfg = {
    "modno": old.get("modno", 0) + 1,
    "version": old.get("version", 6),
    "instance": "rpi5",
    "repos": [{
        "id": "dell-4tb",
        "uri": "rest:http://192.168.1.101:8000/pi/",
        "password": env["RESTIC_PASSWORD"],
        "env": ["RESTIC_REST_USERNAME=pi", "RESTIC_REST_PASSWORD=" + env["RESTIC_REST_PASSWORD"]],
        "prunePolicy": {"schedule": {"cron": "0 5 * * 0", "clock": "CLOCK_LOCAL"}, "maxUnusedPercent": 10},
        "checkPolicy": {"schedule": {"cron": "0 5 1 * *", "clock": "CLOCK_LOCAL"}, "readDataSubsetPercent": 2},
        "autoUnlock": True,
        "autoInitialize": True,
        "commandPrefix": {"ioNice": "IO_BEST_EFFORT_LOW", "cpuNice": "CPU_LOW"},
        "hooks": HOOKS,
    }, {
        # Copia offsite (19/10/2026): RPi4 "rpi-backup" in un altra sede, Seagate 4 TB, rest-server raggiunto con il
        # tunnel SSH inverso (offsite-tunnel) su 172.20.0.1:18000. Inizializzato con restic copy dal repo del DELL:
        # stessa password e stessi chunker params. Pulizia e controllo dopo quelli del DELL.
        "id": "offsite",
        "uri": "rest:http://172.20.0.1:18000/pi/",
        "password": env["RESTIC_PASSWORD"],
        "env": ["RESTIC_REST_USERNAME=pi", "RESTIC_REST_PASSWORD=" + env["RESTIC_REST_PASSWORD"]],
        "prunePolicy": {"schedule": {"cron": "0 6 * * 0", "clock": "CLOCK_LOCAL"}, "maxUnusedPercent": 10},
        "checkPolicy": {"schedule": {"cron": "0 6 2 * *", "clock": "CLOCK_LOCAL"}, "readDataSubsetPercent": 1},
        "autoUnlock": True,
        "guid": "b43c9af072a854b4f155b4ca5cb37bcaf14ee90971d0a8a05e3906b8f5339e3c",  # id restic del repo (restic cat config)
        "commandPrefix": {"ioNice": "IO_BEST_EFFORT_LOW", "cpuNice": "CPU_LOW"},
        "hooks": HOOKS,
    }],
    "plans": [{
        "id": "tr-004",
        "repo": "dell-4tb",
        "paths": ["/userdata"],
        "excludes": EXCLUDES,
        "iexcludes": IEXCLUDES,
        "schedule": {"disabled": True},          # lo avvia daily_backup.sh alle 02:00, dopo manutenzione e dump
        "retention": {"policyTimeBucketed": {"daily": 14, "weekly": 8, "monthly": 6}},
    }, {
        "id": "tr-004-offsite",                  # stessi dati verso il RPi4 offsite, dopo il backup delle 02:00
        "repo": "offsite",
        "paths": ["/userdata"],
        "excludes": EXCLUDES,
        "iexcludes": IEXCLUDES,
        "schedule": {"cron": "30 3 * * *", "clock": "CLOCK_LOCAL"},
        "retention": {"policyTimeBucketed": {"daily": 7, "weekly": 8, "monthly": 12}},
    }],
    "auth": {"disabled": False, "users": [
        {"name": "admin", "passwordBcrypt": bhash(env["BACKREST_UI_PASSWORD"])},
        {"name": "daily-backup", "passwordBcrypt": bhash(env["BACKREST_API_PASSWORD"])},
    ]},
}
# identità dell istanza generata da Backrest al primo avvio + client autorizzati (DELL)
cfg["sync"] = {**({"identity": old["sync"]["identity"]} if "identity" in old.get("sync", {}) else {}), "authorizedClients": [DELL_PEER]}
# guid del repository (assegnato da Backrest all'inizializzazione): va conservato
for r in cfg["repos"]:
    g = next((o.get("guid") for o in old.get("repos", []) if o.get("id") == r["id"] and o.get("guid")), None)
    if g:
        r["guid"] = g
    if r.get("guid"):
        r.pop("autoInitialize", None)  # già inizializzato: Backrest rifiuta guid + autoInitialize insieme
if "--api" in sys.argv:  # applica via API (SetConfig) senza riavviare il container
    # le credenziali passano da stdin (curl -K -), non da argv: niente password nei traceback né in ps
    auth = 'user = "daily-backup:%s"\n' % env["BACKREST_API_PASSWORD"]
    got = subprocess.run(["curl", "-sf", "-K", "-", "-X", "POST", "-H", "Content-Type: application/json", "-d", "{}",
                          "http://localhost:9898/v1.Backrest/GetConfig"], input=auth, capture_output=True, text=True)
    if got.returncode:
        sys.exit("GetConfig fallito (curl %d)" % got.returncode)  # l output contiene segreti: non stamparlo
    live = json.loads(got.stdout)
    cfg["modno"] = live.get("modno", 0)
    cfg["sync"]["identity"] = live["sync"]["identity"]
    for r in cfg["repos"]:
        g = next((o.get("guid") for o in live["repos"] if o["id"] == r["id"] and o.get("guid")), None)
        if g:
            r["guid"] = g
        r.pop("autoInitialize", None)
    body = Path("/run/backrest-setconfig.json")
    body.touch(mode=0o600)
    body.write_text(json.dumps(cfg))
    put = subprocess.run(["curl", "-s", "-w", "\n%{http_code}", "-K", "-", "-X", "POST", "-H", "Content-Type: application/json",
                          "--data-binary", "@" + str(body), "http://localhost:9898/v1.Backrest/SetConfig"],
                         input=auth, capture_output=True, text=True)
    body.unlink()
    if not put.stdout.rstrip().endswith("200"):
        sys.exit("SetConfig fallito: " + put.stdout[-400:])
    print("config applicata via API")
    sys.exit(0)
CONFIG.parent.mkdir(parents=True, exist_ok=True)
tmp = CONFIG.with_suffix(".tmp")
tmp.write_text(json.dumps(cfg, indent=2))
tmp.chmod(0o600)
tmp.replace(CONFIG)
print(f"{CONFIG} scritto (modno {cfg['modno']})")
