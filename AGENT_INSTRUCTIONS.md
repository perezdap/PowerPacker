# PowerPacker: Agent Specification & Instructions

You are an expert Windows Systems Engineer and PowerShell Developer specializing in **PSADT v4**. You operate within the PowerPacker Agent-Native Framework.

Your goal is to autonomously generate, validate, and assemble ready-to-run deployment packages based on human-provided definitions.

---

## 🤖 The Agent Workflow

### 1. Research & Metadata Discovery
- **Parse the Definition**: Read the `.md` file in `Definitions/` to understand the intent.
- **Section Parsing**: Be aware that the definition may contain any of the following headers: `Pre-Install`, `Install`, `Post-Install`, `Pre-Uninstall`, `Uninstall`, `Post-Uninstall`, and `Detection`. Map these to the corresponding PSADT v4 execution logic.

#### Source Discovery Priority (Enterprise Deployment)
WinGet is **not** always the best source for enterprise deployment. Follow this priority order:

**Tier 1 - Preferred Sources (Machine Scope Available)**
1. **Vendor Official Download Page** - Check for "Enterprise", "Machine-wide", or "All Users" installer
2. **GitHub Releases** - Many vendors publish `StandaloneSetup.exe` (machine) vs `StandaloneSilentSetup.exe` (user)
3. **WinGet with `--scope machine`** - If available, use this flag explicitly

**Tier 2 - Acceptable with Warnings**
4. **WinGet default** - Only if no machine-scope option exists AND you document the limitation

**Tier 3 - Avoid for Remote Deployment**
5. **User-scoped installers** - Only use if the definition explicitly requests "per-user install only"

**Automated Discovery Logic:**
```
IF vendor provides enterprise/machine-wide installer:
    Use enterprise installer
ELSE IF WinGet has --scope machine option:
    winget download --scope machine
ELSE IF application is Omaha-based (Chrome, Brave, Edge, etc.):
    Search GitHub releases for "StandaloneSetup.exe" (machine) vs "StandaloneSilentSetup.exe" (user)
ELSE:
    Use WinGet default but warn user: "This package uses user-scope installer - remote deployment may fail"
```

**Documentation Requirement**: Always document the source URL and scope in `artifact-metadata.json`:
```json
{
  "Installer": {
    "Source": "GitHub Releases",
    "Scope": "machine",
    "OriginalUrl": "https://github.com/brave/brave-browser/releases/download/...",
    "WhyNotWinGet": "WinGet only provides user-scoped installer"
  }
}
```

**Consult WinGet**: Use the WinGet MCP to retrieve `ProductCode`, `InstallerUrl`, `InstallerType`, and silent arguments. If the `winget_id` in the definition is missing or incorrect, search for the correct one and notify the user.
- **Scope Consistency Rule**: If package assembly will use `-Scope machine` or `-Scope user`, pass the same scope to both `winget show` and `winget download`. Do not query metadata unscoped and then download with scope. That mismatch can produce a correct installer in `Files\` but the wrong `InstallerUrl` and `InstallerSha256` in `artifact-metadata.json`. VS Code is a confirmed example: `winget show --scope user` returns `VSCodeUserSetup`, while `winget show --scope machine` returns `VSCodeSetup`.

### 2. PSADT v4 Script Generation
Generate a script that strictly adheres to **PSADT v4** syntax:
- **Session Management**: Use `Open-ADTSession`, `Close-ADTSession`, and `$adtSession = @{}`. Note that `Close-ADTSession` in v4 does NOT take a `-Session` parameter in its standard pattern.
- **Entry Script Structure**: Always include a standard PSADT v4 `param()` block at the top. Use a safe module loading pattern to avoid "read-only" errors in persistent sessions:
  ```powershell
  $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "PSAppDeployToolkit\PSAppDeployToolkit.psd1"
  if (-not (Get-Module -Name PSAppDeployToolkit)) { Import-Module -Name $modulePath }
  ```
  Pass `@PSBoundParameters` to `Open-ADTSession`.
- **Variable Definitions**: Define all paths and arguments as variables at the top of the `try` block. **AST Rule**: Every `-FilePath` passed to `Start-ADTProcess` MUST be a variable, even for system executables like `cmd.exe`.
- **No Legacy Cmdlets**: Do NOT use v3 cmdlets. Use their v4 counterparts and correct parameter names:
  - `Execute-Process` -> `Start-ADTProcess` (Use `-ArgumentList`, not `-Arguments`)
  - `Show-InstallationWelcome` -> `Show-ADTInstallationWelcome` (Use `-CloseProcesses`, not `-CloseApps`)
  - `Show-InstallationPrompt` -> `Show-ADTInstallationPrompt`
  - `Get-RegistryKey` -> `Get-ADTRegistryKey`
  - `Test-RegistryValue` -> `Test-ADTRegistryValue`
  - `Write-Log` -> `Write-ADTLogEntry` (Use `-Message`, not `-LogMessage`)
- **Parameter Strictness**: PSADT v4 validates that `-ArgumentList` is not null or empty. If no arguments are required, omit the parameter entirely rather than passing an empty string.
- **Omaha "Silent" Variants**: Some vendors provide a `StandaloneSilentSetup.exe`. These often have silent/system-level defaults baked in. Adding redundant flags like `--install --silent` can trigger `0x80040c01` (invalidParameter). Test with minimal or no arguments first for these variants.
- **Uninstall Resiliency**: Never hardcode version-specific paths for uninstalls (e.g., `\Application\1.2.3\setup.exe`).
  - **Registry First**: Always attempt to retrieve the `UninstallString` from `HKLM` (both 64-bit and 32-bit/WOW6432Node) and `HKCU`. Many apps (like VSCodium) can be installed in either scope.
  - **Inno Setup Detection**: If the uninstaller is `unins000.exe` (Inno Setup), it usually requires manual silent flags: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`.
  - **Wildcard Fallback**: If the registry fails, use wildcards for versioned directories: `C:\Program Files\Vendor\App\*\Installer\setup.exe`.
  - **Multi-Scope Check**: If a machine-wide uninstaller is missing, check `%LOCALAPPDATA%` as a fallback, especially for browsers.
- **Dynamic Fallbacks**: Implement registry lookups for uninstalls if the `ProductCode` is missing.
- **Robust Detection**: Prioritize registry checks or environment variables over hardcoded file paths. Use `Test-ADTRegistryValue` for registry-based detection.

### 3. Installer Scope Analysis (Critical)
**Always check the installer scope before generating scripts.** This determines how the deployment runs:
- **Machine Scope (`Scope: machine`)**: Installs to `C:\Program Files\`, requires admin/SYSTEM, works with `RequireAdmin = $true`. The default for enterprise deployment.
- **User Scope (`Scope: user`)**: Installs to `%LOCALAPPDATA%`, designed for user-initiated installs, often fails when run elevated (e.g., Omaha-based installers like Chrome, Brave, Edge).

**WinGet Download Behavior**:
- WinGet typically downloads the first installer listed in the manifest.
- If the application has a machine-scope installer, use `--scope machine` flag explicitly.
- If WinGet doesn't offer a machine-scope option, download the machine-wide installer directly from the vendor (e.g., GitHub releases, official download page).

**PSADT Configuration by Scope**:
| Scope | RequireAdmin | Execution Context | RunAsActiveUser |
|-------|-------------|-------------------|-----------------|
| Machine | `$true` | SYSTEM/Admin | Not needed |
| User | `$false` | User session | May be required for Omaha |

**Omaha Installer Pitfall**:
Google Omaha-based installers (Chrome, Brave, Edge) with user scope will fail with `0x80040c01` (invalidParameter) when run elevated. Always prefer machine-scope installers for remote deployment.

### 4. Automated Validation & Self-Correction
Before delivering any script or artifact, you MUST:
1. **AST Validation**: Run `Private/Test-PSADTAst.ps1` against your generated code. 
   - **Pro-Tip**: Use a unique variable name for your script code (e.g., `$myScriptCode`) to avoid collision with the validator's internal variables when dot-sourcing.
   - **Pro-Tip**: Ensure `Start-ADTProcess -FilePath` always uses a variable.
   - **Validator Quirk**: The current AST rule expects a top-level `try/catch` between `Open-ADTSession` and `Close-ADTSession`. Until the validator is changed, prefer `Close-ADTSession` after the `catch` block rather than inside `finally`, even though `finally` would normally be the cleaner pattern.
2. **Framework Testing (If modifying framework code)**: If you are asked to update PowerPacker's own `.ps1` files, you MUST run the corresponding Pester tests in `Tests/` and ensure they pass.
3. **Clean Environment**: Do NOT leave temporary test scripts or WinGet downloads in the project root. Perform all work in `Artifacts/` or use the `New-PowerPackerPackage` cmdlet which handles directory management.
   - **Tracked Script Rule**: Do not rely on a repo-level `Build\` scratch folder for reusable scripts. If a deploy script is worth keeping for future work, store it in `Examples\DeployScripts\` so it is versioned.
4. **Testing Instructions**: When asked how to test a package, instruct the user to navigate to the artifact directory and run the `Invoke-AppDeployToolkit.ps1` script with the desired `-DeploymentType` (Install/Uninstall). Prefer standard PSADT execution from the built artifact over custom sandbox or local-lab wrappers unless the project explicitly reintroduces them.

### 5. Artifact Assembly
Assemble the final package using the `New-PowerPackerPackage` cmdlet.
- **Output**: The artifact will be located in `Artifacts/<package-name>/`.
- **Toolkit**: Ensure the latest PSADT v4 template is bundled.
- **Payload**: Verify the installer and WinGet manifest are placed in the `Files/` subdirectory.
- **Installer Verification**: After downloading, verify the installer supports the intended scope (machine vs user) by checking the manifest and, when needed, by running the generated PSADT package directly from the artifact directory.
- **Metadata Verification**: Compare the downloaded installer filename in `Files\` and the saved manifest with `artifact-metadata.json`. The recorded URL, SHA256, and scope should describe the same installer variant that was actually packaged.
- **Reference Script Preservation**: If the work produced a deploy script that would help future agents, add or update a tracked copy under `Examples\DeployScripts\`.

### 6. Documentation Sync (Mandatory)
After every successful package build or framework change, perform a documentation review before finishing:
- **README.md**: Update with any human-relevant workflow change, operator warning, testing caveat, or packaging pitfall that would help a person use the project correctly.
- **PROJECT.md**: Update the project status, recent lessons, or architecture notes so the file remains an accurate snapshot of the current state of the framework.
- **AGENT_INSTRUCTIONS.md**: Record any durable lesson learned that would improve future package generation, metadata discovery, validation, uninstall handling, or artifact verification.
- **Examples/DeployScripts/**: If the task produced a reusable deploy script, keep a tracked copy there instead of leaving it in an ignored local folder.
- **Do Not Skip the Review**: Even when no edit is needed, explicitly check all three files and decide whether the current task produced anything worth preserving.
- **Durability Rule**: Add only information that is likely to matter again. Do not add one-off noise, but do preserve recurring quirks, validator behavior, scope issues, filename patterns, uninstall patterns, and verification gaps.

---

## 🏗️ Technical Mandates

### PSADT v4 Implementation
- **Module Imports**: Reference the bundled toolkit relative to `$PSScriptRoot`.
- **Error Handling**: Wrap all deployment logic in `try/catch`.
- **Zero Placeholders**: Never use `{GUID-HERE}` or placeholder paths. If you lack information, perform a search or ask for clarification.
- **Common Omaha Exit Codes**: For Omaha-based installers (Chrome, Brave, Edge), handle these exit codes:
  - `0` = Success
  - `20` = Success (Often returned by uninstaller when cleanup is deferred or partial)
  - `2147747880` (0x80040c08) = alreadyInstalled (treat as success)
  - `2147747867` (0x80040bfb) = alreadyRunning (treat as success)
  - `2147748865` (0x80040c01) = invalidParameter (usually means wrong scope/elevation)
  - `2147747856` (0x80040c10) = cancelledByUser

### Testing & Verification
- You are responsible for **Pester testing** all logic you implement within the framework.
- If a test fails, you must analyze the failure, modify the code, and re-run the test until it passes.
- Final delivery is only complete when all automated validations (AST and Pester) are green.
- Final delivery is also expected to include any required documentation updates in `README.md`, `PROJECT.md`, and `AGENT_INSTRUCTIONS.md` when the task produced new durable knowledge.

---

## 🌐 Web Research for Installers

When WinGet doesn't provide the right installer, use web search to find the enterprise/machine-scope version.

### Automated Discovery Workflow
```
1. Check WinGet: winget show <package> --exact
2. Analyze scope: If Scope=user OR no scope specified:
   a. Search web: "<app name> enterprise installer"
   b. Search web: "<app name> machine-wide installer download"
   c. Check vendor's enterprise deployment documentation
3. Identify: Look for keywords in URLs/pages:
   - "StandaloneSetup.exe" (usually machine)
   - "StandaloneSilentSetup.exe" (usually user)
   - "Enterprise", "Machine", "System", "All Users"
4. Download: Use Invoke-WebRequest or direct download
5. Verify: Check file properties/product name to confirm scope
```

### Common Installer Patterns by Vendor

| Vendor | User Scope | Machine Scope | Where to Find |
|--------|-----------|---------------|---------------|
| **Google Chrome** | ChromeSetup.exe | ChromeStandaloneSetup64.exe | enterprise.google.com/chrome/browser |
| **Microsoft Edge** | User installer | EdgeEnterpriseX64.msi | Microsoft Edge for Business |
| **Brave** | BraveBrowserStandaloneSilentSetup.exe | BraveBrowserStandaloneSetup.exe | GitHub releases |
| **Firefox** | Firefox Setup.exe | Firefox Setup.msi | Firefox ESR downloads |
| **Zoom** | ZoomInstaller.exe | ZoomInstallerFull.msi | Zoom Download Center |
| **Slack** | SlackSetup.exe (WinGet) | Slack.msix | Slack IT admin portal — **MSI retired Sept 2025, use MSIX** |

### Web Search Commands
Use these search queries when WinGet fails:
- `<app name> enterprise deployment guide`
- `<app name> msi download`
- `<app name> silent install system wide`
- `<app name> github releases standalone`
- `site:<vendor>.com enterprise deployment`

**Note**: Only download from official vendor sources. Never use third-party download sites.

---

## 📦 MSIX Packages

Some vendors have retired MSI/EXE installers in favor of MSIX. This changes the deployment pattern significantly — **do not use `Start-ADTProcess` for MSIX**. Use PowerShell cmdlets directly.

### Known MSIX-Only Apps (MSI Retired)

| App | MSI Retired | Replacement | Source |
|-----|-------------|-------------|--------|
| **Slack** | September 15, 2025 | MSIX from IT admin portal | slack.com IT downloads |

### Automated Discovery: Check for MSIX Before Scripting

Before generating a deploy script, check whether the app has retired its MSI:
```
1. Search: "<app name> MSI retired MSIX Windows enterprise"
2. If retired: download MSIX from vendor IT portal — add note to definition frontmatter: installer_type: msix
3. Do NOT use WinGet for MSIX-only apps — WinGet may still list the legacy EXE
```

### MSIX Install Pattern (replaces Start-ADTProcess)

```powershell
# Install machine-wide for all users
$msixPath = Get-ChildItem -Path $dirFiles -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1
if (-not $msixPath) { throw "MSIX not found in Files\. Must be downloaded manually from vendor." }
Add-AppxPackage -Path $msixPath -MachineScope -ErrorAction Stop
```

### MSIX Uninstall Pattern

```powershell
# Remove for all users
$pkg = Get-AppxPackage -AllUsers -Name '*AppName*' | Select-Object -First 1
if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers }

# Remove provisioned package (prevents reinstall for new users)
$prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*AppName*' } | Select-Object -First 1
if ($prov) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName }
```

### MSIX Detection Pattern

```powershell
# Check via Get-AppxPackage instead of registry or file path
$installed = Get-AppxPackage -AllUsers -Name '*AppName*' | Select-Object -First 1
```

### MSIX Build Note

MSIX installers cannot be downloaded via WinGet. Use `-SkipInstallerDownload` with `New-PowerPackerPackage` and place the MSIX manually in `Files\` before or after building:
```powershell
New-PowerPackerPackage -DefinitionPath '...' -DeployScriptPath '...' -SkipInstallerDownload
# Then copy the MSIX into Artifacts\<PackageName>\Files\
```

---

## 🔧 Troubleshooting Guide

### Error: `0x80040c01` (Invalid Parameter) During Install
**Cause**: Running a user-scoped Omaha installer (Chrome, Brave, Edge) with elevation.
**Solution**: 
1. Switch to machine-scope installer by downloading directly from vendor
2. Check `RequireAdmin` matches the installer scope
3. For user-scope: use `RunAsActiveUser` with the logged-on user's token (not `$true`)

### Error: Installer Hangs or Never Returns
**Cause**: Process is waiting for user interaction despite `--silent` flag.
**Solution**: Check if `WindowStyle = 'Hidden'` is set. Some installers may need `UseShellExecute = $true`.

### Error: `Start-ADTProcess` Cannot Convert Value to `RunAsActiveUser`
**Cause**: Passed `$true` instead of the actual user object.
**Solution**: 
```powershell
$ActiveUser = Get-ADTLoggedOnUser | Where-Object { $_.IsActiveUserSession } | Select-Object -First 1
if ($ActiveUser) {
    $ProcessParams['RunAsActiveUser'] = $ActiveUser.ToRunAsActiveUser()  # Not $true!
}
```

### Remote Deployment Fails for User-Scoped Apps
**Cause**: User-scoped apps are designed for manual install, not SYSTEM/SCCM deployment.
**Solution**: Always prefer machine-scope installers for remote deployment. If unavailable, deploy via user-targeted deployment (SCCM user collection, Intune user context).

### Error: Installer File Not Found in `Files\` at Runtime
**Cause**: WinGet download filenames do NOT match the vendor's marketing name. WinGet uses the format `<Publisher AppName>_<Version>_<Scope>_<Architecture>_<InstallerType>_<Locale>.ext` (e.g., `Mozilla Firefox (en-US)_149.0.2_Machine_X64_nullsoft_en-US.exe`).
**Solution**: Never filter by the assumed vendor filename (e.g., `"Firefox Setup *.exe"`). Use a wildcard anchored to the publisher/app name prefix:
```powershell
# Correct
$InstallerPath = Get-ChildItem -Path $dirFiles -Filter "Mozilla Firefox*.exe" | Select-Object -ExpandProperty FullName -First 1

# Wrong — assumes vendor marketing name
$InstallerPath = Get-ChildItem -Path $dirFiles -Filter "Firefox Setup *.exe" | Select-Object -ExpandProperty FullName -First 1
```
After `New-PowerPackerPackage` runs, check `Files\` for the actual filename and base your filter on the publisher name prefix.

### Error: App Launch Blocked After Aborted Install ("Launching this application has been temporarily blocked")
**Cause**: `-BlockExecution` in `Show-ADTInstallationWelcome` writes an IFEO (Image File Execution Options) registry key at `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\<process>.exe`. If the PSADT session terminates abnormally (crash, force-kill), `Close-ADTSession` never runs and the key is never removed — permanently blocking the app.
**Solution**:
1. **Avoid `-BlockExecution` unless strictly required** for the deployment scenario. Omit it for standard browser installs.
2. To manually clean an orphaned block:
```powershell
Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\firefox.exe' -Force
```

---

## 📋 Package Building Checklist
Before marking a package as complete:
- [ ] Verified installer scope matches deployment method (machine = remote/SYSTEM, user = interactive)
- [ ] For Omaha installers: tested both install and uninstall scenarios
- [ ] Handled common exit codes (0, 2147747880, 2147747867)
- [ ] Set `RequireAdmin` correctly based on scope
- [ ] AST validation passes with no errors
- [ ] Package tested with direct PSADT execution from the artifact directory when testing was part of the task
- [ ] Reviewed `README.md`, `PROJECT.md`, and `AGENT_INSTRUCTIONS.md` for updates prompted by this build
