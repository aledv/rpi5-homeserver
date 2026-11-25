# Raspberry Pi 5 Home Server

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Docker Compose setups and install scripts for running a self-hosted home server on a
**Raspberry Pi 5** with an external drive (DAS/USB disk) mounted at `/mnt/external_drive`. Every service lives in its own folder
with a `docker-compose.yml`; two scripts prepare the OS and bring all containers up.

> This is a real, personal setup published as a reference: take the parts you need and adapt
> paths, domain and hardware to yours rather than running everything as is.

No secrets are stored in this repository: passwords, tokens, domain, e-mail addresses and
usernames are read from local `.env` files that are excluded from git
(see [Configuration and secrets](#configuration-and-secrets)).

## Contents

- [Services](#services)
- [System requirements](#system-requirements)
- [Getting started](#getting-started)
- [Configuration and secrets](#configuration-and-secrets)
- [What the install scripts do](#what-the-install-scripts-do)
- [Notes](#notes)
- [Offsite backup (rpi-backup)](#offsite-backup-rpi-backup)
- [Contributing](#contributing)
- [License](#license)

## Services

- **apcupsd** / **apcupsd-cgi**: APC UPS monitoring daemon and its web interface; `ups-notify` sends power loss/return and low-battery alerts (queued if the notifier is down) and the Pi shuts down cleanly when the battery runs low.
- **backrest**: web UI for restic: nightly encrypted, deduplicated snapshots of `/mnt/external_drive` to a restic rest-server on another machine in the LAN, plus a second copy offsite (see [Offsite backup](#offsite-backup-rpi-backup)). The whole configuration (repositories, plans, retention, exclusions, failure notifications) is generated from `backrest/setup_config.py`, so it can be rebuilt from scratch.
- **beszel**: lightweight server monitoring (hub + agent).
- **code-server**: VS Code in the browser.
- **crowdsec**: collaborative intrusion prevention: reads the Nginx Proxy Manager, SSH and mail server (Postfix/Dovecot) logs and bans attacking IPs on the host firewall (`crowdsec-firewall-bouncer`, installed by `install.sh`); LAN/VPN and your home IP are never banned (`scripts/crowdsec_allow_myip.sh`).
- **ddclient**: dynamic DNS client that keeps your domain pointing to your public IP.
- **docker-socket-proxy**: read-only Docker API for the monitoring containers (homepage, Uptime Kuma, Dozzle, Glances, Beszel), so none of them mounts `/var/run/docker.sock`.
- **dozzle**: real-time Docker log viewer (supports remote agents).
- **glances**: cross-platform system monitoring.
- **homeassistant**: home automation platform (exposes the cameras, the Ring alarm and a BTicino video intercom to Apple HomeKit through its HomeKit bridge; vendored custom components in `homeassistant/custom_components`).
- **homepage**: application dashboard with Docker and service API integrations (bring your own `services.yaml`, `widgets.yaml`, … in `homepage/config/`: `install_containers.sh` copies them to `/mnt/external_drive/homepage`).
- **hp-150nw-monitor**: REST API with the status and toner levels of an HP Color Laser 150nw, for a Homepage widget ([aledv/hp-150nw-monitor](https://github.com/aledv/hp-150nw-monitor)).
- **mailserver**: full mail server (SMTP, IMAP, Rspamd anti-spam) based on docker-mailserver.
- **mosquitto**: MQTT broker.
- **my_telegram_bot**: personal Telegram assistant (music into Plex, documents into Nextcloud, calendar reminders). Its image is **private**: the folder is here so the repository matches the real server one to one, but it cannot be pulled by others.
- **my_transmission_bot**: Telegram bot to control Transmission ([aledv/transmission-telegram-bot](https://github.com/aledv/transmission-telegram-bot)).
- **nextcloud** (+ MariaDB, Redis): self-hosted file sharing and collaboration.
- **notifier_project**: notification relay used by every service and script (POST `/notify` → Telegram + e-mail), [aledv/notify-relay](https://github.com/aledv/notify-relay).
- **nginx-proxy-manager** (+ MariaDB): reverse proxy with Let's Encrypt certificates and access lists.
- **onlyoffice**: online document editor, integrated with Nextcloud.
- **openvpn** / **wireguard**: VPN servers for remote access.
- **paperless** (+ PostgreSQL, Valkey, Tika, Gotenberg): document archive with OCR, full-text search and optional AI features (title/tag suggestions, document chat, semantic search) through an Ollama server on your LAN, or nightly classification with [paperless-ai-classify](https://github.com/aledv/paperless-ai-classify) (`OLLAMA_URL`, e.g. `qwen3:4b-instruct` + `bge-m3` on a CPU-only mini PC). Drop files in `/mnt/external_drive/paperless/consume` (subfolders become tags).
- **photoprism** (+ MariaDB): AI-powered photo management.
- **pihole**: network-wide ad blocker and local DNS. Everything is in the repo: DNS settings as `FTLCONF_*` variables in the compose file (Quad9 + Cloudflare upstreams, DNSSEC, NTP off), blocklists in `pihole/adlists.txt` (applied by `pihole/apply_adlists.sh`, `--check` for a dry run), local records in `pihole/local_dns_hosts.txt` (applied by `pihole/apply_local_dns.sh`).
- **plex**: media server. Its "LAN Networks" setting (`LanNetworksBandwidth` in `Preferences.xml`) lists the home LAN and the VPN networks (the OpenVPN/WireGuard container networks clients are NATed from, plus the client pools), so VPN clients count as local. Those container networks must be private ranges (here `10.101.0.0/24` and `10.102.0.0/24`): with non-RFC1918 addresses Plex treats VPN clients as remote.
- **portainer**: container management UI.
- **pure-ftpd**: FTP server.
- **ring-mqtt**: Ring alarm in Home Assistant through MQTT.
- **roundcube** (+ MariaDB): webmail client with two-factor authentication (TOTP plugin, config applied after the plugin install).
- **samba**: file shares and Time Machine backups.
- **scanservjs**: web UI for a network scanner.
- **scanner-buttons**: the physical buttons of a USB scanner: SCAN → Paperless, PDF → a Nextcloud folder, EMAIL → e-mail, COPY → print. Public image of [sane-scan-buttons](https://github.com/aledv/sane-scan-buttons), configured in the compose file; it owns the scanner and lends it to scanservjs through saned. Needs `NEXTCLOUD_USER` and `PRINTER_QUEUE` in `scanner-buttons/.env`, CUPS on the host for COPY, and the notifier for EMAIL and the confirmations.
- **scrutiny**: S.M.A.R.T. disk health dashboard (supports disks behind JMicron USB RAID enclosures via `jmb39x-q`).
- **speedtest-tracker**: internet connection speed history.
- **stirling-pdf**: local web-based PDF toolkit.
- **transmission**: BitTorrent client.
- **umami** (+ PostgreSQL): privacy-friendly web analytics; `umami_vue` is a small Nextcloud app that embeds the tracker.
- **uptime-kuma**: uptime monitoring and alerting.
- **vaultwarden**: Bitwarden-compatible password manager.
- **website**: my personal site, nginx image built from [aledv/divanni.me](https://github.com/aledv/divanni.me); its Portfolio data is refreshed nightly by `scripts/divanni_repos_update.py`.
- **yi-hack-dashboard** (+ MediaMTX): web dashboard for Yi cameras with yi-hack: live view, recordings, motion stats and notifications ([aledv/yi-hack-cam-dashboard](https://github.com/aledv/yi-hack-cam-dashboard)).

Every image is pinned as `repo:tag@sha256:…`. Instead of Watchtower (which can't see updates for pinned images),
`scripts/image_updates_check.py` (daily cron, needs `skopeo`) looks for a new digest of the same tag or a newer
patch/minor/major version, and `scripts/image_updates_apply.py` applies the safe ones on its own: same-version rebuilds
and patch releases of non-database, non-critical services, with a database dump first, a health check after
`docker compose up -d`, an automatic rollback on failure and one git commit with the new pins. Everything else waits for
a manual `--approve`. Updates you never want are listed in `scripts/image_updates_ignore.txt`.

## System requirements

- Raspberry Pi 5 (tested with 16 GB RAM) running Raspberry Pi OS / Debian 13 "trixie"
- An external drive (DAS or USB disk) mounted at `/mnt/external_drive` (set its UUID in `scripts/fstab.copy`)
- Docker Engine with the Compose plugin (installed by `install.sh`)

## Getting started

1. Start from a clean Raspberry Pi OS image and log in as `pi`, with the DAS connected.
2. Create an SSH key for GitHub and add the public key to your account
   ([guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)):

   ```bash
   ssh-keygen -t ed25519 -C "you@example.com"
   cat ~/.ssh/id_ed25519.pub
   ```

3. Clone the repository:

   ```bash
   git clone git@github.com:aledv/rpi5-homeserver.git
   cd rpi5-homeserver
   ```

4. Create the local configuration (see the next section): every `.env.sample` becomes a `.env`,
   every `*.sample` config file becomes the real file.
5. Prepare the OS, reboot, then start the containers:

   ```bash
   ./install.sh
   sudo reboot
   ./install_containers.sh
   ```

## Configuration and secrets

Nothing sensitive is committed. Each service that needs secrets or personal values has a
`.env.sample` listing the variables; copy it to `.env` in the same folder, fill it in and
restrict its permissions:

```bash
cp paperless/.env.sample paperless/.env
chmod 600 paperless/.env
```

Docker Compose reads `.env` automatically and substitutes `${VARIABLE}` in the compose file.
Common variables are `DOMAIN`, `ADMIN_EMAIL` and the service passwords.

Other files that contain secrets are provided as samples as well:

| Sample | Real file (not in git) |
| --- | --- |
| `ddclient/ddclient.conf.sample` | `ddclient/ddclient.conf` |
| `mailserver/mailserver.env.sample` | `mailserver/mailserver.env` |
| `scripts/rclone.conf.sample` | `scripts/rclone.conf` |
| `scripts/.env.sample` | `scripts/.env` (used by `daily_backup.sh`) |
| `openvpn/.env.sample` | `openvpn/.env` (used by `post_exec.sh`) |
| `ssh_key_git/.env.sample` | `ssh_key_git/.env` (git identity for `setup_ssh.sh`) |

**homepage** configuration is not included (it describes your own services): put your YAML files in
`homepage/config/` (gitignored). Use `{{HOMEPAGE_VAR_...}}` placeholders for passwords and API keys, filled from `homepage/.env` (passed to the container
with `env_file`). Values that start with `{{` must be quoted in YAML.

`install_containers.sh` starts with a `check_secrets` step: it stops with a list of what is
missing if any `.env` is absent, still contains `<DA_COMPILARE>` / empty values, or if one of the
config files above does not exist. Keep a copy of your `.env` files outside the server
(for example in Vaultwarden) — they are the only place where the secrets live.

## What the install scripts do

`install.sh`
- expands the root partition, enables VNC, configures `eth0`
- installs Docker, Fuse, rsync, NCDU, GParted, Picard, fastfetch and printer drivers
- sets swappiness to 10 and the Raspberry Pi swap (zram + file) to 8 GB
- gives Docker 240 s to stop containers at shutdown (clean Oracle/MariaDB shutdown)
- installs the crontab, `/etc/fstab` entries and Docker `daemon.json` from `scripts/`
- installs rsyslog and the CrowdSec firewall bouncer (nftables, auto-restart)
- hardens sshd (`scripts/sshd_hardening.conf`: no root login, 3 attempts, only `pi`); keep SSH reachable only from LAN/VPN
- configures the git SSH key and identity (`ssh_key_git/`)

`install_containers.sh`
- checks that all secrets are present (`check_secrets`)
- copies configuration files to their locations under `/mnt/external_drive`
- creates the shared Docker network and builds/starts every service folder
- applies the Pi-hole local DNS records
- `./install_containers.sh --check`: shows which installed files, containers and DNS records differ from the repository, without changing anything

The nightly `scripts/daily_backup.sh` (root crontab, 02:00) rescans Nextcloud, runs `apt full-upgrade` (and sends a
dedicated message when a reboot is needed), indexes PhotoPrism, refreshes Plex, syncs Paperless and starts the Backrest backup plan;
its log is kept for 14 days in `/mnt/external_drive/utility/logs/`. With `KUMA_PUSH_URL` set it also reports success/failure to an Uptime Kuma push monitor, so a missing backup raises an alert.

## Notes

- Several services expect a domain with a reverse proxy in front (Nginx Proxy Manager) and local
  DNS records in Pi-hole; adapt `DOMAIN` and the proxy hosts to your setup.
- Memory limits (`mem_limit`) are set on the services that tend to spike; tune them for your hardware.
- Notifications (UPS, backup, reboot needed) are sent to an HTTP endpoint accepting `POST /notify` with a `message` field (`http://localhost:5000/notify` in `scripts/`); [notify-relay](https://github.com/aledv/notify-relay) does exactly that (Telegram + e-mail), or plug in any webhook service you like.
- The host's `eth0` connection should have no DNS search domain (`nmcli con mod eth0 ipv4.dns-search ""`): containers inherit it, and a wrong one turns into thousands of useless DNS queries.
- `scripts/crowdsec_allow_myip.sh` needs `DDNS_HOST` (your dynamic DNS hostname) only as a fallback when the public-IP service is unreachable.

## Offsite backup (rpi-backup)

`rpi-backup/` sets up a Raspberry Pi 4 with a USB disk at another location (`rpi-backup/install.sh`, idempotent):

- a restic **rest-server** on the USB disk, which Backrest on the Pi 5 uses as a second repository (daily copy);
- a **WireGuard** client towards the home VPN, limited to the Pi 5 only (no route to the rest of the LAN);
- a **reverse SSH tunnel** (`offsite-tunnel.service`) that exposes the rest-server, and the Beszel/Dozzle/Portainer agents, on the Pi 5. The `offsite` user on the Pi 5 can only open those ports: no shell, no commands, key only (`scripts/sshd_hardening.conf` + `scripts/offsite_authorized_keys.sample`);
- unattended upgrades, the Scrutiny collector (SMART of the USB disk) and the Beszel agent.

No inbound port is needed at the remote location: everything goes out through the VPN.

## Contributing

Issues and pull requests are welcome. Please run the linters and tests before opening a pull request.

## License

MIT, see [LICENSE](LICENSE).
