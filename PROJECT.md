# PowerPacker Project Status

## Objective
Build a native PowerShell tool called "PowerPacker" that generates PSADT v4 deployment scripts from Markdown definitions, using an LLM for generation and the native PowerShell AST for strict validation.

## Status
- [x] Initialized PROJECT.md
- [ ] Initialize Module Structure
- [ ] Implement `Parse-PackageMd`
- [ ] Implement `Test-PSADTAst`
- [ ] Implement `Get-WingetMcpData`
- [ ] Implement `Invoke-LLMGenerate`
- [ ] Implement `Build-PowerPackerPackage`

## Lessons Learned
*(To be populated as development progresses)*

## Coding Practices
- Language: Pure PowerShell (no Python dependencies).
- Architecture: PowerShell Module structure (`Public`, `Private`, `Tests`).
- Validation Engine: Use `[System.Management.Automation.Language.Parser]` for AST analysis.
- Methodology: Red/Green Test-Driven Development (TDD) using Pester.
- API: LLM Integration via `Invoke-RestMethod` (Anthropic/OpenAI).

## To-Do
- [ ] Setup Pester scaffolding.
- [ ] Develop AST rules for PSADT v4 enforcement.
- [ ] Create mock Winget MCP server interaction.
- [ ] Construct comprehensive prompt engineering for PSADT v4 syntax.
