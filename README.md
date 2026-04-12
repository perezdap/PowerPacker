# PowerPacker

PowerPacker is a native PowerShell tool designed to automate the generation of **PowerShell App Deployment Toolkit (PSADT) v4** deployment packages. It leverages Large Language Models (LLMs) to transform simple Markdown definitions into robust, production-ready deployment scripts, while ensuring technical integrity through strict PowerShell AST (Abstract Syntax Tree) validation.

## Key Features

- **Markdown-Driven Packaging**: Define your application installation, uninstallation, and detection logic in simple Markdown files.
- **LLM-Powered Generation**: Supports OpenAI (GPT-4) and Anthropic (Claude 3) to generate complex PSADT v4 code.
- **Strict PSADT v4 Enforcement**: Uses a custom AST validation engine to reject legacy v3 cmdlets and ensure compliance with v4 standards (e.g., `Open-ADTSession`, `$adtSession` hashtable, required try/catch blocks).
- **Winget Integration**: Automatically retrieves metadata and uninstall fallback logic from a Winget MCP (Model Context Protocol) server.
- **Self-Healing Loop**: If the generated code fails AST validation, PowerPacker automatically attempts a one-time repair loop by feeding the errors back to the LLM.

## Architecture

PowerPacker follows a standard PowerShell module structure:

- **Public**: Contains the primary entry point `Build-PowerPackerPackage`.
- **Private**: Internal helper functions for Markdown parsing, LLM interaction, Winget data retrieval, and AST validation.
- **Tests**: Comprehensive Pester tests for all components.

## Prerequisites

- PowerShell 7.2 or higher.
- A valid API key for OpenAI or Anthropic.
- (Optional) A running Winget MCP server (defaults to `http://localhost:8080`).

## Installation

Clone the repository and import the module:

```powershell
git clone https://github.com/your-repo/PowerPacker.git
Import-Module .\PowerPacker\PowerPacker.psd1
```

## Usage

### 1. Create a Package Definition (Markdown)

Create a `.md` file (e.g., `7zip.md`) with the following structure:

```markdown
---
winget_id: 7zip.7zip
name: 7-Zip
version: 23.01
---

## Install
Install the 7-zip msi using the silent switch.

## Uninstall
Uninstall 7-zip using the product code.

## Detection
Check if 7z.exe exists in the Program Files directory.
```

### 2. Generate the PSADT Package

Run the `Build-PowerPackerPackage` cmdlet:

```powershell
Build-PowerPackerPackage -MarkdownPath ".\7zip.md" `
                         -OutDir ".\Build" `
                         -LlmProvider "OpenAI" `
                         -LlmApiKey "your-api-key-here"
```

## How It Works

1. **Parse**: `Parse-PackageMd` extracts YAML frontmatter and Markdown sections.
2. **Enrich**: `Get-WingetMcpData` fetches additional details from the Winget MCP server.
3. **Generate**: `Invoke-LLMGenerate` sends a structured prompt to the chosen LLM provider.
4. **Validate**: `Test-PSADTAst` analyzes the generated script's AST for PSADT v4 compliance.
5. **Repair**: If validation fails, the LLM is prompted again with specific error feedback.
6. **Export**: The final validated script is saved to the specified output directory.

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/cool-new-feature`).
3. Ensure all Pester tests pass (`Invoke-Pester`).
4. Commit your changes.
5. Push to the branch and create a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
