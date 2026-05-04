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

# NOTE: Slack retired its MSI installers on September 15, 2025.
# This script uses the MSIX package from Slack's IT admin portal.
# WinGet (SlackTechnologies.Slack) only provides the user-scope EXE — do NOT use it
# for SYSTEM-context deployment. Download the MSIX manually and place it in Files\.

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
if (-not (Get-Module -Name PSAppDeployToolkit)) {
    Import-Module -Name $modulePath
}

$adtSession = @{
    AppVendor    = 'Slack Technologies'
    AppName      = 'Slack'
    RequireAdmin = $true
}

Open-ADTSession @adtSession @PSBoundParameters

try {
    $dirFiles    = Join-Path -Path $PSScriptRoot -ChildPath 'Files'
    $packageName = '*Slack*'

    if ($DeploymentType -eq 'Install') {
        Show-ADTInstallationWelcome -CloseProcesses 'slack'

        $msixPath = Get-ChildItem -Path $dirFiles -Filter '*.msix' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 1

        if (-not $msixPath) {
            throw "Slack MSIX installer not found in '$dirFiles'. Download from Slack's IT admin portal and place it in Files\."
        }

        Write-ADTLogEntry -Message "Installing Slack MSIX machine-wide from '$msixPath'."
        # Add-AppxProvisionedPackage uses DISM COM APIs that are unreliable in PowerShell 7.
        # Delegate to Windows PowerShell 5.1 where the COM class is properly registered.
        $psPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $escapedPath = $msixPath -replace "'", "''"
        $provisionCommand = "Add-AppxProvisionedPackage -Online -PackagePath '$escapedPath' -SkipLicense -ErrorAction Stop"
        Start-ADTProcess -FilePath $psPath -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $provisionCommand
        Write-ADTLogEntry -Message 'Slack MSIX installation completed.'

        # Remove Desktop shortcuts created during provisioning
        foreach ($desktopRoot in @(
            [Environment]::GetFolderPath('CommonDesktopDirectory'),
            [Environment]::GetFolderPath('Desktop')
        )) {
            $shortcut = Join-Path -Path $desktopRoot -ChildPath 'Slack.lnk'
            if (Test-Path -Path $shortcut) {
                Write-ADTLogEntry -Message "Removing Desktop shortcut at '$shortcut'."
                Remove-Item -Path $shortcut -Force
            }
        }
    }
    elseif ($DeploymentType -eq 'Uninstall') {
        Show-ADTInstallationWelcome -CloseProcesses 'slack'

        # Remove installed package for all users
        $installedPackage = Get-AppxPackage -AllUsers -Name $packageName -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($installedPackage) {
            Write-ADTLogEntry -Message "Removing Slack AppX package '$($installedPackage.PackageFullName)' for all users."
            Remove-AppxPackage -Package $installedPackage.PackageFullName -AllUsers -ErrorAction Stop
            Write-ADTLogEntry -Message 'Slack AppX removal completed.'
        }
        else {
            Write-ADTLogEntry -Message 'No Slack AppX package found for all users.' -Severity 2
        }

        # Remove provisioned package so it is not reinstalled for new users
        $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $packageName } |
            Select-Object -First 1

        if ($provisionedPackage) {
            Write-ADTLogEntry -Message "Removing provisioned Slack package '$($provisionedPackage.PackageName)'."
            # Remove-AppxProvisionedPackage also uses DISM COM APIs; run via Windows PowerShell 5.1.
            $psPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            $removeCommand = "Remove-AppxProvisionedPackage -Online -PackageName '$($provisionedPackage.PackageName)' -ErrorAction Stop"
            Start-ADTProcess -FilePath $psPath -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $removeCommand
            Write-ADTLogEntry -Message 'Slack provisioned package removal completed.'
        }
        else {
            Write-ADTLogEntry -Message 'No provisioned Slack package found.' -Severity 2
        }
    }
}
catch {
    Write-ADTLogEntry -Message "Deployment failed: $($_.Exception.Message)" -Severity 3
    throw
}

Close-ADTSession
