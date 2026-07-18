//go:build windows

package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed Installer.ps1
var installerScript []byte

var defaultOwner = ""
var defaultRepo = ""
var version = "0.2.0-dev"

type installerConfig struct {
	GitHubOwner      string `json:"githubOwner"`
	GitHubRepository string `json:"githubRepository"`
}

func main() {
	exePath, err := os.Executable()
	if err != nil {
		messageBox("Aschente Installer", "Der Pfad des Installers konnte nicht ermittelt werden.\n\n"+err.Error(), 0x10)
		return
	}

	if !isAdmin() {
		if err := relaunchElevated(exePath, os.Args[1:]); err != nil {
			messageBox("Aschente Installer", "Administratorrechte sind für die Installation erforderlich.\n\n"+err.Error(), 0x10)
		}
		return
	}

	owner, repo := readRepositoryConfig(filepath.Dir(exePath))
	tempDir, err := os.MkdirTemp("", "Aschente-Installer-")
	if err != nil {
		messageBox("Aschente Installer", "Temporärer Ordner konnte nicht erstellt werden.\n\n"+err.Error(), 0x10)
		return
	}
	defer os.RemoveAll(tempDir)

	scriptPath := filepath.Join(tempDir, "Installer.ps1")
	if err := os.WriteFile(scriptPath, installerScript, 0o600); err != nil {
		messageBox("Aschente Installer", "Installationsskript konnte nicht vorbereitet werden.\n\n"+err.Error(), 0x10)
		return
	}

	args := []string{"-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", scriptPath}
	args = append(args, os.Args[1:]...)

	cmd := exec.Command("powershell.exe", args...)
	cmd.Env = append(os.Environ(),
		"ASCHENTE_GITHUB_OWNER="+owner,
		"ASCHENTE_GITHUB_REPO="+repo,
		"ASCHENTE_INSTALLER_EXE="+exePath,
		"ASCHENTE_INSTALLER_VERSION="+strings.TrimPrefix(version, "v"),
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Run(); err != nil {
		messageBox("Aschente Installer", fmt.Sprintf("Der Installer wurde mit einem Fehler beendet.\n\n%v", err), 0x10)
	}
}

func readRepositoryConfig(dir string) (string, string) {
	owner := strings.TrimSpace(defaultOwner)
	repo := strings.TrimSpace(defaultRepo)
	path := filepath.Join(dir, "installer-config.json")
	if raw, err := os.ReadFile(path); err == nil {
		var cfg installerConfig
		if json.Unmarshal(raw, &cfg) == nil {
			if strings.TrimSpace(cfg.GitHubOwner) != "" {
				owner = strings.TrimSpace(cfg.GitHubOwner)
			}
			if strings.TrimSpace(cfg.GitHubRepository) != "" {
				repo = strings.TrimSpace(cfg.GitHubRepository)
			}
		}
	}
	return owner, repo
}

func isAdmin() bool {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	proc := shell32.NewProc("IsUserAnAdmin")
	result, _, _ := proc.Call()
	return result != 0
}

func relaunchElevated(exePath string, args []string) error {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	proc := shell32.NewProc("ShellExecuteW")
	verb, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(exePath)
	parameters, _ := syscall.UTF16PtrFromString(joinWindowsArgs(args))
	directory, _ := syscall.UTF16PtrFromString(filepath.Dir(exePath))
	result, _, callErr := proc.Call(
		0,
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(file)),
		uintptr(unsafe.Pointer(parameters)),
		uintptr(unsafe.Pointer(directory)),
		1,
	)
	if result <= 32 {
		return fmt.Errorf("ShellExecuteW fehlgeschlagen (%d): %v", result, callErr)
	}
	return nil
}

func joinWindowsArgs(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		if arg == "" || strings.ContainsAny(arg, " \t\"") {
			arg = `"` + strings.ReplaceAll(arg, `"`, `\"`) + `"`
		}
		quoted = append(quoted, arg)
	}
	return strings.Join(quoted, " ")
}

func messageBox(title, text string, flags uintptr) {
	user32 := syscall.NewLazyDLL("user32.dll")
	proc := user32.NewProc("MessageBoxW")
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString(title)
	proc.Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), flags)
}
