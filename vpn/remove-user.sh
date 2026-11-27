#!/usr/bin/env bash
# Удаляет пользователя:  bash remove-user.sh phone
set -euo pipefail
NAME="${1:?Укажи имя: bash remove-user.sh phone}"
CONF=/usr/local/etc/xray/config.json
tmp="$(mktemp)"
jq --arg n "$NAME" '.inbounds[0].settings.clients |= map(select(.email != $n))' "$CONF" > "$tmp"
mv "$tmp" "$CONF" && chmod 600 "$CONF"
systemctl restart xray
echo "Удалён: $NAME. Осталось: $(jq -r '[.inbounds[0].settings.clients[].email] | join(", ")' "$CONF")"
