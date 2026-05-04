Describe "New-PowerPackerPackage" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Parse-PackageMd.ps1"
        . "$PSScriptRoot/../Private/ConvertFrom-WingetShowOutput.ps1"
        . "$PSScriptRoot/../Private/Assert-InstallerSha256.ps1"
        . "$PSScriptRoot/../Private/Get-PSADTTemplateAsset.ps1"
        . "$PSScriptRoot/../Private/Save-PSADTTemplate.ps1"
        . "$PSScriptRoot/../Private/Resolve-WingetPackageId.ps1"
        . "$PSScriptRoot/../Private/Get-WingetPackageMetadata.ps1"
        . "$PSScriptRoot/../Private/Resolve-WingetArchitectures.ps1"
        . "$PSScriptRoot/../Private/Save-WingetPackageInstaller.ps1"
        . "$PSScriptRoot/../Private/Test-PSADTAst.ps1"
        . "$PSScriptRoot/../Public/New-PowerPackerPackage.ps1"
    }

    It "Should build an artifact folder from a local PSADT template zip" {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().Guid)
        $templateRoot = Join-Path $root 'template'
        $artifactRoot = Join-Path $root 'artifacts'
        $definitionPath = Join-Path $root 'golang-go.md'
        $scriptPath = Join-Path $root 'generated-script.ps1'
        $zipPath = Join-Path $root 'PSAppDeployToolkit_Template_v4.zip'

        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $templateRoot 'Files') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $templateRoot 'SupportFiles') | Out-Null
            Set-Content -LiteralPath (Join-Path $templateRoot 'Invoke-AppDeployToolkit.ps1') -Value "Write-Host 'template'"
            Set-Content -LiteralPath (Join-Path $templateRoot 'Files\Add Setup Files Here.txt') -Value ''
            Set-Content -LiteralPath (Join-Path $templateRoot 'SupportFiles\Add Supporting Files Here.txt') -Value ''
            Compress-Archive -Path (Join-Path $templateRoot '*') -DestinationPath $zipPath -Force

            Set-Content -LiteralPath $definitionPath -Value @"
---
winget_id: Golang.Go
name: Go Programming Language
version: 1.26.2
---

# Install
Install silently.

# Uninstall
Uninstall silently.

# Detection
Detect installation.
"@

            Set-Content -LiteralPath $scriptPath -Value @"
[CmdletBinding()]
param (
    [Parameter(Mandatory = `$false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]`$DeploymentType = 'Install',

    [Parameter(Mandatory = `$false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [string]`$DeployMode = 'Auto',

    [Parameter(Mandatory = `$false)]
    [switch]`$SuppressRebootPassThru,

    [Parameter(Mandatory = `$false)]
    [switch]`$TerminalServerMode,

    [Parameter(Mandatory = `$false)]
    [switch]`$DisableLogging
)

`$modulePath = Join-Path -Path `$PSScriptRoot -ChildPath 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
if (-not (Get-Module -Name PSAppDeployToolkit)) {
    Import-Module -Name `$modulePath
}

`$adtSession = @{
    AppVendor = 'Go'
    AppName = 'Go Programming Language'
    RequireAdmin = `$true
}

Open-ADTSession @adtSession @PSBoundParameters

try {
    Write-ADTLogEntry -Message 'generated'
}
catch {
    Write-ADTLogEntry -Message "Deployment failed: `$(`$_.Exception.Message)" -Severity 3
    throw
}

Close-ADTSession
"@

            $result = New-PowerPackerPackage -DefinitionPath $definitionPath -DeployScriptPath $scriptPath -OutputDirectory $artifactRoot -PsadtTemplateZipPath $zipPath -SkipInstallerDownload -Force

            Test-Path -LiteralPath $result.ArtifactDirectory | Should -Be $true
            Test-Path -LiteralPath (Join-Path $result.ArtifactDirectory 'Invoke-AppDeployToolkit.ps1') | Should -Be $true
            (Get-Content -LiteralPath (Join-Path $result.ArtifactDirectory 'Invoke-AppDeployToolkit.ps1') -Raw) | Should -Match "generated"
            Test-Path -LiteralPath (Join-Path $result.ArtifactDirectory 'Files\Add Setup Files Here.txt') | Should -Be $false
            Test-Path -LiteralPath (Join-Path $result.ArtifactDirectory 'SupportFiles\Add Supporting Files Here.txt') | Should -Be $false
            Test-Path -LiteralPath (Join-Path $result.ArtifactDirectory 'SupportFiles\PowerPacker\generated-script.ps1') | Should -Be $true
            Test-Path -LiteralPath $result.MetadataPath | Should -Be $true

            $metadata = Get-Content -LiteralPath $result.MetadataPath -Raw | ConvertFrom-Json
            $metadata.MetadataSchemaVersion | Should -Be 2
            $metadata.ArchitecturePolicy | Should -Be 'auto'
            $metadata.AvailableArchitectures.Count | Should -Be 0
            $metadata.Installer.Downloaded | Should -Be $false
            $metadata.Package.winget_id | Should -Be "Golang.Go"
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "Should reject a deploy script that fails PSADT AST validation" {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().Guid)
        $artifactRoot = Join-Path $root 'artifacts'
        $definitionPath = Join-Path $root 'golang-go.md'
        $scriptPath = Join-Path $root 'generated-script.ps1'
        $zipPath = Join-Path $root 'PSAppDeployToolkit_Template_v4.zip'

        try {
            New-Item -ItemType Directory -Force -Path $root | Out-Null
            Set-Content -LiteralPath $definitionPath -Value @"
---
winget_id: Golang.Go
name: Go Programming Language
---

# Install
Install silently.
"@

            Set-Content -LiteralPath $scriptPath -Value "Write-Host 'generated'"
            Set-Content -LiteralPath $zipPath -Value 'placeholder'

            {
                New-PowerPackerPackage -DefinitionPath $definitionPath -DeployScriptPath $scriptPath -OutputDirectory $artifactRoot -PsadtTemplateZipPath $zipPath -SkipInstallerDownload -Force
            } | Should -Throw "*failed PSADT AST validation*"

            Test-Path -LiteralPath $artifactRoot | Should -Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
