# PowerPacker.psm1

$publicDirectory = Join-Path $PSScriptRoot 'Public'
$privateDirectory = Join-Path $PSScriptRoot 'Private'
$scriptDirectories = @($publicDirectory, $privateDirectory) | Where-Object { Test-Path -LiteralPath $_ }

foreach ($directory in $scriptDirectories) {
    Get-ChildItem -Path $directory -Filter "*.ps1" -Recurse | ForEach-Object { . $_.FullName }
}

$functionsToExport = if (Test-Path -LiteralPath $publicDirectory) {
    Get-ChildItem -Path $publicDirectory -Filter "*.ps1" -Recurse | Select-Object -ExpandProperty BaseName
} else {
    @()
}

if ($functionsToExport) {
    Export-ModuleMember -Function ($functionsToExport | Sort-Object -Unique)
}
