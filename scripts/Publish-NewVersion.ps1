[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^v?\d+\.\d+\.\d+$')]
    [string]$Version = '0.3.1',

    [string]$CommitMessage,

    [switch]$SkipCommit
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionNumber = $Version.TrimStart('v')
$tag = "v$versionNumber"
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "Release $tag"
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git-Befehl fehlgeschlagen: git $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue) -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git wurde nicht gefunden.'
}

Push-Location $repoRoot
try {
    if (-not (Test-Path -LiteralPath '.git')) {
        throw "Der Ordner '$repoRoot' ist kein Git-Repository."
    }

    $remote = (& git remote get-url origin 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
        throw 'Das Git-Remote „origin“ ist nicht eingerichtet.'
    }
    if ($remote -notmatch 'github\.com[:/]FionaAleksic/Aschente-Launcher(?:\.git)?$') {
        Write-Warning "Das Remote origin zeigt nicht auf FionaAleksic/Aschente-Launcher: $remote"
    }

    $localTag = & git tag --list $tag
    if (-not [string]::IsNullOrWhiteSpace(($localTag -join ''))) {
        throw "Der lokale Tag '$tag' existiert bereits. Verwende eine neue Versionsnummer."
    }

    & git ls-remote --exit-code --tags origin "refs/tags/$tag" *> $null
    if ($LASTEXITCODE -eq 0) {
        throw "Der Tag '$tag' existiert bereits auf GitHub. Verwende eine neue Versionsnummer."
    }

    if (-not $SkipCommit) {
        Invoke-Git add -A
        $changes = & git status --porcelain
        if ($changes) {
            Invoke-Git commit -m $CommitMessage
        }
        else {
            Write-Host 'Keine neuen Dateiänderungen zum Committen gefunden.' -ForegroundColor Yellow
        }
    }

    $branch = (& git branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Es ist kein aktiver Git-Branch ausgewählt.'
    }

    Write-Host "Pushe Branch '$branch' ..." -ForegroundColor Cyan
    Invoke-Git push -u origin $branch

    Write-Host "Erstelle Release-Tag '$tag' ..." -ForegroundColor Cyan
    Invoke-Git tag -a $tag -m "Aschente Launcher $versionNumber"
    Invoke-Git push origin $tag

    Write-Host ''
    Write-Host "Fertig. GitHub Actions baut jetzt Installer.exe und Aschente-Launcher-win-x64.zip." -ForegroundColor Green
    Write-Host 'Build-Status: https://github.com/FionaAleksic/Aschente-Launcher/actions'
    Write-Host 'Releases:     https://github.com/FionaAleksic/Aschente-Launcher/releases'
}
finally {
    Pop-Location
}
