#!/bin/sh
# Recreates the Telegram notification target and the alert rules on the Beszel hub.
# Run in CT 109 next to api.sh: TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... ./alerts.sh
set -eu
cd "$(dirname "$0")"
: "${TELEGRAM_BOT_TOKEN:?}" "${TELEGRAM_CHAT_ID:?}"
id_of() { ./api.sh GET "/api/collections/systems/records?fields=id,name&perPage=50" | python3 -c "import sys,json;print(next(s['id'] for s in json.load(sys.stdin)['items'] if s['name']=='$1'))"; }
ALL=$(for n in mantis crab beetle vultr; do printf '"%s",' "$(id_of $n)"; done | sed 's/,$//')
PHYS=$(for n in mantis crab; do printf '"%s",' "$(id_of $n)"; done | sed 's/,$//')

settings=$(./api.sh GET "/api/collections/user_settings/records" | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['id'])")
printf '{"settings":{"chartTime":"1h","emails":[],"webhooks":["telegram://%s@telegram?chats=%s"]}}' "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" \
  | ./api.sh PATCH "/api/collections/user_settings/records/$settings" x >/dev/null

alert() { printf '{"name":"%s","value":%s,"min":%s,"systems":[%s],"overwrite":true}' "$1" "$2" "$3" "$4" | ./api.sh POST /api/beszel/user-alerts x; echo " $1"; }
alert Status 0 2 "$ALL"
alert Disk 85 10 "$ALL"
alert Memory 90 10 "$ALL"
alert CPU 90 15 "$ALL"
alert Temperature 80 5 "$PHYS"
