# PowerPacker – Copilot Instructions

PowerPacker is an **agent-native framework** for autonomously building [PSADT v4](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit) deployment packages from simple Markdown definitions. Humans write intent; agents generate, validate, and assemble the packages.

---

## Running Tests

Tests use [Pester](https://pester.dev/). Requires Pester v5+.

```powershell
# Full suite
Invoke-Pester -Path .\Tests\

# Single test file
Invoke-Pester -Path .\Tests\Test-PSADTAst.Tests.ps1

# Single named test
Invoke-Pester -Path .\Tests\Test-PSADTAst.Tests.ps1 -FullNameFilter "*Should require*"
```

> Tests dot-source their dependencies directly (e.g., `. "$PSScriptRoot/../Private/Test-PSADTAst.ps1"`). No module import needed.

---

## Architecture

```
Definitions/        ← Human-written Markdown intent files (YAML frontmatter + section headers)
Private/            ← Internal helpers: AST validator, WinGet wrappers, PSADT template downloader
Public/             ← Exported cmdlet: New-PowerPackerPackage
Tests/              ← Pester tests (one per Private/Public file)
Examples/DeployScripts/ ← Tracked reference deploy scripts for reuse
Artifacts/          ← Agent-generated, ready-to-run PSADT packages (git-ignored)
```

**Package build flow:**
1. Agent reads a `Definitions/*.md` file (YAML frontmatter: `winget_id`, `name`)
2. Agent generates a PSADT v4 entry script and validates it with `Private/Test-PSADTAst.ps1`
3. Agent calls `New-PowerPackerPackage` which:
   - Downloads the latest PSADT v4 template via `gh` (GitHub Releases)
   - Copies the generated script as `Invoke-AppDeployToolkit.ps1`
   - Downloads the installer via WinGet into `Files\`
   - Writes `SupportFiles\PowerPacker\artifact-metadata.json`
4. Final artifact lives in `Artifacts/<winget_id>/`

**Module loading:** `PowerPacker.psm1` dot-sources every `*.ps1` in `Public/` and `Private/` and exports all Public function names.

---

## Key Conventions

### PSADT v4 Script Structure (enforced by AST validator)

Every generated entry script must follow this top-level shape:

```powershell
param(...)  # standard PSADT v4 param block

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "PSAppDeployToolkit\PSAppDeployToolkit.psd1"
if (-not (Get-Module -Name PSAppDeployToolkit)) { Import-Module -Name $modulePath }

$adtSession = @{ ... }
Open-ADTSession @adtSession @PSBoundParameters

try {
    # all deployment logic here
} catch {
    ...
}

Close-ADTSession  # MUST be after catch, NOT inside finally
```

**Validator rules (all enforced by `Private/Test-PSADTAst.ps1`):**
- `Open-ADTSession`, `Close-ADTSession`, and `$adtSession = @{}` are required
- `Close-ADTSession` must appear after the `catch` block at the top level — placing it inside `finally` will fail validation even though `finally` is cleaner style
- `Start-ADTProcess -FilePath` must always receive a **variable**, never a hardcoded string (even for system executables like `cmd.exe`)
- `Import-Module` with a path must reference `$PSScriptRoot`
- Legacy v3 cmdlets (`Execute-Process`, `Show-InstallationWelcome`) are banned

**v3 → v4 cmdlet mapping:**

| v3 | v4 | Notes |
|----|----|-------|
| `Execute-Process` | `Start-ADTProcess` | Use `-ArgumentList`, not `-Arguments` |
| `Show-InstallationWelcome` | `Show-ADTInstallationWelcome` | Use `-CloseProcesses`, not `-CloseApps` |
| `Get-RegistryKey` | `Get-ADTRegistryKey` | |
| `Write-Log` | `Write-ADTLogEntry` | Use `-Message` |

### WinGet Scope Consistency

Always pass the **same** `-Scope` flag to both `winget show` and `winget download`. Querying metadata without scope and downloading with scope produces mismatched `InstallerUrl`/`InstallerSha256` in `artifact-metadata.json`. VS Code is a confirmed example of this mismatch.

### WinGet Installer Filenames

WinGet downloads use the format `<Publisher AppName>_<Version>_<Scope>_<Arch>_<Type>_<Locale>.ext`. Never filter by the marketing filename. Use the publisher name as a prefix wildcard:

```powershell
# Correct
$InstallerPath = Get-ChildItem -Path $dirFiles -Filter "Mozilla Firefox*.exe" | Select-Object -ExpandProperty FullName -First 1

# Wrong
$InstallerPath = Get-ChildItem -Path $dirFiles -Filter "Firefox Setup *.exe" | Select-Object -ExpandProperty FullName -First 1
```

### Omaha-Based Installers (Chrome, Brave, Edge)

User-scoped Omaha installers fail with `0x80040c01` when run elevated. Always use machine-scope standalone installers for remote deployment:

| App | Machine installer | Source |
|-----|-------------------|--------|
| Chrome | `ChromeStandaloneSetup64.exe` | enterprise.google.com |
| Brave | `BraveBrowserStandaloneSetup.exe` | GitHub Releases |
| Edge | `EdgeEnterpriseX64.msi` | Microsoft Edge for Business |

Common Omaha exit codes to handle: `0` (success), `20` (deferred success), `2147747880` (already installed), `2147747867` (already running).

### Uninstall Resiliency

Never hardcode version-specific uninstall paths. Always:
1. Check `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` (64-bit and WOW6432Node) and `HKCU` for `UninstallString`
2. If Inno Setup (`unins000.exe`), add `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
3. Fall back to wildcards for versioned directories: `C:\Program Files\Vendor\App\*\setup.exe`

### Artifact Verification (after every build)

Compare these three things together — they must all describe the same installer variant:
- Downloaded file in `Files\`
- Saved WinGet manifest in `SupportFiles\PowerPacker\winget-show.txt`
- `SupportFiles\PowerPacker\artifact-metadata.json` (URL, SHA256, Scope)

### Documentation Sync (mandatory after every build or framework change)

After completing a package build or modifying framework code, review and update if warranted:
- `README.md` — operator warnings, workflow changes, testing caveats
- `PROJECT.md` — project status, recent lessons, architecture notes
- `AGENT_INSTRUCTIONS.md` — durable lessons for future package generation
- `Examples/DeployScripts/` — commit reusable reference scripts here; do not leave them in an ignored scratch folder

### Scratch vs. Tracked Files

- `Artifacts/` is git-ignored — do not treat it as a source of truth
- `Build/` is not used — it is a legacy scratch folder
- Reusable deploy scripts go in `Examples/DeployScripts/` (version-controlled)

### Testing a Built Package

```powershell
cd .\Artifacts\<PackageName>
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Interactive
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall -DeployMode Interactive
```
