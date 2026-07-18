[CmdletBinding()]
param(
    [string]$Version = '0.3.0',
    [string]$GitHubOwner = 'FionaAleksic',
    [string]$GitHubRepository = 'Aschente-Launcher',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dist = [IO.Path]::GetFullPath($OutputDirectory)
$packageDir = Join-Path $dist 'package'

if (-not (Get-Command go.exe -ErrorAction SilentlyContinue)) {
    throw 'Go wurde nicht gefunden. Installiere Go 1.22 oder neuer und öffne PowerShell anschließend neu.'
}

$normalizedVersion = $Version.Trim().TrimStart('v')
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Ungültige Version '$Version'. Erwartet wird beispielsweise 0.3.0."
}
$numericVersion = ($normalizedVersion -split '[-+]')[0]
$winVersion = if (($numericVersion -split '\.').Count -eq 3) { "$numericVersion.0" } else { $numericVersion }

$goPath = (& go env GOPATH).Trim()
$goWinRes = Join-Path $goPath 'bin\go-winres.exe'
if (-not (Test-Path -LiteralPath $goWinRes)) {
    Write-Host 'Installiere go-winres v0.3.3 für Windows-Icon und Versionsinformationen ...'
    & go install github.com/tc-hib/go-winres@v0.3.3
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $goWinRes)) {
        throw 'go-winres konnte nicht installiert werden.'
    }
}

Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

Push-Location $repoRoot
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    $env:CGO_ENABLED = '0'

    Remove-Item .\launcher\rsrc_windows_*.syso, .\installer\rsrc_windows_*.syso -Force -ErrorAction SilentlyContinue

    Write-Host 'Erzeuge Windows-Ressourcen ...'
    Push-Location .\launcher
    try { & $goWinRes make --file-version $winVersion --product-version $winVersion }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw 'Launcher-Ressourcen konnten nicht erzeugt werden.' }

    Push-Location .\installer
    try { & $goWinRes make --file-version $winVersion --product-version $winVersion }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw 'Installer-Ressourcen konnten nicht erzeugt werden.' }

    Write-Host 'Baue Aschente Launcher.exe ...'
    & go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$normalizedVersion" -o (Join-Path $packageDir 'Aschente Launcher.exe') .\launcher
    if ($LASTEXITCODE -ne 0) { throw 'Launcher-Build fehlgeschlagen.' }

    Write-Host 'Baue Installer.exe ...'
    & go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$normalizedVersion" -o (Join-Path $dist 'Installer.exe') .\installer
    if ($LASTEXITCODE -ne 0) { throw 'Installer-Build fehlgeschlagen.' }

    Copy-Item .\LICENSE.txt (Join-Path $packageDir 'LICENSE.txt')
    New-Item -ItemType Directory -Path (Join-Path $packageDir 'Assets') -Force | Out-Null
    Copy-Item .\assets\Aschente_Icon.png (Join-Path $packageDir 'Assets\Aschente_Icon.png')
    Copy-Item .\assets\Aschente_Icon.ico (Join-Path $packageDir 'Assets\Aschente_Icon.ico')

    @"
Aschente Launcher $normalizedVersion

Lokale Spielebibliothek ohne Cloud-Zwang.
Repository: https://github.com/$GitHubOwner/$GitHubRepository

Der Installer lädt immer das neueste veröffentlichte Release aus diesem Repository.
"@ | Set-Content -LiteralPath (Join-Path $packageDir 'README.txt') -Encoding UTF8

    [ordered]@{
        name = 'Aschente Launcher'
        version = $normalizedVersion
        architecture = 'win-x64'
        repository = "$GitHubOwner/$GitHubRepository"
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageDir 'version.json') -Encoding UTF8

    $archive = Join-Path $dist 'Aschente-Launcher-win-x64.zip'
    Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $archive -CompressionLevel Optimal -Force

    $hashLines = @()
    $hashLines += "{0}  Installer.exe" -f (Get-FileHash -LiteralPath (Join-Path $dist 'Installer.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines += "{0}  Aschente-Launcher-win-x64.zip" -f (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII

    Write-Host "Build fertig: $dist"
}
finally {
    Remove-Item .\launcher\rsrc_windows_*.syso, .\installer\rsrc_windows_*.syso -Force -ErrorAction SilentlyContinue
    Pop-Location
}
