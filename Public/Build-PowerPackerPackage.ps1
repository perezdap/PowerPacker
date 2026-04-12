function Build-PowerPackerPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$MarkdownPath,

        [Parameter(Mandatory=$false, Position=1)]
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

    $loadedEnv = @{}
    if (Test-Path -Path $EnvPath -PathType Leaf) {
        Write-Verbose "Loading environment variables from $EnvPath"
        Get-Content -Path $EnvPath -ErrorAction Stop | ForEach-Object {
            $line = $_
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^\s*#') {
                $parts = $line.Split('=', 2)
                if ($parts.Count -ne 2) {
                    Write-Verbose "Skipping malformed .env line: $line"
                    return
                }

                $key = $parts[0].Trim()
                $value = $parts[1].Trim()

                if ([string]::IsNullOrWhiteSpace($key)) {
                    Write-Verbose "Skipping .env entry with empty key."
                    return
                }

                if ($key -notmatch '^POWERPACKER_[A-Za-z0-9_]+$') {
                    Write-Verbose "Skipping unsupported .env key '$key'. Only POWERPACKER_-prefixed keys are allowed."
                    return
                }

                if ($value -match "^'(.*)'$" -or $value -match '^"(.*)"$') {
                    $value = $matches[1]
                }

                $loadedEnv[$key] = $value
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($MarkdownPath)) {
        Write-Verbose "No MarkdownPath provided. Searching in 'Definitions' folder."
        $definitions = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\Definitions") -Filter "*.md"
        if ($definitions.Count -eq 0) {
            throw "No Markdown definitions found in 'Definitions' folder and no MarkdownPath provided."
        }
        $MarkdownPath = $definitions[0].FullName
        Write-Host "Using latest definition: $($definitions[0].Name)" -ForegroundColor Cyan
    }
    elseif (-not (Test-Path $MarkdownPath)) {
        $localDef = Join-Path $PSScriptRoot "..\Definitions" | Join-Path -ChildPath $MarkdownPath
        if (Test-Path $localDef) {
            $MarkdownPath = $localDef
        }
        elseif (Test-Path "$localDef.md") {
            $MarkdownPath = "$localDef.md"
        }
        else {
            throw "Could not find Markdown definition at '$MarkdownPath' or in 'Definitions' folder."
        }
    }

    if ([string]::IsNullOrWhiteSpace($OutDir)) {
        $OutDir = Join-Path $PSScriptRoot "..\Build"
        Write-Verbose "No OutDir provided. Using default: $OutDir"
    }

    $activeProvider = if ($PSBoundParameters.ContainsKey('LlmProvider')) { $LlmProvider } elseif ($loadedEnv.ContainsKey('POWERPACKER_LLM_PROVIDER')) { $loadedEnv['POWERPACKER_LLM_PROVIDER'] } else { $env:POWERPACKER_LLM_PROVIDER }
    $activeApiKey = if ($PSBoundParameters.ContainsKey('LlmApiKey')) { $LlmApiKey } elseif ($loadedEnv.ContainsKey('POWERPACKER_LLM_API_KEY')) { $loadedEnv['POWERPACKER_LLM_API_KEY'] } else { $env:POWERPACKER_LLM_API_KEY }
    $activeBaseUrl = if ($PSBoundParameters.ContainsKey('LlmBaseUrl')) { $LlmBaseUrl } elseif ($loadedEnv.ContainsKey('POWERPACKER_LLM_BASE_URL')) { $loadedEnv['POWERPACKER_LLM_BASE_URL'] } else { $env:POWERPACKER_LLM_BASE_URL }
    $activeModel = if ($PSBoundParameters.ContainsKey('LlmModel')) { $LlmModel } elseif ($loadedEnv.ContainsKey('POWERPACKER_LLM_MODEL')) { $loadedEnv['POWERPACKER_LLM_MODEL'] } else { $env:POWERPACKER_LLM_MODEL }

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
