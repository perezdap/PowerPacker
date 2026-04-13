function New-PowerPackerPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionPath,

        [Parameter(Mandatory = $true)]
        [string]$DeployScriptPath,

        [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\Artifacts'),

        [string]$PackageDirectoryName,

        [string]$EntryScriptName = 'Invoke-AppDeployToolkit.ps1',

        [string]$PsadtTemplateZipPath,

        [string]$WingetVersion,

        [string]$WingetSource,

        [string]$Architecture,

        [string]$InstallerType,

        [string]$Locale,

        [ValidateSet('user', 'machine')]
        [string]$Scope,

        [switch]$SkipInstallerDownload,

        [switch]$Force
    )

    $definition = Parse-PackageMd -Path $DefinitionPath
    if (-not $definition.winget_id) {
        throw "Definition '$DefinitionPath' does not contain a winget_id in YAML frontmatter."
    }

    $packageName = if ($PackageDirectoryName) {
        $PackageDirectoryName
    } else {
        ($definition.winget_id -replace '[<>:"/\\|?*]', '-')
    }

    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    $artifactDirectory = Join-Path $resolvedOutputDirectory $packageName

    if (Test-Path -LiteralPath $artifactDirectory) {
        if (-not $Force) {
            throw "Artifact directory '$artifactDirectory' already exists. Use -Force to overwrite it."
        }

        Remove-Item -LiteralPath $artifactDirectory -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null

    $tempDirectory = Join-Path $artifactDirectory '.powerpacker-temp'
    New-Item -ItemType Directory -Force -Path $tempDirectory | Out-Null

    $psadtMetadata = $null
    $wingetMetadata = $null
    $installerDownload = $null

    try {
        $templateZipPath = $PsadtTemplateZipPath
        if (-not $templateZipPath) {
            $psadtMetadata = Get-PSADTTemplateAsset
            $downloadedTemplate = Save-PSADTTemplate -TagName $psadtMetadata.TagName -AssetName $psadtMetadata.AssetName -Directory $tempDirectory -Repository $psadtMetadata.Repository
            $templateZipPath = $downloadedTemplate.ZipPath
        } else {
            $templateZipPath = [System.IO.Path]::GetFullPath($templateZipPath)
            if (-not (Test-Path -LiteralPath $templateZipPath -PathType Leaf)) {
                throw "PSADT template zip '$templateZipPath' was not found."
            }
        }

        Expand-Archive -Path $templateZipPath -DestinationPath $artifactDirectory -Force

        foreach ($placeholder in @(
                (Join-Path $artifactDirectory 'Files\Add Setup Files Here.txt'),
                (Join-Path $artifactDirectory 'SupportFiles\Add Supporting Files Here.txt')
            )) {
            if (Test-Path -LiteralPath $placeholder) {
                Remove-Item -LiteralPath $placeholder -Force
            }
        }

        $entryScriptPath = Join-Path $artifactDirectory $EntryScriptName
        Copy-Item -LiteralPath $DeployScriptPath -Destination $entryScriptPath -Force

        $powerPackerSupportDirectory = Join-Path $artifactDirectory 'SupportFiles\PowerPacker'
        New-Item -ItemType Directory -Force -Path $powerPackerSupportDirectory | Out-Null

        if ((Split-Path -Leaf $DeployScriptPath) -ne $EntryScriptName) {
            Copy-Item -LiteralPath $DeployScriptPath -Destination (Join-Path $powerPackerSupportDirectory (Split-Path -Leaf $DeployScriptPath)) -Force
        }

        if (-not $SkipInstallerDownload) {
            $wingetMetadataParams = @{
                Id = $definition.winget_id
                Name = $definition.name
            }
            if ($WingetVersion) {
                $wingetMetadataParams.Version = $WingetVersion
            }
            if ($WingetSource) {
                $wingetMetadataParams.Source = $WingetSource
            }
            if ($Architecture) {
                $wingetMetadataParams.Architecture = $Architecture
            }
            if ($InstallerType) {
                $wingetMetadataParams.InstallerType = $InstallerType
            }
            if ($Locale) {
                $wingetMetadataParams.Locale = $Locale
            }
            if ($Scope) {
                $wingetMetadataParams.Scope = $Scope
            }

            $wingetMetadata = Get-WingetPackageMetadata @wingetMetadataParams
            Set-Content -LiteralPath (Join-Path $powerPackerSupportDirectory 'winget-show.txt') -Value $wingetMetadata.RawOutput

            $installerDownloadParams = @{
                Id = $definition.winget_id
                Name = $definition.name
                Directory = (Join-Path $artifactDirectory 'Files')
            }
            if ($WingetVersion) {
                $installerDownloadParams.Version = $WingetVersion
            }
            if ($WingetSource) {
                $installerDownloadParams.Source = $WingetSource
            }
            if ($Architecture) {
                $installerDownloadParams.Architecture = $Architecture
            }
            if ($InstallerType) {
                $installerDownloadParams.InstallerType = $InstallerType
            }
            if ($Locale) {
                $installerDownloadParams.Locale = $Locale
            }
            if ($Scope) {
                $installerDownloadParams.Scope = $Scope
            }

            $installerDownload = Save-WingetPackageInstaller @installerDownloadParams
            Set-Content -LiteralPath (Join-Path $powerPackerSupportDirectory 'winget-download.txt') -Value $installerDownload.RawOutput
        }

        $metadata = [ordered]@{
            CreatedAt         = (Get-Date).ToString('o')
            ArtifactDirectory = $artifactDirectory
            DefinitionPath    = [System.IO.Path]::GetFullPath($DefinitionPath)
            DeployScriptPath  = [System.IO.Path]::GetFullPath($DeployScriptPath)
            EntryScriptName   = $EntryScriptName
            Package           = $definition
            Psadt             = if ($psadtMetadata) {
                [ordered]@{
                    Repository  = $psadtMetadata.Repository
                    TagName     = $psadtMetadata.TagName
                    ReleaseName = $psadtMetadata.ReleaseName
                    AssetName   = $psadtMetadata.AssetName
                    Digest      = $psadtMetadata.Digest
                }
            } else {
                [ordered]@{
                    Source = 'Local override'
                    ZipPath = $templateZipPath
                }
            }
            Installer         = if ($SkipInstallerDownload) {
                [ordered]@{
                    Downloaded = $false
                }
            } else {
                [ordered]@{
                    Downloaded       = $true
                    WingetId         = $wingetMetadata.ResolvedId
                    RequestedId      = $definition.winget_id
                    RequestedVersion = $WingetVersion
                    RequestedScope   = $Scope
                    ResolvedVersion  = $wingetMetadata.Version
                    InstallerType    = $wingetMetadata.InstallerType
                    InstallerUrl     = $wingetMetadata.InstallerUrl
                    InstallerSha256  = $wingetMetadata.InstallerSha256
                    InstallerFiles   = $installerDownload.InstallerFiles
                    ManifestFiles    = $installerDownload.ManifestFiles
                }
            }
        }

        $metadataPath = Join-Path $powerPackerSupportDirectory 'artifact-metadata.json'
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath

        [pscustomobject]@{
            ArtifactDirectory = $artifactDirectory
            EntryScriptPath   = $entryScriptPath
            MetadataPath      = $metadataPath
            InstallerFiles    = if ($installerDownload) { $installerDownload.InstallerFiles } else { @() }
            ManifestFiles     = if ($installerDownload) { $installerDownload.ManifestFiles } else { @() }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempDirectory) {
            Remove-Item -LiteralPath $tempDirectory -Recurse -Force
        }
    }
}
