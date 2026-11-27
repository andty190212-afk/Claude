//go:build windows

package main

import (
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const inetKey = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

var (
	wininet           = windows.NewLazySystemDLL("wininet.dll")
	internetSetOption = wininet.NewProc("InternetSetOptionW")
)

func refresh() {
	internetSetOption.Call(0, 39, 0, 0) // INTERNET_OPTION_SETTINGS_CHANGED
	internetSetOption.Call(0, 37, 0, 0) // INTERNET_OPTION_REFRESH
}

func enableSystemProxy(addr string) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, inetKey, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if err := k.SetStringValue("ProxyServer", addr); err != nil {
		return err
	}
	_ = k.SetStringValue("ProxyOverride", "localhost;127.*;10.*;172.16.*;192.168.*;<local>")
	if err := k.SetDWordValue("ProxyEnable", 1); err != nil {
		return err
	}
	refresh()
	return nil
}

func disableSystemProxy() {
	k, err := registry.OpenKey(registry.CURRENT_USER, inetKey, registry.SET_VALUE)
	if err != nil {
		return
	}
	defer k.Close()
	_ = k.SetDWordValue("ProxyEnable", 0)
	refresh()
}
