//go:build !windows

package main

import "fmt"

// На Linux/macOS системный прокси не трогаем — настрой вручную на 127.0.0.1:10809 (HTTP) или :10808 (SOCKS5).
func enableSystemProxy(addr string) error {
	fmt.Println("Прокси:", addr, "(HTTP) и 127.0.0.1:10808 (SOCKS5) — настрой вручную")
	return nil
}
func disableSystemProxy() {}
