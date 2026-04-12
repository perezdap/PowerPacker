# Local Lab Runner Plan

## Objective
Implement a "Local Lab" testing runner for PowerPacker that runs PSADT packages directly on the host machine. This provides the easiest alternative for users who cannot run Windows Sandbox due to OS restrictions or hardware issues, prioritizing zero-configuration execution at the cost of environment isolation.

## Key Files & Context
- `Public/New-PowerPackerLocalTest.ps1` (New)
- `Public/Start-PowerPackerLocalTest.ps1` (New)
- `PowerPacker.psd1` (Update exports)
- `README.md` (Update docs)

## Implementation Steps

1. **Create `New-PowerPackerLocalTest`**:
   - Accepts a `-PackagePath` (an assembled artifact).
   - Creates a workspace folder (default: `Build\LocalLab\<pkg>`).
   - Generates default install/uninstall registry probe commands (similar to the Sandbox version).
   - Writes a `local-manifest.json` containing paths to the package, staging locations, execution commands, and expected exit codes.
   - *No `wsb` generation or virtualization constraints are applied.*

2. **Create `Start-PowerPackerLocalTest`**:
   - Accepts the manifest path or workspace directory.
   - Copies the package from its original location to an execution staging folder (e.g., `C:\PowerPacker\LocalLab\<pkg>`) to simulate a deployment payload.
   - Executes the install command (e.g., `powershell -ExecutionPolicy Bypass -File Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent`) using standard `Start-Process` with timeouts.
   - Executes the install probe, uninstall command, and uninstall probe.
   - Captures standard output, error, and exit codes into a `local-launch.log` and `local-test-result.json`.
   - Cleans up the staging directory upon completion.

3. **Update Module & Documentation**:
   - Add the new cmdlets to the `FunctionsToExport` array in `PowerPacker.psd1`.
   - Update `README.md` with a new section demonstrating how to use the Local Lab Runner alongside the Sandbox Runner.

## Verification & Testing
- Create a simple mock PSADT package (or use a real one if available).
- Execute `New-PowerPackerLocalTest` and verify the manifest is correct.
- Execute `Start-PowerPackerLocalTest` and verify that the package runs on the host, the JSON report is generated, and the staging folder is cleaned up.