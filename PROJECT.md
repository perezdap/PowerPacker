# PowerPacker Project Status

## Objective
Evolve PowerPacker into an **Agent-Native Framework** that leverages the intelligence of AI Agents (e.g., Gemini CLI) to autonomously generate, validate, and assemble full **PSADT v4** deployment packages from simple Markdown definitions.

## Pivot (Agent-Native Paradigm)
The project originally began as a heavy PowerShell orchestrator that manually queried LLM APIs (`Invoke-LLMGenerate`), managed API keys, and wrapped WinGet CLI (`Get-WingetMcpData`). 

We have removed most of this complexity. The AI Agent now serves as the execution engine, using native CLI tooling (`gh`, `winget`) plus the local AST validator (`Test-PSADTAst.ps1`) to double-check its own code and assemble a ready-to-run artifact.

## Status
- [x] Deleted legacy API orchestration (`Build-PowerPackerPackage.ps1`, `Invoke-LLMGenerate.ps1`).
- [x] Deleted legacy data collection (`Get-WingetMcpData.ps1`).
- [x] Restructured `README.md` as a Human-in-the-Loop Operator's Manual.
- [x] Restructured `AGENT_INSTRUCTIONS.md` as an AI-Native Technical Specification.
- [x] Maintained the strict PowerShell AST validator (`Test-PSADTAst.ps1`) for Agent self-correction.
- [x] Added `New-PowerPackerPackage` to assemble a PSADT v4 template, generated entry script, and downloaded installer into a single artifact.
- [x] Added Windows Sandbox workspace generation and launch helpers for disposable install/uninstall testing.
- [x] Added **Local Lab Runner** as a zero-virtualization alternative for testing.

## Architecture
- **Framework Elements:**
  - `AGENT_INSTRUCTIONS.md` (System Prompt / Rules)
  - `Definitions/` (Markdown Intent)
  - `Private/Test-PSADTAst.ps1` (Local Tool / Validation)
  - `.vscode/mcp.json.example` (Optional WinGet STDIO Integration)
  - `Public/New-PowerPackerPackage.ps1` (PSADT + installer artifact assembly)
  - `Public/New-PowerPackerSandboxTest.ps1` / `Public/Start-PowerPackerSandboxTest.ps1` (Sandbox testing)
  - `Public/New-PowerPackerLocalTest.ps1` / `Public/Start-PowerPackerLocalTest.ps1` (Local host/lab testing)

## To-Do
- [ ] Add more granular AST validation rules for complex registry detections.
- [ ] Create a library of example definitions for complex installers (e.g., Python, Docker).
- [ ] Refine `AGENT_INSTRUCTIONS.md` based on real-world Agent generation tests.
- [ ] Add artifact compression/signing options for distribution workflows.
- [ ] Expand sandbox/local assertions beyond install/uninstall exit-code validation with richer app-specific probes.
