Describe "ConvertFrom-WingetShowOutput" {
    BeforeAll {
        . "$PSScriptRoot/../Private/ConvertFrom-WingetShowOutput.ps1"
    }

    It "Should parse key installer fields from winget show output" {
        $sample = @"
Found Go Programming Language [GoLang.Go]
Version: 1.26.2
Publisher: https://go.dev
Moniker: go
Installer:
  Installer Type: wix
  Installer Locale: en-US
  Installer Url: https://go.dev/dl/go1.26.2.windows-amd64.msi
  Installer SHA256: 84826eca833548bb2beabe7429052eaaec18faa902fde723898d906b42e59a73
  Release Date: 2026-04-07
"@

        $result = ConvertFrom-WingetShowOutput -Text $sample

        $result.Name | Should -Be "Go Programming Language"
        $result.Id | Should -Be "GoLang.Go"
        $result.Version | Should -Be "1.26.2"
        $result.Publisher | Should -Be "https://go.dev"
        $result.Moniker | Should -Be "go"
        $result.Installer.Type | Should -Be "wix"
        $result.Installer.Locale | Should -Be "en-US"
        $result.Installer.Url | Should -Be "https://go.dev/dl/go1.26.2.windows-amd64.msi"
        $result.Installer.Sha256 | Should -Be "84826eca833548bb2beabe7429052eaaec18faa902fde723898d906b42e59a73"
        $result.Installer.ReleaseDate | Should -Be "2026-04-07"
    }
}
