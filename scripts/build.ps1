[CmdletBinding()]
param(
    [string]$Version = '0.2.0',
    [string]$GitHubOwner = 'YOUR_GITHUB_USERNAME',
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

Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

Push-Location $repoRoot
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    $env:CGO_ENABLED = '0'

    Write-Host 'Baue Aschente Launcher.exe ...'
    go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$Version" -o (Join-Path $packageDir 'Aschente Launcher.exe') .\launcher
    if ($LASTEXITCODE -ne 0) { throw 'Launcher-Build fehlgeschlagen.' }

    Write-Host 'Baue Installer.exe ...'
    go build -trimpath -ldflags "-s -w -H windowsgui -X main.version=$Version -X main.defaultOwner=$GitHubOwner -X main.defaultRepo=$GitHubRepository" -o (Join-Path $dist 'Installer.exe') .\installer
    if ($LASTEXITCODE -ne 0) { throw 'Installer-Build fehlgeschlagen.' }

    Copy-Item .\LICENSE.txt (Join-Path $packageDir 'LICENSE.txt')
    @"
Aschente Launcher $Version

Die vollständige Dokumentation befindet sich im GitHub-Repository:
https://github.com/$GitHubOwner/$GitHubRepository
"@ | Set-Content -LiteralPath (Join-Path $packageDir 'README.txt') -Encoding UTF8

    [ordered]@{
        name = 'Aschente Launcher'
        version = $Version
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
    Pop-Location
}
