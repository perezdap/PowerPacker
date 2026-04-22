function Resolve-WingetArchitectures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$Name,
        [string]$Version,
        [string]$Source,
        [string]$InstallerType,
        [string]$Locale,
        [ValidateSet('user', 'machine')]
        [string]$Scope
    )

    $probeDefinitions = @(
        @{ Winget = 'x64'; Canonical = 'X64' },
        @{ Winget = 'arm64'; Canonical = 'ARM64' },
        @{ Winget = 'x86'; Canonical = 'X86' },
        @{ Winget = 'neutral'; Canonical = 'NEUTRAL' }
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $seenInstallerUrls = @{}

    foreach ($probe in $probeDefinitions) {
        $metadataParams = @{
            Id            = $Id
            Name          = $Name
            Architecture  = $probe.Winget
        }

        if ($Version) {
            $metadataParams.Version = $Version
        }

        if ($Source) {
            $metadataParams.Source = $Source
        }

        if ($InstallerType) {
            $metadataParams.InstallerType = $InstallerType
        }

        if ($Locale) {
            $metadataParams.Locale = $Locale
        }

        if ($Scope) {
            $metadataParams.Scope = $Scope
        }

        try {
            $metadata = Get-WingetPackageMetadata @metadataParams
        }
        catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($metadata.InstallerUrl)) {
            continue
        }

        if ($seenInstallerUrls.ContainsKey($metadata.InstallerUrl)) {
            continue
        }

        $seenInstallerUrls[$metadata.InstallerUrl] = $true
        $items.Add(
            [pscustomobject]@{
                CanonicalLabel     = $probe.Canonical
                WingetArchitecture = $probe.Winget
                Metadata             = $metadata
            }
        )
    }

    [pscustomobject]@{
        Items = @($items)
    }
}
