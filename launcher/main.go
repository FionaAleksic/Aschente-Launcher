//go:build windows

package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed AschenteLauncher.ps1
var launcherScript []byte

var version = "0.2.0-dev"

func main() {
	exePath, err := os.Executable()
	if err != nil {
		messageBox("Aschente Launcher", "Der Installationspfad konnte nicht ermittelt werden.\n\n"+err.Error(), 0x10)
		return
	}

	installDir := filepath.Dir(exePath)
	dataDir := filepath.Join(installDir, "Data")
	runtimeDir := filepath.Join(dataDir, "Runtime")
	scriptPath := filepath.Join(runtimeDir, "AschenteLauncher.ps1")

	if err := os.MkdirAll(runtimeDir, 0o755); err != nil {
		messageBox("Aschente Launcher", "Der Datenordner konnte nicht erstellt werden.\n\n"+err.Error(), 0x10)
		return
	}

	if err := writeWhenChanged(scriptPath, launcherScript); err != nil {
		messageBox("Aschente Launcher", "Die eingebettete Programmoberfläche konnte nicht vorbereitet werden.\n\n"+err.Error(), 0x10)
		return
	}

	host := "powershell.exe"
	if path, lookErr := exec.LookPath("pwsh.exe"); lookErr == nil {
		host = path
	}

	args := []string{"-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", scriptPath}
	args = append(args, os.Args[1:]...)

	cmd := exec.Command(host, args...)
	cmd.Dir = installDir
	cmd.Env = append(os.Environ(),
		"ASCHENTE_INSTALL_DIR="+installDir,
		"ASCHENTE_DATA_DIR="+dataDir,
		"ASCHENTE_VERSION="+strings.TrimPrefix(version, "v"),
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Run(); err != nil {
		messageBox("Aschente Launcher", fmt.Sprintf("Der Launcher konnte nicht gestartet werden.\n\nPowerShell: %s\nFehler: %v", host, err), 0x10)
	}
}

func writeWhenChanged(path string, content []byte) error {
	desired := sha256.Sum256(content)
	if existing, err := os.ReadFile(path); err == nil {
		current := sha256.Sum256(existing)
		if hex.EncodeToString(current[:]) == hex.EncodeToString(desired[:]) {
			return nil
		}
	}

	temp := path + ".tmp"
	if err := os.WriteFile(temp, content, 0o644); err != nil {
		return err
	}
	_ = os.Remove(path)
	return os.Rename(temp, path)
}

func messageBox(title, text string, flags uintptr) {
	user32 := syscall.NewLazyDLL("user32.dll")
	proc := user32.NewProc("MessageBoxW")
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString(title)
	proc.Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), flags)
}
