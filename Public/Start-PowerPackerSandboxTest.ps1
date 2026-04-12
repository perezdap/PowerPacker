function Start-PowerPackerSandboxTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest')]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Workspace')]
        [string]$WorkspaceDirectory,

        [int]$TimeoutSeconds = 1800,

        [int]$BootstrapStepTimeoutSeconds = 90,

        [int]$CommandStepTimeoutSeconds = 1800,

        [switch]$WaitForResult,

        [switch]$StopOnTimeout
    )

    function Write-LaunchLog {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string]$Message
        )

        $line = '{0} {1}' -f (Get-Date).ToString('o'), $Message
        Add-Content -LiteralPath $Path -Value $line
    }

    function Invoke-WsbCommandWithTimeout {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Executable,

            [Parameter(Mandatory = $true)]
            [string[]]$Arguments,

            [Parameter(Mandatory = $true)]
            [int]$StepTimeoutSeconds,

            [Parameter(Mandatory = $true)]
            [string]$StepName,

            [Parameter(Mandatory = $true)]
            [string]$LogPath
        )

        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $argumentLine = [string]::Join(' ', @($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + ($_ -replace '"', '\"') + '"'
                } else {
                    $_
                }
            }))

            Write-LaunchLog -Path $LogPath -Message "BEGIN $StepName :: $Executable $argumentLine"
            $process = Start-Process -FilePath $Executable -ArgumentList $argumentLine -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden

            if (-not $process.WaitForExit($StepTimeoutSeconds * 1000)) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }

                $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
                $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
                Write-LaunchLog -Path $LogPath -Message "TIMEOUT $StepName :: stdout=$stdout :: stderr=$stderr"
                throw "Timed out after $StepTimeoutSeconds seconds during step '$StepName'."
            }

            $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
            $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
            Write-LaunchLog -Path $LogPath -Message "END $StepName :: exit=$($process.ExitCode) :: stdout=$stdout :: stderr=$stderr"

            if ($process.ExitCode -ne 0) {
                throw "Step '$StepName' failed with exit code $($process.ExitCode)."
            }

            [pscustomobject]@{
                ExitCode = $process.ExitCode
                StdOut   = $stdout
                StdErr   = $stderr
            }
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-WsbSandboxIds {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Executable,

            [Parameter(Mandatory = $true)]
            [int]$StepTimeoutSeconds,

            [Parameter(Mandatory = $true)]
            [string]$LogPath,

            [Parameter(Mandatory = $true)]
            [string]$StepName
        )

        $response = Invoke-WsbCommandWithTimeout -Executable $Executable -Arguments @('list', '--raw') -StepTimeoutSeconds $StepTimeoutSeconds -StepName $StepName -LogPath $LogPath
        if (-not $response.StdOut) {
            return @()
        }

        $parsed = $response.StdOut | ConvertFrom-Json
        @($parsed.WindowsSandboxEnvironments | ForEach-Object { $_.Id })
    }

    function Get-CommandExitCodeFromWsbOutput {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$StdOut,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$StdErr
        )

        foreach ($text in @($StdOut, $StdErr)) {
            if ($text -match 'Process exited with code:\s*(-?\d+)') {
                return [int]$matches[1]
            }
        }

        return $null
    }

    function Invoke-SandboxStep {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Executable,

            [Parameter(Mandatory = $true)]
            [string]$SandboxId,

            [Parameter(Mandatory = $true)]
            [string]$Command,

            [Parameter(Mandatory = $true)]
            [string]$StepName,

            [Parameter(Mandatory = $true)]
            [int]$StepTimeoutSeconds,

            [Parameter(Mandatory = $true)]
            [string]$LogPath,

            [int[]]$SuccessExitCodes = @(0)
        )

        $response = Invoke-WsbCommandWithTimeout -Executable $Executable -Arguments @('exec', '--id', $SandboxId, '-r', 'System', '-c', $Command) -StepTimeoutSeconds $StepTimeoutSeconds -StepName $StepName -LogPath $LogPath
        $commandExitCode = Get-CommandExitCodeFromWsbOutput -StdOut ([string]$response.StdOut) -StdErr ([string]$response.StdErr)
        $succeeded = ($null -ne $commandExitCode) -and ($SuccessExitCodes -contains $commandExitCode)

        [pscustomobject]@{
            StepName        = $StepName
            Command         = $Command
            CliExitCode     = $response.ExitCode
            CommandExitCode = $commandExitCode
            Succeeded       = $succeeded
            StdOut          = $response.StdOut
            StdErr          = $response.StdErr
        }
    }

    $resolvedManifestPath = if ($PSCmdlet.ParameterSetName -eq 'Workspace') {
        Join-Path ([System.IO.Path]::GetFullPath($WorkspaceDirectory)) 'sandbox-manifest.json'
    } else {
        [System.IO.Path]::GetFullPath($ManifestPath)
    }

    if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
        throw "Sandbox manifest '$resolvedManifestPath' was not found."
    }

    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
    $launchLogPath = if ($manifest.LaunchLogPath) { $manifest.LaunchLogPath } else { Join-Path $manifest.ResultsDirectory 'sandbox-launch.log' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launchLogPath) | Out-Null
    Set-Content -LiteralPath $launchLogPath -Value ''
    Write-LaunchLog -Path $launchLogPath -Message "Loaded manifest $resolvedManifestPath"

    foreach ($path in @($manifest.ResultJsonPath)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    $wsbCli = Get-Command wsb -ErrorAction SilentlyContinue
    $windowsSandbox = Get-Command WindowsSandbox.exe -ErrorAction SilentlyContinue
    if (-not $windowsSandbox) {
        throw "Windows Sandbox is not available on this host."
    }

    if ($WaitForResult -and -not $wsbCli) {
        throw "WaitForResult requires the Windows Sandbox CLI (`wsb`) so commands can be executed inside the sandbox."
    }

    $sandboxProcess = $null
    $sandboxId = $null

    if ($wsbCli) {
        $existingSandboxIds = Get-WsbSandboxIds -Executable $wsbCli.Source -StepTimeoutSeconds $BootstrapStepTimeoutSeconds -LogPath $launchLogPath -StepName 'wsb-list-before-launch'
        Write-LaunchLog -Path $launchLogPath -Message "Existing sandbox ids before launch: $($existingSandboxIds -join ', ')"
    }

    $sandboxProcess = Start-Process -FilePath $windowsSandbox.Source -ArgumentList @($manifest.WsbPath) -PassThru
    Write-LaunchLog -Path $launchLogPath -Message "Launched WindowsSandbox.exe pid=$($sandboxProcess.Id) using $($manifest.WsbPath)"

    if ($wsbCli) {
        $bootstrapDeadline = (Get-Date).AddSeconds($BootstrapStepTimeoutSeconds)
        do {
            Start-Sleep -Seconds 5
            $currentSandboxIds = Get-WsbSandboxIds -Executable $wsbCli.Source -StepTimeoutSeconds $BootstrapStepTimeoutSeconds -LogPath $launchLogPath -StepName 'wsb-list-after-launch'
            $newSandboxIds = @($currentSandboxIds | Where-Object { $_ -notin $existingSandboxIds })
            if ($newSandboxIds.Count -gt 0) {
                $sandboxId = $newSandboxIds[0]
                break
            }
        } while ((Get-Date) -lt $bootstrapDeadline)

        if (-not $sandboxId) {
            throw "Timed out waiting for a new Windows Sandbox instance to appear after launching '$($manifest.WsbPath)'."
        }

        Write-LaunchLog -Path $launchLogPath -Message "Discovered sandbox id $sandboxId"

        Invoke-WsbCommandWithTimeout -Executable $wsbCli.Source -Arguments @('share', '--id', $sandboxId, '--host-path', $manifest.HostPackagePath, '--sandbox-path', $manifest.AutomationSandboxPackagePath) -StepTimeoutSeconds $BootstrapStepTimeoutSeconds -StepName "wsb-share::$($manifest.AutomationSandboxPackagePath)" -LogPath $launchLogPath | Out-Null
    }

    $launchResult = [ordered]@{
        SandboxId        = $sandboxId
        ManifestPath     = $resolvedManifestPath
        WsbPath          = $manifest.WsbPath
        ResultsDirectory = $manifest.ResultsDirectory
        LaunchLogPath    = $launchLogPath
        ResultJsonPath   = $manifest.ResultJsonPath
        LaunchedAt       = (Get-Date).ToString('o')
        WaitedForResult  = [bool]$WaitForResult
        ProcessId        = if ($sandboxProcess) { $sandboxProcess.Id } else { $null }
    }

    if (-not $WaitForResult) {
        return [pscustomobject]$launchResult
    }

    $summary = [ordered]@{
        SandboxId          = $sandboxId
        ManifestPath       = $resolvedManifestPath
        WsbPath            = $manifest.WsbPath
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
        $summary.Install = Invoke-SandboxStep -Executable $wsbCli.Source -SandboxId $sandboxId -Command $manifest.InstallCommand -StepName 'install' -StepTimeoutSeconds $CommandStepTimeoutSeconds -LogPath $launchLogPath -SuccessExitCodes $manifest.SuccessExitCodes
        if (-not $summary.Install.Succeeded) {
            $summary.Errors = @($summary.Errors) + 'Install command did not return an allowed exit code.'
        }

        if ($manifest.InstallProbeCommand) {
            $summary.InstallProbe = Invoke-SandboxStep -Executable $wsbCli.Source -SandboxId $sandboxId -Command $manifest.InstallProbeCommand -StepName 'install-probe' -StepTimeoutSeconds ([Math]::Min($CommandStepTimeoutSeconds, 120)) -LogPath $launchLogPath -SuccessExitCodes @(0)
            if (-not $summary.InstallProbe.Succeeded) {
                $summary.Errors = @($summary.Errors) + 'Install probe failed.'
            }
        }

        if ($manifest.RunUninstall) {
            $summary.Uninstall = Invoke-SandboxStep -Executable $wsbCli.Source -SandboxId $sandboxId -Command $manifest.UninstallCommand -StepName 'uninstall' -StepTimeoutSeconds $CommandStepTimeoutSeconds -LogPath $launchLogPath -SuccessExitCodes $manifest.SuccessExitCodes
            if (-not $summary.Uninstall.Succeeded) {
                $summary.Errors = @($summary.Errors) + 'Uninstall command did not return an allowed exit code.'
            }

            if ($manifest.UninstallProbeCommand) {
                $summary.UninstallProbe = Invoke-SandboxStep -Executable $wsbCli.Source -SandboxId $sandboxId -Command $manifest.UninstallProbeCommand -StepName 'uninstall-probe' -StepTimeoutSeconds ([Math]::Min($CommandStepTimeoutSeconds, 120)) -LogPath $launchLogPath -SuccessExitCodes @(0)
                if (-not $summary.UninstallProbe.Succeeded) {
                    $summary.Errors = @($summary.Errors) + 'Uninstall probe failed.'
                }
            }
        }

        $summary.Success = (@($summary.Errors).Count -eq 0)
    }
    catch {
        $summary.Errors = @($summary.Errors) + $_.Exception.Message
    }
    finally {
        $summary.CompletedAt = (Get-Date).ToString('o')
        $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifest.ResultJsonPath

        if ($manifest.ShutdownWhenComplete -and $wsbCli -and $sandboxId) {
            Write-LaunchLog -Path $launchLogPath -Message "Stopping sandbox after test completion"
            & $wsbCli.Source stop --id $sandboxId | Out-Null
        }
    }

    return [pscustomobject]@{
        SandboxId        = $sandboxId
        ManifestPath     = $resolvedManifestPath
        WsbPath          = $manifest.WsbPath
        ResultsDirectory = $manifest.ResultsDirectory
        LaunchLogPath    = $launchLogPath
        ResultJsonPath   = $manifest.ResultJsonPath
        Result           = ([pscustomobject]$summary)
    }
}
