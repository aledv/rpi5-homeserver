#!/bin/sh

# Crea l'utente 'guest' con home directory /home/ftpuser/test
docker exec -it pure-ftpd pure-pw useradd guest -m -u ftpuser -d /home/ftpuser/test

# Ricrea il database utenti pureftpd.pdb
docker exec -it pure-ftpd pure-pw mkdb