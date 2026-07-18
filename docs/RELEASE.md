# Release erstellen

## Automatisch

```powershell
git tag v0.2.0
git push origin v0.2.0
```

Der Tag startet `.github/workflows/release.yml`. Der Workflow benötigt `contents: write`, um das Release anzulegen und Assets hochzuladen.

## Erzeugte Assets

- `Installer.exe`
- `Aschente-Launcher-win-x64.zip`
- `SHA256SUMS.txt`

Der Dateiname des Launcher-Pakets darf nicht geändert werden, ohne gleichzeitig `$script:AssetName` in `installer/Installer.ps1` anzupassen.
