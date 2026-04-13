---
winget_id: Microsoft.VisualStudioCode
name: Microsoft Visual Studio Code
---

## Pre-Install
Close Visual Studio Code if it is currently running.

## Install
Install Visual Studio Code silently. Prefer a machine-scope install so the application is deployed to `C:\Program Files\Microsoft VS Code` for enterprise use.

## Post-Install
Remove any Desktop shortcut created by the installer. Ensure the `code` command is available from the install directory if PATH integration is enabled by the installer.

## Detection
Check for the machine-wide uninstall entry for `Microsoft Visual Studio Code` in the registry. As a fallback, verify that `C:\Program Files\Microsoft VS Code\Code.exe` exists.

## Uninstall
Uninstall Visual Studio Code using the uninstall command from the registry with silent arguments. Prefer the machine-wide uninstall entry and fall back to the uninstaller in the application directory if the registry entry is unavailable.
