function Assert-InstallerSha256Matches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LiteralPaths,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256,

        [string]$ContextMessage
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        throw 'Installer SHA256 verification requires a non-empty expected hash from winget metadata.'
    }

    $expected = $ExpectedSha256.Trim().ToLowerInvariant()
    foreach ($path in $LiteralPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -eq $expected) {
            return
        }
    }

    $suffix = if ($ContextMessage) { " ($ContextMessage)" } else { '' }
    throw "Installer SHA256 verification failed$suffix. Expected '$expected' to match one of: $($LiteralPaths -join ', ')"
}
