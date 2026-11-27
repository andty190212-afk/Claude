#!/usr/bin/env bash
# Личный VPN (VLESS + Reality) — установка в одну команду, с защитой сервера.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/andty190212-afk/claude/claude/zealous-bell-wylfdx/vpn/install.sh)
#
# Ubuntu 20.04+/Debian 11+, от root. Повторный запуск безопасен: ключи не меняются.
# Переменные (необязательно):
#   PORT=443  SNI=www.microsoft.com  NAME=my-vpn
#   HARDEN_SSH=1   — вход по SSH только по ключу (включай, ТОЛЬКО если уже заходишь по ключу!)
set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-www.microsoft.com}"
NAME="${NAME:-my-vpn}"
CONF_DIR=/usr/local/etc/xray
CONF="$CONF_DIR/config.json"
ENV_FILE="$CONF_DIR/vpn.env"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Запусти от root: sudo bash install.sh"; exit 1; }
command -v apt-get >/dev/null || { echo "Нужен Ubuntu или Debian"; exit 1; }

say "Ставлю пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq openssl qrencode ca-certificates ufw fail2ban unattended-upgrades >/dev/null

say "Ставлю Xray (официальный скрипт XTLS)"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null

mkdir -p "$CONF_DIR"
if [ -f "$ENV_FILE" ] && [ -f "$CONF" ]; then
  say "VPN уже настроен — оставляю ключи и пользователей"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  say "Генерирую ключи"
  UUID="$(xray uuid)"
  KEYS="$(xray x25519)"
  # Разные версии Xray: "Private key:/Public key:" или "PrivateKey:/Password:"
  PRIV="$(echo "$KEYS" | grep -iE '^private ?key' | awk -F': *' '{print $2}' | tr -d ' ')"
  PUB="$(echo "$KEYS" | grep -iE '^(public ?key|password)' | awk -F': *' '{print $2}' | tr -d ' ')"
  [ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "Не удалось разобрать ключи:"; echo "$KEYS"; exit 1; }
  SID="$(openssl rand -hex 8)"
  IP="$(curl -4 -fsS https://api.ipify.org || curl -4 -fsS https://ifconfig.me)"

  jq -n --arg uuid "$UUID" --arg name "$NAME" --argjson port "$PORT" \
        --arg sni "$SNI" --arg priv "$PRIV" --arg sid "$SID" '
  {
    log: { loglevel: "warning", access: "none" },
    inbounds: [{
      listen: "0.0.0.0", port: $port, protocol: "vless", tag: "vless-reality",
      settings: { clients: [{ id: $uuid, flow: "xtls-rprx-vision", email: $name }], decryption: "none" },
      streamSettings: {
        network: "tcp", security: "reality",
        realitySettings: { show: false, dest: ($sni + ":443"), xver: 0,
                           serverNames: [$sni], privateKey: $priv, shortIds: [$sid] }
      },
      sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
    }],
    outbounds: [ { protocol: "freedom", tag: "direct" }, { protocol: "blackhole", tag: "block" } ],
    routing: { rules: [
      { type: "field", ip: ["geoip:private"], outboundTag: "block" },
      { type: "field", protocol: ["bittorrent"], outboundTag: "block" },
      { type: "field", port: "25", outboundTag: "block" }
    ] }
  }' > "$CONF"

  printf 'IP=%s\nPORT=%s\nSNI=%s\nPUB=%s\nSID=%s\n' "$IP" "$PORT" "$SNI" "$PUB" "$SID" > "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"; chmod 640 "$CONF"; chgrp nogroup "$CONF" 2>/dev/null || true
xray run -test -config "$CONF" >/dev/null

say "Устанавливаю команду 'vpn' для управления"
cat > /usr/local/bin/vpn <<'VPN'
#!/usr/bin/env bash
set -euo pipefail
CONF=/usr/local/etc/xray/config.json
# shellcheck disable=SC1091
source /usr/local/etc/xray/vpn.env
link() { echo "vless://$1@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp#$2"; }
uuid_of() { jq -r --arg n "$1" '.inbounds[0].settings.clients[] | select(.email==$n) | .id' "$CONF"; }
save() { xray run -test -config "$1" >/dev/null && mv "$1" "$CONF" && chmod 640 "$CONF" && { chgrp nogroup "$CONF" 2>/dev/null || true; }; systemctl restart xray; }
case "${1:-}" in
  add)  n="${2:?vpn add ИМЯ}"; [ -n "$(uuid_of "$n")" ] && { echo "Уже есть: $n"; exec "$0" show "$n"; }
        t="$(mktemp)"; jq --arg id "$(xray uuid)" --arg n "$n" \
          '.inbounds[0].settings.clients += [{id:$id, flow:"xtls-rprx-vision", email:$n}]' "$CONF" > "$t"
        save "$t"; exec "$0" show "$n" ;;
  del)  n="${2:?vpn del ИМЯ}"; t="$(mktemp)"
        jq --arg n "$n" '.inbounds[0].settings.clients |= map(select(.email != $n))' "$CONF" > "$t"
        save "$t"; echo "Удалён: $n" ;;
  show) n="${2:?vpn show ИМЯ}"; u="$(uuid_of "$n")"; [ -n "$u" ] || { echo "Нет такого: $n"; exit 1; }
        l="$(link "$u" "$n")"; echo; echo "$l"; echo; qrencode -t ansiutf8 "$l" ;;
  list) jq -r '.inbounds[0].settings.clients[].email' "$CONF" ;;
  status) systemctl --no-pager status xray | head -5; echo; ufw status; echo; fail2ban-client status sshd 2>/dev/null | tail -3 ;;
  *) echo "vpn add ИМЯ | del ИМЯ | show ИМЯ | list | status" ;;
esac
VPN
chmod 700 /usr/local/bin/vpn

say "Защита: файрвол (открыты только SSH и VPN)"
SSH_PORT="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"; SSH_PORT="${SSH_PORT:-22}"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw limit "$SSH_PORT"/tcp >/dev/null   # ограничение частоты подключений к SSH
ufw allow "$PORT"/tcp >/dev/null
ufw --force enable >/dev/null

say "Защита: fail2ban (бан за подбор пароля SSH)"
cat > /etc/fail2ban/jail.d/sshd-vpn.local <<F2B
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
F2B
systemctl enable --now fail2ban >/dev/null 2>&1; systemctl restart fail2ban

say "Защита: автоматические обновления безопасности"
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

say "Защита: еженедельное обновление Xray"
cat > /etc/cron.weekly/xray-update <<'CRON'
#!/bin/sh
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 && systemctl restart xray
CRON
chmod 755 /etc/cron.weekly/xray-update

if [ "${HARDEN_SSH:-0}" = 1 ]; then
  if [ -s /root/.ssh/authorized_keys ]; then
    say "Защита: SSH только по ключу"
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-vpn-hardening.conf
    sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd
  else
    echo "HARDEN_SSH пропущен: в /root/.ssh/authorized_keys нет ключа — иначе ты потеряешь доступ."
  fi
fi

say "Включаю BBR"
printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-vpn-bbr.conf
sysctl --system >/dev/null 2>&1 || true

systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 1
systemctl is-active --quiet xray || { journalctl -u xray -n 30 --no-pager; exit 1; }

FIRST="$(jq -r '.inbounds[0].settings.clients[0].email' "$CONF")"
vpn show "$FIRST" | grep '^vless://' > /root/vpn-link.txt; chmod 600 /root/vpn-link.txt
echo
echo "=================== ГОТОВО ==================="
vpn show "$FIRST"
cat <<TXT
Отсканируй QR в Hiddify / v2rayNG / Streisand — и подключайся.
Ссылка также сохранена в /root/vpn-link.txt

Управление:  vpn add phone | vpn del phone | vpn list | vpn status
TXT
