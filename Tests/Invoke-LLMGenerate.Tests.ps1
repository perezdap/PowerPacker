Describe "Invoke-LLMGenerate" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Invoke-LLMGenerate.ps1"
    }

    It "Should construct correct prompt and call Invoke-RestMethod for OpenAI" {
        $content = '```powershell' + "`n" + '$adtSession = @{}' + "`n" + 'Open-ADTSession' + "`n" + 'try { }' + "`n" + 'catch { }' + "`n" + 'Close-ADTSession' + "`n" + '```'
        $mockedResponse = [pscustomobject]@{
            choices = @(
                [pscustomobject]@{
                    message = [pscustomobject]@{
                        content = $content
                    }
                }
            )
        }

        Mock Invoke-RestMethod { return $mockedResponse } -ParameterFilter { $Uri -match 'api.openai.com' }

        $metadata = @{ winget_id = 'Test.App' }
        $instructions = @{ Install = 'Install-App' }
        $wingetData = [pscustomobject]@{ UninstallLogic = '# some uninstall logic' }

        $result = Invoke-LLMGenerate -Provider 'OpenAI' -ApiKey 'fake-key' -Metadata $metadata -Instructions $instructions -WingetData $wingetData

        $result | Should -Match 'Open-ADTSession'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly
    }

    It "Should strip markdown code block backticks from the response" {
        $content = '```powershell' + "`n" + "Write-Host 'Test'" + "`n" + '```'
        $mockedResponse = [pscustomobject]@{
            choices = @(
                [pscustomobject]@{
                    message = [pscustomobject]@{
                        content = $content
                    }
                }
            )
        }

        Mock Invoke-RestMethod { return $mockedResponse } -ParameterFilter { $Uri -match 'api.openai.com' }

        $metadata = @{ winget_id = 'Test.App' }
        $instructions = @{ Install = 'Install-App' }
        $wingetData = [pscustomobject]@{ UninstallLogic = '# some uninstall logic' }

        $result = Invoke-LLMGenerate -Provider 'OpenAI' -ApiKey 'fake-key' -Metadata $metadata -Instructions $instructions -WingetData $wingetData

        $result | Should -Be "Write-Host 'Test'"
    }

    It "Should use provided BaseUrl and Model when constructing the OpenAI request" {
        $capturedUri = $null
        $capturedBody = $null
        Mock Invoke-RestMethod {
            $script:capturedUri = $Uri
            $script:capturedBody = $Body
            return [pscustomobject]@{
                choices = @(
                    [pscustomobject]@{
                        message = [pscustomobject]@{ content = 'Generated' }
                    }
                )
            }
        }

        $metadata = @{ winget_id = 'Test.App'; name = 'Test App' }
        $instructions = @{ Install = 'Install-App'; Uninstall = 'Uninstall-App'; Detection = 'Detect-App' }
        $wingetData = [pscustomobject]@{ UninstallLogic = '# uninstall logic' }

        $result = Invoke-LLMGenerate -Provider 'OpenAI' -ApiKey 'fake-key' -BaseUrl 'https://my-proxy.example.com/v1/' -Model 'gpt-custom' -Metadata $metadata -Instructions $instructions -WingetData $wingetData

        $result | Should -Be 'Generated'
        $script:capturedUri | Should -Be 'https://my-proxy.example.com/v1/chat/completions'
        $bodyObj = $script:capturedBody | ConvertFrom-Json
        $bodyObj.model | Should -Be 'gpt-custom'
    }

    It "Should trim trailing slash from BaseUrl for Anthropic" {
        $capturedUri = $null
        Mock Invoke-RestMethod {
            $script:capturedUri = $Uri
            return [pscustomobject]@{
                content = @(
                    [pscustomobject]@{ text = 'Generated' }
                )
            }
        }

        $metadata = @{ winget_id = 'Test.App'; name = 'Test App' }
        $instructions = @{ Install = 'Install-App'; Uninstall = 'Uninstall-App'; Detection = 'Detect-App' }
        $wingetData = [pscustomobject]@{ UninstallLogic = '# uninstall logic' }

        $result = Invoke-LLMGenerate -Provider 'Anthropic' -ApiKey 'fake-key' -BaseUrl 'https://my-proxy.example.com/v1/' -Model 'claude-custom' -Metadata $metadata -Instructions $instructions -WingetData $wingetData

        $result | Should -Be 'Generated'
        $script:capturedUri | Should -Be 'https://my-proxy.example.com/v1/messages'
    }

    It "Should include repair errors in prompt if provided" {
        Mock Invoke-RestMethod {
            # Assert that the body contains the error
            $bodyObj = $Body | ConvertFrom-Json
            if ($bodyObj.messages[0].content -match 'Legacy v3 cmdlet') {
                return [pscustomobject]@{ choices = @( [pscustomobject]@{ message = [pscustomobject]@{ content = 'Repaired' } } ) }
            }
            return [pscustomobject]@{ choices = @( [pscustomobject]@{ message = [pscustomobject]@{ content = 'Failed' } } ) }
        }

        $metadata = @{ winget_id = 'Test.App' }
        $instructions = @{ Install = 'Install-App' }
        $wingetData = [pscustomobject]@{ UninstallLogic = '# some uninstall logic' }
        $repairErrors = @("Legacy v3 cmdlet 'Execute-Process' is not allowed in v4.")

        $result = Invoke-LLMGenerate -Provider 'OpenAI' -ApiKey 'fake-key' -Metadata $metadata -Instructions $instructions -WingetData $wingetData -RepairErrors $repairErrors

        $result | Should -Be 'Repaired'
    }
}
