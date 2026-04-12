function Save-PSADTTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$AssetName,

        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [string]$Repository = 'PSAppDeployToolkit/PSAppDeployToolkit'
    )

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $output = & gh release download $TagName --repo $Repository --pattern $AssetName --dir $Directory --clobber 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download PSADT release asset '$AssetName'. $output".Trim()
    }

    $zipFile = Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Name -eq $AssetName } | Select-Object -First 1
    if (-not $zipFile) {
        throw "PSADT release asset '$AssetName' was not found in '$Directory' after download."
    }

    [pscustomobject]@{
        ZipPath = $zipFile.FullName
        Output  = $output.Trim()
    }
}
