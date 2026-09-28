#!/bin/bash

# Nome del container di Nginx Proxy Manager
NGINX_PROXY_MANAGER="nginx-proxy-manager"

# Nome del container del mailserver
MAILSERVER="mailserver"

# Fermare Nginx Proxy Manager
echo "Arresto di $NGINX_PROXY_MANAGER..."
docker stop $NGINX_PROXY_MANAGER

# Eseguire Certbot per il rinnovo dei certificati
echo "Esecuzione di Certbot per il rinnovo dei certificati..."
docker run --rm \
  -v "/mnt/external_drive/mailserver/docker-data/certbot/certs/:/etc/letsencrypt/" \
  -v "/mnt/external_drive/mailserver/docker-data/certbot/logs/:/var/log/letsencrypt/" \
  -p 80:80 -p 443:443 certbot/certbot renew

# Avviare di nuovo Nginx Proxy Manager
echo "Riavvio di $NGINX_PROXY_MANAGER..."
docker start $NGINX_PROXY_MANAGER

# Riavviare il mailserver
echo "Riavvio di $MAILSERVER..."
docker restart $MAILSERVER

#Needed to send the notification
sleep 10
