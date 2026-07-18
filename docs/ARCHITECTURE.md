# Architektur

## Launcher-EXE

`launcher/main.go` bettet `launcher/AschenteLauncher.ps1` über `go:embed` direkt in die Windows-EXE ein. Beim Start wird das Skript unter `Data\Runtime` bereitgestellt und mit PowerShell im STA-Modus gestartet. Dadurch bleibt die bestehende WPF-Oberfläche nutzbar, während Anwender ausschließlich `Aschente Launcher.exe` starten.

## Installer-EXE

`installer/main.go` bettet `installer/Installer.ps1` ein. Die EXE fordert über Windows UAC Administratorrechte an und startet danach den WPF-Installer.

Der Installer:

1. fragt das neueste stabile GitHub-Release ab,
2. sucht das Release-Asset `Aschente-Launcher-win-x64.zip`,
3. lädt und prüft das Paket,
4. beendet eine laufende Launcher-Instanz,
5. installiert die Dateien,
6. erhält den vorhandenen `Data`-Ordner,
7. erstellt Verknüpfungen und den Windows-Deinstallationseintrag.

## Datenhaltung

Die Programmdateien und der Datenordner liegen standardmäßig gemeinsam unter `C:\Program Files\Aschente`. Normale Benutzer erhalten Änderungsrechte ausschließlich auf `Data`. Dies folgt der gewünschten portablen, zentralen Datenhaltung, unterscheidet sich aber von der üblichen Windows-Empfehlung, benutzerspezifische Daten unter `%LOCALAPPDATA%` abzulegen.

## Releaseprozess

GitHub Actions baut beide EXE-Dateien mit Go für `windows/amd64`. Beim Release-Build werden Repository-Besitzer und Repository-Name über Linker-Variablen in den Installer geschrieben.
