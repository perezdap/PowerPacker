function Get-PSADTTemplateAsset {
    [CmdletBinding()]
    param(
        [string]$Repository = 'PSAppDeployToolkit/PSAppDeployToolkit',
        [string]$AssetName = 'PSAppDeployToolkit_Template_v4.zip'
    )

    $output = & gh release view --repo $Repository --json tagName,name,assets 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query PSADT releases with gh. $output".Trim()
    }

    $release = $output | ConvertFrom-Json
    $asset = @($release.assets | Where-Object { $_.name -eq $AssetName }) | Select-Object -First 1

    if (-not $asset) {
        throw "Release asset '$AssetName' was not found in $Repository."
    }

    [pscustomobject]@{
        Repository  = $Repository
        TagName     = $release.tagName
        ReleaseName = $release.name
        AssetName   = $asset.name
        DownloadUrl = $asset.url
        Digest      = $asset.digest
    }
}
