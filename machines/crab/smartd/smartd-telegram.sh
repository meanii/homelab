#!/bin/sh
# smartd -M exec hook: sends the warning to Telegram. smartd passes the details in
# SMARTD_* variables and the full message on stdin. Token and chat id come from
# /etc/smartd-telegram.env (root, mode 600): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID.
. /etc/smartd-telegram.env
text="[crab SMART] ${SMARTD_DEVICESTRING:-$SMARTD_DEVICE}: ${SMARTD_FAILTYPE:-test}
$(cat)"
curl -s -m 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${text}" >/dev/null
