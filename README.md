# Aschente Launcher

Aschente Launcher ist eine vollständig lokale Spielebibliothek für Windows. Das Programm verwaltet Steam-Spiele und frei wählbare lokale Spielordner, ohne Anmeldung, Cloud oder Telemetrie.

## Installation für Anwender

1. Auf der GitHub-Seite das neueste Release öffnen.
2. `Installer.exe` herunterladen und starten.
3. Installationsordner und Verknüpfungen auswählen.
4. Auf **Weiter** und anschließend **Installieren** klicken.

Der Installer verwendet fest dieses Repository:

```text
FionaAleksic/Aschente-Launcher
```

Er lädt automatisch das neueste Release-Paket `Aschente-Launcher-win-x64.zip`, prüft dessen SHA-256-Prüfsumme und installiert es.

## Standardpfade

```text
C:\Program Files\Aschente
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Aschente
```

Konfiguration und Bibliothek werden standardmäßig hier gespeichert:

```text
C:\Program Files\Aschente\Data
```

Der Installer vergibt für diesen Datenordner Änderungsrechte an lokale Benutzer. Bei Updates bleibt der komplette `Data`-Ordner erhalten.

## Branding

Das Aschente-Bild aus `assets/Aschente_Icon.png` wird verwendet für:

- Icon von `Installer.exe`
- Icon von `Aschente Launcher.exe`
- Installer-Logo
- Launcher-Logo und Fenster-Icons
- Startmenü- und Desktop-Verknüpfungen

Die Windows-Ressourcen werden beim Build mit `go-winres` erzeugt.

## Repository aktualisieren

Den Inhalt der Update-ZIP direkt in den vorhandenen Repository-Ordner entpacken und vorhandene Dateien ersetzen. Danach im Repository-Ordner ausführen:

```powershell
.\scripts\Publish-NewVersion.ps1 -Version 0.3.0
```

Das Skript committed die Änderungen, pusht den aktuellen Branch, erzeugt den Tag `v0.3.0` und pusht ihn. Der Tag startet automatisch `.github/workflows/release.yml`.

## Automatisch erzeugte Release-Dateien

```text
Installer.exe
Aschente-Launcher-win-x64.zip
SHA256SUMS.txt
```

## Lokaler Build

Voraussetzungen:

- Windows 10 oder Windows 11
- Go 1.22 oder neuer
- Internetzugang beim ersten Build für `go-winres`

```powershell
.\scripts\build.ps1 -Version 0.3.0
```

Die Dateien werden unter `dist` erstellt.

## Projektstruktur

```text
.github/workflows/     GitHub Actions für Build und Release
assets/                Logo und Windows-Icon
installer/             Installer-EXE und WPF-Installationsoberfläche
launcher/              Launcher-EXE und WPF-Anwendung
scripts/               Build- und Veröffentlichungs-Skripte
docs/                  Technische Dokumentation
```

## Wichtiger Hinweis

Der Launcher verwaltet und startet vorhandene Installationen. Er entfernt oder umgeht keine DRM-, Konto-, Lizenz- oder Serverprüfungen eines Spiels.
