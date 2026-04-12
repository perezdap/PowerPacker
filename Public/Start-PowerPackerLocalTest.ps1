function Start-PowerPackerLocalTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest')]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Workspace')]
        [string]$WorkspaceDirectory,

        [int]$CommandStepTimeoutSeconds = 1800,

        [switch]$SkipCleanup
    )

    function Write-LocalLog {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string]$Message
        )

        $line = '{0} {1}' -f (Get-Date).ToString('o'), $Message
        Add-Content -LiteralPath $Path -Value $line
    }

    function Invoke-LocalCommandWithTimeout {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Command,

            [Parameter(Mandatory = $true)]
            [int]$StepTimeoutSeconds,

            [Parameter(Mandatory = $true)]
            [string]$StepName,

            [Parameter(Mandatory = $true)]
            [string]$LogPath,

            [int[]]$SuccessExitCodes = @(0)
        )

        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            Write-LocalLog -Path $LogPath -Message "BEGIN $StepName :: $Command"
            
            # Parse command for Start-Process
            # Simple heuristic: split by space, but respect quotes
            # In our case, we know it's powershell.exe ... or cmd.exe ...
            if ($Command -match '^([^\s"]+|"[^"]+")\s+(.*)$') {
                $executable = $matches[1].Trim('"')
                $arguments = $matches[2]
            } else {
                $executable = $Command.Trim('"')
                $arguments = ''
            }

            $process = Start-Process -FilePath $executable -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden

            if (-not $process.WaitForExit($StepTimeoutSeconds * 1000)) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {}

                $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
                $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
                Write-LocalLog -Path $LogPath -Message "TIMEOUT $StepName :: stdout=$stdout :: stderr=$stderr"
                
                return [pscustomobject]@{
                    StepName        = $StepName
                    Command         = $Command
                    CommandExitCode = -1
                    Succeeded       = $false
                    StdOut          = $stdout
                    StdErr          = $stderr
                    Error           = "Timed out after $StepTimeoutSeconds seconds"
                }
            }

            $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
            $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
            Write-LocalLog -Path $LogPath -Message "END $StepName :: exit=$($process.ExitCode) :: stdout=$stdout :: stderr=$stderr"

            [pscustomobject]@{
                StepName        = $StepName
                Command         = $Command
                CommandExitCode = $process.ExitCode
                Succeeded       = ($SuccessExitCodes -contains $process.ExitCode)
                StdOut          = $stdout
                StdErr          = $stderr
            }
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    $resolvedManifestPath = if ($PSCmdlet.ParameterSetName -eq 'Workspace') {
        Join-Path ([System.IO.Path]::GetFullPath($WorkspaceDirectory)) 'local-manifest.json'
    } else {
        [System.IO.Path]::GetFullPath($ManifestPath)
    }

    if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
        throw "Local manifest '$resolvedManifestPath' was not found."
    }

    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
    $launchLogPath = $manifest.LaunchLogPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launchLogPath) | Out-Null
    Set-Content -LiteralPath $launchLogPath -Value ''
    Write-LocalLog -Path $launchLogPath -Message "Loaded manifest $resolvedManifestPath"

    if (Test-Path -LiteralPath $manifest.ResultJsonPath) {
        Remove-Item -LiteralPath $manifest.ResultJsonPath -Force
    }

    $summary = [ordered]@{
        ManifestPath       = $resolvedManifestPath
        PackagePath        = $manifest.PackagePath
        PackageDisplayName = $manifest.PackageDisplayName
        StartedAt          = (Get-Date).ToString('o')
        CompletedAt        = $null
        Success            = $false
        Install            = $null
        InstallProbe       = $null
        Uninstall          = $null
        UninstallProbe     = $null
        Errors             = @()
    }

    try {
        # 1. Stage the package
        Write-LocalLog -Path $launchLogPath -Message "Staging package to $($manifest.AutomationStagingPath)"
        if (Test-Path -LiteralPath $manifest.AutomationStagingPath) {
            Remove-Item -LiteralPath $manifest.AutomationStagingPath -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifest.AutomationStagingPath) | Out-Null
        Copy-Item -Path $manifest.PackagePath -Destination $manifest.AutomationStagingPath -Recurse -Force

        # 2. Run Install
        $summary.Install = Invoke-LocalCommandWithTimeout -Command $manifest.InstallCommand -StepName 'install' -StepTimeoutSeconds $CommandStepTimeoutSeconds -LogPath $launchLogPath -SuccessExitCodes $manifest.SuccessExitCodes
        if (-not $summary.Install.Succeeded) {
            $summary.Errors += "Install failed with exit code $($summary.Install.CommandExitCode)"
        }

        # 3. Run Install Probe
        if ($manifest.InstallProbeCommand) {
            $summary.InstallProbe = Invoke-LocalCommandWithTimeout -Command $manifest.InstallProbeCommand -StepName 'install-probe' -StepTimeoutSeconds 60 -LogPath $launchLogPath -SuccessExitCodes @(0)
            if (-not $summary.InstallProbe.Succeeded) {
                $summary.Errors += "Install probe failed."
            }
        }

        # 4. Run Uninstall (Optional)
        if ($manifest.RunUninstall) {
            $summary.Uninstall = Invoke-LocalCommandWithTimeout -Command $manifest.UninstallCommand -StepName 'uninstall' -StepTimeoutSeconds $CommandStepTimeoutSeconds -LogPath $launchLogPath -SuccessExitCodes $manifest.SuccessExitCodes
            if (-not $summary.Uninstall.Succeeded) {
                $summary.Errors += "Uninstall failed with exit code $($summary.Uninstall.CommandExitCode)"
            }

            # 5. Run Uninstall Probe
            if ($manifest.UninstallProbeCommand) {
                $summary.UninstallProbe = Invoke-LocalCommandWithTimeout -Command $manifest.UninstallProbeCommand -StepName 'uninstall-probe' -StepTimeoutSeconds 60 -LogPath $launchLogPath -SuccessExitCodes @(0)
                if (-not $summary.UninstallProbe.Succeeded) {
                    $summary.Errors += "Uninstall probe failed."
                }
            }
        }

        $summary.Success = ($summary.Errors.Count -eq 0)
    }
    catch {
        Write-LocalLog -Path $launchLogPath -Message "FATAL ERROR: $_"
        $summary.Errors += $_.Exception.Message
    }
    finally {
        if (-not $SkipCleanup -and (Test-Path -LiteralPath $manifest.AutomationStagingPath)) {
            Write-LocalLog -Path $launchLogPath -Message "Cleaning up staging path $($manifest.AutomationStagingPath)"
            Remove-Item -LiteralPath $manifest.AutomationStagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        $summary.CompletedAt = (Get-Date).ToString('o')
        $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifest.ResultJsonPath
    }

    return [pscustomobject]$summary
}
