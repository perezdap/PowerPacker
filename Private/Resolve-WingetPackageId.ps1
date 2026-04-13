function Resolve-WingetPackageId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$Name,
        [string]$Source
    )

    $arguments = @('show', '--id', $Id, '--accept-source-agreements', '--disable-interactivity')
    if ($Source) {
        $arguments += @('--source', $Source)
    }

    $output = & winget @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $parsed = ConvertFrom-WingetShowOutput -Text $output
        if ($parsed.Id) {
            return $parsed.Id
        }
    }

    if ($Name) {
        $nameArguments = @('show', '--name', $Name, '--accept-source-agreements', '--disable-interactivity')
        if ($Source) {
            $nameArguments += @('--source', $Source)
        }

        $nameOutput = & winget @nameArguments 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $parsed = ConvertFrom-WingetShowOutput -Text $nameOutput
            if ($parsed.Id) {
                return $parsed.Id
            }
        }
    }

    throw "Unable to resolve a current winget package identifier for '$Id'."
}
