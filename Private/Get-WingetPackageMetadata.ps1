function Get-WingetPackageMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$Name,
        [string]$Version,
        [string]$Source,
        [string]$Architecture,
        [string]$InstallerType,
        [string]$Locale,
        [ValidateSet('user', 'machine')]
        [string]$Scope
    )

    $resolvedId = Resolve-WingetPackageId -Id $Id -Name $Name -Source $Source

    $arguments = @('show', '--id', $resolvedId, '--exact', '--accept-source-agreements', '--disable-interactivity')

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
        throw "Failed to query winget metadata for '$Id'. $output".Trim()
    }

    $parsed = ConvertFrom-WingetShowOutput -Text $output
    [pscustomobject]@{
        RawOutput        = $output.Trim()
        PackageName      = $parsed.Name
        WingetId         = $parsed.Id
        RequestedId      = $Id
        ResolvedId       = $resolvedId
        Version          = $parsed.Version
        Publisher        = $parsed.Publisher
        Moniker          = $parsed.Moniker
        InstallerType    = $parsed.Installer.Type
        InstallerLocale  = $parsed.Installer.Locale
        InstallerUrl     = $parsed.Installer.Url
        InstallerSha256  = $parsed.Installer.Sha256
        ReleaseDate      = $parsed.Installer.ReleaseDate
        RequestedVersion = $Version
        RequestedScope   = $Scope
    }
}
