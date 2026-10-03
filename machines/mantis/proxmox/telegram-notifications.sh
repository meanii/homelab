#!/usr/bin/env bash
# Creates the Proxmox notification target "telegram" and a matcher that sends
# every error-severity event (failed backups included) to it.
# Run on the Proxmox host: TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... ./telegram-notifications.sh
# pvesh expects header, body and secret values base64-encoded.
set -euo pipefail
: "${TELEGRAM_BOT_TOKEN:?}" "${TELEGRAM_CHAT_ID:?}"
b64() { printf %s "$1" | base64 -w0; }
pvesh create /cluster/notifications/endpoints/webhook --name telegram --method post \
  --url 'https://api.telegram.org/bot{{ secrets.token }}/sendMessage' \
  --header "name=Content-Type,value=$(b64 application/x-www-form-urlencoded)" \
  --body "$(b64 'chat_id={{ secrets.chat }}&text=[Proxmox {{ severity }}] {{ url-encode title }}%0A%0A{{ url-encode message }}')" \
  --secret "name=token,value=$(b64 "$TELEGRAM_BOT_TOKEN")" \
  --secret "name=chat,value=$(b64 "$TELEGRAM_CHAT_ID")"
pvesh create /cluster/notifications/matchers --name telegram-errors --match-severity error --target telegram
pvesh create /cluster/notifications/targets/telegram/test
