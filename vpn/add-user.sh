#!/usr/bin/env bash
# Добавляет нового пользователя и печатает его ссылку + QR.
#   bash add-user.sh phone
set -euo pipefail
NAME="${1:?Укажи имя: bash add-user.sh phone}"
CONF=/usr/local/etc/xray/config.json
# shellcheck disable=SC1091
source /usr/local/etc/xray/vpn.env

if jq -e --arg n "$NAME" '.inbounds[0].settings.clients[] | select(.email==$n)' "$CONF" >/dev/null; then
  UUID="$(jq -r --arg n "$NAME" '.inbounds[0].settings.clients[] | select(.email==$n) | .id' "$CONF")"
  echo "Пользователь $NAME уже есть — показываю его ссылку."
else
  UUID="$(xray uuid)"
  tmp="$(mktemp)"
  jq --arg id "$UUID" --arg n "$NAME" \
    '.inbounds[0].settings.clients += [{id:$id, flow:"xtls-rprx-vision", email:$n}]' "$CONF" > "$tmp"
  xray run -test -config "$tmp" >/dev/null
  mv "$tmp" "$CONF" && chmod 600 "$CONF"
  systemctl restart xray
fi

LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp#${NAME}"
echo "$LINK"
qrencode -t ansiutf8 "$LINK"
