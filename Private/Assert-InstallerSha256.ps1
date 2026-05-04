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
    $foundPaths = [System.Collections.Generic.List[string]]::new()
    $mismatchedPaths = [System.Collections.Generic.List[string]]::new()

    foreach ($path in $LiteralPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $null = $foundPaths.Add($path)
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -eq $expected) {
            return
        }
        $null = $mismatchedPaths.Add($path)
    }

    $suffix = if ($ContextMessage) { " ($ContextMessage)" } else { '' }
    if ($foundPaths.Count -eq 0) {
        throw "Installer SHA256 verification failed$suffix. No installer files were found at the expected paths: $($LiteralPaths -join ', ')"
    }
    throw "Installer SHA256 verification failed$suffix. Hash mismatch for: $($mismatchedPaths -join ', '). Expected SHA256: '$expected'"
}
