# PowerPacker Project Status

## Objective
Evolve PowerPacker into an **Agent-Native Framework** that leverages the intelligence of AI Agents (e.g., Gemini CLI) via MCP integrations to autonomously generate, validate, and repair **PSADT v4** deployment scripts from simple Markdown definitions.

## Pivot (Agent-Native Paradigm)
The project originally began as a heavy PowerShell orchestrator that manually queried LLM APIs (`Invoke-LLMGenerate`), managed API keys, and wrapped WinGet CLI (`Get-WingetMcpData`). 

We have removed all this complexity. The AI Agent now serves as the execution engine, utilizing its native tool-use capabilities to query the WinGet MCP directly and run the local AST validator (`Test-PSADTAst.ps1`) to double-check its own code.

## Status
- [x] Deleted legacy API orchestration (`Build-PowerPackerPackage.ps1`, `Invoke-LLMGenerate.ps1`).
- [x] Deleted legacy data collection (`Get-WingetMcpData.ps1`).
- [x] Drafted universal `AGENT_INSTRUCTIONS.md` containing strict PSADT v4 syntax rules and the Agent Workflow.
- [x] Rewrote `README.md` to reflect the new framework architecture.
- [x] Maintained the strict PowerShell AST validator (`Test-PSADTAst.ps1`) for Agent self-correction.

## Architecture
- **Framework Elements:**
  - `AGENT_INSTRUCTIONS.md` (System Prompt / Rules)
  - `Definitions/` (Markdown Intent)
  - `Private/Test-PSADTAst.ps1` (Local Tool / Validation)
  - `.vscode/mcp.json.example` (WinGet STDIO Integration)

## To-Do
- [ ] Add more granular AST validation rules for complex registry detections.
- [ ] Create a library of example definitions for complex installers (e.g., Python, Docker).
- [ ] Refine `AGENT_INSTRUCTIONS.md` based on real-world Agent generation tests.
