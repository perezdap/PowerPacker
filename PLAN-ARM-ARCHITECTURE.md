# Plan: ARM vs x86 Build Architecture Handling

> **Status:** Draft  
> **Scope:** Framework  
> **Target:** PowerPacker Agent-Native Framework  

## Problem

Enterprise fleets are increasingly mixed-architecture: x64 desktops and laptops coexist with ARM64 devices (Surface Pro X, Copilot+ PCs, Snapdragon-based systems, etc.).

PowerPacker currently supports a single `$Architecture` parameter, which is passed through to WinGet at build time. However, there is no strategy for:

- **Universal packages:** Building a single artifact that works across x64 and ARM64 endpoints.
- **Runtime detection:** The generated PSADT deploy scripts assume a single installer file and hardcode its path.
- **ARM64 fallback:** If a vendor offers x64 but not ARM64, ARM64 Windows can emulate x64, but the agent currently has no knowledge of this fallback chain.
- **Metadata integrity:** `artifact-metadata.json` records one installer; multi-arch packages need structured provenance for each architecture present in the artifact.

## Goals

1. Allow the **human** to declare an architecture policy in the definition (`auto`, `native`, `x64`, `x86`, `arm64`).
2. Allow the **agent** to download and package the correct installer(s) based on that policy.
3. Ensure generated deploy scripts **detect the OS architecture at runtime** and select the appropriate installer when multiple architectures are present.
4. Record exact provenance for every included architecture in `artifact-metadata.json`.
5. Update validation and testing so multi-arch packages are covered by the AST validator and Pester tests.

## Proposed Architecture Policies

| Policy | Behavior | Use Case |
|--------|----------|----------|
| **`auto`** (default) | Download all available architectures. The deploy script detects the OS architecture at runtime and selects the correct file. Falls back to x64 on ARM64 if native ARM64 is unavailable. | Universal enterprise packages deployed to mixed fleets |
| **`native`** | Download all available architectures. Prefer native ARM64 on ARM64, otherwise x64 on x64/x86. Same runtime selection as `auto`, but semantically signals "give me the best native build." | Performance-sensitive deployments on mixed fleets |
| **`x64`** | Lock to x64. Only one installer is downloaded and referenced. | x64-only managed collections |
| **`x86`** | Lock to x86. Only one installer is downloaded and referenced. | Legacy 32-bit-only applications |
| **`arm64`** | Lock to ARM64. Only one installer is downloaded and referenced. | ARM64-only managed collections |

## Framework Changes

### 1. Definition Schema (`Definitions/`, `Private/Parse-PackageMd.ps1`)

Update YAML frontmatter parsing to recognize an optional `architecture` key:

```yaml
---
winget_id: Microsoft.VisualStudioCode
name: Visual Studio Code
architecture: auto   # auto | native | x64 | x86 | arm64 (default: auto)
---
```

- If omitted, default to `auto`.
- If present, validate it against the allowed set.

### 2. Multi-Architecture Discovery (`Private/Resolve-WingetArchitectures.ps1` — New)

A new helper that queries WinGet to determine which architectures are actually available for a given package/version/scope:

```powershell
function Resolve-WingetArchitectures {
    param([string]$Id, [string]$Version, [string]$Scope)
    # Queries `winget show --architecture <arch>` for x64, arm64, x86
    # Returns an array of available architectures
}
```

This prevents downloading non-existent installers and lets the agent make informed fallback decisions.

### 3. Downloader Changes (`Private/Save-WingetPackageInstaller.ps1`)

For `auto`/`native` policies:
- Iterate over available architectures returned by `Resolve-WingetArchitectures`.
- Call `winget download --architecture <arch>` once per architecture.
- Ensure all files land in `Files/` without collision (WinGet already embeds architecture in filenames).

For `x64`/`x86`/`arm64` policies:
- Current single-download behavior is preserved, but the architecture is explicitly passed to WinGet.

### 4. Artifact Assembly (`Public/New-PowerPackerPackage.ps1`)

Update the orchestrator to:
1. Read `architecture` from the parsed definition.
2. If policy is `auto` or `native`, call `Resolve-WingetArchitectures`, then loop through results calling `Save-WingetPackageInstaller` per architecture.
3. Build an architecture-to-filename mapping for `artifact-metadata.json`.
4. Continue to support `Architecture` as an override parameter to the cmdlet itself.

### 5. Runtime Selection Template (Injected into Generated Deploy Scripts)

Generated PSADT entry scripts must include safe, reusable OS-architecture detection when multiple installers exist:

```powershell
# Runtime OS architecture detection
$script:osArch = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
} else {
    $env:PROCESSOR_ARCHITECTURE
}

$script:targetArch = switch ($script:osArch) {
    'ARM64' { 'ARM64' }
    'AMD64' { 'X64' }
    'x86'   { 'X86' }
    default { 'X64' }
}

# Installer selection with fallback
$dirFiles = Join-Path -Path $PSScriptRoot -ChildPath 'Files'
$installerPath = Get-ChildItem -Path $dirFiles -Filter "*_$($script:targetArch)_*" -File |
    Select-Object -ExpandProperty FullName -First 1

if (-not $installerPath -and $script:targetArch -eq 'ARM64') {
    Write-ADTLogEntry -Message "ARM64 installer not found. Falling back to X64 via emulation." -Severity 2
    $installerPath = Get-ChildItem -Path $dirFiles -Filter "*_X64_*" -File |
        Select-Object -ExpandProperty FullName -First 1
}
```

This logic should be included in `AGENT_INSTRUCTIONS.md` as a required pattern for `auto`/`native` builds.

### 6. Metadata Schema (`artifact-metadata.json`)

Update the installer metadata block:

```json
{
  "ArchitecturePolicy": "auto",
  "AvailableArchitectures": ["X64", "ARM64"],
  "InstallerFiles": {
    "X64": "Files/Microsoft Visual Studio Code (en-US)_1.99.3_Machine_X64_inno_en-US.exe",
    "ARM64": "Files/Microsoft Visual Studio Code (en-US)_1.99.3_Machine_ARM64_inno_en-US.exe"
  }
}
```

For locked-architecture builds, the existing flat `InstallerFiles` array can remain for backward compatibility, or we can standardize on the new mapping.

### 7. AST Validator (`Private/Test-PSADTAst.ps1`)

Add a validation rule:

> **Rule:** If the deploy script contains multiple installer files in `Files\`, the script must derive `Start-ADTProcess -FilePath` from a runtime architecture detection variable (not a hardcoded path or simple wildcard that ignores architecture).

This prevents agents from generating naive scripts that ignore architecture in fat packages.

### 8. Agent Instructions (`AGENT_INSTRUCTIONS.md`)

Add dedicated sections for:
- How to interpret `architecture: auto/native/x64/x86/arm64` in definitions.
- When to prefer native ARM64 and when x64 emulation fallback is acceptable.
- The exact PowerShell runtime detection snippet to inject in generated deploy scripts.
- Metadata requirements for multi-arch provenance.
- Omaha/G Omaha-based apps note: these are extremely scope-sensitive; adding architecture adds another dimension to verify. Ensure machine-wide ARM64 builds are used when available.

### 9. Testing

New or updated Pester tests:
- `Parse-PackageMd.Tests.p1` — Validates `architecture` key parsing and defaults.
- `New-PowerPackerPackage.Tests.ps1` — Validates multi-arch download behavior and `artifact-metadata.json` shape.
- `Test-PSADTAst.Tests.ps1` — Validates the new AST rule for runtime architecture detection.
- (Optional) `Resolve-WingetArchitectures.Tests.ps1` — Mocks WinGet output and validates architecture resolution.

## Implementation Phases

| Phase | Scope | Files to Touch | Deliverable |
|-------|-------|----------------|-------------|
| **1** | Schema & parser | `Parse-PackageMd.ps1`, `Test-*` definition fixture, `AGENT_INSTRUCTIONS.md` (draft rules) | Definitions can declare `architecture`. Tests pass. |
| **2** | Discovery & download | `Resolve-WingetArchitectures.ps1` (new), `Save-WingetPackageInstaller.ps1`, `New-PowerPackerPackage.ps1` | Agent can download multiple architectures for `auto`/`native`. |
| **3** | Runtime script template | `AGENT_INSTRUCTIONS.md` (inject pattern), `Examples/DeployScripts/` (add a multi-arch reference) | Generated scripts detect OS arch and select installer. |
| **4** | Metadata & validation | `New-PowerPackerPackage.ps1` (JSON shape), `Test-PSADTAst.ps1` (new rule), `AGENT_INSTRUCTIONS.md` (finalize) | Fat packages are validated and auditable. |
| **5** | Tests & docs | All `Tests/*.Tests.ps1`, `README.md`, `PROJECT.md` | Full test coverage, human docs updated. |

## Open Questions

1. **Should `auto` be the real default, or should the default remain undefined to preserve backward compatibility?**  
   *Recommendation:* Default to `auto`. Mixed fleets are becoming the norm, and a universal package is the least-surprise behavior for enterprise tooling. Existing definitions without the key will silently upgrade to `auto`, which is safe because the runtime selection logic is backward-compatible with single-installer packages.

2. **Should ARM64 fall back to x86 when x64 is also missing?**  
   *Recommendation:* No. The fallback chain should be `ARM64 → X64`. x86 emulation on ARM64 is a last resort and almost never needed in modern enterprise software. If neither ARM64 nor X64 is available, log a warning and fail.

3. **PSADT v4 module architecture:** Does the bundled PSADT v4 toolkit itself ship architecture-specific components?  
   *Answer:* PSADT v4 is pure PowerShell. No native binaries. The architecture concern is strictly about the **payload installer** in `Files/`. No changes needed to the PSADT template download logic.

4. **WinGet locale/arch interaction:** Does `--architecture arm64` interact with `--locale`?  
   *Answer:* In practice, no. But the agent should still pass both parameters consistently when specified in the definition.

## Acceptance Criteria

- [ ] A definition with `architecture: auto` produces an artifact containing both X64 and ARM64 installers.
- [ ] `artifact-metadata.json` lists all included architectures and their file mappings.
- [ ] The generated deploy script runs successfully on x64 Windows using the X64 installer.
- [ ] The generated deploy script runs successfully on ARM64 Windows, preferring the ARM64 installer if present, otherwise falling back to X64.
- [ ] AST validation passes for multi-arch deploy scripts.
- [ ] Pester tests cover architecture parsing, resolution, download, metadata, and AST rules.
- [ ] `README.md` and `AGENT_INSTRUCTIONS.md` explain the new architecture policy.
