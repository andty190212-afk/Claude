#!/usr/bin/env bash
# VPN для iPhone/iPad/Mac БЕЗ приложений — встроенный IKEv2.
# Создаёт профиль .mobileconfig: открыл на iPhone → «Установить» → готово.
#
#   bash ios.sh ИМЯ          (или на сервере: vpn ios ИМЯ)
#
# Первый запуск ставит strongSwan (IKEv2), дальше только добавляет пользователей.
set -euo pipefail

NAME="${1:?Укажи имя: bash ios.sh iphone}"
[[ "$NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Имя только латиницей/цифрами"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Запусти от root"; exit 1; }

D=/etc/ipsec.d
CA_CN="MyVPN CA"
POOL=10.10.10.0/24

if [ -f /usr/local/etc/xray/vpn.env ]; then
  # shellcheck disable=SC1091
  IP="$(. /usr/local/etc/xray/vpn.env; echo "$IP")"
else
  IP="$(curl -4 -fsS https://api.ipify.org || curl -4 -fsS https://ifconfig.me)"
fi

setup() {
  echo "==> Первый запуск: ставлю IKEv2 (strongSwan)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins openssl ufw >/dev/null

  mkdir -p "$D"/{cacerts,certs,private}; chmod 700 "$D/private"
  pki --gen --type rsa --size 3072 --outform pem > "$D/private/ca-key.pem"
  pki --self --ca --lifetime 3650 --in "$D/private/ca-key.pem" --type rsa \
      --dn "CN=$CA_CN" --outform pem > "$D/cacerts/ca-cert.pem"
  pki --gen --type rsa --size 3072 --outform pem > "$D/private/server-key.pem"
  pki --pub --in "$D/private/server-key.pem" --type rsa \
    | pki --issue --lifetime 1825 --cacert "$D/cacerts/ca-cert.pem" --cakey "$D/private/ca-key.pem" \
          --dn "CN=$IP" --san "$IP" --flag serverAuth --flag ikeIntermediate --outform pem \
    > "$D/certs/server-cert.pem"
  chmod 600 "$D"/private/*

  cat > /etc/ipsec.conf <<CONF
config setup
    charondebug="ike 0, knl 0, cfg 0"
    uniqueids=no

conn ikev2
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=$IP
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=$POOL
    rightdns=1.1.1.1,8.8.8.8
    rightsendcert=never
    eap_identity=%identity
    ike=aes256gcm16-prfsha384-ecp384,aes256-sha256-modp2048!
    esp=aes256gcm16-ecp384,aes256gcm16,aes256-sha256!
CONF
  printf ': RSA "server-key.pem"\n' > /etc/ipsec.secrets
  chmod 600 /etc/ipsec.secrets

  echo "==> Сеть: пересылка пакетов и NAT"
  printf 'net.ipv4.ip_forward=1\nnet.ipv4.conf.all.accept_redirects=0\nnet.ipv4.conf.all.send_redirects=0\n' > /etc/sysctl.d/99-vpn-ikev2.conf
  sysctl --system >/dev/null 2>&1 || true
  sed -i 's|^#net/ipv4/ip_forward=1|net/ipv4/ip_forward=1|' /etc/ufw/sysctl.conf 2>/dev/null || true

  IFACE="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  if ! grep -q MYVPN-IKEV2 /etc/ufw/before.rules; then
    tmp="$(mktemp)"
    cat > "$tmp" <<RULES
# MYVPN-IKEV2 start
*nat
-A POSTROUTING -s $POOL -o $IFACE -m policy --pol ipsec --dir out -j ACCEPT
-A POSTROUTING -s $POOL -o $IFACE -j MASQUERADE
COMMIT
*mangle
-A FORWARD --match policy --pol ipsec --dir in -s $POOL -o $IFACE -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
COMMIT
# MYVPN-IKEV2 end
RULES
    cat /etc/ufw/before.rules >> "$tmp" && mv "$tmp" /etc/ufw/before.rules
  fi
  ufw allow 500/udp >/dev/null
  ufw allow 4500/udp >/dev/null
  ufw route allow from "$POOL" >/dev/null
  ufw --force enable >/dev/null
  ufw reload >/dev/null

  systemctl enable strongswan-starter >/dev/null 2>&1 || true
  systemctl restart strongswan-starter 2>/dev/null || ipsec restart
}

[ -f "$D/cacerts/ca-cert.pem" ] || setup

# --- пользователь ---
if grep -q "^$NAME : EAP " /etc/ipsec.secrets; then
  PASS="$(grep "^$NAME : EAP " /etc/ipsec.secrets | sed -E 's/.*EAP "(.*)"/\1/')"
else
  PASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
  printf '%s : EAP "%s"\n' "$NAME" "$PASS" >> /etc/ipsec.secrets
  ipsec rereadsecrets >/dev/null 2>&1 || true
fi

# --- профиль .mobileconfig ---
CA_B64="$(openssl x509 -in "$D/cacerts/ca-cert.pem" -outform der | base64 -w0)"
uuid() { cat /proc/sys/kernel/random/uuid; }
OUT="/root/MyVPN-$NAME.mobileconfig"
cat > "$OUT" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadDisplayName</key><string>MyVPN ($NAME)</string>
  <key>PayloadIdentifier</key><string>myvpn.$NAME</string>
  <key>PayloadUUID</key><string>$(uuid)</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.security.root</string>
      <key>PayloadIdentifier</key><string>myvpn.$NAME.ca</string>
      <key>PayloadUUID</key><string>$(uuid)</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadDisplayName</key><string>$CA_CN</string>
      <key>PayloadContent</key><data>$CA_B64</data>
    </dict>
    <dict>
      <key>PayloadType</key><string>com.apple.vpn.managed</string>
      <key>PayloadIdentifier</key><string>myvpn.$NAME.vpn</string>
      <key>PayloadUUID</key><string>$(uuid)</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadDisplayName</key><string>MyVPN</string>
      <key>UserDefinedName</key><string>MyVPN</string>
      <key>VPNType</key><string>IKEv2</string>
      <key>IKEv2</key>
      <dict>
        <key>RemoteAddress</key><string>$IP</string>
        <key>RemoteIdentifier</key><string>$IP</string>
        <key>LocalIdentifier</key><string>$NAME</string>
        <key>ServerCertificateIssuerCommonName</key><string>$CA_CN</string>
        <key>ServerCertificateCommonName</key><string>$IP</string>
        <key>AuthenticationMethod</key><string>None</string>
        <key>ExtendedAuthEnabled</key><integer>1</integer>
        <key>AuthName</key><string>$NAME</string>
        <key>AuthPassword</key><string>$PASS</string>
        <key>EnablePFS</key><integer>1</integer>
        <key>DeadPeerDetectionRate</key><string>Medium</string>
        <key>DisableMOBIKE</key><integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256-GCM</string>
          <key>IntegrityAlgorithm</key><string>SHA2-384</string>
          <key>DiffieHellmanGroup</key><integer>20</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256-GCM</string>
          <key>IntegrityAlgorithm</key><string>SHA2-384</string>
          <key>DiffieHellmanGroup</key><integer>20</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
      </dict>
    </dict>
  </array>
</dict>
</plist>
XML
chmod 600 "$OUT"

cat <<TXT

=============== ГОТОВО ===============
Профиль для iPhone: $OUT

1. Скачай файл на компьютер:  scp root@$IP:$OUT .
2. Отправь его себе на iPhone (AirDrop, почта или Telegram → «Сохранить в Файлы»).
3. Открой файл на iPhone → «Профиль загружен».
4. Настройки → «Профиль загружен» → Установить (введи код телефона).
5. Включай VPN: Настройки → VPN → MyVPN.
TXT
