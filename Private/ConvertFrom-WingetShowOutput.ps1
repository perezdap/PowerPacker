function ConvertFrom-WingetShowOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $result = [ordered]@{
        RawText   = $Text.Trim()
        Name      = $null
        Id        = $null
        Version   = $null
        Publisher = $null
        Moniker   = $null
        Installer = [ordered]@{
            Type          = $null
            Locale        = $null
            Architecture = $null
            Url           = $null
            Sha256        = $null
            ReleaseDate   = $null
        }
    }

    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^Found\s+(.+)\s+\[(.+)\]$') {
            $result.Name = $matches[1].Trim()
            $result.Id = $matches[2].Trim()
            continue
        }

        if ($line -match '^\s*Version:\s*(.+)$') {
            $result.Version = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Publisher:\s*(.+)$') {
            $result.Publisher = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Moniker:\s*(.+)$') {
            $result.Moniker = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Installer Type:\s*(.+)$') {
            $result.Installer.Type = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Installer Locale:\s*(.+)$') {
            $result.Installer.Locale = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Architecture:\s*(.+)$') {
            $result.Installer.Architecture = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Installer Url:\s*(.+)$') {
            $result.Installer.Url = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Installer SHA256:\s*(.+)$') {
            $result.Installer.Sha256 = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Release Date:\s*(.+)$') {
            $result.Installer.ReleaseDate = $matches[1].Trim()
            continue
        }
    }

    [pscustomobject]$result
}
