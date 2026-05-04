Describe "Test-PSADTAst" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Test-PSADTAst.ps1"
    }

    It "Should reject v3 cmdlets like Execute-Process" {
        $code = "Execute-Process -Path 'setup.exe'"
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Legacy v3 cmdlet 'Execute-Process' is not allowed in v4."
    }

    It "Should reject v3 cmdlets like Show-InstallationWelcome" {
        $code = "Show-InstallationWelcome -CloseApps 'iexplore'"
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Legacy v3 cmdlet 'Show-InstallationWelcome' is not allowed in v4."
    }

    It "Should require Open-ADTSession, Close-ADTSession, and `$adtSession" {
        $code = "Write-Host 'Doing things'"
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Missing required v4 cmdlet: Open-ADTSession"
        $result.Errors | Should -Contain "Missing required v4 cmdlet: Close-ADTSession"
        $result.Errors | Should -Contain "Missing required variable initialization: `$adtSession = @{}"
    }

    It "Should require Start-ADTProcess -FilePath to use a variable" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
try {
    Start-ADTProcess -FilePath 'C:\setup.exe'
} catch {}
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Start-ADTProcess -FilePath must use a variable, not a hardcoded string."
    }

    It "Should allow Start-ADTProcess -FilePath with a variable" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
try {
    `$myPath = 'C:\setup.exe'
    Start-ADTProcess -FilePath `$myPath
} catch {}
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $true
    }

    It "Should ensure main logic is wrapped in try/catch" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
Write-Host 'No try catch'
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Main deployment logic must be wrapped in a try/catch block."
    }

    It "Should ensure Import-Module uses relative path to `$PSScriptRoot" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
try {
    Import-Module 'C:\absolute\path\module.psm1'
} catch {}
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Import-Module must use paths relative to `$PSScriptRoot."
    }

    It "Should allow Import-Module with `$PSScriptRoot" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
try {
    Import-Module `"`$PSScriptRoot\module.psm1`"
} catch {}
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $true
    }

    It "Should reject architecture-aware scripts that omit OS architecture detection" {
        $code = @"
`$adtSession = @{}
Open-ADTSession
try {
    `$artifactMetadata = '{}' | ConvertFrom-Json
    `$map = `$artifactMetadata.InstallerFilesByArchitecture
    `$p = 'C:\setup.exe'
    Start-ADTProcess -FilePath `$p
} catch {}
Close-ADTSession
"@
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Architecture-aware scripts must query OS architecture via [System.Runtime.InteropServices.RuntimeInformation]."
    }

    It "Should accept architecture-aware scripts that follow the documented structure" {
        $examplePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Examples\DeployScripts\multi-arch.installer.example.ps1'
        $code = Get-Content -LiteralPath $examplePath -Raw
        $result = Test-PSADTAst -ScriptCode $code
        $result.IsValid | Should -Be $true
    }
}
