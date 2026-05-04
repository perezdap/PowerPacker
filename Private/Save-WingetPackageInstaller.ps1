function Save-WingetPackageInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [string]$Name,
        [string]$Version,
        [string]$Source,
        [string]$Architecture,
        [string]$InstallerType,
        [string]$Locale,
        [ValidateSet('user', 'machine')]
        [string]$Scope,

        [string]$ExpectedSha256
    )

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $existingFiles = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $Directory -Recurse -File -ErrorAction SilentlyContinue)) {
        $existingFiles[$file.FullName] = $true
    }

    $resolvedId = Resolve-WingetPackageId -Id $Id -Name $Name -Source $Source

    $arguments = @(
        'download'
        '--id', $resolvedId
        '--exact'
        '--download-directory', $Directory
        '--accept-source-agreements'
        '--accept-package-agreements'
        '--disable-interactivity'
    )

    if ($Version) {
        $arguments += @('--version', $Version)
    }
    if ($Source) {
        $arguments += @('--source', $Source)
    }
    if ($Architecture) {
        $arguments += @('--architecture', $Architecture)
    }
    if ($InstallerType) {
        $arguments += @('--installer-type', $InstallerType)
    }
    if ($Locale) {
        $arguments += @('--locale', $Locale)
    }
    if ($Scope) {
        $arguments += @('--scope', $Scope)
    }

    $output = & winget @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download installer for '$Id'. $output".Trim()
    }

    $newFiles = foreach ($file in (Get-ChildItem -LiteralPath $Directory -Recurse -File -ErrorAction SilentlyContinue)) {
        if (-not $existingFiles.ContainsKey($file.FullName)) {
            $file
        }
    }

    $installerFiles = @($newFiles | Where-Object { $_.Extension -notin @('.yaml', '.yml', '.txt') } | Select-Object -ExpandProperty FullName)
    $manifestFiles = @($newFiles | Where-Object { $_.Extension -in @('.yaml', '.yml') } | Select-Object -ExpandProperty FullName)

    if ($PSBoundParameters.ContainsKey('ExpectedSha256') -and -not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Assert-InstallerSha256Matches -LiteralPaths $installerFiles -ExpectedSha256 $ExpectedSha256 -ContextMessage $resolvedId
    }

    [pscustomobject]@{
        DownloadDirectory = $Directory
        RequestedId       = $Id
        ResolvedId        = $resolvedId
        InstallerFiles    = $installerFiles
        ManifestFiles     = $manifestFiles
        RawOutput         = $output.Trim()
    }
}
