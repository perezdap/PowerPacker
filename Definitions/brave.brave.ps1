[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode = 'Auto',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "PSAppDeployToolkit\PSAppDeployToolkit.psd1"
if (-not (Get-Module -Name PSAppDeployToolkit)) {
    Import-Module -Name $modulePath
}

$adtSession = @{
    AppVendor = "Brave Software Inc"
    AppName = "Brave"
    AppVersion = "1.89.132"
    RequireAdmin = $true
}

# Open session
Open-ADTSession @adtSession @PSBoundParameters

try {
    if ($DeploymentType -eq 'Install') {
        # Variables
        $InstallerFile = "BraveBrowserStandaloneSilentSetup.exe"
        $InstallerPath = Join-Path -Path $PSScriptRoot -ChildPath "Files\$InstallerFile"
        
        # Pre-Install
        Show-ADTInstallationWelcome -CloseProcesses "brave" -BlockExecution -CheckDiskSpace

        # Install
        $Result = Start-ADTProcess -FilePath $InstallerPath -PassThru
        
        # Handle Omaha Exit Codes
        $SuccessCodes = @(0, 2147747880, 2147747867)
        if ($SuccessCodes -contains $Result.ExitCode) {
            Write-ADTLogEntry -Message "Installation successful or application already installed (Exit Code: $($Result.ExitCode))" -Severity 1
        } else {
            throw "Installation failed with exit code $($Result.ExitCode)"
        }

        # Post-Install
        $PublicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
        $ShortcutPath = Join-Path -Path $PublicDesktop -ChildPath "Brave.lnk"
        if (Test-Path -Path $ShortcutPath) {
            Remove-Item -Path $ShortcutPath -Force
        }
    }
    elseif ($DeploymentType -eq 'Uninstall') {
        # Search for Brave uninstaller in all likely locations
        $UninstallPath = $null
        
        # 1. Check Registry (Machine-wide 64-bit and 32-bit/WOW64)
        $RegPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\BraveSoftware Brave-Browser",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\BraveSoftware Brave-Browser"
        )
        
        foreach ($RegPath in $RegPaths) {
            if (Test-Path $RegPath) {
                $Val = (Get-ItemProperty -Path $RegPath -Name "UninstallString" -ErrorAction SilentlyContinue).UninstallString
                if ($Val -match '"([^"]+)"') { $UninstallPath = $Matches[1] } elseif ($Val) { $UninstallPath = $Val }
                if ($UninstallPath -and (Test-Path $UninstallPath)) { break }
            }
        }

        # 2. Check Filesystem Fallbacks (Machine-wide)
        if (-not $UninstallPath -or -not (Test-Path $UninstallPath)) {
            $Paths = @(
                "C:\Program Files\BraveSoftware\Brave-Browser\Application\*\Installer\setup.exe",
                "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\*\Installer\setup.exe"
            )
            foreach ($P in $Paths) {
                $Found = Get-ChildItem -Path $P -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
                if ($Found) { $UninstallPath = $Found; break }
            }
        }

        # 3. Check Filesystem Fallbacks (User-scoped)
        if (-not $UninstallPath -or -not (Test-Path $UninstallPath)) {
            $UserSetupPath = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\Application\*\Installer\setup.exe"
            $Found = Get-ChildItem -Path $UserSetupPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
            if ($Found) { $UninstallPath = $Found }
        }

        if ($UninstallPath -and (Test-Path $UninstallPath)) {
            Write-ADTLogEntry -Message "Executing Brave uninstaller: $UninstallPath" -Severity 1
            $UninstArgs = "--uninstall --force-uninstall"
            if ($UninstallPath -notlike "*\AppData\Local\*") {
                $UninstArgs += " --system-level"
            }

            # Exit code 20 often means "Success, but could not delete self/cleanup entirely" for Omaha variants
            $Result = Start-ADTProcess -FilePath $UninstallPath -ArgumentList $UninstArgs -PassThru
            if (@(0, 20) -contains $Result.ExitCode) {
                Write-ADTLogEntry -Message "Uninstallation successful (Exit Code: $($Result.ExitCode))" -Severity 1
            } else {
                throw "Uninstallation failed with exit code $($Result.ExitCode)"
            }
        } else {
            Write-ADTLogEntry -Message "Brave uninstaller (setup.exe) not found. Skipping." -Severity 2
        }
    }

} catch {
    Write-ADTLogEntry -Message "Deployment failed: $($_.Exception.Message)" -Severity 3
    exit 1
} finally {
    Close-ADTSession
}
