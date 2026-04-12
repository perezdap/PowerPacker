Describe "Parse-PackageMd" {
    BeforeAll {
        . "$PSScriptRoot/../Private/Parse-PackageMd.ps1"
    }

    It "Should extract YAML frontmatter and Markdown sections" {
        $tempFile = New-TemporaryFile
        $mockContent = @"
---
winget_id: Mozilla.Firefox
name: Firefox
version: 120.0
---

## Install
Install-Process "firefox.exe"

## Uninstall
Remove-Process "firefox.exe"

## Detection
Test-Path "C:\Program Files\Mozilla Firefox\firefox.exe"
"@
        Set-Content -Path $tempFile.FullName -Value $mockContent

        $result = Parse-PackageMd -Path $tempFile.FullName

        $result.winget_id | Should -Be "Mozilla.Firefox"
        $result.name | Should -Be "Firefox"
        $result.version | Should -Be "120.0"
        $result.Install | Should -Match "Install-Process"
        $result.Uninstall | Should -Match "Remove-Process"
        $result.Detection | Should -Match "Test-Path"

        Remove-Item -Path $tempFile.FullName -Force
    }

    It "Should accept single-hash Markdown headings used by definitions" {
        $tempFile = New-TemporaryFile
        $mockContent = @"
---
winget_id: Golang.Go
name: Go Programming Language
version: 1.22.2
---

# Install
Install silently.

# Uninstall
Uninstall silently.

# Detection
Detect installation.
"@
        Set-Content -Path $tempFile.FullName -Value $mockContent

        $result = Parse-PackageMd -Path $tempFile.FullName

        $result.Install | Should -Be "Install silently."
        $result.Uninstall | Should -Be "Uninstall silently."
        $result.Detection | Should -Be "Detect installation."

        Remove-Item -Path $tempFile.FullName -Force
    }
}
