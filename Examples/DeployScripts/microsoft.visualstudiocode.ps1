[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [string]$DeployMode = 'Auto',

    [Parameter(Mandatory = $false)]
    [switch]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
if (-not (Get-Module -Name PSAppDeployToolkit)) {
    Import-Module -Name $modulePath
}

$adtSession = @{
    AppVendor    = 'Microsoft Corporation'
    AppName      = 'Microsoft Visual Studio Code'
    RequireAdmin = $true
}

Open-ADTSession @adtSession @PSBoundParameters

try {
    $dirFiles = Join-Path -Path $PSScriptRoot -ChildPath 'Files'
    $installerPath = Get-ChildItem -Path $dirFiles -Filter 'Microsoft Visual Studio Code*.exe' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName -First 1
    $installerArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'

    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $desktopShortcutPath = Join-Path -Path $publicDesktop -ChildPath 'Visual Studio Code.lnk'

    $machineInstallDir = 'C:\Program Files\Microsoft VS Code'
    $userInstallDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Microsoft VS Code'
    $machineUninstallPattern = Join-Path -Path $machineInstallDir -ChildPath 'unins*.exe'
    $userUninstallPattern = Join-Path -Path $userInstallDir -ChildPath 'unins*.exe'

    if ($DeploymentType -eq 'Install') {
        Show-ADTInstallationWelcome -CloseProcesses 'Code'

        if (-not $installerPath) {
            throw "Visual Studio Code installer not found in '$dirFiles'."
        }

        $installResult = Start-ADTProcess -FilePath $installerPath -ArgumentList $installerArgs -PassThru
        if ($installResult.ExitCode -ne 0) {
            throw "Visual Studio Code installation failed with exit code $($installResult.ExitCode)."
        }

        if (Test-Path -Path $desktopShortcutPath) {
            Write-ADTLogEntry -Message "Removing Desktop shortcut at '$desktopShortcutPath'."
            Remove-Item -Path $desktopShortcutPath -Force
        }
    }
    elseif ($DeploymentType -eq 'Uninstall') {
        Show-ADTInstallationWelcome -CloseProcesses 'Code'

        $registryRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        $uninstallPath = $null
        $uninstallArgs = $null

        foreach ($registryRoot in $registryRoots) {
            $uninstallKey = Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue |
                Where-Object {
                    $keyProperties = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    $keyProperties.DisplayName -like '*Visual Studio Code*'
                } |
                Select-Object -First 1

            if (-not $uninstallKey) {
                continue
            }

            $keyProperties = Get-ItemProperty -Path $uninstallKey.PSPath -ErrorAction SilentlyContinue
            $uninstallCommand = if ($keyProperties.QuietUninstallString) {
                $keyProperties.QuietUninstallString
            }
            else {
                $keyProperties.UninstallString
            }

            if (-not $uninstallCommand) {
                continue
            }

            if ($uninstallCommand -match '^\s*"([^"]+)"\s*(.*)$') {
                $uninstallPath = $matches[1]
                $uninstallArgs = $matches[2].Trim()
            }
            elseif ($uninstallCommand -match '^\s*(\S+)\s*(.*)$') {
                $uninstallPath = $matches[1]
                $uninstallArgs = $matches[2].Trim()
            }

            if ($uninstallPath) {
                break
            }
        }

        if (-not $uninstallPath -or -not (Test-Path -Path $uninstallPath)) {
            $uninstallPath = Get-ChildItem -Path $machineUninstallPattern -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName -First 1
        }

        if ((-not $uninstallPath -or -not (Test-Path -Path $uninstallPath)) -and (Test-Path -Path $userInstallDir)) {
            $uninstallPath = Get-ChildItem -Path $userUninstallPattern -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName -First 1
        }

        if (-not $uninstallPath -or -not (Test-Path -Path $uninstallPath)) {
            Write-ADTLogEntry -Message 'Visual Studio Code uninstall command was not found. Skipping uninstall.' -Severity 2
        }
        else {
            if ($uninstallPath -match 'unins\d+\.exe$' -and [string]::IsNullOrWhiteSpace($uninstallArgs)) {
                $uninstallArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
            }

            Write-ADTLogEntry -Message "Executing Visual Studio Code uninstaller '$uninstallPath' with arguments '$uninstallArgs'."
            $uninstallResult = if ([string]::IsNullOrWhiteSpace($uninstallArgs)) {
                Start-ADTProcess -FilePath $uninstallPath -PassThru
            }
            else {
                Start-ADTProcess -FilePath $uninstallPath -ArgumentList $uninstallArgs -PassThru
            }

            if ($uninstallResult.ExitCode -ne 0) {
                throw "Visual Studio Code uninstall failed with exit code $($uninstallResult.ExitCode)."
            }
        }
    }
}
catch {
    Write-ADTLogEntry -Message "Deployment failed: $($_.Exception.Message)" -Severity 3
    throw
}

Close-ADTSession
