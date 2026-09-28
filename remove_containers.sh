#!/bin/bash

# Quando attivi set -e, lo script si interrompe immediatamente se un comando restituisce un codice di uscita diverso da zero (cioè se il comando fallisce). 
set -e

# Percorso della directory principale
main_folder="."

# Loop sulle subfolder
for dir in "$main_folder"/*; do
    if [ -d "$dir" ]; then
        if [ -f "$dir/docker-compose.yml" ]; then
            echo "Trovato docker-compose.yml in $dir. Eseguo docker-compose down"
            # Esegui solo docker-compose down
            (cd "$dir" && sudo docker compose down)
        fi
    fi
done