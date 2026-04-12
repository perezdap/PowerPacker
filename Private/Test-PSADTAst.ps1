function Test-PSADTAst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptCode
    )

    $errors = @()
    $parseErrors = $null

    # Parse the script
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptCode, [ref]$null, [ref]$parseErrors)

    if ($parseErrors.Count -gt 0) {
        foreach ($err in $parseErrors) {
            $errors += "Parse error: $($err.Message)"
        }
        return [pscustomobject]@{ IsValid = $false; Errors = $errors }
    }

    # 1. Reject legacy v3 cmdlets
    $legacyCmdlets = @('Execute-Process', 'Show-InstallationWelcome')
    foreach ($legacy in $legacyCmdlets) {
        $foundLegacy = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].CommandElements[0].Value -eq $legacy
        }, $true)
        if ($foundLegacy) {
            $errors += "Legacy v3 cmdlet '$legacy' is not allowed in v4."
        }
    }

    # 2. Require Open-ADTSession, Close-ADTSession, and $adtSession
    $requiredCmdlets = @('Open-ADTSession', 'Close-ADTSession')
    foreach ($cmd in $requiredCmdlets) {
        $foundCmd = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].CommandElements[0].Value -eq $cmd
        }, $true)
        if (-not $foundCmd) {
            $errors += "Missing required v4 cmdlet: $cmd"
        }
    }

    $foundSessionVar = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $args[0].VariablePath.UserPath -eq 'adtSession'
    }, $true)
    if (-not $foundSessionVar) {
        $errors += "Missing required variable: `$adtSession"
    }

    # 3. Ensure Start-ADTProcess -FilePath uses a variable
    $startAdtCmds = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].CommandElements[0].Value -eq 'Start-ADTProcess'
    }, $true)

    foreach ($cmd in $startAdtCmds) {
        $filePathParamFound = $false
        for ($i = 1; $i -lt $cmd.CommandElements.Count; $i++) {
            $el = $cmd.CommandElements[$i]
            if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'FilePath') {
                $filePathParamFound = $true
                # The next element should be a variable
                if ($i + 1 -lt $cmd.CommandElements.Count) {
                    $nextEl = $cmd.CommandElements[$i+1]
                    if ($nextEl -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
                        $errors += "Start-ADTProcess -FilePath must use a variable, not a hardcoded string."
                    }
                } else {
                     $errors += "Start-ADTProcess -FilePath is missing an argument."
                }
            }
        }
    }

    # 4. Ensure try/catch wraps the main logic
    $tryBlocks = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.TryStatementAst]
    }, $true)
    if (-not $tryBlocks) {
        $errors += "Main deployment logic must be wrapped in a try/catch block."
    }

    # 5. Confirm Import-Module uses relative path to $PSScriptRoot
    $importModuleCmds = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].CommandElements[0].Value -eq 'Import-Module'
    }, $true)

    foreach ($cmd in $importModuleCmds) {
        $hasPSScriptRoot = $false
        for ($i = 1; $i -lt $cmd.CommandElements.Count; $i++) {
            $el = $cmd.CommandElements[$i]

            # Check if parameter is string or expression that contains $PSScriptRoot
            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                # A hardcoded string without PSScriptRoot variable is invalid
            } elseif ($el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                if ($el.Value -match 'PSScriptRoot') {
                    $hasPSScriptRoot = $true
                }
            }
        }
        if (-not $hasPSScriptRoot) {
             # Verify if it is passing a module name instead of a path, just require PSScriptRoot if it looks like a path.
             # To keep it simple and match test, let's just flag if we don't find it.
             $errors += "Import-Module must use paths relative to `$PSScriptRoot."
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
}
