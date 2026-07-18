# Aschente Launcher

**Aschente Launcher** ist eine lokale Windows-Spielebibliothek. Sie verwaltet Steam-Installationen und frei gewählte lokale Spielordner, ohne Benutzerkonto, Cloud-Zwang oder Telemetrie.

## Aktueller Stand

Version: **0.2.0**

Die Anwendung besteht aus zwei Windows-Programmen:

- `Aschente Launcher.exe` – startet die lokale Spielebibliothek.
- `Installer.exe` – lädt das neueste stabile GitHub-Release herunter und installiert oder aktualisiert den Launcher.

Der Installer kompiliert auf dem Ziel-PC keinen Quellcode. Die EXE-Dateien werden reproduzierbar durch GitHub Actions erzeugt. Der Installer lädt anschließend das veröffentlichte Paket `Aschente-Launcher-win-x64.zip` aus dem neuesten GitHub-Release.

## Standardpfade

Programm und lokale Daten:

```text
C:\Program Files\Aschente\
├── Aschente Launcher.exe
├── Uninstall Aschente Launcher.exe
├── README.txt
├── LICENSE.txt
├── version.json
└── Data\
    ├── config.json
    ├── library.json
    ├── app.log
    └── Runtime\AschenteLauncher.ps1
```

Startmenü:

```text
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Aschente\
├── Aschente Launcher.lnk
└── Aschente Launcher deinstallieren.lnk
```

Der Installationspfad ist im Installer frei änderbar. Nur der Unterordner `Data` erhält Schreibrechte für normale Benutzer; die EXE-Dateien bleiben administrativ geschützt.

## Funktionen

- Einrichtungsassistent beim ersten Start
- Frei wählbare lokale Bibliothekspfade
- Steam-Bibliotheken automatisch erkennen
- Lokale Spieleordner nach sinnvollen Startdateien durchsuchen
- Unsichere Starter zur manuellen Prüfung markieren
- Spiele suchen, filtern, favorisieren und starten
- Einträge manuell hinzufügen oder korrigieren
- Fehlende Installationen erkennen
- Einstellungen und Pfade jederzeit ändern
- Vollständig lokale JSON-Datenhaltung
- Updates über GitHub Releases
- Keine Anmeldung, Cloud oder Telemetrie

## Repository erstmals auf GitHub veröffentlichen

1. Den Inhalt dieser Repository-ZIP in ein neues GitHub-Repository kopieren.
2. Alles committen und pushen.
3. Einen Release-Tag erstellen, zum Beispiel:

```powershell
git tag v0.2.0
git push origin v0.2.0
```

4. Der Workflow `.github/workflows/release.yml` erstellt automatisch:
   - `Installer.exe`
   - `Aschente-Launcher-win-x64.zip`
   - `SHA256SUMS.txt`
5. Diese Dateien werden an das GitHub-Release angehängt.

Der Installer wird beim GitHub-Build automatisch mit dem tatsächlichen Repository-Besitzer und Repository-Namen verbunden. Dadurch sind keine persönlichen Werte im eigentlichen Launcher fest eingebaut.

## Lokaler Build unter Windows

Voraussetzung: Go 1.22 oder neuer.

```powershell
.\scripts\build.ps1 `
    -Version 0.2.0 `
    -GitHubOwner DEIN_GITHUB_NAME `
    -GitHubRepository Aschente-Launcher
```

Die fertigen Dateien liegen danach unter `dist`.

## Installer für ein anderes Repository konfigurieren

Beim GitHub-Actions-Build geschieht dies automatisch. Für einen bereits kompilierten Installer kann optional eine Datei `installer-config.json` direkt neben `Installer.exe` liegen:

```json
{
  "githubOwner": "DEIN_GITHUB_NAME",
  "githubRepository": "DEIN_REPOSITORY"
}
```

Diese Datei überschreibt die beim Build eingebettete GitHub-Quelle.

## Update-Verhalten

Der Installer fragt GitHubs Endpunkt für das neueste stabile Release ab. Er sucht dort nach `Aschente-Launcher-win-x64.zip`, lädt es herunter und ersetzt die Programmdateien. Der Ordner `Data` wird bei einem Update nicht überschrieben.

## Grenzen

Aschente Launcher verwaltet und startet vorhandene Installationen. Er umgeht keine DRM-, Konto-, Lizenz- oder Serverprüfungen eines Spiels. Ob ein Spiel vollständig offline funktioniert, hängt vom jeweiligen Spiel ab.

## Lizenz

MIT – siehe `LICENSE.txt`.
