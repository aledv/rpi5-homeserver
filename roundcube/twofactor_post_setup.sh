#!/bin/sh
# Eseguito dal container roundcube dopo l installazione dei plugin (entrypoint post-setup):
# sostituisce la configurazione di esempio del plugin 2FA con la nostra.
cp /opt/twofactor_gauthenticator.config.inc.php /var/www/html/plugins/twofactor_gauthenticator/config.inc.php
chown www-data:www-data /var/www/html/plugins/twofactor_gauthenticator/config.inc.php
echo "Configurazione 2FA applicata"
