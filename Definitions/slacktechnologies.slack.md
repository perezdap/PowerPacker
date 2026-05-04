---
winget_id: SlackTechnologies.Slack
name: Slack
installer_type: msix
installer_source: vendor
---

> **Note:** Slack retired both per-user and machine-wide MSI installers on September 15, 2025.
> WinGet only provides the legacy user-scope EXE (`SlackSetup.exe`), which is unsuitable for
> SYSTEM-context enterprise deployment. The correct installer for machine-wide deployment is the
> MSIX package available from Slack's IT admin download page. It must be downloaded manually and
> placed in the `Files\` directory before building.

## Pre-Install
Close Slack if it is currently running.

## Install
Install Slack machine-wide using the MSIX package from Slack's IT admin portal. Use
`Add-AppxProvisionedPackage -Online -PackagePath <msix> -SkipLicense` to provision for all users
on the machine. Do NOT use `Start-ADTProcess` — MSIX deployment is handled by the
`Add-AppxProvisionedPackage` PowerShell cmdlet directly.

## Post-Install
Remove any Desktop shortcuts created during provisioning.

## Detection
Check for an installed Slack Appx package via `Get-AppxPackage -AllUsers -Name '*Slack*'`.

## Uninstall
Remove Slack for all users via `Remove-AppxPackage -AllUsers` using the `PackageFullName` returned
by `Get-AppxPackage`. Also remove any provisioned package via `Remove-AppxProvisionedPackage` so
the app is not reinstalled for new users.
