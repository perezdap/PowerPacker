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
    AppVendor    = 'Example Vendor'
    AppName      = 'Multi-Architecture Example'
    RequireAdmin = $true
}

Open-ADTSession @adtSession @PSBoundParameters

try {
    $metadataPath = Join-Path -Path $PSScriptRoot -ChildPath 'SupportFiles\PowerPacker\artifact-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "artifact-metadata.json was not found at '$metadataPath'."
    }

    $artifactMetadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $installerMap = $artifactMetadata.InstallerFilesByArchitecture

    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $osArchLabel = [string]$osArch

    $installerRelativePath = switch ($osArchLabel) {
        'Arm64' {
            if ($installerMap.ARM64) {
                Write-ADTLogEntry -Message 'Using ARM64 installer from PowerPacker metadata.'
                $installerMap.ARM64
            }
            elseif ($installerMap.X64) {
                Write-ADTLogEntry -Message 'ARM64 installer unavailable; falling back to X64 installer.'
                $installerMap.X64
            }
            elseif ($installerMap.NEUTRAL) {
                Write-ADTLogEntry -Message 'ARM64/X64 installers unavailable; falling back to neutral installer.'
                $installerMap.NEUTRAL
            }
            else {
                throw 'No compatible installer mapping was found for ARM64 endpoints.'
            }
        }
        'X64' {
            if ($installerMap.X64) {
                Write-ADTLogEntry -Message 'Using X64 installer from PowerPacker metadata.'
                $installerMap.X64
            }
            elseif ($installerMap.NEUTRAL) {
                Write-ADTLogEntry -Message 'X64 installer unavailable; falling back to neutral installer.'
                $installerMap.NEUTRAL
            }
            else {
                throw 'No compatible installer mapping was found for X64 endpoints.'
            }
        }
        'X86' {
            if ($installerMap.X86) {
                Write-ADTLogEntry -Message 'Using X86 installer from PowerPacker metadata.'
                $installerMap.X86
            }
            elseif ($installerMap.NEUTRAL) {
                Write-ADTLogEntry -Message 'X86 installer unavailable; falling back to neutral installer.'
                $installerMap.NEUTRAL
            }
            else {
                throw 'No compatible installer mapping was found for X86 endpoints.'
            }
        }
        default {
            throw "Unsupported OS architecture '$osArchLabel'."
        }
    }

    $installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerRelativePath
    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Resolved installer path '$installerPath' does not exist."
    }

    if ($DeploymentType -eq 'Install') {
        Show-ADTInstallationWelcome
        Start-ADTProcess -FilePath $installerPath -PassThru | Out-Null
    }
    elseif ($DeploymentType -eq 'Uninstall') {
        Show-ADTInstallationWelcome
        # Look up the UninstallString from the registry rather than hard-coding a version-specific path.
        # See Examples/DeployScripts/mozilla.firefox.ps1 for a full registry-driven uninstall pattern.
        throw 'Uninstall is not implemented in this example. Add registry-driven uninstall logic here.'
    }
}
catch {
    Write-ADTLogEntry -Message "Deployment failed: $($_.Exception.Message)" -Severity 3
    throw
}

Close-ADTSession
