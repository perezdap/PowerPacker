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

        [ValidateSet('auto', 'native', 'x64', 'x86', 'arm64')]
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

    $architecturePolicy = if ($PSBoundParameters.ContainsKey('Architecture') -and -not [string]::IsNullOrWhiteSpace($Architecture)) {
        $Architecture.Trim().ToLowerInvariant()
    }
    else {
        [string]$definition.architecture
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
    $wingetArchitectureJobs = @()

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
                Id   = $definition.winget_id
                Name = $definition.name
            }
            if ($WingetVersion) {
                $wingetMetadataParams.Version = $WingetVersion
            }
            if ($WingetSource) {
                $wingetMetadataParams.Source = $WingetSource
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

            if ($architecturePolicy -in @('auto', 'native')) {
                $resolvedArchitectures = Resolve-WingetArchitectures @wingetMetadataParams
                if (-not $resolvedArchitectures.Items -or $resolvedArchitectures.Items.Count -eq 0) {
                    throw "No winget installers were discovered for '$($definition.winget_id)' across probed architectures. Check the package id, scope, and source."
                }

                $wingetArchitectureJobs = @($resolvedArchitectures.Items)
            }
            else {
                $lockedMetadata = Get-WingetPackageMetadata @wingetMetadataParams -Architecture $architecturePolicy
                $canonicalLabel = switch ($architecturePolicy) {
                    'x64' { 'X64' }
                    'x86' { 'X86' }
                    'arm64' { 'ARM64' }
                    default { 'X64' }
                }

                $wingetArchitectureJobs = @(
                    [pscustomobject]@{
                        CanonicalLabel     = $canonicalLabel
                        WingetArchitecture = $architecturePolicy
                        Metadata             = $lockedMetadata
                    }
                )
            }

            $wingetMetadata = $wingetArchitectureJobs[0].Metadata
        }

        $installerFilesByArchitecture = [ordered]@{}
        $installerMetadataByArchitecture = [ordered]@{}
        $availableArchitectures = [System.Collections.Generic.List[string]]::new()
        $aggregatedInstallerFiles = [System.Collections.Generic.List[string]]::new()
        $aggregatedManifestFiles = [System.Collections.Generic.List[string]]::new()
        $lastRawDownloadOutput = $null

        if (-not $SkipInstallerDownload) {
            $filesDirectory = Join-Path $artifactDirectory 'Files'

            foreach ($job in $wingetArchitectureJobs) {
                $jobMetadata = $job.Metadata
                $archSupportLabel = $job.WingetArchitecture

                Set-Content -LiteralPath (Join-Path $powerPackerSupportDirectory "winget-show-$archSupportLabel.txt") -Value $jobMetadata.RawOutput

                if ([string]::IsNullOrWhiteSpace($jobMetadata.InstallerSha256)) {
                    throw "winget metadata for '$($definition.winget_id)' ($archSupportLabel) is missing Installer SHA256; cannot verify downloaded payloads."
                }

                $installerDownloadParams = @{
                    Id        = $definition.winget_id
                    Name      = $definition.name
                    Directory = $filesDirectory
                }
                if ($WingetVersion) {
                    $installerDownloadParams.Version = $WingetVersion
                }
                if ($WingetSource) {
                    $installerDownloadParams.Source = $WingetSource
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

                $installerDownloadParams.Architecture = $job.WingetArchitecture
                $installerDownloadParams.ExpectedSha256 = $jobMetadata.InstallerSha256

                $jobDownload = Save-WingetPackageInstaller @installerDownloadParams
                $lastRawDownloadOutput = $jobDownload.RawOutput
                Set-Content -LiteralPath (Join-Path $powerPackerSupportDirectory "winget-download-$archSupportLabel.txt") -Value $jobDownload.RawOutput

                $primaryInstallerPath = $jobDownload.InstallerFiles | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace([string]$primaryInstallerPath)) {
                    throw "winget download for '$($definition.winget_id)' ($archSupportLabel) did not produce an installer file."
                }

                $artifactRootFull = [System.IO.Path]::GetFullPath($artifactDirectory)
                $installerFullPath = [System.IO.Path]::GetFullPath([string]$primaryInstallerPath)
                $relativeInstallerPath = $installerFullPath.Substring($artifactRootFull.Length).TrimStart('\')

                $null = $availableArchitectures.Add($job.CanonicalLabel)
                $installerFilesByArchitecture[$job.CanonicalLabel] = $relativeInstallerPath
                $installerMetadataByArchitecture[$job.CanonicalLabel] = [ordered]@{
                    InstallerUrl     = $jobMetadata.InstallerUrl
                    InstallerSha256  = $jobMetadata.InstallerSha256
                    InstallerType    = $jobMetadata.InstallerType
                    ResolvedVersion  = $jobMetadata.Version
                    Scope            = $Scope
                }

                foreach ($path in $jobDownload.InstallerFiles) {
                    if (-not $aggregatedInstallerFiles.Contains($path)) {
                        $null = $aggregatedInstallerFiles.Add($path)
                    }
                }

                foreach ($path in $jobDownload.ManifestFiles) {
                    if (-not $aggregatedManifestFiles.Contains($path)) {
                        $null = $aggregatedManifestFiles.Add($path)
                    }
                }
            }

            $installerDownload = [pscustomobject]@{
                InstallerFiles = @($aggregatedInstallerFiles)
                ManifestFiles  = @($aggregatedManifestFiles)
                RawOutput      = if ($lastRawDownloadOutput) { $lastRawDownloadOutput } else { '' }
            }

            $legacyPriority = @('X64', 'ARM64', 'X86', 'NEUTRAL')
            $legacyMetadata = $null
            foreach ($label in $legacyPriority) {
                $match = $wingetArchitectureJobs | Where-Object { $_.CanonicalLabel -eq $label } | Select-Object -First 1
                if ($match) {
                    $legacyMetadata = $match.Metadata
                    break
                }
            }

            if (-not $legacyMetadata) {
                $legacyMetadata = $wingetArchitectureJobs[0].Metadata
            }

            $wingetMetadata = $legacyMetadata
        }

        $metadata = [ordered]@{
            MetadataSchemaVersion           = 2
            ArchitecturePolicy              = $architecturePolicy
            AvailableArchitectures          = @($availableArchitectures)
            InstallerFilesByArchitecture    = $installerFilesByArchitecture
            InstallerMetadataByArchitecture = $installerMetadataByArchitecture
            CreatedAt                       = (Get-Date).ToString('o')
            ArtifactDirectory               = $artifactDirectory
            DefinitionPath                  = [System.IO.Path]::GetFullPath($DefinitionPath)
            DeployScriptPath                = [System.IO.Path]::GetFullPath($DeployScriptPath)
            EntryScriptName                 = $EntryScriptName
            Package                         = $definition
            Psadt                           = if ($psadtMetadata) {
                [ordered]@{
                    Repository  = $psadtMetadata.Repository
                    TagName     = $psadtMetadata.TagName
                    ReleaseName = $psadtMetadata.ReleaseName
                    AssetName   = $psadtMetadata.AssetName
                    Digest      = $psadtMetadata.Digest
                }
            }
            else {
                [ordered]@{
                    Source  = 'Local override'
                    ZipPath = $templateZipPath
                }
            }
            Installer                       = if ($SkipInstallerDownload) {
                [ordered]@{
                    Downloaded = $false
                }
            }
            else {
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
                    InstallerFiles   = @($installerDownload.InstallerFiles)
                    ManifestFiles    = @($installerDownload.ManifestFiles)
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
