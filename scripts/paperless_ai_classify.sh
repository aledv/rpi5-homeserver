#!/bin/bash
# Nightly classification of Paperless documents with a local LLM (Ollama on another LAN machine): documents stay home.
# Code in the public repo aledv/paperless-ai-classify. Root cron at 04:15 (crontab.copy); PAPERLESS_TOKEN in
# /mnt/external_drive/utility/.env, read by the cron line. Arguments go to the classifier (--dry-run, --max N, --ids 1,2).
exec docker run --rm --network host \
  -e PAPERLESS_TOKEN -e TZ=Europe/Rome \
  -e PAPERLESS_URL=http://localhost:8010 \
  -e OLLAMA_URL=http://192.168.1.101:11434 -e OLLAMA_MODEL=qwen3.5:4b \
  -e DOC_LANGUAGE=Italian -e "TAG_REVIEW=AI da verificare" -e "TAG_SEEN=AI visto" \
  -e STOP_AT=06:30 -e MAX_DOCS=400 \
  ghcr.io/aledv/paperless-ai-classify:f7fc2e4@sha256:bb2201ec288ad20a537d47e9d3658915c400dd0f8e660e427e7f40d3a822421f "$@"
