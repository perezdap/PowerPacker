function Build-PowerPackerPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$MarkdownPath,

        [Parameter(Mandatory=$true)]
        [string]$OutDir,

        [Parameter(Mandatory=$false)]
        [ValidateSet('OpenAI', 'Anthropic')]
        [string]$LlmProvider,

        [Parameter(Mandatory=$false)]
        [string]$LlmApiKey,

        [Parameter(Mandatory=$false)]
        [string]$LlmBaseUrl,

        [Parameter(Mandatory=$false)]
        [string]$LlmModel,

        [Parameter(Mandatory=$false)]
        [string]$EnvPath = ".env",

        [Parameter(Mandatory=$false)]
        [string]$McpServerUrl = "http://localhost:8080"
    )

    if (Test-Path $EnvPath) {
        Write-Verbose "Loading environment variables from $EnvPath"
        Get-Content $EnvPath | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^\s*#') {
                $parts = $_.Split('=', 2)
                if ($parts.Count -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    if ($value -match "^'(.*)'$" -or $value -match '^"(.*)"$') {
                        $value = $matches[1]
                    }
                    Set-Item -Path "Env:$key" -Value $value
                }
            }
        }
    }

    $activeProvider = if ($PSBoundParameters.ContainsKey('LlmProvider')) { $LlmProvider } else { $env:POWERPACKER_LLM_PROVIDER }
    $activeApiKey = if ($PSBoundParameters.ContainsKey('LlmApiKey')) { $LlmApiKey } else { $env:POWERPACKER_LLM_API_KEY }
    $activeBaseUrl = if ($PSBoundParameters.ContainsKey('LlmBaseUrl')) { $LlmBaseUrl } else { $env:POWERPACKER_LLM_BASE_URL }
    $activeModel = if ($PSBoundParameters.ContainsKey('LlmModel')) { $LlmModel } else { $env:POWERPACKER_LLM_MODEL }

    if ([string]::IsNullOrWhiteSpace($activeProvider)) {
        throw "LlmProvider must be provided via parameter or POWERPACKER_LLM_PROVIDER environment variable."
    }
    if ([string]::IsNullOrWhiteSpace($activeApiKey)) {
        throw "LlmApiKey must be provided via parameter or POWERPACKER_LLM_API_KEY environment variable."
    }

    Write-Verbose "Parsing $MarkdownPath"
    $parsedData = Parse-PackageMd -Path $MarkdownPath

    if (-not $parsedData.winget_id) {
        Write-Error "Markdown file must contain a 'winget_id' in the YAML frontmatter."
        return [pscustomobject]@{ Success = $false; Errors = @("Missing winget_id") }
    }

    Write-Verbose "Retrieving Winget MCP data for $($parsedData.winget_id)"
    $wingetData = Get-WingetMcpData -WingetId $parsedData.winget_id -McpServerUrl $McpServerUrl

    if ($null -eq $wingetData) {
        Write-Error "Failed to retrieve Winget data from MCP for $($parsedData.winget_id)"
        return [pscustomobject]@{ Success = $false; Errors = @("Failed to retrieve Winget data from MCP for $($parsedData.winget_id)") }
    }

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

    Write-Verbose "Prompting LLM ($activeProvider)"
    $generatedCode = Invoke-LLMGenerate -Provider $activeProvider -ApiKey $activeApiKey -BaseUrl $activeBaseUrl -Model $activeModel -Metadata $metadata -Instructions $instructions -WingetData $wingetData

    Write-Verbose "Validating AST"
    $validationResult = Test-PSADTAst -ScriptCode $generatedCode
    $repaired = $false

    if (-not $validationResult.IsValid) {
        Write-Warning "AST Validation failed. Attempting one-time repair loop."
        $repairedCode = Invoke-LLMGenerate -Provider $activeProvider -ApiKey $activeApiKey -BaseUrl $activeBaseUrl -Model $activeModel -Metadata $metadata -Instructions $instructions -WingetData $wingetData -RepairErrors $validationResult.Errors

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
