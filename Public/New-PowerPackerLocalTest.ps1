function New-PowerPackerLocalTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [string]$WorkspaceRoot = (Join-Path $PSScriptRoot '..\Build\LocalLab'),

        [string]$EntryScriptName = 'Invoke-AppDeployToolkit.ps1',

        [int[]]$SuccessExitCodes = @(0, 3010, 1641),

        [switch]$RunUninstall,
        [string]$InstallProbeCommand,
        [string]$UninstallProbeCommand,
        [switch]$SkipDefaultProbes,
        [switch]$Force
    )

    function New-DefaultInstallProbeCommand {
        param(
            [Parameter(Mandatory = $true)]
            [string]$DisplayName
        )

        $escapedDisplayName = $DisplayName.Replace('"', '\"')
        'cmd.exe /c (reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "{0}" >nul 2>nul || reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "{0}" >nul 2>nul)' -f $escapedDisplayName
    }

    function New-DefaultUninstallProbeCommand {
        param(
            [Parameter(Mandatory = $true)]
            [string]$DisplayName
        )

        $escapedDisplayName = $DisplayName.Replace('"', '\"')
        'cmd.exe /c (reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "{0}" >nul 2>nul || reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "{0}" >nul 2>nul) && exit /b 1 || exit /b 0' -f $escapedDisplayName
    }

    $resolvedPackagePath = [System.IO.Path]::GetFullPath($PackagePath)
    if (-not (Test-Path -LiteralPath $resolvedPackagePath -PathType Container)) {
        throw "Package path '$PackagePath' was not found."
    }

    $entryScriptHostPath = Join-Path $resolvedPackagePath $EntryScriptName
    if (-not (Test-Path -LiteralPath $entryScriptHostPath -PathType Leaf)) {
        throw "Entry script '$EntryScriptName' was not found under '$resolvedPackagePath'."
    }

    $artifactMetadataPath = Join-Path $resolvedPackagePath 'SupportFiles\PowerPacker\artifact-metadata.json'
    $artifactMetadata = $null
    if (Test-Path -LiteralPath $artifactMetadataPath -PathType Leaf) {
        $artifactMetadata = Get-Content -LiteralPath $artifactMetadataPath -Raw | ConvertFrom-Json
    }

    $packageDisplayName = if ($artifactMetadata -and $artifactMetadata.Package -and $artifactMetadata.Package.name) {
        [string]$artifactMetadata.Package.name
    } else {
        $null
    }

    if (-not $InstallProbeCommand -and -not $SkipDefaultProbes -and $packageDisplayName) {
        $InstallProbeCommand = New-DefaultInstallProbeCommand -DisplayName $packageDisplayName
    }

    if (-not $UninstallProbeCommand -and -not $SkipDefaultProbes -and $packageDisplayName) {
        $UninstallProbeCommand = New-DefaultUninstallProbeCommand -DisplayName $packageDisplayName
    }

    $packageName = Split-Path -Leaf $resolvedPackagePath
    $workspaceDirectory = Join-Path ([System.IO.Path]::GetFullPath($WorkspaceRoot)) $packageName

    if (Test-Path -LiteralPath $workspaceDirectory) {
        if (-not $Force) {
            throw "LocalLab workspace '$workspaceDirectory' already exists. Use -Force to overwrite it."
        }

        Remove-Item -LiteralPath $workspaceDirectory -Recurse -Force
    }

    $resultsDirectory = Join-Path $workspaceDirectory 'Results'
    New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
    $launchLogPath = Join-Path $resultsDirectory 'local-launch.log'

    # Local Lab specific staging paths
    # We use a path that is likely to be accessible and simulate a standard deployment root
    $stagingRoot = 'C:\PowerPacker\LocalLab'
    $automationPackagePath = Join-Path $stagingRoot $packageName
    $automationEntryScriptPath = Join-Path $automationPackagePath $EntryScriptName

    $installCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $automationEntryScriptPath -DeploymentType Install -DeployMode Silent"
    $uninstallCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $automationEntryScriptPath -DeploymentType Uninstall -DeployMode Silent"

    $manifest = [ordered]@{
        PackagePath               = $resolvedPackagePath
        WorkspaceDirectory        = $workspaceDirectory
        ResultsDirectory          = $resultsDirectory
        HostPackagePath           = $resolvedPackagePath
        HostResultsPath           = $resultsDirectory
        ArtifactMetadataPath      = if ($artifactMetadata) { $artifactMetadataPath } else { $null }
        PackageDisplayName        = $packageDisplayName
        EntryScriptName           = $EntryScriptName
        AutomationStagingPath     = $automationPackagePath
        AutomationEntryScriptPath = $automationEntryScriptPath
        ResultJsonPath            = (Join-Path $resultsDirectory 'local-test-result.json')
        LaunchLogPath             = $launchLogPath
        RunUninstall              = [bool]$RunUninstall
        SuccessExitCodes          = @($SuccessExitCodes | Sort-Object -Unique)
        InstallCommand            = $installCommand
        UninstallCommand          = $uninstallCommand
        InstallProbeCommand       = $InstallProbeCommand
        UninstallProbeCommand     = $UninstallProbeCommand
        DefaultProbesEnabled      = [bool](-not $SkipDefaultProbes)
    }

    $manifestPath = Join-Path $workspaceDirectory 'local-manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath

    [pscustomobject]@{
        WorkspaceDirectory = $workspaceDirectory
        ManifestPath       = $manifestPath
        ResultsDirectory   = $resultsDirectory
        LaunchLogPath      = $launchLogPath
        ResultJsonPath     = $manifest.ResultJsonPath
    }
}
