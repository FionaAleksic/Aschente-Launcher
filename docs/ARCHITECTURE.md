# Architektur

## Installer.exe

`installer/main.go` enthält das Installationsskript und das Logo als eingebettete Dateien. Beim Start:

1. werden Administratorrechte angefordert,
2. wird das PowerShell-Skript mit UTF-8-BOM in einen temporären Ordner geschrieben,
3. wird die feste GitHub-Quelle `FionaAleksic/Aschente-Launcher` übergeben,
4. lädt das Skript das neueste Release,
5. prüft SHA-256,
6. installiert die Dateien und erstellt Verknüpfungen.

## Aschente Launcher.exe

`launcher/main.go` enthält die WPF-Anwendung und das Logo. Beim Start werden beide in `Data\Runtime` aktualisiert und anschließend mit PowerShell 7 oder Windows PowerShell 5.1 ausgeführt.

## Datenhaltung

```text
<Installationsordner>\Data\config.json
<Installationsordner>\Data\library.json
<Installationsordner>\Data\app.log
<Installationsordner>\Data\Runtime\...
```

Der Installer überschreibt `Data` bei einem Update nicht.

## Release-Paket

GitHub Actions erzeugt:

```text
Aschente-Launcher-win-x64.zip
├── Aschente Launcher.exe
├── Assets
│   ├── Aschente_Icon.ico
│   └── Aschente_Icon.png
├── LICENSE.txt
├── README.txt
└── version.json
```
