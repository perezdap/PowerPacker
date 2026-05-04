Describe "Resolve-WingetArchitectures" {
    BeforeAll {
        function Get-WingetPackageMetadata {
            param(
                [string]$Id,
                [string]$Name,
                [string]$Version,
                [string]$Source,
                [string]$Architecture,
                [string]$InstallerType,
                [string]$Locale,
                [string]$Scope
            )

            if ($Architecture -eq 'x64') {
                return [pscustomobject]@{
                    RawOutput        = 'mock-x64'
                    InstallerUrl     = 'https://example.test/app-x64.exe'
                    InstallerSha256  = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                    InstallerType    = 'exe'
                    Version          = '1.0.0'
                    ResolvedId       = $Id
                }
            }

            if ($Architecture -eq 'arm64') {
                return [pscustomobject]@{
                    RawOutput        = 'mock-arm64'
                    InstallerUrl     = 'https://example.test/app-arm64.exe'
                    InstallerSha256  = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                    InstallerType    = 'exe'
                    Version          = '1.0.0'
                    ResolvedId       = $Id
                }
            }

            if ($Architecture -eq 'x86') {
                return [pscustomobject]@{
                    RawOutput        = 'mock-x86'
                    InstallerUrl     = 'https://example.test/app-x86.exe'
                    InstallerSha256  = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
                    InstallerType    = 'exe'
                    Version          = '1.0.0'
                    ResolvedId       = $Id
                }
            }

            throw "No metadata for architecture '$Architecture'"
        }

        . "$PSScriptRoot/../Private/Resolve-WingetArchitectures.ps1"
    }

    It "Should return unique installers per probed architecture" {
        $result = Resolve-WingetArchitectures -Id 'Example.Package'

        $result.Items.Count | Should -Be 3
        $result.Items[0].CanonicalLabel | Should -Be 'X64'
        $result.Items[1].CanonicalLabel | Should -Be 'ARM64'
        $result.Items[2].CanonicalLabel | Should -Be 'X86'
    }

    It "Should deduplicate installers that share the same download URL" {
        function Get-WingetPackageMetadata {
            param(
                [string]$Id,
                [string]$Architecture
            )

            return [pscustomobject]@{
                RawOutput       = "mock-$Architecture"
                InstallerUrl    = 'https://example.test/same.exe'
                InstallerSha256 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
                InstallerType   = 'exe'
                Version         = '1.0.0'
                ResolvedId      = $Id
            }
        }

        . "$PSScriptRoot/../Private/Resolve-WingetArchitectures.ps1"

        $result = Resolve-WingetArchitectures -Id 'Example.Package'

        $result.Items.Count | Should -Be 1
        $result.Items[0].CanonicalLabel | Should -Be 'X64'
    }
}
