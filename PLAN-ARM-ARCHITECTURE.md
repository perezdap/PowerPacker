# Plan: Multi-Architecture (x64/x86/ARM64) Packaging for PowerPacker

> **Status: COMPLETE** — All acceptance criteria are implemented and verified. This document is archived for reference only; do not treat it as active work. See `README.md` and `AGENTS.md` for current operator and agent guidance.  
> **Scope:** Framework (parser, downloader, orchestrator, metadata, validator, docs/tests)  
> **Target:** Universal + locked-architecture PSADT artifacts

## Objective

Add first-class architecture policy support so PowerPacker can produce:
- **Universal artifacts** for mixed fleets (x64 + ARM64, with safe fallback behavior)
- **Locked artifacts** for controlled collections (x64/x86/arm64)
- **Auditable metadata** with per-architecture provenance and hash verification

---

## Architecture Policy Model

Definitions may declare:
- `auto` (default): include all available architectures and select at runtime
- `native`: same artifact behavior as `auto`, semantically "prefer native architecture"
- `x64`: locked x64 artifact
- `x86`: locked x86 artifact
- `arm64`: locked ARM64 artifact

### Precedence
1. `New-PowerPackerPackage -Architecture` (explicit override)  
2. Definition frontmatter `architecture:`  
3. Default = `auto`

### Normalized architecture labels
Use canonical labels in framework metadata and script logic:
- `X64`, `X86`, `ARM64`, optional `NEUTRAL`

---

## What has to be done

## 1) Definition schema + parser

**Files**
- `Private/Parse-PackageMd.ps1`
- `Tests/Parse-PackageMd.Tests.ps1`

**Required work**
- Parse optional `architecture` from YAML frontmatter.
- Validate against allowed values: `auto|native|x64|x86|arm64`.
- Normalize case to lowercase in parser output.
- Default to `auto` if omitted.
- Return explicit parser error for invalid values.

---

## 2) Architecture discovery helper (new)

**Files**
- `Private/Resolve-WingetArchitectures.ps1` (new)
- `Tests/Resolve-WingetArchitectures.Tests.ps1` (new)

**Required work**
- Add helper to discover available architectures using `winget show --architecture <arch>` probes.
- Probe at least: `x64`, `arm64`, `x86`.
- Detect and represent `NEUTRAL` installers when applicable.
- Preserve scope/version/source/locale/installer-type consistency when probing.
- Return normalized available architecture set for downstream download orchestration.

---

## 3) Metadata query and download orchestration updates

**Files**
- `Private/Get-WingetPackageMetadata.ps1`
- `Private/Save-WingetPackageInstaller.ps1`
- `Public/New-PowerPackerPackage.ps1`
- Related tests under `Tests/`

**Required work**
- For `auto/native`: resolve available architectures, then run metadata + download per architecture.
- For locked policies: keep current single-arch behavior.
- Keep scope consistency: if scope is specified, pass the same scope to both `show` and `download`.
- Capture per-arch outputs (`winget-show`, `winget-download`) in support files with architecture context.
- Add post-download hash verification:
  - Compute SHA256 for each downloaded installer.
  - Compare to corresponding winget metadata SHA.
  - Fail build on mismatch.

---

## 4) Artifact metadata schema v2

**Files**
- `Public/New-PowerPackerPackage.ps1`
- `README.md` / `AGENTS.md` docs examples

**Required work**
- Add `MetadataSchemaVersion` (e.g., `2`).
- Emit architecture policy and availability in metadata.
- Record per-architecture installer file mapping and provenance (URL/SHA/type/scope/version).
- Keep legacy flat installer list during transition (backward compatibility).

**Target shape (example)**
```json
{
  "MetadataSchemaVersion": 2,
  "ArchitecturePolicy": "auto",
  "AvailableArchitectures": ["X64", "ARM64"],
  "InstallerFilesByArchitecture": {
    "X64": "Files/App_1.0.0_Machine_X64.exe",
    "ARM64": "Files/App_1.0.0_Machine_ARM64.exe"
  },
  "InstallerMetadataByArchitecture": {
    "X64": {
      "InstallerUrl": "...",
      "InstallerSha256": "...",
      "InstallerType": "...",
      "ResolvedVersion": "...",
      "Scope": "machine"
    },
    "ARM64": {
      "InstallerUrl": "...",
      "InstallerSha256": "...",
      "InstallerType": "...",
      "ResolvedVersion": "...",
      "Scope": "machine"
    }
  }
}
```

---

## 5) Runtime installer selection pattern (generated scripts)

**Files**
- `AGENTS.md`
- `Examples/DeployScripts/` (add a multi-arch reference script)

**Required work**
- Standardize runtime OS architecture detection in generated scripts.
- Select installer from architecture-aware mapping (prefer metadata-driven selection).
- Enforce fallback behavior:
  - ARM64 endpoint: `ARM64 -> X64 -> NEUTRAL -> fail`
  - X64 endpoint: `X64 -> NEUTRAL -> fail`
  - X86 endpoint: `X86 -> NEUTRAL -> fail`
- Log fallback decisions with `Write-ADTLogEntry`.
- Keep single-installer behavior compatible.

---

## 6) AST validator updates (enforceable)

**Files**
- `Private/Test-PSADTAst.ps1`
- `Tests/Test-PSADTAst.Tests.ps1`

**Required work**
- Keep existing rule: `Start-ADTProcess -FilePath` must use a variable.
- Add enforceable AST rule for multi-arch-safe installer selection pattern (without requiring filesystem inspection).
- Ensure rule is script-structure based (detectable from AST only).

---

## 7) Tests

**Files**
- `Tests/Parse-PackageMd.Tests.ps1`
- `Tests/New-PowerPackerPackage.Tests.ps1`
- `Tests/Test-PSADTAst.Tests.ps1`
- `Tests/Resolve-WingetArchitectures.Tests.ps1` (new)
- Optional updates to metadata/downloader tests

**Required work**
- Add parser tests for architecture defaults and validation.
- Add orchestrator tests for multi-arch aggregation and metadata v2 output.
- Add tests for precedence (`cmdlet override > definition > default`).
- Add AST tests for runtime selection compliance.
- Add regression tests for current single-arch flows.

---

## 8) Documentation updates

**Files**
- `README.md`
- `PROJECT.md`
- `AGENTS.md`
- `PLAN-ARM-ARCHITECTURE.md`

**Required work**
- Document architecture policies, precedence, and fallback matrix.
- Document metadata schema v2 fields.
- Document hash verification behavior.
- Add at least one multi-arch deploy script reference under `Examples/DeployScripts/`.
- Correct test filename typo references (`*.ps1`, not `*.p1`).

---

## Acceptance criteria

- [x] Definitions support `architecture: auto|native|x64|x86|arm64`, invalid values are rejected.
- [x] Missing architecture in definition defaults to `auto`.
- [x] `New-PowerPackerPackage -Architecture` overrides definition policy.
- [x] `auto`/`native` builds include all available architectures discovered from winget.
- [x] Locked builds include only requested architecture.
- [x] Metadata includes `MetadataSchemaVersion`, `ArchitecturePolicy`, `AvailableArchitectures`, and per-architecture installer mappings/provenance.
- [x] Downloaded installer SHA256 values are verified against metadata; mismatches fail the build.
- [x] Generated deploy scripts select installer by runtime OS architecture and follow documented fallback matrix.
- [x] ARM64 endpoints prefer ARM64 installer and correctly fall back to X64 when ARM64 is unavailable.
- [x] X86 endpoints do not attempt invalid X64 fallback.
- [x] AST validator passes compliant scripts and fails non-compliant multi-arch selection patterns.
- [x] Full Pester suite passes with new and existing tests.
- [x] README/PROJECT/AGENTS are updated to reflect the implemented architecture model.

---

## Out of scope (for this plan)

- Cross-platform/non-Windows packaging changes.
- Altering PSADT template acquisition logic for architecture reasons (PSADT itself is PowerShell-based and architecture-neutral).
- Code-signing and distribution pipeline enhancements (can be follow-up work).
