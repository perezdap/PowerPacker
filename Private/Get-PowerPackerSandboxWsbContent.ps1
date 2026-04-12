function Get-PowerPackerSandboxWsbContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostPackagePath,

        [Parameter(Mandatory = $true)]
        [string]$HostResultsPath,

        [Parameter(Mandatory = $true)]
        [string]$SandboxPackagePath,

        [Parameter(Mandatory = $true)]
        [string]$SandboxResultsPath,

        [switch]$DisableNetworking,
        [switch]$DisableVGpu
    )

    $escape = {
        param([string]$Value)
        [System.Security.SecurityElement]::Escape($Value)
    }

    $networkingElement = if ($DisableNetworking) { "  <Networking>Disable</Networking>`n" } else { '' }
    $vGpuElement = if ($DisableVGpu) { "  <VGpu>Disable</VGpu>`n" } else { '' }

@"
<Configuration>
$vGpuElement$networkingElement  <MappedFolders>
    <MappedFolder>
      <HostFolder>$(& $escape $HostPackagePath)</HostFolder>
      <SandboxFolder>$(& $escape $SandboxPackagePath)</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$(& $escape $HostResultsPath)</HostFolder>
      <SandboxFolder>$(& $escape $SandboxResultsPath)</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
</Configuration>
"@
}
