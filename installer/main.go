//go:build windows

package main

import (
	_ "embed"
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

//go:embed Aschente_Icon.png
var brandImage []byte

var version = "0.3.1-dev"

const (
	githubOwner      = "FionaAleksic"
	githubRepository = "Aschente-Launcher"
)

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

	tempDir, err := os.MkdirTemp("", "Aschente-Installer-")
	if err != nil {
		messageBox("Aschente Installer", "Der temporäre Ordner konnte nicht erstellt werden.\n\n"+err.Error(), 0x10)
		return
	}
	defer os.RemoveAll(tempDir)

	scriptPath := filepath.Join(tempDir, "Installer.ps1")
	brandPath := filepath.Join(tempDir, "Aschente_Icon.png")
	if err := writeUTF8BOM(scriptPath, installerScript, 0o600); err != nil {
		messageBox("Aschente Installer", "Das Installationsskript konnte nicht vorbereitet werden.\n\n"+err.Error(), 0x10)
		return
	}
	if err := os.WriteFile(brandPath, brandImage, 0o600); err != nil {
		messageBox("Aschente Installer", "Das Programmlogo konnte nicht vorbereitet werden.\n\n"+err.Error(), 0x10)
		return
	}

	args := []string{"-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", scriptPath}
	args = append(args, os.Args[1:]...)

	cmd := exec.Command("powershell.exe", args...)
	cmd.Env = append(os.Environ(),
		"ASCHENTE_GITHUB_OWNER="+githubOwner,
		"ASCHENTE_GITHUB_REPO="+githubRepository,
		"ASCHENTE_INSTALLER_EXE="+exePath,
		"ASCHENTE_INSTALLER_VERSION="+strings.TrimPrefix(version, "v"),
		"ASCHENTE_BRAND_IMAGE="+brandPath,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Run(); err != nil {
		messageBox("Aschente Installer", fmt.Sprintf("Der Installer wurde mit einem Fehler beendet.\n\n%v", err), 0x10)
	}
}

func writeUTF8BOM(path string, content []byte, mode os.FileMode) error {
	bom := []byte{0xEF, 0xBB, 0xBF}
	if len(content) >= 3 && content[0] == bom[0] && content[1] == bom[1] && content[2] == bom[2] {
		return os.WriteFile(path, content, mode)
	}
	withBOM := make([]byte, 0, len(content)+3)
	withBOM = append(withBOM, bom...)
	withBOM = append(withBOM, content...)
	return os.WriteFile(path, withBOM, mode)
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
