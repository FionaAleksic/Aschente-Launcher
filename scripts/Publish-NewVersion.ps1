[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidatePattern('^v?\d+\.\d+\.\d+$')]
    [string]$Version = '0.3.0',

    [Parameter(Mandatory = $false)]
    [string]$CommitMessage,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCommit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$versionNumber = $Version.TrimStart('v')
$tag = "v$versionNumber"

if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "Release $tag"
}

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$GitArguments
    )

    Write-Host ("git " + ($GitArguments -join ' ')) -ForegroundColor DarkGray
    & git @GitArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Git-Befehl fehlgeschlagen: git $($GitArguments -join ' ')"
    }
}

$gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
}
if (-not $gitCommand) {
    throw 'Git wurde nicht gefunden. Installiere Git oder füge es der PATH-Umgebungsvariable hinzu.'
}

Push-Location -LiteralPath $repoRoot
try {
    if (-not (Test-Path -LiteralPath '.git')) {
        throw "Der Ordner '$repoRoot' ist kein Git-Repository."
    }

    $remoteOutput = & git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Das Git-Remote "origin" ist nicht eingerichtet.'
    }

    $remote = [string]($remoteOutput | Select-Object -First 1)
    $remote = $remote.Trim()

    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw 'Das Git-Remote "origin" ist nicht eingerichtet.'
    }

    if ($remote -notmatch 'github\.com[:/]FionaAleksic/Aschente-Launcher(?:\.git)?$') {
        Write-Warning "Das Remote origin zeigt nicht auf FionaAleksic/Aschente-Launcher: $remote"
    }

    $localTag = & git tag --list $tag
    if (-not [string]::IsNullOrWhiteSpace([string]($localTag -join ''))) {
        throw "Der lokale Tag '$tag' existiert bereits. Verwende eine neue Versionsnummer."
    }

    & git ls-remote --exit-code --tags origin "refs/tags/$tag" *> $null
    if ($LASTEXITCODE -eq 0) {
        throw "Der Tag '$tag' existiert bereits auf GitHub. Verwende eine neue Versionsnummer."
    }

    if (-not $SkipCommit) {
        Invoke-Git -GitArguments @('add', '-A')

        $changes = & git status --porcelain
        if ($LASTEXITCODE -ne 0) {
            throw 'Git-Status konnte nicht gelesen werden.'
        }

        if ($changes) {
            Invoke-Git -GitArguments @('commit', '-m', $CommitMessage)
        }
        else {
            Write-Host 'Keine neuen Dateiänderungen zum Committen gefunden.' -ForegroundColor Yellow
        }
    }

    $branchOutput = & git branch --show-current
    if ($LASTEXITCODE -ne 0) {
        throw 'Der aktuelle Git-Branch konnte nicht gelesen werden.'
    }

    $branch = [string]($branchOutput | Select-Object -First 1)
    $branch = $branch.Trim()

    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Es ist kein aktiver Git-Branch ausgewählt.'
    }

    Write-Host "Pushe Branch '$branch' ..." -ForegroundColor Cyan
    Invoke-Git -GitArguments @('push', '-u', 'origin', $branch)

    Write-Host "Erstelle Release-Tag '$tag' ..." -ForegroundColor Cyan
    Invoke-Git -GitArguments @('tag', '-a', $tag, '-m', "Aschente Launcher $versionNumber")
    Invoke-Git -GitArguments @('push', 'origin', $tag)

    Write-Host ''
    Write-Host 'Fertig. GitHub Actions baut jetzt Installer.exe und Aschente-Launcher-win-x64.zip.' -ForegroundColor Green
    Write-Host 'Build-Status: https://github.com/FionaAleksic/Aschente-Launcher/actions'
    Write-Host 'Releases:     https://github.com/FionaAleksic/Aschente-Launcher/releases'
}
finally {
    Pop-Location
}
