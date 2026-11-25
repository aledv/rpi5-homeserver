#!/bin/bash
# Nightly classification of Paperless documents with a local LLM (Ollama on another LAN machine): documents stay home.
# Code in the public repo aledv/paperless-ai-classify. Root cron at 04:15 (crontab.copy); PAPERLESS_TOKEN in
# /mnt/external_drive/utility/.env, read by the cron line. Arguments go to the classifier (--dry-run, --max N, --ids 1,2).
exec docker run --rm --network host \
  -e PAPERLESS_TOKEN -e TZ=Europe/Rome \
  -e PAPERLESS_URL=http://localhost:8010 \
  -e OLLAMA_URL=http://192.168.1.101:11434 -e OLLAMA_MODEL=qwen3.5:4b \
  -e DOC_LANGUAGE=Italian -e "TAG_REVIEW=AI da verificare" -e "TAG_SEEN=AI visto" \
  -e STOP_AT=06:30 -e MAX_DOCS=400 -e "EXCLUDE_TYPES=Certificazione fiscale" \
  ghcr.io/aledv/paperless-ai-classify:8a7b4e1@sha256:bf475ef68073134dcc2d38c55e20abc4a9d286fa62223b46d84333a71751f8d7 "$@"
