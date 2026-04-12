Describe "New-PowerPackerSandboxTest" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Get-PowerPackerSandboxWsbContent.ps1"
        . "$PSScriptRoot/../Public/New-PowerPackerSandboxTest.ps1"
        . "$PSScriptRoot/../Public/Start-PowerPackerSandboxTest.ps1"
    }

    It "Should create a sandbox workspace with a .wsb file and manifest" {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().Guid)
        $packagePath = Join-Path $root 'Artifacts\SamplePackage'
        $workspaceRoot = Join-Path $root 'Build\Sandbox'

        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $packagePath 'SupportFiles\PowerPacker') | Out-Null
            Set-Content -LiteralPath (Join-Path $packagePath 'Invoke-AppDeployToolkit.ps1') -Value "Write-Host 'test'"
            @'
{
  "Package": {
    "name": "Sample App"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $packagePath 'SupportFiles\PowerPacker\artifact-metadata.json')

            $result = New-PowerPackerSandboxTest -PackagePath $packagePath -WorkspaceRoot $workspaceRoot -RunUninstall -DisableVGpu -ShutdownWhenComplete -Force

            Test-Path -LiteralPath $result.WsbPath | Should -Be $true
            Test-Path -LiteralPath $result.ManifestPath | Should -Be $true
            Test-Path -LiteralPath $result.LaunchLogPath | Should -Be $false

            $wsbContent = Get-Content -LiteralPath $result.WsbPath -Raw
            $wsbContent | Should -Match '<Networking>Disable</Networking>'
            $wsbContent | Should -Match '<VGpu>Disable</VGpu>'
            $wsbContent | Should -Match 'C:\\PowerPackerManual\\Package'
            $wsbContent | Should -Not -Match '<LogonCommand>'

            $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
            $manifest.AutomationSandboxPackagePath | Should -Be 'C:\PowerPacker\Package'
            $manifest.InstallCommand | Should -Match 'Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent'
            $manifest.UninstallCommand | Should -Match 'Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall -DeployMode Silent'
            $manifest.InstallProbeCommand | Should -Match 'Sample App'
            $manifest.UninstallProbeCommand | Should -Match 'Sample App'
            $manifest.DisableNetworking | Should -Be $true
            $manifest.EnableNetworking | Should -Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "Should read a manifest and return launch metadata without waiting when Start is called" {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().Guid)
        $manifestPath = Join-Path $root 'sandbox-manifest.json'
        $wsbPath = Join-Path $root 'PowerPackerSandbox.wsb'
        $resultsDirectory = Join-Path $root 'Results'
        $resultJsonPath = Join-Path $resultsDirectory 'sandbox-test-result.json'
        $launchLogPath = Join-Path $resultsDirectory 'sandbox-launch.log'

        try {
            New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
            Set-Content -LiteralPath $wsbPath -Value '<Configuration />'
            @{
                WsbPath = $wsbPath
                ResultsDirectory = $resultsDirectory
                ResultJsonPath = $resultJsonPath
                LaunchLogPath = $launchLogPath
            } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath

            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'wsb' }
            Mock Get-Command {
                [pscustomobject]@{ Source = 'C:\Windows\System32\WindowsSandbox.exe' }
            } -ParameterFilter { $Name -eq 'WindowsSandbox.exe' }
            Mock Start-Process {
                [pscustomobject]@{ Id = 4242 }
            }

            $result = Start-PowerPackerSandboxTest -ManifestPath $manifestPath
            $result.ManifestPath | Should -Be $manifestPath
            $result.WaitedForResult | Should -Be $false
            $result.ProcessId | Should -Be 4242
            Test-Path -LiteralPath $launchLogPath | Should -Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
