# PowerPacker Automated Setup Script
# This script configures the local development environment, including:
# 1. Generating .vscode/mcp.json from the WinGet MCP server
# 2. Creating a .env file from .env.example

Write-Host "--- PowerPacker Setup ---" -ForegroundColor Cyan

# 1. Configure WinGet MCP
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "[*] Configuring .vscode/mcp.json..." -NoNewline
    $mcpOutput = winget mcp 2>$null | Out-String
    
    # Extract the JSON fragment from the winget mcp output
    # The output typically says "use the following JSON fragment...: { ... }"
    if ($mcpOutput -match '\{[\s\S]*\}') {
        $jsonContent = $matches[0]
        $fullMcpJson = @{
            servers = @{
                "winget-mcp" = ($jsonContent | ConvertFrom-Json)
            }
            inputs = @()
        } | ConvertTo-Json -Depth 5
        
        $dotVscode = Join-Path $PSScriptRoot ".vscode"
        if (-not (Test-Path $dotVscode)) { New-Item -ItemType Directory -Path $dotVscode | Out-Null }
        
        $mcpPath = Join-Path $dotVscode "mcp.json"
        $fullMcpJson | Out-File -FilePath $mcpPath -Encoding utf8
        Write-Host " Done." -ForegroundColor Green
    } else {
        Write-Host " Failed." -ForegroundColor Yellow
        Write-Warning "Could not parse JSON fragment from 'winget mcp'. Please configure .vscode/mcp.json manually."
    }
} else {
    Write-Warning "WinGet not found. WinGet MCP integration will be unavailable."
}

# 2. Configure .env
$envFile = Join-Path $PSScriptRoot ".env"
$envExample = Join-Path $PSScriptRoot ".env.example"

if (-not (Test-Path $envFile)) {
    Write-Host "[*] Creating .env from .env.example..." -NoNewline
    if (Test-Path $envExample) {
        Copy-Item -Path $envExample -Destination $envFile
        Write-Host " Done." -ForegroundColor Green
        Write-Host " [!] Remember to update .env with your LLM API keys." -ForegroundColor Cyan
    } else {
        Write-Host " Failed." -ForegroundColor Red
        Write-Warning ".env.example not found."
    }
} else {
    Write-Host "[*] .env already exists. Skipping." -ForegroundColor Gray
}

Write-Host "`nSetup complete! You can now import the module or start building packages." -ForegroundColor Green
Write-Host "To use the module: Import-Module .\PowerPacker\PowerPacker.psd1" -ForegroundColor Gray
