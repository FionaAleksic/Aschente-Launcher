[CmdletBinding()]
param(
    [switch]$ResetConfiguration
)

$ErrorActionPreference = 'Stop'

function Restart-InStaMode {
    try {
        if ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') { return }

        $hostExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath))
        if ($ResetConfiguration) { $arguments += '-ResetConfiguration' }

        Start-Process -FilePath $hostExe -ArgumentList ($arguments -join ' ')
        exit
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Die Anwendung konnte nicht im STA-Modus neu gestartet werden.`n`n$($_.Exception.Message)",
            'Aschente Launcher',
            'OK',
            'Error'
        ) | Out-Null
        exit 1
    }
}

Restart-InStaMode

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:AppName = 'Aschente Launcher'
$script:AppVersion = if ([string]::IsNullOrWhiteSpace($env:ASCHENTE_VERSION)) { '0.3.0' } else { $env:ASCHENTE_VERSION.TrimStart('v') }
$script:InstallDirectory = if ([string]::IsNullOrWhiteSpace($env:ASCHENTE_INSTALL_DIR)) { Split-Path -Parent $PSCommandPath } else { $env:ASCHENTE_INSTALL_DIR }
$script:DataDirectory = if ([string]::IsNullOrWhiteSpace($env:ASCHENTE_DATA_DIR)) { Join-Path $script:InstallDirectory 'Data' } else { $env:ASCHENTE_DATA_DIR }
$script:BrandImagePath = $env:ASCHENTE_BRAND_IMAGE
$script:ConfigPath = Join-Path $script:DataDirectory 'config.json'
$script:LibraryPath = Join-Path $script:DataDirectory 'library.json'
$script:LogPath = Join-Path $script:DataDirectory 'app.log'
$script:Config = $null
$script:Games = @()
$script:FilteredGames = @()
$script:MainWindow = $null
$script:GameGrid = $null
$script:SearchBox = $null
$script:SourceFilter = $null
$script:FavoritesOnly = $null
$script:StatusText = $null
$script:DetailTitle = $null
$script:DetailSource = $null
$script:DetailPath = $null
$script:DetailTarget = $null
$script:DetailWarning = $null
$script:WarningBorder = $null
$script:LaunchButton = $null
$script:FavoriteButton = $null
$script:OpenFolderButton = $null
$script:EditButton = $null
$script:HideButton = $null
$script:IsScanning = $false

$script:DefaultConfig = [ordered]@{
    Version = 1
    SetupComplete = $false
    ScanOnStartup = $true
    SteamEnabled = $true
    SteamPath = ''
    LocalLibraries = @()
    ScanMaxDepth = 5
    IncludeHiddenFolders = $false
    ShowHiddenGames = $false
    ShowMissingGames = $true
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO'
    )

    try {
        if (-not (Test-Path $script:DataDirectory)) {
            New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
        }
        $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
    catch { }
}

function Show-Error {
    param([string]$Message, [string]$Title = $script:AppName)
    Write-Log -Message $Message -Level ERROR
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
}

function Show-Info {
    param([string]$Message, [string]$Title = $script:AppName)
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
}

function Get-BrandImageSource {
    if ([string]::IsNullOrWhiteSpace($script:BrandImagePath) -or -not (Test-Path -LiteralPath $script:BrandImagePath)) {
        return $null
    }

    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri([IO.Path]::GetFullPath($script:BrandImagePath), [UriKind]::Absolute)
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    }
    catch { return $null }
}

function Set-WindowBranding {
    param([Parameter(Mandatory)]$Window)
    $source = Get-BrandImageSource
    if (-not $source) { return }

    try { $Window.Icon = $source } catch { }
    try {
        $image = $Window.FindName('BrandImage')
        if ($image) { $image.Source = $source }
    }
    catch { }
}

function Ensure-DataDirectory {
    if (-not (Test-Path $script:DataDirectory)) {
        New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
    }
}

function ConvertTo-MutableObject {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    return ($InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string]$Path
    )

    Ensure-DataDirectory
    $tempPath = "$Path.tmp"
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Load-Configuration {
    Ensure-DataDirectory

    if ($ResetConfiguration) {
        Remove-Item -LiteralPath $script:ConfigPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:LibraryPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $script:ConfigPath)) {
        $script:Config = ConvertTo-MutableObject $script:DefaultConfig
        Save-Configuration
        return
    }

    try {
        $loaded = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Config = ConvertTo-MutableObject $script:DefaultConfig

        foreach ($property in $loaded.PSObject.Properties) {
            $existingProperty = $script:Config.PSObject.Properties[$property.Name]
            if ($null -ne $existingProperty) {
                $existingProperty.Value = $property.Value
            }
            else {
                $script:Config | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
        }

        if ($null -eq $script:Config.LocalLibraries) {
            $script:Config.LocalLibraries = @()
        }
    }
    catch {
        $backup = "$script:ConfigPath.broken-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $script:ConfigPath -Destination $backup -Force -ErrorAction SilentlyContinue
        $script:Config = ConvertTo-MutableObject $script:DefaultConfig
        Save-Configuration
        Write-Log -Message "Beschädigte Konfiguration wurde ersetzt: $($_.Exception.Message)" -Level WARN
    }
}

function Save-Configuration {
    Save-JsonFile -Object $script:Config -Path $script:ConfigPath
}

function Load-Library {
    if (-not (Test-Path $script:LibraryPath)) {
        $script:Games = @()
        return
    }

    try {
        $loaded = Get-Content -LiteralPath $script:LibraryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $loaded) {
            $script:Games = @()
        }
        elseif ($loaded -is [System.Array]) {
            $script:Games = @($loaded)
        }
        else {
            $script:Games = @($loaded)
        }
    }
    catch {
        $backup = "$script:LibraryPath.broken-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $script:LibraryPath -Destination $backup -Force -ErrorAction SilentlyContinue
        $script:Games = @()
        Write-Log -Message "Beschädigte Bibliothek wurde ignoriert: $($_.Exception.Message)" -Level WARN
    }
}

function Save-Library {
    Save-JsonFile -Object @($script:Games) -Path $script:LibraryPath
}

function Get-StableHash {
    param([Parameter(Mandatory)] [string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash).Replace('-', '').Substring(0, 24).ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function Normalize-Text {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text.ToLowerInvariant() -replace '[^a-z0-9äöüß]+', ' ').Trim())
}

function Get-CommonSteamPath {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $candidates.Add([string]$reg.SteamPath) }
        if ($reg.SteamExe) { $candidates.Add((Split-Path -Parent ([string]$reg.SteamExe))) }
    }
    catch { }

    try {
        $reg64 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        if ($reg64.InstallPath) { $candidates.Add([string]$reg64.InstallPath) }
    }
    catch { }

    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Steam')) }
    if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path (Join-Path $candidate 'steam.exe'))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return ''
}

function Select-Folder {
    param([string]$Description = 'Ordner auswählen', [string]$InitialPath = '')
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path $InitialPath)) {
        $dialog.SelectedPath = $InitialPath
    }
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Select-Executable {
    param([string]$InitialDirectory = '')
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Programm oder Spielstarter auswählen'
    $dialog.Filter = 'Programme (*.exe;*.bat;*.cmd;*.lnk)|*.exe;*.bat;*.cmd;*.lnk|Alle Dateien (*.*)|*.*'
    $dialog.CheckFileExists = $true
    if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $dialog.InitialDirectory = $InitialDirectory
    }
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

function New-GameObject {
    param(
        [string]$Id,
        [string]$Name,
        [string]$SourceType,
        [string]$SourceName,
        [string]$InstallPath,
        [string]$LaunchType,
        [string]$LaunchTarget,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [bool]$NeedsReview = $false,
        [bool]$IsManual = $false
    )

    return [PSCustomObject][ordered]@{
        Id = $Id
        Name = $Name
        SourceType = $SourceType
        SourceName = $SourceName
        InstallPath = $InstallPath
        LaunchType = $LaunchType
        LaunchTarget = $LaunchTarget
        Arguments = $Arguments
        WorkingDirectory = $WorkingDirectory
        Favorite = $false
        Hidden = $false
        IsMissing = $false
        NeedsReview = $NeedsReview
        IsManual = $IsManual
        IsCustomized = $false
        LastPlayed = $null
        PlayCount = 0
        AddedAt = (Get-Date).ToString('o')
        UpdatedAt = (Get-Date).ToString('o')
    }
}

function Get-FilesLimitedDepth {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [int]$MaxDepth = 5,
        [string[]]$Extensions = @('.exe', '.bat', '.cmd', '.lnk')
    )

    $results = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([PSCustomObject]@{ Path = $Root; Depth = 0 })

    $skipDirectories = @(
        'redist', '_commonredist', 'redistributable', 'redistributables',
        'directx', 'dotnet', 'support', 'installer', 'installers',
        'crashdumps', 'logs', 'screenshots', 'save', 'saves', 'saved',
        'documentation', 'docs', '__macosx', 'node_modules', '.git'
    )

    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue()
        try {
            foreach ($file in Get-ChildItem -LiteralPath $entry.Path -File -ErrorAction SilentlyContinue) {
                if ($Extensions -contains $file.Extension.ToLowerInvariant()) {
                    $results.Add([PSCustomObject]@{ File = $file; Depth = $entry.Depth })
                }
            }

            if ($entry.Depth -ge $MaxDepth) { continue }

            foreach ($directory in Get-ChildItem -LiteralPath $entry.Path -Directory -ErrorAction SilentlyContinue) {
                $name = $directory.Name.ToLowerInvariant()
                if (-not $script:Config.IncludeHiddenFolders -and ($directory.Name.StartsWith('.') -or ($directory.Attributes -band [IO.FileAttributes]::Hidden))) {
                    continue
                }
                if ($skipDirectories -contains $name) { continue }
                $queue.Enqueue([PSCustomObject]@{ Path = $directory.FullName; Depth = ($entry.Depth + 1) })
            }
        }
        catch {
            Write-Log -Message "Ordner konnte nicht vollständig gelesen werden: $($entry.Path) – $($_.Exception.Message)" -Level WARN
        }
    }

    return @($results)
}

function Get-ExecutableScore {
    param(
        [Parameter(Mandatory)] [IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$GameFolderName,
        [int]$Depth = 0
    )

    $score = 0
    $exeName = [IO.Path]::GetFileNameWithoutExtension($File.Name)
    $normalizedExe = Normalize-Text $exeName
    $normalizedFolder = Normalize-Text $GameFolderName

    $badPatterns = @(
        'unins', 'uninstall', 'setup', 'install', 'repair', 'crash', 'report',
        'diagnostic', 'benchmark', 'config', 'settings', 'updater', 'update',
        'patcher', 'helper', 'service', 'server', 'editor', 'modmanager',
        'mod loader', 'easyanticheat', 'eac', 'battleye', 'unitycrashhandler',
        'vc redist', 'vcredist', 'dxsetup', 'launcherhelper', 'cefprocess',
        'qtwebengineprocess', 'notification', 'telemetry'
    )

    foreach ($pattern in $badPatterns) {
        if ($normalizedExe -like "*$pattern*") { $score -= 120 }
    }

    if ($normalizedExe -eq $normalizedFolder) { $score += 180 }
    elseif ($normalizedFolder -and ($normalizedExe.Contains($normalizedFolder) -or $normalizedFolder.Contains($normalizedExe))) { $score += 90 }

    $folderTokens = @($normalizedFolder -split ' ' | Where-Object { $_.Length -ge 3 })
    foreach ($token in $folderTokens) {
        if ($normalizedExe -like "*$token*") { $score += 16 }
    }

    if ($normalizedExe -match 'launcher|start|play') { $score += 20 }
    if ($normalizedExe -match 'shipping|win64') { $score += 25 }
    if ($File.Extension -eq '.exe') { $score += 25 }
    elseif ($File.Extension -eq '.lnk') { $score += 10 }

    try {
        if ($File.Length -gt 100MB) { $score += 35 }
        elseif ($File.Length -gt 20MB) { $score += 25 }
        elseif ($File.Length -gt 2MB) { $score += 10 }
        elseif ($File.Length -lt 100KB -and $File.Extension -eq '.exe') { $score -= 10 }
    }
    catch { }

    $score -= ($Depth * 4)
    if ($Depth -eq 0) { $score += 18 }

    return $score
}

function Find-BestLauncher {
    param([Parameter(Mandatory)] [string]$GameDirectory)

    $folderName = Split-Path -Leaf $GameDirectory
    $candidates = Get-FilesLimitedDepth -Root $GameDirectory -MaxDepth ([int]$script:Config.ScanMaxDepth)
    $scored = @()

    foreach ($candidate in $candidates) {
        $score = Get-ExecutableScore -File $candidate.File -GameFolderName $folderName -Depth $candidate.Depth
        $scored += [PSCustomObject]@{
            Path = $candidate.File.FullName
            WorkingDirectory = $candidate.File.DirectoryName
            Score = $score
            Depth = $candidate.Depth
            Size = $candidate.File.Length
        }
    }

    $ordered = @($scored | Sort-Object Score, Size -Descending)
    if ($ordered.Count -eq 0) {
        return [PSCustomObject]@{ Path = ''; WorkingDirectory = $GameDirectory; NeedsReview = $true; Score = -999 }
    }

    $best = $ordered[0]
    $needsReview = ($best.Score -lt 25)
    if ($ordered.Count -gt 1 -and (($best.Score - $ordered[1].Score) -lt 12)) {
        $needsReview = $true
    }

    return [PSCustomObject]@{
        Path = $best.Path
        WorkingDirectory = $best.WorkingDirectory
        NeedsReview = $needsReview
        Score = $best.Score
    }
}

function Scan-LocalLibrary {
    param($Library)

    $games = New-Object System.Collections.Generic.List[object]
    $root = [string]$Library.Path
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Log -Message "Lokaler Bibliothekspfad fehlt: $root" -Level WARN
        return @()
    }

    try {
        $directories = Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop
        foreach ($directory in $directories) {
            if (-not $script:Config.IncludeHiddenFolders -and ($directory.Name.StartsWith('.') -or ($directory.Attributes -band [IO.FileAttributes]::Hidden))) {
                continue
            }

            $launcher = Find-BestLauncher -GameDirectory $directory.FullName
            $id = 'local:' + (Get-StableHash $directory.FullName)
            $game = New-GameObject `
                -Id $id `
                -Name $directory.Name `
                -SourceType 'Local' `
                -SourceName ([string]$Library.Name) `
                -InstallPath $directory.FullName `
                -LaunchType 'Executable' `
                -LaunchTarget $launcher.Path `
                -WorkingDirectory $launcher.WorkingDirectory `
                -NeedsReview ([bool]$launcher.NeedsReview)
            $games.Add($game)
        }

        foreach ($file in Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue) {
            if (@('.exe', '.bat', '.cmd', '.lnk') -notcontains $file.Extension.ToLowerInvariant()) { continue }
            $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ((Get-ExecutableScore -File $file -GameFolderName $name -Depth 0) -lt -20) { continue }

            $id = 'localfile:' + (Get-StableHash $file.FullName)
            $game = New-GameObject `
                -Id $id `
                -Name $name `
                -SourceType 'Local' `
                -SourceName ([string]$Library.Name) `
                -InstallPath $root `
                -LaunchType 'Executable' `
                -LaunchTarget $file.FullName `
                -WorkingDirectory $root `
                -NeedsReview $false
            $games.Add($game)
        }
    }
    catch {
        Write-Log -Message "Lokale Bibliothek konnte nicht gescannt werden: $root – $($_.Exception.Message)" -Level ERROR
    }

    return @($games)
}

function Read-VdfValue {
    param([string]$Content, [string]$Key)
    $escaped = [Regex]::Escape($Key)
    $match = [Regex]::Match($Content, '"' + $escaped + '"\s+"([^"]*)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Get-SteamLibraries {
    param([Parameter(Mandatory)] [string]$SteamPath)

    $libraries = New-Object System.Collections.Generic.List[string]
    $primary = Join-Path $SteamPath 'steamapps'
    if (Test-Path $primary) { $libraries.Add($primary) }

    $vdf = Join-Path $primary 'libraryfolders.vdf'
    if (Test-Path $vdf) {
        try {
            $content = Get-Content -LiteralPath $vdf -Raw -Encoding UTF8
            $matches = [Regex]::Matches($content, '"path"\s+"([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $path = $match.Groups[1].Value -replace '\\\\', '\'
                $steamApps = Join-Path $path 'steamapps'
                if (Test-Path $steamApps) { $libraries.Add($steamApps) }
            }
        }
        catch {
            Write-Log -Message "Steam-Bibliotheksdatei konnte nicht gelesen werden: $($_.Exception.Message)" -Level WARN
        }
    }

    return @($libraries | Select-Object -Unique)
}

function Scan-SteamLibrary {
    param([Parameter(Mandatory)] [string]$SteamPath)

    $games = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path (Join-Path $SteamPath 'steam.exe'))) {
        Write-Log -Message "Steam wurde am eingestellten Pfad nicht gefunden: $SteamPath" -Level WARN
        return @()
    }

    foreach ($steamApps in Get-SteamLibraries -SteamPath $SteamPath) {
        foreach ($manifest in Get-ChildItem -LiteralPath $steamApps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
            try {
                $content = Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8
                $appId = Read-VdfValue -Content $content -Key 'appid'
                $name = Read-VdfValue -Content $content -Key 'name'
                $installDir = Read-VdfValue -Content $content -Key 'installdir'
                if (-not $appId -or -not $name) { continue }

                $installPath = if ($installDir) { Join-Path (Join-Path $steamApps 'common') $installDir } else { '' }
                $game = New-GameObject `
                    -Id "steam:$appId" `
                    -Name $name `
                    -SourceType 'Steam' `
                    -SourceName 'Steam' `
                    -InstallPath $installPath `
                    -LaunchType 'Uri' `
                    -LaunchTarget "steam://rungameid/$appId" `
                    -WorkingDirectory $installPath `
                    -NeedsReview $false
                $game | Add-Member -NotePropertyName SteamAppId -NotePropertyValue $appId -Force
                $games.Add($game)
            }
            catch {
                Write-Log -Message "Steam-Manifest konnte nicht gelesen werden: $($manifest.FullName) – $($_.Exception.Message)" -Level WARN
            }
        }
    }

    return @($games)
}

function Merge-DetectedGames {
    param([object[]]$Detected)

    $oldById = @{}
    foreach ($old in @($script:Games)) {
        if ($old.Id) { $oldById[[string]$old.Id] = $old }
    }

    $merged = New-Object System.Collections.Generic.List[object]
    $detectedIds = New-Object System.Collections.Generic.HashSet[string]

    foreach ($game in @($Detected)) {
        [void]$detectedIds.Add([string]$game.Id)
        if ($oldById.ContainsKey([string]$game.Id)) {
            $old = $oldById[[string]$game.Id]
            foreach ($property in @('Favorite', 'Hidden', 'LastPlayed', 'PlayCount', 'AddedAt', 'IsCustomized')) {
                if ($null -ne $old.PSObject.Properties[$property]) {
                    $game.$property = $old.$property
                }
            }

            if ($old.IsCustomized) {
                foreach ($property in @('Name', 'LaunchType', 'LaunchTarget', 'Arguments', 'WorkingDirectory', 'NeedsReview')) {
                    if ($null -ne $old.PSObject.Properties[$property]) {
                        $game.$property = $old.$property
                    }
                }
            }
        }
        $game.IsMissing = $false
        $game.UpdatedAt = (Get-Date).ToString('o')
        $merged.Add($game)
    }

    foreach ($old in @($script:Games)) {
        if ($old.IsManual) {
            $merged.Add($old)
            continue
        }

        if (-not $detectedIds.Contains([string]$old.Id)) {
            $old.IsMissing = $true
            $merged.Add($old)
        }
    }

    $script:Games = @($merged | Group-Object Id | ForEach-Object { $_.Group | Select-Object -First 1 })
    Save-Library
}

function Invoke-LibraryScan {
    if ($script:IsScanning) { return }
    $script:IsScanning = $true

    try {
        if ($script:StatusText) { $script:StatusText.Text = 'Bibliothek wird gescannt …' }
        if ($script:MainWindow) { $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Wait }
        [System.Windows.Forms.Application]::DoEvents()

        $detected = New-Object System.Collections.Generic.List[object]
        foreach ($library in @($script:Config.LocalLibraries)) {
            if ($null -ne $library.Enabled -and -not [bool]$library.Enabled) { continue }
            foreach ($game in Scan-LocalLibrary -Library $library) { $detected.Add($game) }
        }

        if ($script:Config.SteamEnabled) {
            $steamPath = [string]$script:Config.SteamPath
            if (-not $steamPath) {
                $steamPath = Get-CommonSteamPath
                if ($steamPath) {
                    $script:Config.SteamPath = $steamPath
                    Save-Configuration
                }
            }
            if ($steamPath) {
                foreach ($game in Scan-SteamLibrary -SteamPath $steamPath) { $detected.Add($game) }
            }
        }

        Merge-DetectedGames -Detected @($detected)
        Apply-GameFilter
        if ($script:StatusText) {
            $reviewCount = @($script:Games | Where-Object { $_.NeedsReview -and -not $_.Hidden }).Count
            $script:StatusText.Text = "$(@($script:Games | Where-Object { -not $_.Hidden }).Count) Spiele – $reviewCount Einträge prüfen"
        }
    }
    catch {
        Show-Error "Der Scan wurde mit einem Fehler beendet:`n`n$($_.Exception.Message)"
    }
    finally {
        if ($script:MainWindow) { $script:MainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow }
        $script:IsScanning = $false
    }
}

function Get-GameStatusText {
    param($Game)
    if ($Game.IsMissing) { return 'Nicht gefunden' }
    if ($Game.NeedsReview) { return 'Starter prüfen' }
    if (-not $Game.LaunchTarget) { return 'Kein Starter' }
    return 'Bereit'
}

function Get-GameDisplayRows {
    param([object[]]$Games)

    foreach ($game in @($Games)) {
        [PSCustomObject]@{
            Name = [string]$game.Name
            Source = [string]$game.SourceName
            Type = [string]$game.SourceType
            Status = Get-GameStatusText $game
            Favorite = if ($game.Favorite) { '★' } else { '' }
            Game = $game
        }
    }
}

function Apply-GameFilter {
    if (-not $script:GameGrid) { return }

    $search = if ($script:SearchBox) { [string]$script:SearchBox.Text } else { '' }
    $search = $search.Trim()
    $source = if ($script:SourceFilter -and $script:SourceFilter.SelectedItem) {
        [string]$script:SourceFilter.SelectedItem.Content
    } else { 'Alle Quellen' }
    $favoritesOnly = if ($script:FavoritesOnly) { [bool]$script:FavoritesOnly.IsChecked } else { $false }

    $filtered = @($script:Games | Where-Object {
        $game = $_
        if (-not $script:Config.ShowHiddenGames -and $game.Hidden) { return $false }
        if (-not $script:Config.ShowMissingGames -and $game.IsMissing) { return $false }
        if ($favoritesOnly -and -not $game.Favorite) { return $false }
        if ($source -ne 'Alle Quellen' -and $game.SourceName -ne $source -and $game.SourceType -ne $source) { return $false }
        if ($search -and ($game.Name -notlike "*$search*" -and $game.SourceName -notlike "*$search*" -and $game.InstallPath -notlike "*$search*")) { return $false }
        return $true
    } | Sort-Object @{ Expression = { -not [bool]$_.Favorite } }, Name)

    $script:FilteredGames = $filtered
    $rows = @(Get-GameDisplayRows -Games $filtered)
    $script:GameGrid.ItemsSource = $rows

    if ($rows.Count -gt 0) {
        $script:GameGrid.SelectedIndex = 0
    }
    else {
        Update-GameDetails -Game $null
    }
}

function Get-SelectedGame {
    if (-not $script:GameGrid -or -not $script:GameGrid.SelectedItem) { return $null }
    return $script:GameGrid.SelectedItem.Game
}

function Update-GameDetails {
    param($Game)

    $hasGame = $null -ne $Game
    foreach ($button in @($script:LaunchButton, $script:FavoriteButton, $script:OpenFolderButton, $script:EditButton, $script:HideButton)) {
        if ($button) { $button.IsEnabled = $hasGame }
    }

    if (-not $hasGame) {
        $script:DetailTitle.Text = 'Kein Spiel ausgewählt'
        $script:DetailSource.Text = ''
        $script:DetailPath.Text = ''
        $script:DetailTarget.Text = ''
        $script:WarningBorder.Visibility = 'Collapsed'
        return
    }

    $script:DetailTitle.Text = [string]$Game.Name
    $script:DetailSource.Text = "Quelle: $($Game.SourceName)"
    $script:DetailPath.Text = if ($Game.InstallPath) { "Ordner: $($Game.InstallPath)" } else { 'Ordner: –' }
    $script:DetailTarget.Text = if ($Game.LaunchTarget) { "Starter: $($Game.LaunchTarget)" } else { 'Starter: nicht festgelegt' }
    $script:FavoriteButton.Content = if ($Game.Favorite) { '★ Aus Favoriten entfernen' } else { '☆ Zu Favoriten' }
    $script:HideButton.Content = if ($Game.Hidden) { 'Wieder einblenden' } else { 'Ausblenden' }

    if ($Game.IsMissing) {
        $script:DetailWarning.Text = 'Der gespeicherte Installationsort wurde beim letzten Scan nicht gefunden.'
        $script:WarningBorder.Visibility = 'Visible'
    }
    elseif ($Game.NeedsReview) {
        $script:DetailWarning.Text = 'Der automatisch gewählte Starter ist unsicher. Bitte den Eintrag bearbeiten und die richtige Datei auswählen.'
        $script:WarningBorder.Visibility = 'Visible'
    }
    else {
        $script:WarningBorder.Visibility = 'Collapsed'
    }

    $script:LaunchButton.IsEnabled = [bool]$Game.LaunchTarget -and -not [bool]$Game.IsMissing
}

function Start-Game {
    param($Game)
    if ($null -eq $Game) { return }
    if (-not $Game.LaunchTarget) {
        Show-Info 'Für dieses Spiel wurde noch kein Starter festgelegt. Öffne „Bearbeiten“ und wähle die passende Datei aus.'
        return
    }

    try {
        if ($Game.LaunchType -eq 'Uri') {
            Start-Process -FilePath ([string]$Game.LaunchTarget)
        }
        else {
            $parameters = @{
                FilePath = [string]$Game.LaunchTarget
            }
            if ($Game.Arguments) { $parameters.ArgumentList = [string]$Game.Arguments }
            if ($Game.WorkingDirectory -and (Test-Path -LiteralPath $Game.WorkingDirectory)) {
                $parameters.WorkingDirectory = [string]$Game.WorkingDirectory
            }
            Start-Process @parameters
        }

        $Game.LastPlayed = (Get-Date).ToString('o')
        $Game.PlayCount = [int]$Game.PlayCount + 1
        Save-Library
        Update-GameDetails -Game $Game
    }
    catch {
        Show-Error "Das Spiel konnte nicht gestartet werden:`n`n$($_.Exception.Message)"
    }
}

function Open-GameFolder {
    param($Game)
    if ($null -eq $Game) { return }
    $path = [string]$Game.InstallPath
    if (-not $path -and $Game.LaunchTarget -and $Game.LaunchType -ne 'Uri') {
        $path = Split-Path -Parent ([string]$Game.LaunchTarget)
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path)
    }
    else {
        Show-Info 'Der Installationsordner wurde nicht gefunden.'
    }
}

function Show-GameEditor {
    param($Game = $null)

    $isNew = $null -eq $Game
    if ($isNew) {
        $Game = New-GameObject `
            -Id ('manual:' + [guid]::NewGuid().ToString('N')) `
            -Name '' `
            -SourceType 'Manual' `
            -SourceName 'Manuell' `
            -InstallPath '' `
            -LaunchType 'Executable' `
            -LaunchTarget '' `
            -WorkingDirectory '' `
            -NeedsReview $false `
            -IsManual $true
    }

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Spiel bearbeiten" Width="650" Height="470" WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize" Background="#11131A" Foreground="#F2F4F8">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#20242F"/><Setter Property="Foreground" Value="#F2F4F8"/>
            <Setter Property="BorderBrush" Value="#3B4150"/><Setter Property="Padding" Value="8"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#343B4A"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="14,8"/><Setter Property="Margin" Value="4"/>
        </Style>
        <Style TargetType="Label"><Setter Property="Foreground" Value="#C8CDD8"/></Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Name" FontWeight="SemiBold"/>
        <TextBox x:Name="NameBox" Grid.Row="1" Margin="0,6,0,14"/>
        <TextBlock Grid.Row="2" Text="Starter (.exe, .bat, .cmd oder .lnk)" FontWeight="SemiBold"/>
        <Grid Grid.Row="3" Margin="0,6,0,14">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBox x:Name="TargetBox"/>
            <Button x:Name="BrowseButton" Grid.Column="1" Content="Durchsuchen …" Margin="8,0,0,0"/>
        </Grid>
        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Startargumente (optional)" FontWeight="SemiBold"/>
                <TextBox x:Name="ArgumentsBox" Margin="0,6,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="2">
                <TextBlock Text="Arbeitsordner" FontWeight="SemiBold"/>
                <TextBox x:Name="WorkingBox" Margin="0,6,0,0"/>
            </StackPanel>
        </Grid>
        <TextBlock Grid.Row="5" Margin="0,18,0,0" Foreground="#9EA6B5" TextWrapping="Wrap"
                   Text="Bei Steam-Spielen wird normalerweise die Steam-URI verwendet. Ein manuell ausgewählter Starter überschreibt die automatische Erkennung dauerhaft."/>
        <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="CancelButton" Content="Abbrechen"/>
            <Button x:Name="SaveButton" Content="Speichern" Background="#6D5EF7"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowBranding -Window $window
    $window.Owner = $script:MainWindow

    $nameBox = $window.FindName('NameBox')
    $targetBox = $window.FindName('TargetBox')
    $argumentsBox = $window.FindName('ArgumentsBox')
    $workingBox = $window.FindName('WorkingBox')
    $browseButton = $window.FindName('BrowseButton')
    $saveButton = $window.FindName('SaveButton')
    $cancelButton = $window.FindName('CancelButton')

    $nameBox.Text = [string]$Game.Name
    $targetBox.Text = [string]$Game.LaunchTarget
    $argumentsBox.Text = [string]$Game.Arguments
    $workingBox.Text = [string]$Game.WorkingDirectory

    $browseButton.Add_Click({
        $initial = if ($workingBox.Text) { $workingBox.Text } elseif ($Game.InstallPath) { $Game.InstallPath } else { '' }
        $selected = Select-Executable -InitialDirectory $initial
        if ($selected) {
            $targetBox.Text = $selected
            $workingBox.Text = Split-Path -Parent $selected
            if (-not $nameBox.Text) { $nameBox.Text = [IO.Path]::GetFileNameWithoutExtension($selected) }
        }
    })

    $cancelButton.Add_Click({ $window.DialogResult = $false; $window.Close() })
    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($nameBox.Text)) {
            Show-Info 'Bitte gib einen Namen ein.' 'Spiel bearbeiten'
            return
        }
        if ([string]::IsNullOrWhiteSpace($targetBox.Text)) {
            Show-Info 'Bitte wähle einen Starter aus.' 'Spiel bearbeiten'
            return
        }

        $Game.Name = $nameBox.Text.Trim()
        $Game.LaunchTarget = $targetBox.Text.Trim()
        $Game.Arguments = $argumentsBox.Text.Trim()
        $Game.WorkingDirectory = $workingBox.Text.Trim()
        $Game.InstallPath = if ($Game.WorkingDirectory) { $Game.WorkingDirectory } else { Split-Path -Parent $Game.LaunchTarget }
        $Game.LaunchType = if ($Game.LaunchTarget -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { 'Uri' } else { 'Executable' }
        $Game.NeedsReview = $false
        $Game.IsCustomized = $true
        $Game.UpdatedAt = (Get-Date).ToString('o')

        if ($isNew) { $script:Games += $Game }
        Save-Library
        $window.DialogResult = $true
        $window.Close()
    })

    if ($window.ShowDialog() -eq $true) {
        Apply-GameFilter
    }
}

function Show-SettingsWindow {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen" Width="760" Height="640" WindowStartupLocation="CenterOwner"
        Background="#11131A" Foreground="#F2F4F8">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#343B4A"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="13,8"/><Setter Property="Margin" Value="4"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#20242F"/><Setter Property="Foreground" Value="#F2F4F8"/>
            <Setter Property="BorderBrush" Value="#3B4150"/><Setter Property="Padding" Value="8"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E7EAF0"/><Setter Property="Margin" Value="0,6"/></Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="210"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Lokale Bibliotheksordner" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <ListBox x:Name="LibraryList" Grid.Row="1" Background="#181B24" Foreground="White" BorderBrush="#303644"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,8,0,22">
            <Button x:Name="AddLibraryButton" Content="Ordner hinzufügen"/>
            <Button x:Name="RemoveLibraryButton" Content="Ausgewählten entfernen"/>
        </StackPanel>
        <TextBlock Grid.Row="3" Text="Steam" FontSize="20" FontWeight="SemiBold"/>
        <StackPanel Grid.Row="4" Margin="0,6,0,14">
            <CheckBox x:Name="SteamCheck" Content="Installierte Steam-Spiele einlesen"/>
            <Grid Margin="0,6,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBox x:Name="SteamPathBox"/>
                <Button x:Name="SteamBrowseButton" Grid.Column="1" Content="Steam-Ordner …" Margin="8,0,0,0"/>
            </Grid>
        </StackPanel>
        <StackPanel Grid.Row="5">
            <TextBlock Text="Verhalten" FontSize="20" FontWeight="SemiBold"/>
            <CheckBox x:Name="StartupScanCheck" Content="Bibliothek beim Programmstart neu scannen"/>
            <CheckBox x:Name="MissingCheck" Content="Nicht gefundene Spiele weiterhin anzeigen"/>
            <CheckBox x:Name="HiddenFoldersCheck" Content="Versteckte Ordner beim Scan berücksichtigen"/>
            <TextBlock Text="Maximale Suchtiefe für Spielstarter" Margin="0,12,0,4" Foreground="#C8CDD8"/>
            <ComboBox x:Name="DepthBox" Width="120" HorizontalAlignment="Left" Background="#20242F" Foreground="White">
                <ComboBoxItem Content="2"/><ComboBoxItem Content="3"/><ComboBoxItem Content="4"/>
                <ComboBoxItem Content="5"/><ComboBoxItem Content="6"/><ComboBoxItem Content="7"/><ComboBoxItem Content="8"/>
            </ComboBox>
        </StackPanel>
        <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="OpenDataButton" Content="Datenordner öffnen"/>
            <Button x:Name="CancelButton" Content="Abbrechen"/>
            <Button x:Name="SaveButton" Content="Speichern und scannen" Background="#6D5EF7"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowBranding -Window $window
    $window.Owner = $script:MainWindow

    $libraryList = $window.FindName('LibraryList')
    $addLibraryButton = $window.FindName('AddLibraryButton')
    $removeLibraryButton = $window.FindName('RemoveLibraryButton')
    $steamCheck = $window.FindName('SteamCheck')
    $steamPathBox = $window.FindName('SteamPathBox')
    $steamBrowseButton = $window.FindName('SteamBrowseButton')
    $startupScanCheck = $window.FindName('StartupScanCheck')
    $missingCheck = $window.FindName('MissingCheck')
    $hiddenFoldersCheck = $window.FindName('HiddenFoldersCheck')
    $depthBox = $window.FindName('DepthBox')
    $openDataButton = $window.FindName('OpenDataButton')
    $saveButton = $window.FindName('SaveButton')
    $cancelButton = $window.FindName('CancelButton')

    $workingLibraries = New-Object System.Collections.ArrayList
    foreach ($library in @($script:Config.LocalLibraries)) {
        [void]$workingLibraries.Add([PSCustomObject]@{
            Id = [string]$library.Id
            Name = [string]$library.Name
            Path = [string]$library.Path
            Enabled = if ($null -eq $library.Enabled) { $true } else { [bool]$library.Enabled }
        })
    }

    function Refresh-SettingsLibraryList {
        $libraryList.Items.Clear()
        foreach ($library in $workingLibraries) {
            [void]$libraryList.Items.Add("$($library.Name) — $($library.Path)")
        }
    }

    Refresh-SettingsLibraryList
    $steamCheck.IsChecked = [bool]$script:Config.SteamEnabled
    $steamPathBox.Text = [string]$script:Config.SteamPath
    $startupScanCheck.IsChecked = [bool]$script:Config.ScanOnStartup
    $missingCheck.IsChecked = [bool]$script:Config.ShowMissingGames
    $hiddenFoldersCheck.IsChecked = [bool]$script:Config.IncludeHiddenFolders

    foreach ($item in $depthBox.Items) {
        if ([int]$item.Content -eq [int]$script:Config.ScanMaxDepth) { $depthBox.SelectedItem = $item; break }
    }
    if (-not $depthBox.SelectedItem) { $depthBox.SelectedIndex = 3 }

    $addLibraryButton.Add_Click({
        $path = Select-Folder -Description 'Ordner auswählen, dessen direkte Unterordner einzelne Spiele enthalten'
        if (-not $path) { return }
        if (@($workingLibraries | Where-Object { $_.Path -eq $path }).Count -gt 0) {
            Show-Info 'Dieser Ordner ist bereits eingetragen.' 'Einstellungen'
            return
        }
        $name = Split-Path -Leaf $path
        if (-not $name) { $name = $path }
        [void]$workingLibraries.Add([PSCustomObject]@{
            Id = [guid]::NewGuid().ToString('N')
            Name = $name
            Path = $path
            Enabled = $true
        })
        Refresh-SettingsLibraryList
        $libraryList.SelectedIndex = $libraryList.Items.Count - 1
    })

    $removeLibraryButton.Add_Click({
        if ($libraryList.SelectedIndex -lt 0) { return }
        $workingLibraries.RemoveAt($libraryList.SelectedIndex)
        Refresh-SettingsLibraryList
    })

    $steamBrowseButton.Add_Click({
        $path = Select-Folder -Description 'Steam-Installationsordner auswählen' -InitialPath $steamPathBox.Text
        if ($path) { $steamPathBox.Text = $path }
    })

    $openDataButton.Add_Click({
        Ensure-DataDirectory
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:DataDirectory)
    })

    $cancelButton.Add_Click({ $window.DialogResult = $false; $window.Close() })
    $saveButton.Add_Click({
        $script:Config.LocalLibraries = @($workingLibraries)
        $script:Config.SteamEnabled = [bool]$steamCheck.IsChecked
        $script:Config.SteamPath = $steamPathBox.Text.Trim()
        $script:Config.ScanOnStartup = [bool]$startupScanCheck.IsChecked
        $script:Config.ShowMissingGames = [bool]$missingCheck.IsChecked
        $script:Config.IncludeHiddenFolders = [bool]$hiddenFoldersCheck.IsChecked
        $script:Config.ScanMaxDepth = [int]$depthBox.SelectedItem.Content
        Save-Configuration
        $window.DialogResult = $true
        $window.Close()
    })

    if ($window.ShowDialog() -eq $true) {
        Invoke-LibraryScan
        Refresh-SourceFilter
    }
}

function Show-SetupWizard {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Aschente Launcher – Einrichtung" Width="820" Height="590"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#10121A" Foreground="#F4F6FA">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#343B4A"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="16,9"/><Setter Property="Margin" Value="4"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#20242F"/><Setter Property="Foreground" Value="#F2F4F8"/>
            <Setter Property="BorderBrush" Value="#3B4150"/><Setter Property="Padding" Value="8"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E7EAF0"/><Setter Property="Margin" Value="0,8"/></Style>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="215"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Background="#171A24" Padding="24">
            <StackPanel>
                <Image x:Name="BrandImage" Width="142" Height="142" Stretch="Uniform" HorizontalAlignment="Left" Margin="0,0,0,18"/>
                <TextBlock Text="ASCHENTE" FontSize="25" FontWeight="Bold"/>
                <TextBlock Text="GAME LIBRARY" FontSize="13" Foreground="#9EA6B5" Margin="0,2,0,24"/>
                <TextBlock x:Name="StepIndicator" Text="Schritt 1 von 4" Foreground="#AFA7FF" FontWeight="SemiBold"/>
                <TextBlock Text="Alles bleibt auf diesem PC." TextWrapping="Wrap" Margin="0,22,0,0" Foreground="#BBC1CC"/>
            </StackPanel>
        </Border>
        <Grid Grid.Column="1" Margin="34,28,34,24">
            <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid x:Name="PageHost">
                <Grid x:Name="Page1">
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Deine Spiele. Deine Bibliothek." FontSize="31" FontWeight="Bold"/>
                        <TextBlock Margin="0,18,0,0" FontSize="16" Foreground="#C6CBD5" TextWrapping="Wrap"
                                   Text="Diese Anwendung erstellt eine lokale Übersicht über installierte Spiele. Sie benötigt kein Konto und sendet keine Bibliotheksdaten ins Internet."/>
                        <Border Margin="0,28,0,0" Background="#191D27" CornerRadius="8" Padding="18">
                            <TextBlock Foreground="#DDE1E8" TextWrapping="Wrap"
                                       Text="Du bestimmst gleich selbst, welche Ordner gescannt werden. Die Auswahl lässt sich später jederzeit in den Einstellungen ändern."/>
                        </Border>
                    </StackPanel>
                </Grid>
                <Grid x:Name="Page2" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <TextBlock Text="Lokale Spielordner" FontSize="30" FontWeight="Bold"/>
                    <TextBlock Grid.Row="1" Margin="0,12,0,14" Foreground="#C6CBD5" TextWrapping="Wrap"
                               Text="Wähle Ordner, deren direkte Unterordner jeweils ein Spiel enthalten. Beispiel: D:\Spiele\Spielname\Spiel.exe"/>
                    <ListBox x:Name="WizardLibraryList" Grid.Row="2" Background="#191D27" Foreground="White" BorderBrush="#303644"/>
                    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0">
                        <Button x:Name="WizardAddLibrary" Content="Ordner hinzufügen"/>
                        <Button x:Name="WizardRemoveLibrary" Content="Entfernen"/>
                    </StackPanel>
                </Grid>
                <Grid x:Name="Page3" Visibility="Collapsed">
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Steam einbinden" FontSize="30" FontWeight="Bold"/>
                        <TextBlock Margin="0,12,0,20" Foreground="#C6CBD5" TextWrapping="Wrap"
                                   Text="Steam kann automatisch erkannt werden. Dabei werden ausschließlich lokale Manifestdateien gelesen."/>
                        <CheckBox x:Name="WizardSteamCheck" Content="Installierte Steam-Spiele anzeigen" FontSize="16"/>
                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBox x:Name="WizardSteamPath"/>
                            <Button x:Name="WizardSteamBrowse" Grid.Column="1" Content="Ordner auswählen …" Margin="8,0,0,0"/>
                        </Grid>
                        <TextBlock Margin="0,12,0,0" Foreground="#929AA9" Text="Das Feld darf leer bleiben, wenn Steam automatisch erkannt werden soll."/>
                    </StackPanel>
                </Grid>
                <Grid x:Name="Page4" Visibility="Collapsed">
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Bereit zum ersten Scan" FontSize="30" FontWeight="Bold"/>
                        <TextBlock Margin="0,14,0,20" Foreground="#C6CBD5" TextWrapping="Wrap"
                                   Text="Die Anwendung durchsucht nur die ausgewählten Ordner. Gefundene Starter können später pro Spiel korrigiert werden."/>
                        <CheckBox x:Name="WizardStartupScan" Content="Beim Programmstart automatisch neu scannen" IsChecked="True"/>
                        <Border Background="#191D27" CornerRadius="8" Padding="16" Margin="0,18,0,0">
                            <TextBlock x:Name="WizardSummary" TextWrapping="Wrap"/>
                        </Border>
                    </StackPanel>
                </Grid>
            </Grid>
            <Grid Grid.Row="1" Margin="0,20,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Button x:Name="WizardBack" Content="Zurück" Visibility="Hidden" HorizontalAlignment="Left"/>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="WizardCancel" Content="Abbrechen"/>
                    <Button x:Name="WizardNext" Content="Weiter" Background="#6D5EF7"/>
                </StackPanel>
            </Grid>
        </Grid>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowBranding -Window $window

    $pages = @(
        $window.FindName('Page1'),
        $window.FindName('Page2'),
        $window.FindName('Page3'),
        $window.FindName('Page4')
    )
    $stepIndicator = $window.FindName('StepIndicator')
    $backButton = $window.FindName('WizardBack')
    $nextButton = $window.FindName('WizardNext')
    $cancelButton = $window.FindName('WizardCancel')
    $libraryList = $window.FindName('WizardLibraryList')
    $addLibraryButton = $window.FindName('WizardAddLibrary')
    $removeLibraryButton = $window.FindName('WizardRemoveLibrary')
    $steamCheck = $window.FindName('WizardSteamCheck')
    $steamPathBox = $window.FindName('WizardSteamPath')
    $steamBrowseButton = $window.FindName('WizardSteamBrowse')
    $startupScanCheck = $window.FindName('WizardStartupScan')
    $summary = $window.FindName('WizardSummary')

    $wizardLibraries = New-Object System.Collections.ArrayList
    foreach ($library in @($script:Config.LocalLibraries)) { [void]$wizardLibraries.Add($library) }
    $steamCheck.IsChecked = [bool]$script:Config.SteamEnabled
    $steamPathBox.Text = if ($script:Config.SteamPath) { [string]$script:Config.SteamPath } else { Get-CommonSteamPath }

    function Refresh-WizardLibraries {
        $libraryList.Items.Clear()
        foreach ($library in $wizardLibraries) {
            [void]$libraryList.Items.Add("$($library.Name) — $($library.Path)")
        }
    }

    function Update-WizardPage {
        param([int]$Index)
        for ($i = 0; $i -lt $pages.Count; $i++) {
            $pages[$i].Visibility = if ($i -eq $Index) { 'Visible' } else { 'Collapsed' }
        }
        $stepIndicator.Text = "Schritt $($Index + 1) von 4"
        $backButton.Visibility = if ($Index -eq 0) { 'Hidden' } else { 'Visible' }
        $nextButton.Content = if ($Index -eq 3) { 'Einrichtung abschließen' } else { 'Weiter' }
        if ($Index -eq 3) {
            $steamText = if ($steamCheck.IsChecked) { 'Steam: aktiviert' } else { 'Steam: deaktiviert' }
            $summary.Text = "Lokale Ordner: $($wizardLibraries.Count)`n$steamText`n`nAlle Angaben können später geändert werden."
        }
    }

    Refresh-WizardLibraries
    $script:WizardPageIndex = 0
    Update-WizardPage -Index $script:WizardPageIndex

    $addLibraryButton.Add_Click({
        $path = Select-Folder -Description 'Ordner auswählen, dessen direkte Unterordner einzelne Spiele enthalten'
        if (-not $path) { return }
        if (@($wizardLibraries | Where-Object { $_.Path -eq $path }).Count -gt 0) { return }
        $name = Split-Path -Leaf $path
        if (-not $name) { $name = $path }
        [void]$wizardLibraries.Add([PSCustomObject]@{
            Id = [guid]::NewGuid().ToString('N')
            Name = $name
            Path = $path
            Enabled = $true
        })
        Refresh-WizardLibraries
    })

    $removeLibraryButton.Add_Click({
        if ($libraryList.SelectedIndex -lt 0) { return }
        $wizardLibraries.RemoveAt($libraryList.SelectedIndex)
        Refresh-WizardLibraries
    })

    $steamBrowseButton.Add_Click({
        $path = Select-Folder -Description 'Steam-Installationsordner auswählen' -InitialPath $steamPathBox.Text
        if ($path) { $steamPathBox.Text = $path }
    })

    $backButton.Add_Click({
        if ($script:WizardPageIndex -gt 0) { $script:WizardPageIndex-- }
        Update-WizardPage -Index $script:WizardPageIndex
    })

    $cancelButton.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $nextButton.Add_Click({
        if ($script:WizardPageIndex -lt 3) {
            $script:WizardPageIndex++
            Update-WizardPage -Index $script:WizardPageIndex
            return
        }

        $script:Config.LocalLibraries = @($wizardLibraries)
        $script:Config.SteamEnabled = [bool]$steamCheck.IsChecked
        $script:Config.SteamPath = $steamPathBox.Text.Trim()
        $script:Config.ScanOnStartup = [bool]$startupScanCheck.IsChecked
        $script:Config.SetupComplete = $true
        Save-Configuration
        $window.DialogResult = $true
        $window.Close()
    })

    return ($window.ShowDialog() -eq $true)
}

function Refresh-SourceFilter {
    if (-not $script:SourceFilter) { return }
    $selected = if ($script:SourceFilter.SelectedItem) { [string]$script:SourceFilter.SelectedItem.Content } else { 'Alle Quellen' }
    $script:SourceFilter.Items.Clear()
    [void]$script:SourceFilter.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{ Content = 'Alle Quellen' }))

    $sources = @($script:Games | ForEach-Object { $_.SourceName } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($source in $sources) {
        [void]$script:SourceFilter.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{ Content = [string]$source }))
    }

    $found = $false
    foreach ($item in $script:SourceFilter.Items) {
        if ([string]$item.Content -eq $selected) {
            $script:SourceFilter.SelectedItem = $item
            $found = $true
            break
        }
    }
    if (-not $found) { $script:SourceFilter.SelectedIndex = 0 }
}

function Show-MainWindow {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Aschente Launcher" Width="1180" Height="720" MinWidth="920" MinHeight="580"
        WindowStartupLocation="CenterScreen" Background="#0F1118" Foreground="#F3F5F8">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#303645"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="14,9"/><Setter Property="Margin" Value="4"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1C202A"/><Setter Property="Foreground" Value="#F2F4F8"/>
            <Setter Property="BorderBrush" Value="#353B49"/><Setter Property="Padding" Value="10"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#1C202A"/><Setter Property="Foreground" Value="#F2F4F8"/>
            <Setter Property="BorderBrush" Value="#353B49"/><Setter Property="Padding" Value="7"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E7EAF0"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#13161E"/><Setter Property="Foreground" Value="#ECEDF2"/>
            <Setter Property="RowBackground" Value="#151922"/><Setter Property="AlternatingRowBackground" Value="#191D27"/>
            <Setter Property="GridLinesVisibility" Value="None"/><Setter Property="BorderThickness" Value="0"/>
            <Setter Property="HeadersVisibility" Value="Column"/><Setter Property="RowHeight" Value="42"/>
            <Setter Property="SelectionMode" Value="Single"/><Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="CanUserAddRows" Value="False"/><Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="IsReadOnly" Value="True"/><Setter Property="AutoGenerateColumns" Value="False"/>
        </Style>
    </Window.Resources>
    <DockPanel>
        <Border DockPanel.Dock="Top" Background="#161923" Padding="18,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="300"/><ColumnDefinition Width="*"/><ColumnDefinition Width="190"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="58"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Image x:Name="BrandImage" Width="50" Height="50" Stretch="Uniform" VerticalAlignment="Center"/>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="10,0,0,0">
                        <TextBlock Text="ASCHENTE LAUNCHER" FontSize="18" FontWeight="Bold"/>
                        <TextBlock Text="Lokale Offline-Bibliothek" Foreground="#8F97A8" FontSize="12"/>
                    </StackPanel>
                </Grid>
                <TextBox x:Name="SearchBox" Grid.Column="1" Margin="14,0" VerticalContentAlignment="Center" ToolTip="Spiele durchsuchen"/>
                <ComboBox x:Name="SourceFilter" Grid.Column="2" Margin="4,0" VerticalContentAlignment="Center"/>
                <CheckBox x:Name="FavoritesOnly" Grid.Column="3" Content="Nur Favoriten" Margin="12,0"/>
                <Button x:Name="ScanButton" Grid.Column="4" Content="Neu scannen" Background="#6D5EF7"/>
                <Button x:Name="SettingsButton" Grid.Column="5" Content="Einstellungen"/>
            </Grid>
        </Border>

        <StatusBar DockPanel.Dock="Bottom" Background="#151821" Foreground="#AEB5C2">
            <StatusBarItem><TextBlock x:Name="StatusText" Text="Bereit"/></StatusBarItem>
            <Separator/>
            <StatusBarItem><TextBlock Text="Keine Cloud · Keine Anmeldung · Keine Telemetrie"/></StatusBarItem>
        </StatusBar>

        <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="2*" MinWidth="520"/><ColumnDefinition Width="390"/></Grid.ColumnDefinitions>
            <Border Margin="16,16,8,16" Background="#13161E" CornerRadius="10">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Grid Margin="16,14">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <TextBlock Text="Bibliothek" FontSize="22" FontWeight="SemiBold"/>
                        <Button x:Name="AddGameButton" Grid.Column="1" Content="+ Spiel hinzufügen"/>
                    </Grid>
                    <DataGrid x:Name="GameGrid" Grid.Row="1" Margin="0,0,0,4" AlternationCount="2">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="" Binding="{Binding Favorite}" Width="38"/>
                            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*"/>
                            <DataGridTextColumn Header="Quelle" Binding="{Binding Source}" Width="140"/>
                            <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="120"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
            </Border>

            <Border Grid.Column="1" Margin="8,16,16,16" Background="#171A24" CornerRadius="10" Padding="22">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <TextBlock x:Name="DetailTitle" Text="Kein Spiel ausgewählt" FontSize="27" FontWeight="Bold" TextWrapping="Wrap"/>
                    <TextBlock x:Name="DetailSource" Grid.Row="1" Margin="0,10,0,0" Foreground="#AAB1BF"/>
                    <TextBlock x:Name="DetailPath" Grid.Row="2" Margin="0,16,0,0" Foreground="#C6CBD5" TextWrapping="Wrap"/>
                    <TextBlock x:Name="DetailTarget" Grid.Row="3" Margin="0,8,0,0" Foreground="#C6CBD5" TextWrapping="Wrap"/>
                    <Border x:Name="WarningBorder" Grid.Row="4" Margin="0,18,0,0" Background="#3A2D1B" CornerRadius="6" Padding="12" Visibility="Collapsed">
                        <TextBlock x:Name="DetailWarning" Foreground="#FFD49A" TextWrapping="Wrap"/>
                    </Border>
                    <StackPanel Grid.Row="5" Margin="0,24,0,0">
                        <Button x:Name="LaunchButton" Content="▶ Spielen" Background="#6D5EF7" FontSize="16"/>
                        <Button x:Name="FavoriteButton" Content="☆ Zu Favoriten"/>
                        <Button x:Name="OpenFolderButton" Content="Ordner öffnen"/>
                        <Button x:Name="EditButton" Content="Eintrag bearbeiten"/>
                        <Button x:Name="HideButton" Content="Ausblenden"/>
                    </StackPanel>
                    <TextBlock Grid.Row="6" Text="Doppelklick auf ein Spiel startet es direkt." Foreground="#858E9F" TextWrapping="Wrap"/>
                </Grid>
            </Border>
        </Grid>
    </DockPanel>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowBranding -Window $window
    $script:MainWindow = $window
    $script:GameGrid = $window.FindName('GameGrid')
    $script:SearchBox = $window.FindName('SearchBox')
    $script:SourceFilter = $window.FindName('SourceFilter')
    $script:FavoritesOnly = $window.FindName('FavoritesOnly')
    $script:StatusText = $window.FindName('StatusText')
    $script:DetailTitle = $window.FindName('DetailTitle')
    $script:DetailSource = $window.FindName('DetailSource')
    $script:DetailPath = $window.FindName('DetailPath')
    $script:DetailTarget = $window.FindName('DetailTarget')
    $script:DetailWarning = $window.FindName('DetailWarning')
    $warningBorder = $window.FindName('WarningBorder')
    $script:WarningBorder = $warningBorder
    $script:LaunchButton = $window.FindName('LaunchButton')
    $script:FavoriteButton = $window.FindName('FavoriteButton')
    $script:OpenFolderButton = $window.FindName('OpenFolderButton')
    $script:EditButton = $window.FindName('EditButton')
    $script:HideButton = $window.FindName('HideButton')
    $scanButton = $window.FindName('ScanButton')
    $settingsButton = $window.FindName('SettingsButton')
    $addGameButton = $window.FindName('AddGameButton')

    $script:SearchBox.Add_TextChanged({ Apply-GameFilter })
    $script:SourceFilter.Add_SelectionChanged({ Apply-GameFilter })
    $script:FavoritesOnly.Add_Click({ Apply-GameFilter })
    $scanButton.Add_Click({ Invoke-LibraryScan; Refresh-SourceFilter })
    $settingsButton.Add_Click({ Show-SettingsWindow })
    $addGameButton.Add_Click({ Show-GameEditor })

    $script:GameGrid.Add_SelectionChanged({
        $game = Get-SelectedGame
        if ($game) {
            if ($game.IsMissing) {
                $script:DetailWarning.Text = 'Der gespeicherte Installationsort wurde beim letzten Scan nicht gefunden.'
                $warningBorder.Visibility = 'Visible'
            }
            elseif ($game.NeedsReview) {
                $script:DetailWarning.Text = 'Der automatisch gewählte Starter ist unsicher. Bitte den Eintrag bearbeiten und die richtige Datei auswählen.'
                $warningBorder.Visibility = 'Visible'
            }
            else {
                $warningBorder.Visibility = 'Collapsed'
            }
        }
        Update-GameDetails -Game $game
        if ($game -and -not $game.IsMissing -and -not $game.NeedsReview) { $warningBorder.Visibility = 'Collapsed' }
        elseif (-not $game) { $warningBorder.Visibility = 'Collapsed' }
        else { $warningBorder.Visibility = 'Visible' }
    })

    $script:GameGrid.Add_MouseDoubleClick({ Start-Game -Game (Get-SelectedGame) })
    $script:LaunchButton.Add_Click({ Start-Game -Game (Get-SelectedGame) })
    $script:OpenFolderButton.Add_Click({ Open-GameFolder -Game (Get-SelectedGame) })
    $script:EditButton.Add_Click({
        $game = Get-SelectedGame
        if ($game) { Show-GameEditor -Game $game }
    })
    $script:FavoriteButton.Add_Click({
        $game = Get-SelectedGame
        if (-not $game) { return }
        $game.Favorite = -not [bool]$game.Favorite
        Save-Library
        Apply-GameFilter
    })
    $script:HideButton.Add_Click({
        $game = Get-SelectedGame
        if (-not $game) { return }
        $game.Hidden = -not [bool]$game.Hidden
        Save-Library
        Apply-GameFilter
    })

    $window.Add_Closing({ Save-Library; Save-Configuration })

    Refresh-SourceFilter
    Apply-GameFilter
    $script:StatusText.Text = "$(@($script:Games | Where-Object { -not $_.Hidden }).Count) Spiele"

    if ($script:Config.ScanOnStartup) {
        $window.Add_ContentRendered({
            $window.Dispatcher.BeginInvoke([Action]{
                Invoke-LibraryScan
                Refresh-SourceFilter
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        })
    }

    $window.ShowDialog() | Out-Null
}

try {
    Load-Configuration
    Load-Library

    if (-not $script:Config.SetupComplete) {
        if (-not (Show-SetupWizard)) { exit }
    }

    Show-MainWindow
}
catch {
    $message = "Die Anwendung wurde wegen eines unerwarteten Fehlers beendet.`n`n$($_.Exception.Message)`n`nProtokoll: $script:LogPath"
    Write-Log -Message $_.Exception.ToString() -Level ERROR
    [System.Windows.MessageBox]::Show($message, $script:AppName, 'OK', 'Error') | Out-Null
    exit 1
}
