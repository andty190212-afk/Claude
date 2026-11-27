#!/usr/bin/env bash
# Личный VPN на VLESS + Reality (Xray) — установка одной командой.
# Работает на Ubuntu 20.04+/Debian 11+. Запускать от root на чистом VPS.
#
#   bash install.sh
#
# Переменные (необязательно):
#   PORT=443                  порт сервера
#   SNI=www.microsoft.com     сайт, под который маскируется трафик
#   NAME=my-vpn               имя первого пользователя
set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-www.microsoft.com}"
NAME="${NAME:-my-vpn}"
CONF_DIR=/usr/local/etc/xray
CONF="$CONF_DIR/config.json"
ENV_FILE="$CONF_DIR/vpn.env"

[ "$(id -u)" -eq 0 ] || { echo "Запусти от root: sudo bash install.sh"; exit 1; }
command -v apt-get >/dev/null || { echo "Нужен Ubuntu или Debian"; exit 1; }

echo "==> Ставлю зависимости"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq openssl qrencode ca-certificates >/dev/null

echo "==> Ставлю Xray (официальный скрипт XTLS)"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null

echo "==> Генерирую ключи"
UUID="$(xray uuid)"
KEYS="$(xray x25519)"
# Формат вывода разный в разных версиях Xray: "Private key:/Public key:" или "PrivateKey:/Password:"
PRIV="$(echo "$KEYS" | grep -iE '^private ?key' | awk -F': *' '{print $2}' | tr -d ' ')"
PUB="$(echo "$KEYS" | grep -iE '^(public ?key|password)' | awk -F': *' '{print $2}' | tr -d ' ')"
[ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "Не удалось разобрать ключи:"; echo "$KEYS"; exit 1; }
SID="$(openssl rand -hex 8)"

IP="$(curl -4 -fsS https://api.ipify.org || curl -4 -fsS https://ifconfig.me)"

mkdir -p "$CONF_DIR"
jq -n \
  --arg uuid "$UUID" --arg name "$NAME" --argjson port "$PORT" \
  --arg sni "$SNI" --arg priv "$PRIV" --arg sid "$SID" '
{
  log: { loglevel: "warning" },
  inbounds: [{
    listen: "0.0.0.0", port: $port, protocol: "vless", tag: "vless-reality",
    settings: { clients: [{ id: $uuid, flow: "xtls-rprx-vision", email: $name }], decryption: "none" },
    streamSettings: {
      network: "tcp", security: "reality",
      realitySettings: {
        show: false, dest: ($sni + ":443"), xver: 0,
        serverNames: [$sni], privateKey: $priv, shortIds: [$sid]
      }
    },
    sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
  }],
  outbounds: [
    { protocol: "freedom", tag: "direct" },
    { protocol: "blackhole", tag: "block" }
  ],
  routing: { rules: [ { type: "field", ip: ["geoip:private"], outboundTag: "block" } ] }
}' > "$CONF"

cat > "$ENV_FILE" <<ENV
IP=$IP
PORT=$PORT
SNI=$SNI
PUB=$PUB
SID=$SID
ENV
chmod 600 "$CONF" "$ENV_FILE"

xray run -test -config "$CONF" >/dev/null

echo "==> Включаю BBR (быстрее на плохих каналах)"
grep -q 'tcp_congestion_control=bbr' /etc/sysctl.conf 2>/dev/null || {
  echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
  echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
}
sysctl -p >/dev/null 2>&1 || true

if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow "$PORT"/tcp >/dev/null
fi

systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 1
systemctl is-active --quiet xray || { journalctl -u xray -n 30 --no-pager; exit 1; }

LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp#${NAME}"

echo
echo "================ ГОТОВО ================"
echo "Ссылка для подключения (скопируй в приложение):"
echo
echo "$LINK"
echo
qrencode -t ansiutf8 "$LINK"
echo "Добавить ещё устройство/друга:  bash add-user.sh имя"
