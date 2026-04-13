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
- [x] Fixed scope-aware WinGet metadata so `artifact-metadata.json` matches the actual scoped installer downloaded into `Files\`.
- [x] Added documentation-sync expectations so agents review `README.md`, `PROJECT.md`, and `AGENT_INSTRUCTIONS.md` after package builds and framework changes.

## Recent Lessons
- WinGet scope must be applied consistently across both metadata lookup and installer download. VS Code exposed this by returning different user and machine installer URLs.
- Artifact verification needs to compare three things together: the downloaded installer in `Files\`, the saved WinGet manifest, and `artifact-metadata.json`.
- The current AST validator is stricter than typical PSADT style and expects `Close-ADTSession` after `catch`, not inside `finally`.
- Durable lessons should be written back into both human-facing docs and agent-facing instructions, not left buried in a single artifact or chat session.

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
