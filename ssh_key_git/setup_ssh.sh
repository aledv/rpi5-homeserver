#!/bin/bash

# Creo la directory .ssh se non esiste
mkdir -p /home/pi/.ssh/
chmod 700 /home/pi/.ssh/
chown pi:pi /home/pi/.ssh/

# Verifica se la chiave SSH esiste prima di copiarla
if [ -f ssh_key_git/id_ed25519 ]; then
  cp ssh_key_git/id_ed25519* /home/pi/.ssh/
else
  echo "La chiave SSH non è stata trovata!"
  exit 1
fi

# Imposta i permessi corretti sulla chiave SSH
chmod 600 /home/pi/.ssh/id_ed25519
chown pi:pi /home/pi/.ssh/id_ed25519

# Aggiunge GitHub a known_hosts per evitare richieste di conferma
ssh-keyscan github.com >> /home/pi/.ssh/known_hosts
chown pi:pi /home/pi/.ssh/known_hosts
chmod 644 /home/pi/.ssh/known_hosts

# Avvia l'agente SSH e aggiungi la chiave
eval "$(ssh-agent -s)"
ssh-add /home/pi/.ssh/id_ed25519

# Verifica la connessione a GitHub
ssh -T git@github.com

# Set user.email and name
# Identità git letta da ssh_key_git/.env (escluso da git), vedi .env.sample
[ -f ssh_key_git/.env ] && . ssh_key_git/.env
if [ -n "$GIT_USER_EMAIL" ] && [ -n "$GIT_USER_NAME" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
  git config --global user.name "$GIT_USER_NAME"
else
  echo "GIT_USER_EMAIL/GIT_USER_NAME non impostati in ssh_key_git/.env: identità git non configurata"
fi
