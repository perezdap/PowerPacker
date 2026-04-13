# PowerPacker: Agent-Native PSADT Framework

PowerPacker is a framework designed to let AI Agents (Gemini CLI, Claude Code, Cursor) autonomously build, validate, and test **PowerShell App Deployment Toolkit (PSADT) v4** packages.

The Human provides the **Intent**; the Agent provides the **Engine**.

---

## 🛠️ Setup (Human)

1. **Install an AI Agent**: Ensure you have a tool like [Gemini CLI](https://github.com/google/gemini-cli) installed.
2. **WinGet Integration**: Configure your Agent to use the WinGet MCP server (see `.vscode/mcp.json.example`).
3. **Environment**: Ensure `gh` (GitHub CLI) is authenticated so the Agent can download the PSADT template.

---

## 🕹️ The Human-in-the-Loop Workflow

### 1. Define the Intent
Create a simple Markdown file in the `Definitions/` folder. This is your primary manual task. You can use any of the following standard PSADT v4 sections:

- `# Pre-Install` / `# Post-Install`
- `# Install`
- `# Pre-Uninstall` / `# Post-Uninstall`
- `# Uninstall`
- `# Detection`

#### Scope Preference (Critical)
By default, the Agent will attempt to find a **machine-scope** installer suitable for remote/SYSTEM deployment. 

- **Machine Scope (`scope: machine`)**: Installs to `Program Files`. The default and recommended for enterprise deployment.
- **User Scope (`scope: user`)**: Installs to `%LOCALAPPDATA%`. Only use if specifically requested.

**Omaha Application Warning**: Google Omaha-based apps (Brave, Chrome, Edge) are highly sensitive to scope. If you request a **user-scope** install but run it as an Administrator, the installation will likely fail with error `0x80040c01`. The Agent is instructed to prefer **Standalone machine-wide installers** for these apps to ensure reliable deployment.

**Example: `Definitions/firefox.md` - Installation & Uninstall**
```markdown
---
winget_id: Mozilla.Firefox
name: Mozilla Firefox
---
## Pre-Install
Close Firefox if it is currently running.

## Install
Install Firefox using the silent installer.

## Post-Install
Remove the Desktop shortcut created by the installer.

## Uninstall
Uninstall Firefox using the system's uninstall command.

## Detection
Check for firefox.exe in the Program Files directory.
```

#### Writing the Uninstall Section
When defining the uninstall process, provide clear instructions for the Agent:

- **Silent Uninstall**: Specify if the uninstall should run silently (e.g., "Uninstall using silent arguments")
- **Custom Actions**: Note any pre-uninstall tasks (close applications, stop services) or post-uninstall cleanup
- **Registry Fallback**: If the ProductCode is unknown, mention that a registry lookup should be used to find the uninstall string

**Example: `Definitions/7zip.md` - Uninstall Focus**
```markdown
---
winget_id: 7zip.7zip
name: 7-Zip
---
## Install
Install 7-Zip using the MSI installer.

## Uninstall
Uninstall 7-Zip using the MSI ProductCode with silent arguments.
If ProductCode is unavailable, look up the uninstall string from the registry under:
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\`
- `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\`

## Detection
Verify by checking if 7z.exe exists in the installation directory or via the registry ProductCode.
```

### 2. Prompt the Agent
Tell the agent to pack the application. It will handle metadata lookup, script generation, AST validation, and artifact assembly.

> **Prompt:** *"Pack 7zip.7zip based on the definition."*

### 3. Verify the Artifact
Once the Agent finishes, it will create an artifact in the `Artifacts/` folder. You can now test it locally or in a sandbox.

#### Option A: Local Lab (Direct Host)
Navigate to the artifact folder and run the entry script with PowerShell:

```powershell
cd .\Artifacts\VSCodium.VSCodium
# Run Install
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Interactive

# Run Uninstall
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall -DeployMode Interactive
```

#### Option B: Windows Sandbox (Isolated)
If you want to test in a clean environment, you can use the `New-PowerPackerSandbox.wsb` (if provided) or simply copy the artifact folder into a Windows Sandbox instance and run the same commands as above.

> **Tip**: Since artifacts are standard PSADT v4 packages, you can use all standard PSADT parameters like `-DeployMode Silent` or `-AllowRebootPassThru`.

---

## 📂 Project Structure
*   `Definitions/`: Human-written application requirements.
*   `Artifacts/`: Agent-generated, ready-to-run PSADT packages.
*   `AGENT_INSTRUCTIONS.md`: The rulebook you must feed to your AI Agent.
*   `Private/`: Internal tools (AST Validators, Parsers) used by the Agent.
*   `Public/`: Core cmdlets like `New-PowerPackerPackage`.
