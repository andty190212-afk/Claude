# iPhone / iPad / Mac — без App Store

`ios.sh` включает на сервере встроенный в iOS VPN (IKEv2) и создаёт профиль
`.mobileconfig`. На сервере:

```bash
vpn ios iphone
```

Открой полученный файл на iPhone → Настройки → «Профиль загружен» → Установить.
Включай VPN: Настройки → VPN → MyVPN.

⚠️ IKEv2 легко распознать, в странах с сильными блокировками он может не работать —
тогда используй ссылку `vless://` в Streisand / V2Box / Hiddify.
