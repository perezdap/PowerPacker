Describe "Get-WingetMcpData" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Get-WingetMcpData.ps1"
    }

    It "Should retrieve UninstallString, ProductCode, and SilentArgs from Winget MCP" {
        # Use a non-default URL so the TCP port check is bypassed and Invoke-RestMethod is always called.
        Mock Invoke-RestMethod {
            return [pscustomobject]@{
                Id = "Mozilla.Firefox"
                UninstallString = '"C:\Program Files\Mozilla Firefox\uninstall\helper.exe"'
                ProductCode = "{12345678-ABCD-EFGH-1234-567890ABCDEF}"
                SilentArgs = "/S"
            }
        } -ParameterFilter { $Uri -match 'localhost:9999' }

        $result = Get-WingetMcpData -WingetId "Mozilla.Firefox" -McpServerUrl "http://localhost:9999"

        $result.UninstallString | Should -Be '"C:\Program Files\Mozilla Firefox\uninstall\helper.exe"'
        $result.ProductCode | Should -Be "{12345678-ABCD-EFGH-1234-567890ABCDEF}"
        $result.SilentArgs | Should -Be "/S"

        Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly
    }

    It "Should format the uninstall hierarchy fallback logic" {
         Mock Invoke-RestMethod {
            return [pscustomobject]@{
                Id = "Some.App"
                UninstallString = '"C:\App\uninst.exe"'
                ProductCode = $null
                SilentArgs = "/quiet"
            }
        } -ParameterFilter { $Uri -match 'localhost:9999' }

        $result = Get-WingetMcpData -WingetId "Some.App" -McpServerUrl "http://localhost:9999"

        # The function should also pre-format a fallback block for the LLM
        $result.UninstallLogic | Should -Match "MSI ProductCode"
        $result.UninstallLogic | Should -Match "Registry UninstallString"
        $result.UninstallLogic | Should -Match "Winget Manifest fallback"
    }
}
