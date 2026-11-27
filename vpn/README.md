# Свой VPN за ~$3 в месяц

Протокол **VLESS + Reality** (Xray). Трафик выглядит как обычный HTTPS к крупному сайту,
поэтому он хорошо работает даже там, где WireGuard и OpenVPN блокируют.

## 1. Арендуй VPS (~$3/мес)

Хватит самого дешёвого тарифа: 1 vCPU, 512 МБ–1 ГБ RAM, **Ubuntu 22.04/24.04**.
Где искать (цены меняются, проверь на сайте):

| Провайдер | Цена примерно | Заметки |
|---|---|---|
| Hetzner (CX22 / CAX11) | от ~€3.8 | Германия/Финляндия, быстрый |
| RackNerd (акции) | ~$10–15 в **год** | самый дешёвый, США |
| Aeza / VDSina / 4VPS | ~$3–4 | удобно платить картой РФ |
| Vultr / DigitalOcean | $4–6 | надёжно, почасовая оплата |

Локация: ближайшая страна вне твоей (Нидерланды, Германия, Финляндия) — меньше пинг.

## 2. Установка (2 минуты)

Подключись к серверу (`ssh root@IP_СЕРВЕРА`) и выполни:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/andty190212-afk/claude.git
cd claude/vpn && bash install.sh
```

В конце скрипт выведет ссылку `vless://...` и QR-код.

Настройки (необязательно): `PORT=8443 SNI=www.apple.com NAME=laptop bash install.sh`

## 3. Подключение

Импортируй ссылку (или отсканируй QR) в приложение:

- **Android:** v2rayNG, Hiddify
- **iPhone:** Streisand, V2Box, Hiddify
- **Windows / macOS / Linux:** Hiddify, v2rayN, Nekoray

## Пользователи

```bash
bash add-user.sh phone      # новое устройство/друг — своя ссылка
bash remove-user.sh phone   # отключить
```

## Если не работает

- `systemctl status xray` и `journalctl -u xray -n 50` — логи.
- Проверь, что у провайдера VPS открыт порт 443 (firewall в панели).
- Сменить сайт маскировки: переустановить с `SNI=www.apple.com`.
