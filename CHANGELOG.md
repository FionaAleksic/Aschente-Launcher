# Changelog

## 0.3.0

- Produktname und Branding vollständig auf **Aschente Launcher** umgestellt
- GitHub-Quelle fest auf `FionaAleksic/Aschente-Launcher` eingestellt
- GitHub-Eingabefeld aus dem Installer entfernt
- zweistufige Installer-Oberfläche mit **Weiter**, **Zurück** und **Installieren**
- UTF-8-BOM beim Start der eingebetteten PowerShell-Skripte, damit Umlaute korrekt angezeigt werden
- Aschente-Logo als Installer- und Launcher-Branding eingebunden
- Windows-EXE-Icons und Versionsinformationen über `go-winres`
- SHA-256-Prüfung über GitHub-Asset-Digest oder `SHA256SUMS.txt`
- neues `Publish-NewVersion.ps1` für Commit, Push und Release-Tag
- Updates erhalten den vollständigen `Data`-Ordner

## 0.2.0

- Installer mit Download des neuesten GitHub-Releases
- Standardinstallation unter `C:\Program Files\Aschente`
- Startmenü- und optionale Desktop-Verknüpfung
- Registrierung unter Windows „Installierte Apps“
- Deinstallationsprogramm

## 0.1.0

- erste lokale Spielebibliothek
- Steam-Import und lokale Ordnerscans
- Favoriten, Suche, Filter und manuelle Einträge
