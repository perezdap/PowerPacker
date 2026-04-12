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
