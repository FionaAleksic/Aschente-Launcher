[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

$script:ProductName = 'Aschente Launcher'
$script:Publisher = 'Aschente Project'
$script:AssetName = 'Aschente-Launcher-win-x64.zip'
$script:DefaultInstallPath = Join-Path $env:ProgramFiles 'Aschente'
$script:StartMenuRoot = [Environment]::GetFolderPath('CommonPrograms')
$script:StartMenuDirectory = Join-Path $script:StartMenuRoot 'Aschente'
$script:UninstallRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AschenteLauncher'
$script:Owner = $env:ASCHENTE_GITHUB_OWNER
$script:Repository = $env:ASCHENTE_GITHUB_REPO
$script:InstallerExecutable = $env:ASCHENTE_INSTALLER_EXE
$script:LatestRelease = $null
$script:InstalledVersion = $null

function Show-Error {
    param([string]$Message)
    [System.Windows.MessageBox]::Show($Message, 'Aschente Installer', 'OK', 'Error') | Out-Null
}

function Show-Info {
    param([string]$Message)
    [System.Windows.MessageBox]::Show($Message, 'Aschente Installer', 'OK', 'Information') | Out-Null
}

function Test-RepositoryConfiguration {
    return -not [string]::IsNullOrWhiteSpace($script:Owner) -and
        -not [string]::IsNullOrWhiteSpace($script:Repository) -and
        $script:Owner -notmatch '^YOUR_' -and
        $script:Repository -notmatch '^YOUR_'
}

function Get-InstalledInformation {
    if (Test-Path $script:UninstallRegistryPath) {
        try {
            $entry = Get-ItemProperty -LiteralPath $script:UninstallRegistryPath
            return [pscustomobject]@{
                InstallLocation = $entry.InstallLocation
                DisplayVersion = $entry.DisplayVersion
            }
        }
        catch { }
    }
    return $null
}

function Invoke-UiPump {
    try {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Background
        )
    }
    catch { }
}

function Get-LatestRelease {
    if (-not (Test-RepositoryConfiguration)) {
        throw 'Die GitHub-Quelle ist noch nicht konfiguriert. Trage in installer-config.json den GitHub-Benutzernamen und den Repository-Namen ein oder baue den Installer über GitHub Actions.'
    }

    $uri = "https://api.github.com/repos/$($script:Owner)/$($script:Repository)/releases/latest"
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = "Aschente-Installer/$($env:ASCHENTE_INSTALLER_VERSION)"
    }
    return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}

function Stop-RunningLauncher {
    param([Parameter(Mandatory)][string]$InstallPath)

    $launcherPath = Join-Path $InstallPath 'Aschente Launcher.exe'
    $runtimeScript = Join-Path $InstallPath 'Data\Runtime\AschenteLauncher.ps1'

    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.ExecutablePath -and $_.ExecutablePath -ieq $launcherPath) -or
                ($_.CommandLine -and $_.CommandLine.IndexOf($runtimeScript, [StringComparison]::OrdinalIgnoreCase) -ge 0)
            } |
            ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null }
        Start-Sleep -Milliseconds 500
    }
    catch { }
}

function Set-DataDirectoryPermissions {
    param([Parameter(Mandatory)][string]$DataPath)

    New-Item -ItemType Directory -Path $DataPath -Force | Out-Null
    & icacls.exe $DataPath '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Die Schreibrechte für den Datenordner konnten nicht gesetzt werden (icacls: $LASTEXITCODE)."
    }
}

function New-Shortcut {
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = 'Lokale Spielebibliothek'
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
}

function Register-Uninstaller {
    param(
        [Parameter(Mandatory)][string]$InstallPath,
        [Parameter(Mandatory)][string]$Version
    )

    $uninstaller = Join-Path $InstallPath 'Uninstall Aschente Launcher.exe'
    New-Item -Path $script:UninstallRegistryPath -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name DisplayName -Value $script:ProductName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name DisplayVersion -Value $Version -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name Publisher -Value $script:Publisher -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name InstallLocation -Value $InstallPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name DisplayIcon -Value (Join-Path $InstallPath 'Aschente Launcher.exe') -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name UninstallString -Value ('"{0}" -Uninstall' -f $uninstaller) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name QuietUninstallString -Value ('"{0}" -Uninstall' -f $uninstaller) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name URLInfoAbout -Value "https://github.com/$($script:Owner)/$($script:Repository)" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $script:UninstallRegistryPath -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
}

function Install-LatestRelease {
    param(
        [Parameter(Mandatory)][string]$InstallPath,
        [Parameter(Mandatory)][bool]$CreateStartMenu,
        [Parameter(Mandatory)][bool]$CreateDesktop,
        [Parameter(Mandatory)][scriptblock]$StatusCallback,
        [Parameter(Mandatory)][scriptblock]$ProgressCallback
    )

    & $StatusCallback 'Neueste GitHub-Version wird ermittelt …'
    & $ProgressCallback 8
    $release = Get-LatestRelease
    $script:LatestRelease = $release

    $asset = @($release.assets | Where-Object { $_.name -eq $script:AssetName }) | Select-Object -First 1
    if ($null -eq $asset) {
        throw "Im neuesten Release '$($release.tag_name)' fehlt die Datei '$($script:AssetName)'."
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("Aschente-Install-" + [Guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $tempRoot $script:AssetName
    $extractPath = Join-Path $tempRoot 'Extracted'
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    try {
        & $StatusCallback "Version $($release.tag_name) wird heruntergeladen …"
        & $ProgressCallback 20
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing

        if ($asset.digest -and $asset.digest -match '^sha256:(?<Hash>[0-9a-fA-F]{64})$') {
            & $StatusCallback 'Download wird per SHA-256 geprüft …'
            & $ProgressCallback 38
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ine $Matches.Hash) {
                throw 'Die SHA-256-Prüfung des Downloads ist fehlgeschlagen. Die Installation wurde abgebrochen.'
            }
        }

        & $StatusCallback 'Paket wird entpackt …'
        & $ProgressCallback 48
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

        $launcherSource = Join-Path $extractPath 'Aschente Launcher.exe'
        if (-not (Test-Path -LiteralPath $launcherSource)) {
            throw 'Das Release-Paket enthält keine „Aschente Launcher.exe“. '
        }

        & $StatusCallback 'Laufende Instanz wird beendet …'
        & $ProgressCallback 56
        Stop-RunningLauncher -InstallPath $InstallPath

        & $StatusCallback 'Programmdateien werden installiert …'
        & $ProgressCallback 64
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Get-ChildItem -LiteralPath $extractPath -Force | ForEach-Object {
            if ($_.Name -ne 'Data') {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $InstallPath $_.Name) -Recurse -Force
            }
        }

        $dataPath = Join-Path $InstallPath 'Data'
        Set-DataDirectoryPermissions -DataPath $dataPath

        & $StatusCallback 'Deinstallationsprogramm wird eingerichtet …'
        & $ProgressCallback 76
        $uninstallerPath = Join-Path $InstallPath 'Uninstall Aschente Launcher.exe'
        if (-not [string]::IsNullOrWhiteSpace($script:InstallerExecutable)) {
            $sourceFull = [IO.Path]::GetFullPath($script:InstallerExecutable)
            $targetFull = [IO.Path]::GetFullPath($uninstallerPath)
            if ($sourceFull -ine $targetFull) {
                Copy-Item -LiteralPath $sourceFull -Destination $targetFull -Force
            }
        }

        & $StatusCallback 'Verknüpfungen werden erstellt …'
        & $ProgressCallback 84
        $launcherTarget = Join-Path $InstallPath 'Aschente Launcher.exe'
        if ($CreateStartMenu) {
            New-Item -ItemType Directory -Path $script:StartMenuDirectory -Force | Out-Null
            New-Shortcut -ShortcutPath (Join-Path $script:StartMenuDirectory 'Aschente Launcher.lnk') -TargetPath $launcherTarget -WorkingDirectory $InstallPath
            New-Shortcut -ShortcutPath (Join-Path $script:StartMenuDirectory 'Aschente Launcher deinstallieren.lnk') -TargetPath $uninstallerPath -WorkingDirectory $InstallPath
        }
        else {
            Remove-Item -LiteralPath $script:StartMenuDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        $desktopShortcut = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Aschente Launcher.lnk'
        if ($CreateDesktop) {
            New-Shortcut -ShortcutPath $desktopShortcut -TargetPath $launcherTarget -WorkingDirectory $InstallPath
        }
        else {
            Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
        }

        & $StatusCallback 'Windows-Programmeintrag wird geschrieben …'
        & $ProgressCallback 92
        $displayVersion = [string]$release.tag_name
        if ($displayVersion.StartsWith('v')) { $displayVersion = $displayVersion.Substring(1) }
        Register-Uninstaller -InstallPath $InstallPath -Version $displayVersion

        & $StatusCallback "Aschente Launcher $displayVersion wurde installiert."
        & $ProgressCallback 100
        return [pscustomobject]@{
            Version = $displayVersion
            LauncherPath = $launcherTarget
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Uninstall {
    $installed = Get-InstalledInformation
    $installPath = if ($installed -and -not [string]::IsNullOrWhiteSpace($installed.InstallLocation)) {
        [string]$installed.InstallLocation
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:InstallerExecutable)) {
        Split-Path -Parent $script:InstallerExecutable
    }
    else {
        $script:DefaultInstallPath
    }

    $answer = [System.Windows.MessageBox]::Show(
        "Soll der Aschente Launcher deinstalliert werden?`n`nJa: Einstellungen und Bibliothek behalten`nNein: Alles einschließlich der Daten löschen`nAbbrechen: Nichts ändern",
        'Aschente Launcher deinstallieren',
        'YesNoCancel',
        'Question'
    )

    if ($answer -eq 'Cancel') { return }
    $keepData = $answer -eq 'Yes'

    try {
        Stop-RunningLauncher -InstallPath $installPath
        Remove-Item -LiteralPath $script:StartMenuDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Aschente Launcher.lnk') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:UninstallRegistryPath -Recurse -Force -ErrorAction SilentlyContinue

        if ($keepData) {
            Get-ChildItem -LiteralPath $installPath -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'Data' } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $remainingUninstaller = Join-Path $installPath 'Uninstall Aschente Launcher.exe'
            $escapedUninstaller = $remainingUninstaller.Replace('"', '""')
            Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList "/d /c timeout /t 2 /nobreak >nul & del /f /q `"$escapedUninstaller`"" | Out-Null
            Show-Info "Aschente Launcher wurde entfernt.`n`nDie Daten bleiben erhalten unter:`n$installPath\Data"
        }
        else {
            $escaped = $installPath.Replace('"', '""')
            Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList "/d /c timeout /t 2 /nobreak >nul & rmdir /s /q `"$escaped`"" | Out-Null
            Show-Info 'Aschente Launcher und seine lokalen Daten werden vollständig entfernt.'
        }
    }
    catch {
        Show-Error "Die Deinstallation konnte nicht vollständig abgeschlossen werden.`n`n$($_.Exception.Message)"
    }
}

if ($Uninstall) {
    Invoke-Uninstall
    exit
}

$installedInfo = Get-InstalledInformation
if ($installedInfo -and -not [string]::IsNullOrWhiteSpace($installedInfo.InstallLocation)) {
    $script:DefaultInstallPath = [string]$installedInfo.InstallLocation
    $script:InstalledVersion = [string]$installedInfo.DisplayVersion
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Aschente Launcher – Installation"
        Width="720" Height="520" MinWidth="680" MinHeight="500"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#15171C">
    <Grid Margin="30">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
            <TextBlock Text="Aschente Launcher" FontSize="30" FontWeight="SemiBold" Foreground="#F5F7FA"/>
            <TextBlock Text="Lokale Spielebibliothek installieren oder aktualisieren" Margin="0,6,0,0" FontSize="15" Foreground="#AEB6C5"/>
        </StackPanel>

        <Border Grid.Row="2" Background="#20242C" CornerRadius="10" Padding="18">
            <StackPanel>
                <TextBlock Text="Installationsordner" FontWeight="SemiBold" Foreground="#F5F7FA"/>
                <Grid Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="InstallPathBox" Height="34" Padding="9,6" VerticalContentAlignment="Center"/>
                    <Button x:Name="BrowseButton" Grid.Column="1" Content="Durchsuchen …" Margin="10,0,0,0" Padding="14,5"/>
                </Grid>
                <TextBlock Text="Standard: C:\Program Files\Aschente" Margin="0,8,0,0" Foreground="#929BAB" FontSize="12"/>
            </StackPanel>
        </Border>

        <Border Grid.Row="4" Background="#20242C" CornerRadius="10" Padding="18">
            <StackPanel>
                <CheckBox x:Name="StartMenuCheck" Content="Startmenü-Verknüpfung für alle Benutzer erstellen" IsChecked="True" Foreground="#F5F7FA"/>
                <CheckBox x:Name="DesktopCheck" Content="Desktop-Verknüpfung für alle Benutzer erstellen" Margin="0,10,0,0" Foreground="#F5F7FA"/>
                <TextBlock Text="GitHub-Quelle (Besitzer/Repository)" Margin="0,14,0,0" FontWeight="SemiBold" Foreground="#F5F7FA"/>
                <TextBox x:Name="RepositoryBox" Margin="0,8,0,0" Height="32" Padding="9,5" VerticalContentAlignment="Center"/>
                <TextBlock x:Name="RepositoryHint" Margin="0,7,0,0" Foreground="#929BAB" FontSize="12" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <StackPanel Grid.Row="6">
            <ProgressBar x:Name="ProgressBar" Height="9" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock x:Name="StatusText" Margin="0,10,0,0" Foreground="#C8CFDA" Text="Bereit zur Installation." TextWrapping="Wrap"/>
        </StackPanel>

        <TextBlock Grid.Row="7" Margin="0,18,0,0" Foreground="#818A99" TextWrapping="Wrap"
                   Text="Der Installer lädt das neueste veröffentlichte GitHub-Release. Bestehende Einstellungen und Bibliothekseinträge im Data-Ordner bleiben bei Updates erhalten."/>

        <StackPanel Grid.Row="8" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
            <Button x:Name="CancelButton" Content="Abbrechen" MinWidth="110" Padding="14,7"/>
            <Button x:Name="InstallButton" Content="Installieren" MinWidth="150" Margin="12,0,0,0" Padding="14,7" FontWeight="SemiBold"/>
        </StackPanel>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$installPathBox = $window.FindName('InstallPathBox')
$browseButton = $window.FindName('BrowseButton')
$startMenuCheck = $window.FindName('StartMenuCheck')
$desktopCheck = $window.FindName('DesktopCheck')
$repositoryBox = $window.FindName('RepositoryBox')
$repositoryHint = $window.FindName('RepositoryHint')
$progressBar = $window.FindName('ProgressBar')
$statusText = $window.FindName('StatusText')
$cancelButton = $window.FindName('CancelButton')
$installButton = $window.FindName('InstallButton')

$installPathBox.Text = $script:DefaultInstallPath
if (Test-RepositoryConfiguration) {
    $repositoryBox.Text = "$($script:Owner)/$($script:Repository)"
    $repositoryBox.IsReadOnly = $true
    $repositoryHint.Text = 'Diese Quelle wurde beim Build des Installers eingebettet.'
}
else {
    $repositoryBox.Text = ''
    $repositoryHint.Text = 'Beim lokalen Vorschau-Installer einmalig eintragen. Der GitHub-Actions-Release-Build füllt dieses Feld automatisch.'
    $repositoryHint.Foreground = '#FFD27D'
}
if ($script:InstalledVersion) {
    $statusText.Text = "Installierte Version: $($script:InstalledVersion). Die neueste Version wird beim Start der Installation geladen."
    $installButton.Content = 'Aktualisieren'
}

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Installationsordner für Aschente Launcher auswählen'
    $dialog.SelectedPath = $installPathBox.Text
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $installPathBox.Text = $dialog.SelectedPath
    }
})

$cancelButton.Add_Click({ $window.Close() })

$script:InstallationComplete = $false
$script:InstalledLauncherPath = $null

$installButton.Add_Click({
    if ($script:InstallationComplete) {
        try { Start-Process -FilePath $script:InstalledLauncherPath }
        catch { Show-Error $_.Exception.Message }
        $window.Close()
        return
    }

    try {
        $repositoryValue = $repositoryBox.Text.Trim()
        if ($repositoryValue -notmatch '^(?<Owner>[^\s/\\]+)/(?<Repository>[^\s/\\]+)$') {
            throw 'Bitte gib die GitHub-Quelle im Format Besitzer/Repository an.'
        }
        $script:Owner = $Matches.Owner
        $script:Repository = $Matches.Repository

        $installPath = [Environment]::ExpandEnvironmentVariables($installPathBox.Text.Trim())
        if ([string]::IsNullOrWhiteSpace($installPath)) {
            throw 'Bitte wähle einen Installationsordner aus.'
        }
        if (-not [IO.Path]::IsPathRooted($installPath)) {
            throw 'Der Installationsordner muss ein vollständiger Windows-Pfad sein.'
        }

        $installButton.IsEnabled = $false
        $browseButton.IsEnabled = $false
        $cancelButton.IsEnabled = $false
        $window.Cursor = 'Wait'

        $result = Install-LatestRelease `
            -InstallPath $installPath `
            -CreateStartMenu ([bool]$startMenuCheck.IsChecked) `
            -CreateDesktop ([bool]$desktopCheck.IsChecked) `
            -StatusCallback {
                param($message)
                $statusText.Text = $message
                Invoke-UiPump
            } `
            -ProgressCallback {
                param($value)
                $progressBar.Value = $value
                Invoke-UiPump
            }

        $window.Cursor = 'Arrow'
        $cancelButton.Content = 'Schließen'
        $cancelButton.IsEnabled = $true
        $installButton.Content = 'Launcher starten'
        $installButton.IsEnabled = $true
        $browseButton.IsEnabled = $false
        $installPathBox.IsEnabled = $false
        $startMenuCheck.IsEnabled = $false
        $desktopCheck.IsEnabled = $false
        $repositoryBox.IsEnabled = $false

        $script:InstalledLauncherPath = [string]$result.LauncherPath
        $script:InstallationComplete = $true
    }
    catch {
        $window.Cursor = 'Arrow'
        $installButton.IsEnabled = $true
        $browseButton.IsEnabled = $true
        $cancelButton.IsEnabled = $true
        $progressBar.Value = 0
        $statusText.Text = 'Installation fehlgeschlagen.'
        Show-Error "Die Installation konnte nicht abgeschlossen werden.`n`n$($_.Exception.Message)"
    }
})

$window.ShowDialog() | Out-Null
