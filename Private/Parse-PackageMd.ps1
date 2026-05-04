function Parse-PackageMd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Definition path '$Path' not found."
    }

    $content = Get-Content -Path $Path -Raw
    $result = @{}

    # Extract YAML frontmatter
    if ($content -match '(?sm)^\s*---\s*(.*?)\s*---\s*(.*)$') {
        $yaml = $matches[1]
        $markdown = $matches[2]

        # Basic YAML parsing
        $yaml -split "`r?`n" | ForEach-Object {
            if ($_ -match '([^:]+):\s*(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $result[$key] = $value
            }
        }
    } else {
        $markdown = $content
    }

    # Extract Markdown sections for PSADT v4
    $sections = @(
        'Pre-Install', 
        'Install', 
        'Post-Install', 
        'Pre-Uninstall', 
        'Uninstall', 
        'Post-Uninstall', 
        'Detection'
    )

    foreach ($section in $sections) {
        # Match case-insensitively but use the canonical section name in the result
        if ($markdown -match "(?smi)^#{1,6}\s+$section\s*(.*?)(?=^\s*#{1,6}\s+|\z)") {
            $result[$section] = $matches[1].Trim()
        }
    }

    $architectureKeys = @($result.Keys | Where-Object { $_.ToLowerInvariant() -eq 'architecture' })
    foreach ($key in $architectureKeys) {
        if ($key -cne 'architecture') {
            $null = $result.Remove($key)
        }
    }

    $rawArchitecture = if ($result.ContainsKey('architecture')) { $result['architecture'] } else { $null }
    if ([string]::IsNullOrWhiteSpace($rawArchitecture)) {
        $result['architecture'] = 'auto'
    }
    else {
        $normalizedArchitecture = $rawArchitecture.Trim().ToLowerInvariant()
        $allowedArchitectures = @('auto', 'native', 'x64', 'x86', 'arm64')
        if ($normalizedArchitecture -notin $allowedArchitectures) {
            throw "Invalid architecture '$rawArchitecture' in definition frontmatter. Allowed values: $($allowedArchitectures -join ', ')."
        }

        $result['architecture'] = $normalizedArchitecture
    }

    return [pscustomobject]$result
}
