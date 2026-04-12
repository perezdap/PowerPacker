# PowerPacker Agent-Native Framework

PowerPacker has evolved into an **Agent-Native Framework** designed specifically for AI Agents (like Gemini CLI, Claude Code, GitHub Copilot, or Cursor). It provides the "rails"—strict syntax rules, package assembly helpers, and local AST validation—so that *any* capable agent can autonomously generate ready-to-run **PowerShell App Deployment Toolkit (PSADT) v4** packages from simple Markdown definitions.

There is no complex orchestrator script to run, no `.env` files to configure, and no API keys to manage. **The Agent is the engine.**

## How it Works

1. **Definitions**: You write a simple Markdown file (`Definitions/google-go.md`) explaining how an app should be installed, uninstalled, and detected.
2. **Package Metadata**: Your Agent uses `winget` to resolve installer metadata and download the installer package directly into the artifact.
3. **PSADT Bootstrap**: PowerPacker downloads the latest `PSAppDeployToolkit_Template_v4.zip` release with `gh` and expands it into an artifact folder.
4. **Agent Action**: You simply tell your Agent: *"Pack GoLang.Go"*.
5. **Validation Engine**: The Agent writes the script, runs the local `.\Private\Test-PSADTAst.ps1` validator to ensure it matches the required PSADT v4 rules, fixes its own mistakes, and then assembles a full PSADT package with the entry script and installer already in place.

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

## Building a Full Artifact

Once you have a validated `Invoke-AppDeployToolkit.ps1` script, you can assemble a full package:

```powershell
Import-Module .\PowerPacker.psd1 -Force

New-PowerPackerPackage `
  -DefinitionPath .\Definitions\golang-go.md `
  -DeployScriptPath .\Build\Invoke-AppDeployToolkit-GoLang.Go.ps1 `
  -Force
```

The resulting folder under `Artifacts\` contains:

*   The latest PSADT v4 template
*   Your generated `Invoke-AppDeployToolkit.ps1`
*   The downloaded installer and winget manifest in `Files\`
*   Build metadata in `SupportFiles\PowerPacker\`

## Sandbox Testing

You can create a disposable Windows Sandbox workspace for any built artifact:

```powershell
Import-Module .\PowerPacker.psd1 -Force

New-PowerPackerSandboxTest `
  -PackagePath .\Artifacts\GoLang.Go-sample `
  -RunUninstall `
  -DisableVGpu `
  -ShutdownWhenComplete `
  -Force
```

This creates a workspace under `Build\Sandbox\<package>\` containing:

*   `PowerPackerSandbox.wsb` for manual launch
*   `sandbox-manifest.json` describing the automated test commands
*   `Results\` for host-visible launch logs and test summaries

To launch the run and wait for the result file:

```powershell
Start-PowerPackerSandboxTest `
  -WorkspaceDirectory .\Build\Sandbox\GoLang.Go-sample `
  -WaitForResult `
  -BootstrapStepTimeoutSeconds 60
```

The automated runner is host-orchestrated. It launches the `.wsb` with `WindowsSandbox.exe`, shares the package into the sandbox, runs the install and optional uninstall directly with `wsb exec -r System`, and writes `sandbox-test-result.json` plus `sandbox-launch.log` on the host. Networking is disabled by default; use `-EnableNetworking` only if the installer truly requires internet access.

## Architecture

*   `AGENT_INSTRUCTIONS.md`: The universal "brain" and rulebook for the Agent.
*   `Definitions/`: The folder where you define your app logic in plain Markdown.
*   `Private/Test-PSADTAst.ps1`: The strict local validation engine the Agent uses to double-check its generated syntax.
*   `Public/New-PowerPackerPackage.ps1`: The artifact builder that downloads PSADT and the target installer into a ready-to-run package.
*   `Public/New-PowerPackerSandboxTest.ps1`: Creates a Windows Sandbox workspace and `.wsb` file for disposable package testing.
*   `Public/Start-PowerPackerSandboxTest.ps1`: Launches the sandbox test workspace and optionally waits for the result JSON.
*   `.vscode/mcp.json.example`: An example MCP file retained for agents that prefer MCP-based package metadata lookup.

## Contributing
Since this framework relies on Agent intelligence, contributions focus on:
1. Adding new AST validation rules (`Test-PSADTAst.ps1`) to catch edge-case hallucinations.
2. Refining `AGENT_INSTRUCTIONS.md` to improve Agent reasoning and script output.
3. Expanding package assembly support for more complex multi-installer or dependency scenarios.
