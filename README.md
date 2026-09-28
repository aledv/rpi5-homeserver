# Raspberry Pi 5 Home Server

Docker Compose setups and install scripts for running a self-hosted home server on a
**Raspberry Pi 5** with an external drive (DAS/USB disk) mounted at `/mnt/external_drive`. Every service lives in its own folder
with a `docker-compose.yml`; two scripts prepare the OS and bring all containers up.

No secrets are stored in this repository: passwords, tokens, domain, e-mail addresses and
usernames are read from local `.env` files that are excluded from git
(see [Configuration and secrets](#configuration-and-secrets)).

## Services

- **apcupsd** / **apcupsd-cgi**: APC UPS monitoring daemon and its web interface.
- **beszel**: lightweight server monitoring (hub + agent).
- **code-server**: VS Code in the browser.
- **crowdsec**: collaborative intrusion prevention: reads the Nginx Proxy Manager and SSH logs and bans attacking IPs on the host firewall (`crowdsec-firewall-bouncer`, installed by `install.sh`); LAN/VPN and your home IP are never banned (`scripts/crowdsec_allow_myip.sh`).
- **ddclient**: dynamic DNS client that keeps your domain pointing to your public IP.
- **docker-socket-proxy**: read-only Docker API for the monitoring containers (homepage, Uptime Kuma, Dozzle, Glances, Beszel), so none of them mounts `/var/run/docker.sock`.
- **dozzle**: real-time Docker log viewer (supports remote agents).
- **glances**: cross-platform system monitoring.
- **homeassistant**: home automation platform.
- **homebridge**: exposes non-HomeKit devices to Apple HomeKit.
- **homepage**: application dashboard with Docker and service API integrations (bring your own `services.yaml`/`widgets.yaml` in `/mnt/external_drive/homepage/config`).
- **mailserver**: full mail server (SMTP, IMAP, Rspamd anti-spam) based on docker-mailserver.
- **mosquitto**: MQTT broker.
- **nextcloud** (+ MariaDB, Redis): self-hosted file sharing and collaboration.
- **nginx-proxy-manager**: reverse proxy with Let's Encrypt certificates and access lists.
- **onlyoffice**: online document editor, integrated with Nextcloud.
- **openvpn** / **wireguard**: VPN servers for remote access.
- **oracle-xe**: Oracle Database 23ai Free.
- **photoprism** (+ MariaDB): AI-powered photo management.
- **phpmyadmin**: MySQL/MariaDB administration.
- **pihole**: network-wide ad blocker and local DNS (local records kept in `pihole/local_dns_hosts.txt`, applied by `pihole/apply_local_dns.sh`).
- **plex**: media server.
- **portainer**: container management UI.
- **pure-ftpd**: FTP server.
- **roundcube**: webmail client with two-factor authentication (TOTP plugin, config applied after the plugin install).
- **samba**: file shares and Time Machine backups.
- **scanservjs**: web UI for a network scanner.
- **scrutiny**: S.M.A.R.T. disk health dashboard (supports disks behind JMicron USB RAID enclosures via `jmb39x-q`).
- **speedtest-tracker**: internet connection speed history.
- **stirling-pdf**: local web-based PDF toolkit.
- **transmission**: BitTorrent client.
- **umami** (+ PostgreSQL): privacy-friendly web analytics; `umami_vue` is a small Nextcloud app that embeds the tracker.
- **uptime-kuma**: uptime monitoring and alerting.
- **vaultwarden**: Bitwarden-compatible password manager.
- **watchtower**: automatic container image updates.

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
cp oracle-xe/.env.sample oracle-xe/.env
chmod 600 oracle-xe/.env
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

**homepage** uses its own variable syntax: `services.yaml`, `settings.yaml` and `bookmarks.yaml`
contain `{{HOMEPAGE_VAR_...}}` placeholders, filled from `homepage/.env` (passed to the container
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
- configures the git SSH key and identity (`ssh_key_git/`)

`install_containers.sh`
- checks that all secrets are present (`check_secrets`)
- copies configuration files to their locations under `/mnt/external_drive`
- creates the shared Docker network and builds/starts every service folder
- applies the Pi-hole local DNS records
- `./install_containers.sh --check`: shows which installed files, containers and DNS records differ from the repository, without changing anything

The nightly `scripts/daily_backup.sh` (root crontab, 02:00) rescans Nextcloud, runs `apt full-upgrade` (and sends a
dedicated message when a reboot is needed), indexes PhotoPrism, refreshes Plex and rsyncs the DAS to a backup server;
its log is kept for 14 days in `/mnt/external_drive/utility/logs/`.

## Notes

- Several services expect a domain with a reverse proxy in front (Nginx Proxy Manager) and local
  DNS records in Pi-hole; adapt `DOMAIN` and the proxy hosts to your setup.
- Memory limits (`mem_limit`) are set on the services that tend to spike; tune them for your hardware.
- Notifications (UPS, backup, reboot needed) are sent to an HTTP endpoint accepting `POST /notify` with a `message` field (`http://localhost:5000/notify` in `scripts/`); plug in any webhook-to-Telegram/e-mail service you like.
- The nightly backup rsyncs to `BACKUP_TARGET` (an rsync daemon module, set in `scripts/.env`).
- `scripts/crowdsec_allow_myip.sh` needs `DDNS_HOST` (your dynamic DNS hostname) only as a fallback when the public-IP service is unreachable.

## License

MIT, see [LICENSE](LICENSE).
