function Parse-PackageMd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $content = Get-Content -Path $Path -Raw
    $result = @{}

    # Extract YAML frontmatter
    if ($content -match '(?sm)^\s*---\s*(.*?)\s*---\s*(.*)$') {
        $yaml = $matches[1]
        $markdown = $matches[2]

        # Basic YAML parsing (for our specific needs)
        $yaml -split "`r?`n" | Where-Object { $_ -match '([^:]+):\s*(.*)' } | ForEach-Object {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $result[$key] = $value
        }
    } else {
        $markdown = $content
    }

    # Extract Markdown sections
    $sections = @('Install', 'Uninstall', 'Detection')

    foreach ($section in $sections) {
        if ($markdown -match "(?sm)##\s+$section\s*(.*?)(?=##\s+[A-Z]|$)") {
            $result[$section] = $matches[1].Trim()
        }
    }

    return [pscustomobject]$result
}
