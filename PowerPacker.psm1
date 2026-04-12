# PowerPacker.psm1

# Load Public functions
Get-ChildItem -Path "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse | ForEach-Object { . $_.FullName }

# Load Private functions
Get-ChildItem -Path "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse | ForEach-Object { . $_.FullName }

# Export Public functions
Export-ModuleMember -Function (Get-ChildItem -Path "$PSScriptRoot/Public" -Filter "*.ps1" | Select-Object -ExpandProperty BaseName)
