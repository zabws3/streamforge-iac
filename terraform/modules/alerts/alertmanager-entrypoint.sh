#!/bin/sh
# Runs Alertmanager with runtime-only Telegram credentials.
set -eu

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"

if ! printf '%s' "$TELEGRAM_CHAT_ID" | grep -Eq '^-?[0-9]+$'; then
    echo "TELEGRAM_CHAT_ID must be an integer." >&2
    exit 1
fi

umask 077
printf '%s' "$TELEGRAM_BOT_TOKEN" > /run/telegram_bot_token
sed "s/__TELEGRAM_CHAT_ID__/${TELEGRAM_CHAT_ID}/g" \
    /etc/alertmanager/alertmanager.yml.template \
    > /run/alertmanager.yml

exec /bin/alertmanager \
    --config.file=/run/alertmanager.yml \
    --storage.path=/alertmanager
