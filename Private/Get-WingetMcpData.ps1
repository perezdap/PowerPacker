function Get-WingetMcpData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WingetId,

        [Parameter(Mandatory=$false)]
        [string]$McpServerUrl = "http://localhost:8080"
    )

    $wingetData = @{
        UninstallString = $null
        ProductCode = $null
        SilentArgs = $null
        InstallerType = $null
        InstallerUrl = $null
    }

    # 1. Try real WinGet CLI first (as fallback if MCP is not available as REST)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Verbose "Attempting to retrieve data from local WinGet CLI for $WingetId"
        $showOutput = winget show $WingetId 2>&1
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $showOutput) {
                if ($line -match 'Installer Type:\s*(.*)') { $wingetData.InstallerType = $matches[1].Trim() }
                if ($line -match 'Installer Url:\s*(.*)') { $wingetData.InstallerUrl = $matches[1].Trim() }
                if ($line -match 'Product Code:\s*(.*)') { $wingetData.ProductCode = $matches[1].Trim() }
            }
        }
    }

    # 2. Try the MCP REST API if provided (supports existing mock/proxy setups)
    # Use a cross-platform TCP check to determine whether the MCP endpoint is reachable.
    $isPortOpen = $false
    $mcpServerUri = $null
    if ($McpServerUrl) {
        try {
            $mcpServerUri = [System.Uri]$McpServerUrl
        } catch {
            $mcpServerUri = $null
        }
    }

    if ($mcpServerUri) {
        # Use a fast TcpClient check with a short timeout (500ms) to avoid hanging
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $connectTask = $tcpClient.ConnectAsync($mcpServerUri.Host, $mcpServerUri.Port)
            $isPortOpen = $connectTask.Wait(500) -and $tcpClient.Connected
            if ($tcpClient.Connected) { $tcpClient.Close() }
            $tcpClient.Dispose()
        } catch {
            $isPortOpen = $false
        }
    }

    if ($McpServerUrl -and ($McpServerUrl -ne "http://localhost:8080" -or $isPortOpen)) {
        try {
            Write-Verbose "Calling WinGet MCP REST endpoint at $McpServerUrl for $WingetId"
            $mcpUri = "$McpServerUrl/api/winget/$WingetId"
            $apiData = Invoke-RestMethod -Uri $mcpUri -Method Get -ErrorAction Stop
            
            if ($apiData) {
                $wingetData.UninstallString = $apiData.UninstallString
                $wingetData.ProductCode = $apiData.ProductCode
                $wingetData.SilentArgs = $apiData.SilentArgs
            }
        } catch {
            Write-Warning "Failed to retrieve data from MCP REST API at $McpServerUrl"
        }
    }

    # Build the uninstall fallback logic based on hierarchy
    $uninstallLogic = @"
# 1. MSI ProductCode
if (`$ProductCode) {
    Remove-MSIApplications -Name `$ProductCode
}
# 2. Registry UninstallString lookup
elseif (`$UninstallString) {
    Start-ADTProcess -FilePath `$UninstallString -ArgumentList `$SilentArgs
}
# 3. Winget Manifest fallback
else {
    # Dynamically search registry
    `$regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    `$app = Get-ItemProperty `$regPaths | Where-Object { `$_.DisplayName -match ([regex]::Escape('$WingetId')) }
    if (`$app.UninstallString) {
         `$uninstPath = `$app.UninstallString
         Start-ADTProcess -FilePath `$uninstPath
    }
}
"@

    return [pscustomobject]@{
        UninstallString = $wingetData.UninstallString
        ProductCode = $wingetData.ProductCode
        SilentArgs = $wingetData.SilentArgs
        InstallerType = $wingetData.InstallerType
        InstallerUrl = $wingetData.InstallerUrl
        UninstallLogic = $uninstallLogic
    }
}
