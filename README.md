# PowerPacker Agent-Native Framework

PowerPacker has evolved into an **Agent-Native Framework** designed specifically for AI Agents (like Gemini CLI, Claude Code, GitHub Copilot, or Cursor). It provides the "rails"—strict syntax rules, WinGet MCP configurations, and local AST validation—so that *any* capable agent can autonomously generate flawless, production-ready **PowerShell App Deployment Toolkit (PSADT) v4** packages from simple Markdown definitions.

There is no complex orchestrator script to run, no `.env` files to configure, and no API keys to manage. **The Agent is the engine.**

## How it Works

1. **Definitions**: You write a simple Markdown file (`Definitions/google-go.md`) explaining how an app should be installed, uninstalled, and detected.
2. **MCP Integration**: Your Agent uses the local WinGet MCP server (configured via `.vscode/mcp.json.example`) to natively query live metadata (ProductCodes, SilentArgs, InstallerUrls).
3. **Agent Action**: You simply tell your Agent: *"Pack Google.Go"*.
4. **Validation Engine**: The Agent writes the script, runs the local `.\Private\Test-PSADTAst.ps1` validator to ensure it perfectly matches PSADT v4 syntax rules, fixes its own mistakes, and delivers the final `Deploy-Application.ps1` file.

## Getting Started (For Humans)

1. Ensure you have a capable AI Agent installed (e.g., Gemini CLI) and that it supports MCP.
2. Configure your Agent to use the WinGet MCP server using the provided `.vscode/mcp.json.example`.
3. Feed the `AGENT_INSTRUCTIONS.md` to your Agent (e.g., set it as your `.cursorrules` or load it into your prompt context).
4. Create a definition in the `Definitions/` folder.

**Example Definition (`Definitions/7zip.md`):**
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

5. Tell your Agent: *"Pack 7zip.7zip based on the definitions."*

## Architecture

*   `AGENT_INSTRUCTIONS.md`: The universal "brain" and rulebook for the Agent.
*   `Definitions/`: The folder where you define your app logic in plain Markdown.
*   `Private/Test-PSADTAst.ps1`: The strict local validation engine the Agent uses to double-check its generated syntax.
*   `.vscode/mcp.json.example`: The configuration required to give your Agent native WinGet search capabilities via STDIO.

## Contributing
Since this framework relies on Agent intelligence, contributions focus on:
1. Adding new AST validation rules (`Test-PSADTAst.ps1`) to catch edge-case hallucinations.
2. Refining `AGENT_INSTRUCTIONS.md` to improve Agent reasoning and script output.
