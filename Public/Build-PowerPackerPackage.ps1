function Build-PowerPackerPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$MarkdownPath,

        [Parameter(Mandatory=$true)]
        [string]$OutDir,

        [Parameter(Mandatory=$true)]
        [ValidateSet('OpenAI', 'Anthropic')]
        [string]$LlmProvider,

        [Parameter(Mandatory=$true)]
        [string]$LlmApiKey,

        [Parameter(Mandatory=$false)]
        [string]$McpServerUrl = "http://localhost:8080"
    )

    Write-Verbose "Parsing $MarkdownPath"
    $parsedData = Parse-PackageMd -Path $MarkdownPath

    if (-not $parsedData.winget_id) {
        Write-Error "Markdown file must contain a 'winget_id' in the YAML frontmatter."
        return [pscustomobject]@{ Success = $false; Errors = @("Missing winget_id") }
    }

    Write-Verbose "Retrieving Winget MCP data for $($parsedData.winget_id)"
    $wingetData = Get-WingetMcpData -WingetId $parsedData.winget_id -McpServerUrl $McpServerUrl

    $metadata = @{
        winget_id = $parsedData.winget_id
        name = $parsedData.name
        version = $parsedData.version
    }

    $instructions = @{
        Install = $parsedData.Install
        Uninstall = $parsedData.Uninstall
        Detection = $parsedData.Detection
    }

    Write-Verbose "Prompting LLM ($LlmProvider)"
    $generatedCode = Invoke-LLMGenerate -Provider $LlmProvider -ApiKey $LlmApiKey -Metadata $metadata -Instructions $instructions -WingetData $wingetData

    Write-Verbose "Validating AST"
    $validationResult = Test-PSADTAst -ScriptCode $generatedCode
    $repaired = $false

    if (-not $validationResult.IsValid) {
        Write-Warning "AST Validation failed. Attempting one-time repair loop."
        $repairedCode = Invoke-LLMGenerate -Provider $LlmProvider -ApiKey $LlmApiKey -Metadata $metadata -Instructions $instructions -WingetData $wingetData -RepairErrors $validationResult.Errors

        $revalidationResult = Test-PSADTAst -ScriptCode $repairedCode

        if (-not $revalidationResult.IsValid) {
            Write-Error "Repair loop failed AST validation."
            return [pscustomobject]@{ Success = $false; Errors = $revalidationResult.Errors; Repaired = $false }
        }

        $generatedCode = $repairedCode
        $repaired = $true
    }

    Write-Verbose "Validation passed. Writing to Build folder."
    if (-not (Test-Path $OutDir)) {
        New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
    }

    $outFilePath = Join-Path $OutDir "Deploy-$($parsedData.winget_id).ps1"
    Set-Content -Path $outFilePath -Value $generatedCode

    return [pscustomobject]@{
        Success = $true
        Repaired = $repaired
        OutputFilePath = $outFilePath
    }
}
