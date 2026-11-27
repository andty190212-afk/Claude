// MyVPN — клиент для Windows в один файл.
// Двойной клик → подключено. Закрыл окно → отключено.
//
// Ссылка vless:// берётся (по порядку):
//  1. вшитая в конец exe (её добавляет команда `vpn exe ИМЯ` на сервере);
//  2. файл vpn.txt рядом с exe;
//  3. сохранённая ранее в %APPDATA%\MyVPN\link.txt;
//  4. спрашивается в окне (один раз, потом запоминается).
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
)

const (
	marker    = "#MYVPN-LINK#"
	httpPort  = 10809
	socksPort = 10808
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--off" {
		disableSystemProxy()
		fmt.Println("Системный прокси выключен.")
		return
	}
	if err := run(); err != nil {
		fmt.Println("\nОшибка:", err)
		pause()
		os.Exit(1)
	}
}

func run() error {
	fmt.Println("=== MyVPN ===")
	link, err := findLink()
	if err != nil {
		return err
	}
	cfg, name, err := buildConfig(link)
	if err != nil {
		return err
	}

	inst, err := core.StartInstance("json", cfg)
	if err != nil {
		return fmt.Errorf("не удалось запустить VPN: %w", err)
	}
	defer inst.Close()

	proxy := fmt.Sprintf("127.0.0.1:%d", httpPort)
	if err := enableSystemProxy(proxy); err != nil {
		return fmt.Errorf("не удалось включить системный прокси: %w", err)
	}
	defer disableSystemProxy()

	fmt.Printf("\nПодключаюсь к %s…\n", name)
	if ip := checkIP(); ip != "" {
		fmt.Println("\n✔ VPN подключен. Твой IP теперь:", ip)
	} else {
		fmt.Println("\n⚠ VPN запущен, но проверка не прошла. Если сайты не открываются —")
		fmt.Println("  проверь, что сервер работает (vpn status) и ссылка верная.")
	}
	fmt.Println("\n  Не закрывай это окно, пока пользуешься VPN.")
	fmt.Println("  Чтобы отключиться — просто закрой окно или нажми Ctrl+C.")

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
	fmt.Println("\nОтключаюсь…")
	return nil
}

// ---------- поиск ссылки ----------

func findLink() (string, error) {
	exe, _ := os.Executable()

	if b, err := os.ReadFile(exe); err == nil {
		if i := bytes.LastIndex(b, []byte(marker)); i >= 0 {
			if l := strings.TrimSpace(string(b[i+len(marker):])); strings.HasPrefix(l, "vless://") {
				return l, nil
			}
		}
	}
	if b, err := os.ReadFile(filepath.Join(filepath.Dir(exe), "vpn.txt")); err == nil {
		if l := strings.TrimSpace(string(b)); strings.HasPrefix(l, "vless://") {
			return l, nil
		}
	}
	saved := savedLinkPath()
	if b, err := os.ReadFile(saved); err == nil {
		if l := strings.TrimSpace(string(b)); strings.HasPrefix(l, "vless://") {
			return l, nil
		}
	}

	fmt.Println("\nВставь ссылку vless:// (правый клик в окне = вставить) и нажми Enter:")
	l, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	l = strings.TrimSpace(l)
	if !strings.HasPrefix(l, "vless://") {
		return "", errors.New("ссылка должна начинаться с vless://")
	}
	_ = os.MkdirAll(filepath.Dir(saved), 0o700)
	_ = os.WriteFile(saved, []byte(l), 0o600)
	return l, nil
}

func savedLinkPath() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = "."
	}
	return filepath.Join(dir, "MyVPN", "link.txt")
}

// ---------- vless:// → конфиг Xray ----------

func buildConfig(link string) ([]byte, string, error) {
	u, err := url.Parse(link)
	if err != nil || u.Scheme != "vless" || u.User == nil {
		return nil, "", errors.New("неверная ссылка vless://")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, "", errors.New("в ссылке нет порта")
	}
	q := u.Query()
	if q.Get("security") != "reality" || q.Get("pbk") == "" {
		return nil, "", errors.New("поддерживаются только ссылки VLESS + Reality")
	}
	fp := q.Get("fp")
	if fp == "" {
		fp = "chrome"
	}
	name := u.Fragment
	if name == "" {
		name = u.Hostname()
	}

	cfg := map[string]any{
		"log": map[string]any{"loglevel": "warning", "access": "none"},
		"inbounds": []any{
			map[string]any{"tag": "http", "listen": "127.0.0.1", "port": httpPort, "protocol": "http"},
			map[string]any{"tag": "socks", "listen": "127.0.0.1", "port": socksPort, "protocol": "socks",
				"settings": map[string]any{"udp": true}},
		},
		"outbounds": []any{
			map[string]any{
				"tag": "proxy", "protocol": "vless",
				"settings": map[string]any{"vnext": []any{map[string]any{
					"address": u.Hostname(), "port": port,
					"users": []any{map[string]any{"id": u.User.Username(), "encryption": "none", "flow": q.Get("flow")}},
				}}},
				"streamSettings": map[string]any{
					"network": "tcp", "security": "reality",
					"realitySettings": map[string]any{
						"serverName": q.Get("sni"), "fingerprint": fp,
						"publicKey": q.Get("pbk"), "shortId": q.Get("sid"),
					},
				},
			},
			map[string]any{"tag": "direct", "protocol": "freedom"},
		},
		"routing": map[string]any{"rules": []any{
			map[string]any{"type": "field", "outboundTag": "direct", "ip": []string{
				"127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
				"169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"}},
		}},
	}
	b, err := json.Marshal(cfg)
	return b, name, err
}

// ---------- проверка ----------

func checkIP() string {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", httpPort), 5*time.Second)
	if err != nil {
		return ""
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(10 * time.Second))
	fmt.Fprint(c, "GET http://api.ipify.org/ HTTP/1.1\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n")
	var buf bytes.Buffer
	_, _ = buf.ReadFrom(c)
	parts := strings.SplitN(buf.String(), "\r\n\r\n", 2)
	if len(parts) != 2 || !strings.Contains(parts[0], " 200 ") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func pause() {
	fmt.Println("\nНажми Enter, чтобы закрыть.")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}
