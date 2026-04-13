---
winget_id: Brave.Brave
name: Brave
---
## Pre-Install
Close Brave if it is currently running.

## Install
Install Brave using the silent installer.

## Post-Install
Remove the Desktop shortcut created by the installer.

## Detection
Check for Brave installation by checking the registry for the machine-wide uninstall entry.
Registry Key: `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\BraveSoftware Brave-Browser`
(or `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\BraveSoftware Brave-Browser` on 32-bit)

## Uninstall
Uninstall Brave using the machine-wide uninstall command:
`"C:\Program Files\BraveSoftware\Brave-Browser\Application\1.89.132\Installer\setup.exe" --uninstall --system-level --force-uninstall`
