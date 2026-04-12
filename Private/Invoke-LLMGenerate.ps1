function Invoke-LLMGenerate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('OpenAI', 'Anthropic')]
        [string]$Provider,

        [Parameter(Mandatory=$true)]
        [string]$ApiKey,

        [Parameter(Mandatory=$true)]
        [hashtable]$Metadata,

        [Parameter(Mandatory=$true)]
        [hashtable]$Instructions,

        [Parameter(Mandatory=$true)]
        [pscustomobject]$WingetData,

        [Parameter(Mandatory=$false)]
        [string[]]$RepairErrors,

        [Parameter(Mandatory=$false)]
        [string]$BaseUrl,

        [Parameter(Mandatory=$false)]
        [string]$Model
    )

    $systemPrompt = @"
You are an expert Windows Systems Engineer and PowerShell Developer specializing in PSADT v4.
Your goal is to output a fully functional PSADT v4 deployment script.

CRITICAL RULES:
1. ONLY use pure PSADT v4 syntax. DO NOT use legacy v3 cmdlets (e.g., `Execute-Process`, `Show-InstallationWelcome`).
2. MUST use `Open-ADTSession`, `Close-ADTSession`, and create an `$adtSession = @{}` hashtable.
3. All main deployment logic MUST be wrapped in a try/catch block.
4. `Start-ADTProcess -FilePath` MUST use a variable for the file path (no hardcoded strings).
5. `Import-Module` MUST use paths relative to `$PSScriptRoot`.
6. Use the provided Uninstall logic fallback.
7. Return ONLY the raw PowerShell code without any markdown code block wrappers or backticks.
"@

    $userPrompt = "Generate PSADT v4 script for $($Metadata.name) ($($Metadata.winget_id)).`n`n"

    $userPrompt += "INSTALL INSTRUCTIONS:`n$($Instructions.Install)`n`n"
    $userPrompt += "UNINSTALL INSTRUCTIONS:`n$($Instructions.Uninstall)`n`n"
    $userPrompt += "DETECTION INSTRUCTIONS:`n$($Instructions.Detection)`n`n"

    $userPrompt += "UNINSTALL FALLBACK LOGIC TO INCLUDE:`n$($WingetData.UninstallLogic)`n`n"

    if ($RepairErrors) {
        $userPrompt += "CRITICAL ERROR: The previous script you generated failed AST validation. Please fix these errors:`n"
        $userPrompt += ($RepairErrors -join "`n")
    }

    try {
        if ($Provider -eq 'OpenAI') {
            $uri = if ([string]::IsNullOrWhiteSpace($BaseUrl)) { 'https://api.openai.com/v1/chat/completions' } else { "$($BaseUrl.TrimEnd('/'))/chat/completions" }
            $headers = @{
                "Authorization" = "Bearer $ApiKey"
                "Content-Type" = "application/json"
            }
            $activeModel = if ([string]::IsNullOrWhiteSpace($Model)) { "gpt-4" } else { $Model }
            Write-Verbose "Using OpenAI API URI: $uri"
            Write-Verbose "Using OpenAI Model: $activeModel"
            $body = @{
                model = $activeModel
                messages = @(
                    @{ role = "system"; content = $systemPrompt },
                    @{ role = "user"; content = $userPrompt }
                )
            } | ConvertTo-Json -Depth 5

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
            $generatedCode = $response.choices[0].message.content
        } else {
            # Anthropic integration (simplified for example)
            $uri = if ([string]::IsNullOrWhiteSpace($BaseUrl)) { 'https://api.anthropic.com/v1/messages' } else { "$($BaseUrl.TrimEnd('/'))/messages" }
            $headers = @{
                "x-api-key" = $ApiKey
                "anthropic-version" = "2023-06-01"
                "Content-Type" = "application/json"
            }
            $activeModel = if ([string]::IsNullOrWhiteSpace($Model)) { "claude-3-opus-20240229" } else { $Model }
            Write-Verbose "Using Anthropic API URI: $uri"
            Write-Verbose "Using Anthropic Model: $activeModel"
            $body = @{
                model = $activeModel
                max_tokens = 4096
                system = $systemPrompt
                messages = @(
                    @{ role = "user"; content = $userPrompt }
                )
            } | ConvertTo-Json -Depth 5

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
            $generatedCode = $response.content[0].text
        }

        # Strip markdown code blocks if the LLM hallucinated them despite instructions
        $generatedCode = $generatedCode -replace '(?sm)^```powershell\s*|^```\s*', ''
        $generatedCode = $generatedCode -replace '(?sm)\s*```$', ''

        return $generatedCode.Trim()
    } catch {
        Write-Warning "LLM Generation failed: $_"
        throw
    }
}
