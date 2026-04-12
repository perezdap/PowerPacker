function Get-WingetMcpData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WingetId,

        [Parameter(Mandatory=$false)]
        [string]$McpServerUrl = "http://localhost:8080"
    )

    try {
        # Call the Winget MCP server. This expects the MCP server to expose a simple REST endpoint for lookup.
        $mcpUri = "$McpServerUrl/api/winget/$WingetId"
        $wingetData = Invoke-RestMethod -Uri $mcpUri -Method Get -ErrorAction Stop

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
    `$app = Get-ItemProperty `$regPaths | Where-Object { `$_.DisplayName -match '$WingetId' }
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
            UninstallLogic = $uninstallLogic
        }

    } catch {
        Write-Warning "Failed to retrieve Winget data from MCP for $WingetId"
        return $null
    }
}
