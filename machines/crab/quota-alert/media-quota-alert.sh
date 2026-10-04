#!/bin/sh
# Daily check of the media project quota on /mnt/data (project 1000, 1.2 TB).
# Sends a Telegram message when use reaches THRESHOLD percent of the hard limit.
# Token and chat id come from /etc/smartd-telegram.env (shared with smartd).
THRESHOLD=${THRESHOLD:-85}
line=$(repquota -P /mnt/data | awk '$1=="#1000"')
used=$(echo "$line" | awk '{print $3}'); hard=$(echo "$line" | awk '{print $5}')
[ -n "$used" ] && [ "${hard:-0}" -gt 0 ] || { echo "no quota line for project 1000"; exit 1; }
pct=$((used * 100 / hard))
echo "media quota: ${pct}% ($((used/1048576)) of $((hard/1048576)) GiB)"
[ "$pct" -ge "$THRESHOLD" ] || exit 0
. /etc/smartd-telegram.env
curl -s -m 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=[crab] media folder at ${pct}% of its quota ($((used/1048576)) of $((hard/1048576)) GiB). Free space before it fills: Sonarr/Radarr stop importing at the limit." >/dev/null
