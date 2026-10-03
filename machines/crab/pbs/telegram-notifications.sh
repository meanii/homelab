#!/usr/bin/env bash
# Sends PBS errors (failed prune, garbage collection, verify, sync) to Telegram,
# the same way machines/mantis/proxmox/telegram-notifications.sh does for Proxmox VE.
# Run on crab: set -a; . ~/.config/homelab/telegram.env; set +a; bash telegram-notifications.sh
# Header, body and secret values are base64-encoded.
set -euo pipefail
[[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]] || { echo "set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"; exit 1; }
m() { docker exec pbs proxmox-backup-manager "$@"; }
b64() { printf %s "$1" | base64 -w0; }
m notification endpoint webhook create telegram --method post \
  --url 'https://api.telegram.org/bot{{ secrets.token }}/sendMessage' \
  --header "name=Content-Type,value=$(b64 application/x-www-form-urlencoded)" \
  --body "$(b64 'chat_id={{ secrets.chat }}&text=[PBS crab {{ severity }}] {{ url-encode title }}%0A%0A{{ url-encode message }}')" \
  --secret "name=token,value=$(b64 "$TELEGRAM_BOT_TOKEN")" \
  --secret "name=chat,value=$(b64 "$TELEGRAM_CHAT_ID")"
m notification matcher create telegram-errors --match-severity error --target telegram
m datastore update hdd --notification-mode notification-system
