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

    return [pscustomobject]$result
}
