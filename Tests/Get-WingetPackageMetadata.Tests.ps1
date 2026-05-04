Describe "Get-WingetPackageMetadata" {
    BeforeAll {
        . "$PSScriptRoot/../Private/ConvertFrom-WingetShowOutput.ps1"
        . "$PSScriptRoot/../Private/Get-WingetPackageMetadata.ps1"
    }

    It "Should pass scope to winget show and return the scoped metadata" {
        function Resolve-WingetPackageId {
            param(
                [string]$Id
            )

            return $Id
        }

        $script:capturedWingetArgs = $null
        function winget {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Arguments
            )

            $script:capturedWingetArgs = $Arguments
            $global:LASTEXITCODE = 0

@"
Found Microsoft Visual Studio Code [Microsoft.VisualStudioCode]
Version: 1.115.0
Publisher: Microsoft Corporation
Moniker: vscode
Installer:
  Installer Type: inno
  Installer Url: https://example.test/VSCodeSetup-x64-1.115.0.exe
  Installer SHA256: deadbeef
"@
        }

        $result = Get-WingetPackageMetadata -Id 'Microsoft.VisualStudioCode' -Scope machine

        $script:capturedWingetArgs | Should -Contain '--scope'
        $scopeIndex = [Array]::IndexOf($script:capturedWingetArgs, '--scope')
        $scopeIndex | Should -BeGreaterThan -1
        $script:capturedWingetArgs[$scopeIndex + 1] | Should -Be 'machine'
        $result.InstallerUrl | Should -Be 'https://example.test/VSCodeSetup-x64-1.115.0.exe'
        $result.RequestedScope | Should -Be 'machine'
        $result.RequestedArchitecture | Should -BeNullOrEmpty
    }
}
