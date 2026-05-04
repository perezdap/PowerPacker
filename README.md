# PowerPacker: Agent-Native PSADT Framework

PowerPacker is a framework designed to let AI Agents (Gemini CLI, Claude Code, Cursor) autonomously build, validate, and test **PowerShell App Deployment Toolkit (PSADT) v4** packages.

The Human provides the **Intent**; the Agent provides the **Engine**.

---

## 🛠️ Setup (Human)

1. **Install an AI Agent**: Ensure you have a tool like [Gemini CLI](https://github.com/google/gemini-cli) installed.
2. **WinGet Integration**: Configure your Agent to use the WinGet MCP server (see `.vscode/mcp.json.example`).
3. **Environment**: Ensure `gh` (GitHub CLI) is authenticated so the Agent can download the PSADT template.
4. **Module (local packing)**: From the repository root, `Import-Module .\PowerPacker.psd1` to use `New-PowerPackerPackage` in PowerShell.

---

## 🕹️ The Human-in-the-Loop Workflow

### 1. Define the Intent
Create a simple Markdown file in the `Definitions/` folder. This is your primary manual task. You can use any of the following standard PSADT v4 sections:

- `# Pre-Install` / `# Post-Install`
- `# Install`
- `# Pre-Uninstall` / `# Post-Uninstall`
- `# Uninstall`
- `# Detection`

YAML frontmatter must include at least `winget_id` (and typically `name`). Optional keys such as `version` are parsed and echoed under `Package` in `artifact-metadata.json`; **pinning a WinGet version for downloads uses** `New-PowerPackerPackage -WingetVersion`, not frontmatter `version` automatically.

#### Architecture policy (WinGet)
Definitions may set `architecture` in YAML frontmatter (`auto`, `native`, `x64`, `x86`, or `arm64`). Omitted values default to `auto`, which probes WinGet for `x64`, `arm64`, `x86`, and `neutral`, downloads each distinct installer URL it finds, and records per-architecture provenance in `artifact-metadata.json` (`MetadataSchemaVersion` 2): **`InstallerFilesByArchitecture`** (paths under the artifact) and **`InstallerMetadataByArchitecture`** (per-architecture installer URL, SHA256, type, resolved version, and requested scope when supplied). `native` uses the same discovery rules as `auto` but records a different `ArchitecturePolicy` label when you want metadata to express a native-first posture. Locked values download exactly one architecture.

For more detail on endpoint behavior and deploy-script patterns, see [PLAN-ARM-ARCHITECTURE.md](PLAN-ARM-ARCHITECTURE.md).

**Runtime fallback matrix (deploy scripts)**  
ARM64 endpoints: `ARM64 → X64 → NEUTRAL → fail`.  
X64 endpoints: `X64 → NEUTRAL → fail`.  
X86 endpoints: `X86 → NEUTRAL → fail` (do not fall back to X64).

`New-PowerPackerPackage -Architecture` overrides the definition when you need a one-off build (for example, forcing `x64` on a definition that normally uses `auto`).

#### Scope preference (Critical)
For **`New-PowerPackerPackage`**, WinGet metadata and download scope are controlled by the **`-Scope`** parameter (`machine` or `user`). If you omit `-Scope`, WinGet is invoked without an explicit scope flag.

You may still document intent in definition YAML (for example `scope: machine`), but **that YAML is not read by the cmdlet today**; use `-Scope` for consistent `winget show` / `winget download` behavior and matching rows in `artifact-metadata.json`.

- **Machine scope (`-Scope machine`)**: Aligns with installers that land under `Program Files` when the manifest supports it. Recommended default for enterprise deployment when the package supports it.
- **User scope (`-Scope user`)**: Aligns with per-user installers under `%LOCALAPPDATA%`. Use when the definition explicitly calls for per-user deployment.

**Omaha Application Warning**: Google Omaha-based apps (Brave, Chrome, Edge) are highly sensitive to scope. If you request a **user-scope** install but run it as an Administrator, the installation will likely fail with error `0x80040c01`. The Agent is instructed to prefer **Standalone machine-wide installers** for these apps to ensure reliable deployment.

**Example: [Definitions/mozilla.firefox.md](Definitions/mozilla.firefox.md)**
```markdown
---
winget_id: Mozilla.Firefox
name: Mozilla Firefox
version: 124.0.2
---

## Install
Install Firefox using the silent installer.

## Uninstall
Uninstall Firefox using the helper.exe in the installation directory or the product code.

## Detection
Check for the existence of `C:\Program Files\Mozilla Firefox\firefox.exe`.
```

#### Writing the Uninstall Section
When defining the uninstall process, provide clear instructions for the Agent:

- **Silent Uninstall**: Specify if the uninstall should run silently (e.g., "Uninstall using silent arguments")
- **Custom Actions**: Note any pre-uninstall tasks (close applications, stop services) or post-uninstall cleanup
- **Registry Fallback**: If the ProductCode is unknown, mention that a registry lookup should be used to find the uninstall string

**Example: [Definitions/microsoft.visualstudiocode.md](Definitions/microsoft.visualstudiocode.md)** (uninstall and registry-oriented guidance)
```markdown
---
winget_id: Microsoft.VisualStudioCode
name: Microsoft Visual Studio Code
---

## Detection
Check for the machine-wide uninstall entry for `Microsoft Visual Studio Code` in the registry.

## Uninstall
Uninstall Visual Studio Code using the uninstall command from the registry with silent arguments. Prefer the machine-wide uninstall entry and fall back to the uninstaller in the application directory if the registry entry is unavailable.
```

### 2. Prompt the Agent
Tell the agent to pack the application. It will handle metadata lookup, script generation, AST validation, and artifact assembly.

> **Prompt:** *"Pack 7zip.7zip based on the definition."*  
> **Prompt:** *"Pack VSCodium from `Definitions/vscodium.vscodium.md` using the deploy script under `Examples/DeployScripts/`."*

### 3. Pack from PowerShell (no agent)
You can assemble an artifact without an agent by calling **`New-PowerPackerPackage`** with a definition Markdown file and a PSADT entry script (often copied or adapted from [Examples/DeployScripts/](Examples/DeployScripts/)).

```powershell
Import-Module .\PowerPacker.psd1 -Force

New-PowerPackerPackage `
  -DefinitionPath .\Definitions\vscodium.vscodium.md `
  -DeployScriptPath .\Examples\DeployScripts\multi-arch.installer.example.ps1 `
  -Scope machine `
  -Force
```

Useful parameters (see [Public/New-PowerPackerPackage.ps1](Public/New-PowerPackerPackage.ps1)):

| Parameter | Purpose |
|-----------|---------|
| `-DefinitionPath` / `-DeployScriptPath` | Required inputs. |
| `-OutputDirectory` | Where to create the artifact folder (default: `Artifacts` under the module). |
| `-PackageDirectoryName` | Override the default folder name derived from `winget_id`. |
| `-EntryScriptName` | PSADT entry script name in the artifact (default: `Invoke-AppDeployToolkit.ps1`). |
| `-PsadtTemplateZipPath` | Use a local PSADT v4 template zip instead of downloading via `gh`. |
| `-WingetVersion` / `-WingetSource` | Pin WinGet version or source. |
| `-Architecture` | Override definition frontmatter (`auto`, `native`, `x64`, `x86`, `arm64`). |
| `-InstallerType` / `-Locale` | Passed through to WinGet resolution and download. |
| `-Scope` | `machine` or `user` for WinGet show/download consistency. |
| `-SkipInstallerDownload` | Expand template and write metadata without downloading installers (offline or layout checks). |
| `-Force` | Overwrite an existing artifact directory for the same package name. |

The default artifact directory name is the **`winget_id` with characters that are invalid in folder names replaced by `-`** (for example `VSCodium.VSCodium` → `Artifacts\VSCodium.VSCodium`).

### 4. Verify the Artifact
Once packing finishes, the artifact lives under `Artifacts/<PackageFolder>/`. Test the package by running the standard PSADT entry script from that directory:

```powershell
cd .\Artifacts\VSCodium.VSCodium
# Run Install
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Interactive

# Run Uninstall
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall -DeployMode Interactive
```

**`artifact-metadata.json` (schema v2)** under `SupportFiles\PowerPacker\` includes, among others: `MetadataSchemaVersion`, `ArchitecturePolicy`, `AvailableArchitectures`, `InstallerFilesByArchitecture`, `InstallerMetadataByArchitecture`, a summary **`Installer`** block (legacy “primary” installer view), `Package` (parsed definition frontmatter and sections), and PSADT template provenance.

> **Tip**: Since artifacts are standard PSADT v4 packages, you can use all standard PSADT parameters like `-DeployMode Silent`, `-DeployMode Interactive`, or `-AllowRebootPassThru`.

---

## ⚠️ Recent Pitfalls

- **Keep WinGet scope consistent**: If the package is intended for machine deployment, use the same scope for both metadata lookup and installer download (for the cmdlet, **`-Scope machine`**; for manual debugging, the same flag on `winget show` and `winget download`). Querying `winget show` without `--scope machine` and then downloading with `--scope machine` can produce mismatched metadata in `artifact-metadata.json`.
- **Multi-architecture builds verify SHA256**: When installers are downloaded, PowerPacker hashes each payload and fails the build if it does not match the WinGet metadata SHA256 for that architecture.
- **Per-architecture WinGet logs**: Multi-architecture builds save `winget-show-<arch>.txt` and `winget-download-<arch>.txt` under `SupportFiles\PowerPacker\` instead of a single pair of files.
- **Verify artifact metadata against the downloaded installer**: After packaging, compare the installer filename in `Files/`, the saved WinGet manifest, and `SupportFiles\PowerPacker\artifact-metadata.json`. The URL, SHA256, and scope should all describe the same installer variant.
- **AST validation (`Test-PSADTAst`)**: The validator expects `Open-ADTSession`, then a **top-level** `try`/`catch` wrapping main logic before the statement that contains `Close-ADTSession`. Scripts that only call `Close-ADTSession` inside `finally` can fail that layout rule. Scripts that read **`InstallerFilesByArchitecture`** must use `[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture`, a `switch` mapping, and **`Write-ADTLogEntry`** for selection and fallbacks.
- **Do not treat `Build/` as a source-of-truth folder**: Reusable deploy scripts should live in a tracked folder, not an ignored scratch directory. This repo uses `Examples\DeployScripts\` for committed reference scripts (see [Examples/DeployScripts/README.md](Examples/DeployScripts/README.md)). Canonical multi-arch selection: `multi-arch.installer.example.ps1`; app-specific examples include `microsoft.visualstudiocode.ps1` and `slacktechnologies.slack.ps1`.

---

## 📂 Project Structure
*   `Definitions/`: Human-written application requirements.
*   `Artifacts/`: Generated, ready-to-run PSADT packages (default output of `New-PowerPackerPackage`).
*   `Examples/DeployScripts/`: Tracked reference deploy scripts worth reusing or adapting ([README](Examples/DeployScripts/README.md)).
*   `Tests/`: Pester tests; run `Invoke-Pester .\Tests\` from the repository root after installing the [Pester](https://github.com/pester/Pester) module.
*   `AGENTS.md`: The rulebook you must feed to your AI Agent.
*   `Private/`: Internal tools (AST validators, parsers, WinGet helpers) used by the module and Agent.
*   `Public/`: Core cmdlets like `New-PowerPackerPackage`.
