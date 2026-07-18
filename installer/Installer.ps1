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
$script:Owner = if ([string]::IsNullOrWhiteSpace($env:ASCHENTE_GITHUB_OWNER)) { 'FionaAleksic' } else { $env:ASCHENTE_GITHUB_OWNER }
$script:Repository = if ([string]::IsNullOrWhiteSpace($env:ASCHENTE_GITHUB_REPO)) { 'Aschente-Launcher' } else { $env:ASCHENTE_GITHUB_REPO }
$script:BrandImagePath = $env:ASCHENTE_BRAND_IMAGE
$script:InstallerExecutable = $env:ASCHENTE_INSTALLER_EXE
$script:LatestRelease = $null
$script:InstalledVersion = $null

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { }

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
        throw 'Die fest eingebaute GitHub-Quelle FionaAleksic/Aschente-Launcher ist ungültig.'
    }

    $uri = "https://api.github.com/repos/$($script:Owner)/$($script:Repository)/releases/latest"
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = "Aschente-Installer/$($env:ASCHENTE_INSTALLER_VERSION)"
    }

    try {
        return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }

        if ($statusCode -eq 404) {
            throw @"
Auf GitHub wurde noch kein veröffentlichtes Release gefunden.

Bitte veröffentliche zuerst eine Version im Repository:
https://github.com/$($script:Owner)/$($script:Repository)/releases

Erst danach kann der Installer automatisch die neueste Version herunterladen.
"@
        }

        throw "Das neueste GitHub-Release konnte nicht abgefragt werden.`n`n$($_.Exception.Message)"
    }
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
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$Arguments = ''
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = 'Lokale Spielebibliothek'
    $shortcut.Arguments = $Arguments
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

        & $StatusCallback 'Download wird per SHA-256 geprüft …'
        & $ProgressCallback 38
        $expectedHash = $null
        if ($asset.digest -and $asset.digest -match '^sha256:(?<Hash>[0-9a-fA-F]{64})$') {
            $expectedHash = $Matches.Hash
        }
        else {
            $checksumAsset = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' }) | Select-Object -First 1
            if ($checksumAsset) {
                $checksumPath = Join-Path $tempRoot 'SHA256SUMS.txt'
                Invoke-WebRequest -Uri $checksumAsset.browser_download_url -OutFile $checksumPath -UseBasicParsing
                $escapedAssetName = [Regex]::Escape($script:AssetName)
                $checksumLine = Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match "^(?<Hash>[0-9a-fA-F]{64})\s+\*?${escapedAssetName}$" } | Select-Object -First 1
                if ($checksumLine -and $checksumLine -match '^(?<Hash>[0-9a-fA-F]{64})') {
                    $expectedHash = $Matches.Hash
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($expectedHash)) {
            throw 'Für das Release wurde keine SHA-256-Prüfsumme gefunden (SHA256SUMS.txt fehlt oder ist unvollständig). Die Installation wurde aus Sicherheitsgründen abgebrochen.'
        }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ine $expectedHash) {
            throw 'Die SHA-256-Prüfung des Downloads ist fehlgeschlagen. Die Installation wurde abgebrochen.'
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
            New-Shortcut -ShortcutPath (Join-Path $script:StartMenuDirectory 'Aschente Launcher deinstallieren.lnk') -TargetPath $uninstallerPath -WorkingDirectory $InstallPath -Arguments '-Uninstall'
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
        Width="760" Height="640" MinWidth="720" MinHeight="600"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#0E1218" Foreground="#F4F7FB">
    <Window.Resources>
        <SolidColorBrush x:Key="PanelBrush" Color="#171D26"/>
        <SolidColorBrush x:Key="PanelBrushAlt" Color="#121821"/>
        <SolidColorBrush x:Key="BorderBrushPanel" Color="#2A3340"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#2563EB"/>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1C2430"/>
            <Setter Property="Foreground" Value="#F4F7FB"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="17,9"/>
            <Setter Property="MinHeight" Value="38"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Background" Value="#0D131A"/>
            <Setter Property="Foreground" Value="#F4F7FB"/>
            <Setter Property="BorderBrush" Value="#364152"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#E7ECF3"/>
            <Setter Property="Margin" Value="0,7"/>
        </Style>
    </Window.Resources>

    <Grid Margin="28">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="88"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border Width="72" Height="72" CornerRadius="8" Background="#111722" BorderBrush="#2A3340" BorderThickness="1" VerticalAlignment="Center">
                <Image x:Name="BrandImage" Stretch="Uniform" Margin="5"/>
            </Border>
            <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="16,0,0,0">
                <TextBlock Text="Aschente Launcher" FontSize="29" FontWeight="SemiBold"/>
                <TextBlock Text="Lokale Spielebibliothek installieren oder aktualisieren"
                           Margin="0,5,0,0" FontSize="15" Foreground="#A8B3C2"/>
            </StackPanel>
        </Grid>

        <Border Grid.Row="2" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource BorderBrushPanel}" BorderThickness="1" CornerRadius="6" Padding="22">
            <Grid>
                <Grid x:Name="OptionsPage">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="18"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="18"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBlock Text="Installationsoptionen" FontSize="22" FontWeight="SemiBold"/>
                    <TextBlock Grid.Row="1" Margin="0,7,0,0" Foreground="#A8B3C2" TextWrapping="Wrap"
                               Text="Der Installer lädt automatisch das neueste Release von FionaAleksic/Aschente-Launcher. Eine GitHub-Eingabe ist nicht erforderlich."/>

                    <StackPanel Grid.Row="3">
                        <TextBlock Text="Installationsordner" FontWeight="SemiBold"/>
                        <Grid Margin="0,9,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="InstallPathBox"/>
                            <Button x:Name="BrowseButton" Grid.Column="1" Content="Durchsuchen…" Margin="10,0,0,0"/>
                        </Grid>
                        <TextBlock Text="Standard: C:\Program Files\Aschente" Margin="0,7,0,0" Foreground="#7F8B9A" FontSize="12"/>
                    </StackPanel>

                    <StackPanel Grid.Row="5">
                        <CheckBox x:Name="StartMenuCheck" Content="Startmenü-Verknüpfung für alle Benutzer erstellen" IsChecked="True"/>
                        <CheckBox x:Name="DesktopCheck" Content="Desktop-Verknüpfung für alle Benutzer erstellen"/>
                        <Border Margin="0,18,0,0" Background="{StaticResource PanelBrushAlt}" BorderBrush="#273241" BorderThickness="1" CornerRadius="5" Padding="14">
                            <TextBlock Foreground="#B9C3D0" TextWrapping="Wrap"
                                       Text="Bei einem Update bleiben Konfiguration, Bibliothekseinträge und Protokolle im Data-Ordner erhalten."/>
                        </Border>
                    </StackPanel>
                </Grid>

                <Grid x:Name="SummaryPage" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="18"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="18"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Installation bestätigen" FontSize="22" FontWeight="SemiBold"/>
                    <TextBlock Grid.Row="1" Margin="0,7,0,0" Foreground="#A8B3C2" TextWrapping="Wrap"
                               Text="Prüfe die Einstellungen. Mit „Installieren“ wird das neueste GitHub-Release heruntergeladen und eingerichtet."/>
                    <Border Grid.Row="3" Background="{StaticResource PanelBrushAlt}" BorderBrush="#273241" BorderThickness="1" CornerRadius="5" Padding="16">
                        <TextBlock x:Name="SummaryText" TextWrapping="Wrap" FontSize="14" LineHeight="24"/>
                    </Border>
                    <StackPanel Grid.Row="5">
                        <ProgressBar x:Name="ProgressBar" Height="8" Minimum="0" Maximum="100" Value="0" Background="#0C1117" Foreground="#2563EB"/>
                        <TextBlock x:Name="StatusText" Margin="0,11,0,0" Foreground="#CBD5E1" Text="Bereit zur Installation." TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Grid>
        </Border>

        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="BackButton" Content="Zurück" MinWidth="110" Visibility="Hidden" HorizontalAlignment="Left"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
                <Button x:Name="CancelButton" Content="Abbrechen" MinWidth="110"/>
                <Button x:Name="NextButton" Content="Weiter" MinWidth="150" Margin="12,0,0,0" Style="{StaticResource AccentButton}"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$brandImage = $window.FindName('BrandImage')
$optionsPage = $window.FindName('OptionsPage')
$summaryPage = $window.FindName('SummaryPage')
$installPathBox = $window.FindName('InstallPathBox')
$browseButton = $window.FindName('BrowseButton')
$startMenuCheck = $window.FindName('StartMenuCheck')
$desktopCheck = $window.FindName('DesktopCheck')
$summaryText = $window.FindName('SummaryText')
$progressBar = $window.FindName('ProgressBar')
$statusText = $window.FindName('StatusText')
$backButton = $window.FindName('BackButton')
$cancelButton = $window.FindName('CancelButton')
$nextButton = $window.FindName('NextButton')

$imageSource = Get-BrandImageSource
if ($imageSource) {
    $brandImage.Source = $imageSource
    $window.Icon = $imageSource
}

$installPathBox.Text = $script:DefaultInstallPath
if ($script:InstalledVersion) {
    $statusText.Text = "Installierte Version: $($script:InstalledVersion). Die neueste Version wird bei der Installation ermittelt."
}

function Get-ValidatedInstallPath {
    $installPath = [Environment]::ExpandEnvironmentVariables($installPathBox.Text.Trim())
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        throw 'Bitte wähle einen Installationsordner aus.'
    }
    if (-not [IO.Path]::IsPathRooted($installPath)) {
        throw 'Der Installationsordner muss ein vollständiger Windows-Pfad sein.'
    }
    return [IO.Path]::GetFullPath($installPath)
}

function Update-InstallSummary {
    $path = Get-ValidatedInstallPath
    $startMenuText = if ([bool]$startMenuCheck.IsChecked) { 'Ja' } else { 'Nein' }
    $desktopText = if ([bool]$desktopCheck.IsChecked) { 'Ja' } else { 'Nein' }
    $mode = if ($script:InstalledVersion) { "Update von Version $($script:InstalledVersion)" } else { 'Neuinstallation' }
    $summaryText.Text = "Vorgang: $mode`nInstallationsordner: $path`nStartmenü-Verknüpfung: $startMenuText`nDesktop-Verknüpfung: $desktopText`nQuelle: github.com/FionaAleksic/Aschente-Launcher (neuestes Release)"
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

$script:CurrentPage = 1
$script:InstallationComplete = $false
$script:InstalledLauncherPath = $null

$backButton.Add_Click({
    if ($script:CurrentPage -ne 2 -or $script:InstallationComplete) { return }
    $summaryPage.Visibility = 'Collapsed'
    $optionsPage.Visibility = 'Visible'
    $backButton.Visibility = 'Hidden'
    $nextButton.Content = 'Weiter'
    $script:CurrentPage = 1
})

$cancelButton.Add_Click({ $window.Close() })

$nextButton.Add_Click({
    if ($script:InstallationComplete) {
        try { Start-Process -FilePath $script:InstalledLauncherPath }
        catch { Show-Error $_.Exception.Message }
        $window.Close()
        return
    }

    if ($script:CurrentPage -eq 1) {
        try {
            Update-InstallSummary
            $optionsPage.Visibility = 'Collapsed'
            $summaryPage.Visibility = 'Visible'
            $backButton.Visibility = 'Visible'
            $nextButton.Content = if ($script:InstalledVersion) { 'Aktualisieren' } else { 'Installieren' }
            $script:CurrentPage = 2
        }
        catch { Show-Error $_.Exception.Message }
        return
    }

    try {
        $installPath = Get-ValidatedInstallPath
        $nextButton.IsEnabled = $false
        $backButton.IsEnabled = $false
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
        $nextButton.Content = 'Launcher starten'
        $nextButton.IsEnabled = $true
        $backButton.Visibility = 'Hidden'
        $script:InstalledLauncherPath = [string]$result.LauncherPath
        $script:InstallationComplete = $true
    }
    catch {
        $window.Cursor = 'Arrow'
        $nextButton.IsEnabled = $true
        $backButton.IsEnabled = $true
        $cancelButton.IsEnabled = $true
        $progressBar.Value = 0
        $statusText.Text = 'Installation fehlgeschlagen.'
        Show-Error "Die Installation konnte nicht abgeschlossen werden.`n`n$($_.Exception.Message)"
    }
})

$window.ShowDialog() | Out-Null
