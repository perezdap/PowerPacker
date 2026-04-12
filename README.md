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
Create a simple Markdown file in the `Definitions/` folder. This is your only manual task.

**Example: `Definitions/7zip.md`**
```markdown
---
winget_id: 7zip.7zip
name: 7-Zip
---
## Install
Install 7-zip MSI silently.
## Detection
Check for 7z.exe in Program Files.
```

### 2. Prompt the Agent
Tell the agent to pack the application. It will handle metadata lookup, script generation, AST validation, and artifact assembly.

> **Prompt:** *"Pack 7zip.7zip based on the definition."*

### 3. Verify the Artifact
Once the Agent finishes, it will create an artifact in the `Artifacts/` folder. You can now run a manual, disposable test.

**Option A: Windows Sandbox (Isolated)**
```powershell
New-PowerPackerSandboxTest -PackagePath .\Artifacts\7zip.7zip -RunUninstall -Force
Start-PowerPackerSandboxTest -WorkspaceDirectory .\Build\Sandbox\7zip.7zip -WaitForResult
```

**Option B: Local Lab (Direct Host)**
```powershell
New-PowerPackerLocalTest -PackagePath .\Artifacts\7zip.7zip -RunUninstall -Force
Start-PowerPackerLocalTest -WorkspaceDirectory .\Build\LocalLab\7zip.7zip
```

---

## 📂 Project Structure
*   `Definitions/`: Human-written application requirements.
*   `Artifacts/`: Agent-generated, ready-to-run PSADT packages.
*   `AGENT_INSTRUCTIONS.md`: The rulebook you must feed to your AI Agent.
*   `Build/`: Temporary workspaces for Sandbox and Local testing.
*   `Private/`: Internal tools (AST Validators, Parsers) used by the Agent.
