# Neue Version veröffentlichen

## Empfohlener Weg

Im Repository-Ordner:

```powershell
.\scripts\Publish-NewVersion.ps1 -Version 0.3.0
```

Das Skript führt im Wesentlichen diese Befehle aus:

```powershell
git add -A
git commit -m "Release v0.3.0"
git push origin main
git tag -a v0.3.0 -m "Aschente Launcher 0.3.0"
git push origin v0.3.0
```

Der Tag startet den Release-Workflow. GitHub Actions baut die EXE-Dateien, erstellt das Release-Paket und veröffentlicht alle drei Assets.

## Versionsregel

Verwende immer eine neue Version im Format:

```text
vHAUPTVERSION.NEBENVERSION.PATCH
```

Beispiel:

```text
v0.3.1
```

Ein vorhandener Release-Tag darf nicht erneut verwendet werden.
