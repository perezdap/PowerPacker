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
    AppVendor    = 'Mozilla'
    AppName      = 'Firefox'
    RequireAdmin = $true
}

Open-ADTSession @adtSession @PSBoundParameters

try {
    $dirFiles = Join-Path -Path $PSScriptRoot -ChildPath 'Files'
    $metadataPath = Join-Path -Path $PSScriptRoot -ChildPath 'SupportFiles\PowerPacker\artifact-metadata.json'

    $installerPath = $null

    if (Test-Path -Path $metadataPath) {
        $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
        $installerMap = @{}

        if ($metadata.InstallerFilesByArchitecture) {
            foreach ($property in $metadata.InstallerFilesByArchitecture.PSObject.Properties) {
                $installerMap[$property.Name.ToUpperInvariant()] = [string]$property.Value
            }

            $osArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToUpperInvariant()
            $candidateArchitectures = @()

            switch ($osArchitecture) {
                'ARM64' { $candidateArchitectures = @('ARM64', 'X64', 'NEUTRAL') }
                'X64' { $candidateArchitectures = @('X64', 'NEUTRAL') }
                'X86' { $candidateArchitectures = @('X86', 'NEUTRAL') }
                default {
                    Write-ADTLogEntry -Message "Unrecognized OS architecture '$osArchitecture'. Falling back to neutral installer selection."
                    $candidateArchitectures = @('NEUTRAL')
                }
            }

            foreach ($candidate in $candidateArchitectures) {
                if ($installerMap.ContainsKey($candidate)) {
                    $relativeInstallerPath = $installerMap[$candidate]
                    $installerPath = Join-Path -Path $PSScriptRoot -ChildPath $relativeInstallerPath
                    Write-ADTLogEntry -Message "Selected installer for '$candidate' architecture at '$installerPath'."
                    break
                }

                Write-ADTLogEntry -Message "No installer mapped for '$candidate'. Trying next fallback architecture."
            }
        }
    }

    if (-not $installerPath -or -not (Test-Path -Path $installerPath)) {
        $installerPath = Get-ChildItem -Path $dirFiles -Filter 'Mozilla Firefox*.exe' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 1
    }

    if ((-not $installerPath -or -not (Test-Path -Path $installerPath)) -and (Test-Path -Path $dirFiles)) {
        $installerPath = Get-ChildItem -Path $dirFiles -Filter 'Mozilla Firefox*.msi' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 1
    }

    if ($DeploymentType -eq 'Install') {
        Show-ADTInstallationWelcome -CloseProcesses 'firefox'

        if (-not $installerPath -or -not (Test-Path -Path $installerPath)) {
            throw "Firefox installer was not found in '$dirFiles'."
        }

        $installerExtension = [System.IO.Path]::GetExtension($installerPath).ToLowerInvariant()
        $installResult = $null

        if ($installerExtension -eq '.msi') {
            $msiExecPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\msiexec.exe'
            $msiInstallArgs = "/i `"$installerPath`" /qn /norestart"
            Write-ADTLogEntry -Message "Installing Firefox MSI from '$installerPath'."
            $installResult = Start-ADTProcess -FilePath $msiExecPath -ArgumentList $msiInstallArgs -PassThru
        }
        else {
            $exeInstallArgs = '-ms'
            Write-ADTLogEntry -Message "Installing Firefox EXE from '$installerPath' with arguments '$exeInstallArgs'."
            $installResult = Start-ADTProcess -FilePath $installerPath -ArgumentList $exeInstallArgs -PassThru
        }

        if ($installResult.ExitCode -ne 0) {
            throw "Firefox installation failed with exit code $($installResult.ExitCode)."
        }

        $machineDetectionPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Mozilla Firefox\firefox.exe'
        if (-not (Test-Path -Path $machineDetectionPath)) {
            Write-ADTLogEntry -Message "Firefox executable was not found at '$machineDetectionPath' after installation." -Severity 2
        }
    }
    elseif ($DeploymentType -eq 'Uninstall') {
        Show-ADTInstallationWelcome -CloseProcesses 'firefox'

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
                    $keyProperties.DisplayName -like 'Mozilla Firefox*' -or $keyProperties.DisplayName -like 'Firefox*'
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
            $helperCandidates = @()
            if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
                $helperCandidates += (Join-Path -Path $env:ProgramFiles -ChildPath 'Mozilla Firefox\uninstall\helper.exe')
            }
            if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
                $helperCandidates += (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Mozilla Firefox\uninstall\helper.exe')
            }
            if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
                $helperCandidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Mozilla Firefox\uninstall\helper.exe')
            }

            foreach ($candidatePath in $helperCandidates) {
                if (Test-Path -Path $candidatePath) {
                    $uninstallPath = $candidatePath
                    break
                }
            }
        }

        if (-not $uninstallPath -or -not (Test-Path -Path $uninstallPath)) {
            Write-ADTLogEntry -Message 'Firefox uninstall command was not found. Skipping uninstall.' -Severity 2
        }
        else {
            if ($uninstallPath -match '(?i)helper\.exe$' -and [string]::IsNullOrWhiteSpace($uninstallArgs)) {
                $uninstallArgs = '-ms'
            }

            if ($uninstallPath -match '(?i)msiexec(\.exe)?$') {
                if (-not [string]::IsNullOrWhiteSpace($uninstallArgs) -and $uninstallArgs -match '(?i)(^|\s)/i(?=\s|\{|$)') {
                    $uninstallArgs = [regex]::Replace($uninstallArgs, '(?i)(^|\s)/i(?=\s|\{|$)', '$1/x', 1)
                }

                if ([string]::IsNullOrWhiteSpace($uninstallArgs)) {
                    throw "Firefox uninstall command resolved to '$uninstallPath' but no uninstall arguments were found."
                }

                if ($uninstallArgs -notmatch '(?i)/q') {
                    $uninstallArgs = "$uninstallArgs /qn"
                }
                if ($uninstallArgs -notmatch '(?i)/norestart') {
                    $uninstallArgs = "$uninstallArgs /norestart"
                }
            }

            Write-ADTLogEntry -Message "Executing Firefox uninstaller '$uninstallPath' with arguments '$uninstallArgs'."
            $uninstallResult = if ([string]::IsNullOrWhiteSpace($uninstallArgs)) {
                Start-ADTProcess -FilePath $uninstallPath -PassThru
            }
            else {
                Start-ADTProcess -FilePath $uninstallPath -ArgumentList $uninstallArgs -PassThru
            }

            if ($uninstallResult.ExitCode -ne 0) {
                throw "Firefox uninstall failed with exit code $($uninstallResult.ExitCode)."
            }
        }
    }
}
catch {
    Write-ADTLogEntry -Message "Deployment failed: $($_.Exception.Message)" -Severity 3
    throw
}

Close-ADTSession
