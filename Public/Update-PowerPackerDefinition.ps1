function Update-PowerPackerDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$MarkdownPath,

        [Parameter(Mandatory=$false)]
        [string]$McpServerUrl = "http://localhost:8080"
    )

    # Path Resolution
    if ([string]::IsNullOrWhiteSpace($MarkdownPath)) {
        $definitions = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\Definitions") -Filter "*.md"
        if ($definitions.Count -eq 0) {
            throw "No Markdown definitions found in 'Definitions' folder and no MarkdownPath provided."
        }
        $MarkdownPath = $definitions[0].FullName
    }
    elseif (-not (Test-Path $MarkdownPath)) {
        $localDef = Join-Path $PSScriptRoot "..\Definitions" | Join-Path -ChildPath $MarkdownPath
        if (Test-Path $localDef) { $MarkdownPath = $localDef }
        elseif (Test-Path "$localDef.md") { $MarkdownPath = "$localDef.md" }
        else { throw "Could not find Markdown definition at '$MarkdownPath'." }
    }

    Write-Host "Updating definition: $MarkdownPath" -ForegroundColor Cyan

    # 1. Parse current definition
    $content = Get-Content -Path $MarkdownPath -Raw
    $parsedData = Parse-PackageMd -Path $MarkdownPath

    if (-not $parsedData.winget_id) {
        throw "Markdown file must contain a 'winget_id' in the YAML frontmatter."
    }

    # 2. Get latest data from WinGet/MCP
    Write-Verbose "Fetching latest data for $($parsedData.winget_id)..."
    $wingetData = Get-WingetMcpData -WingetId $parsedData.winget_id -McpServerUrl $McpServerUrl

    if ($null -eq $wingetData) {
        throw "Failed to retrieve latest Winget data for $($parsedData.winget_id)."
    }

    # 3. Update Frontmatter
    # We want to replace the version in the frontmatter if it has changed
    $newVersion = $null
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $showOutput = winget show $parsedData.winget_id 2>$null
        foreach ($line in $showOutput) {
            if ($line -match 'Version:\s*(.*)') { $newVersion = $matches[1].Trim() }
        }
    }

    if (-not $newVersion) { $newVersion = $parsedData.version } # Fallback to existing

    $updatedContent = $content
    if ($parsedData.version -ne $newVersion) {
        Write-Host "Updating version: $($parsedData.version) -> $newVersion" -ForegroundColor Green
        $updatedContent = $updatedContent -replace "version: $($parsedData.version)", "version: $newVersion"
    } else {
        Write-Host "Version is already up to date ($newVersion)." -ForegroundColor Gray
    }

    # 4. Save changes
    $updatedContent | Set-Content -Path $MarkdownPath -Encoding utf8

    Write-Host "Update complete!" -ForegroundColor Green
}
