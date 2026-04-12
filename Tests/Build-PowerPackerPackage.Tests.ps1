Describe "Build-PowerPackerPackage" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Parse-PackageMd.ps1"
        . "$PSScriptRoot/../Private/Get-WingetMcpData.ps1"
        . "$PSScriptRoot/../Private/Invoke-LLMGenerate.ps1"
        . "$PSScriptRoot/../Private/Test-PSADTAst.ps1"
        . "$PSScriptRoot/../Public/Build-PowerPackerPackage.ps1"
    }

    It "Should orchestrate the full pipeline and output a valid script" {
        $tempMd = New-TemporaryFile
        $mockContent = @"
---
winget_id: Mozilla.Firefox
name: Firefox
---
## Install
## Uninstall
"@
        Set-Content -Path $tempMd.FullName -Value $mockContent
        $outDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "PowerPackerOut"

        # Mocking external calls
        Mock Get-WingetMcpData { return [pscustomobject]@{ UninstallLogic = "mocked" } }

        # Mock LLM generation to return valid code
        Mock Invoke-LLMGenerate {
            return @"
`$adtSession = @{}
Open-ADTSession
try {
    `$file = 'setup.exe'
    Start-ADTProcess -FilePath `$file
} catch {}
Close-ADTSession
"@
        }

        $result = Build-PowerPackerPackage -MarkdownPath $tempMd.FullName -OutDir $outDir -LlmProvider "OpenAI" -LlmApiKey "fake"

        $result.Success | Should -Be $true
        Test-Path (Join-Path $outDir "Deploy-Mozilla.Firefox.ps1") | Should -Be $true

        # Clean up
        Remove-Item -Path $tempMd.FullName -Force
        Remove-Item -Path $outDir -Recurse -Force
    }

    It "Should attempt repair if AST validation fails" {
         $tempMd = New-TemporaryFile
         $mockContent = @"
---
winget_id: Test.App
---
"@
         Set-Content -Path $tempMd.FullName -Value $mockContent
         $outDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "PowerPackerOut2"

         Mock Get-WingetMcpData { return [pscustomobject]@{ UninstallLogic = "mocked" } }

         $script:callCount = 0
         Mock Invoke-LLMGenerate {
            $script:callCount++
            if ($script:callCount -eq 1) {
                # Invalid v3 code
                return "Execute-Process -Path 'setup.exe'"
            } else {
                # Valid v4 code
                return @"
`$adtSession = @{}
Open-ADTSession
try { `$file = 'setup.exe'; Start-ADTProcess -FilePath `$file } catch {}
Close-ADTSession
"@
            }
         }

         $result = Build-PowerPackerPackage -MarkdownPath $tempMd.FullName -OutDir $outDir -LlmProvider "OpenAI" -LlmApiKey "fake"

         $script:callCount | Should -Be 2
         $result.Success | Should -Be $true
         $result.Repaired | Should -Be $true

         # Clean up
         Remove-Item -Path $tempMd.FullName -Force
         Remove-Item -Path $outDir -Recurse -Force
    }

    It "Should fail if repair also fails AST validation" {
         $tempMd = New-TemporaryFile
         $mockContent = @"
---
winget_id: Fail.App
---
"@
         Set-Content -Path $tempMd.FullName -Value $mockContent
         $outDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "PowerPackerOut3"

         Mock Get-WingetMcpData { return [pscustomobject]@{ UninstallLogic = "mocked" } }

         # Always return invalid code
         Mock Invoke-LLMGenerate { return "Execute-Process -Path 'setup.exe'" }

         $result = Build-PowerPackerPackage -MarkdownPath $tempMd.FullName -OutDir $outDir -LlmProvider "OpenAI" -LlmApiKey "fake"

         $result.Success | Should -Be $false
         $result.Errors.Count | Should -BeGreaterThan 0

         # Clean up
         Remove-Item -Path $tempMd.FullName -Force
         if (Test-Path $outDir) { Remove-Item -Path $outDir -Recurse -Force }
    }
}
