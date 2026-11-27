# Windows — MyVPN.exe

Исходный код клиента для ПК (Go + ядро Xray). Двойной клик → VPN подключён,
закрыл окно → отключён.

**Скачать готовый exe:**
https://github.com/andty190212-afk/claude/releases/download/client-latest/MyVPN.exe

Личный exe со ссылкой внутри: на сервере `vpn exe ИМЯ`.

Сборка вручную:

```bash
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o MyVPN.exe .
```

Каждый пуш в эту папку пересобирает exe автоматически (GitHub Actions).
