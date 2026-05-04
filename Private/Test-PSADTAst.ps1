[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$ScriptCode
)

function Test-PSADTAst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
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

        return [pscustomobject]@{
            IsValid = $false
            Errors = $errors
        }
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

    $foundSessionVarInitialization = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $args[0].Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $args[0].Left.VariablePath.UserPath -eq 'adtSession' -and
        ($args[0].Right -is [System.Management.Automation.Language.HashtableAst] -or
            ($args[0].Right -is [System.Management.Automation.Language.CommandExpressionAst] -and $args[0].Right.Expression -is [System.Management.Automation.Language.HashtableAst]))
    }, $true)
    if (-not $foundSessionVarInitialization) {
        $errors += "Missing required variable initialization: `$adtSession = @{}"
    }

    # 3. Ensure Start-ADTProcess -FilePath uses a variable
    $startAdtCmds = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].CommandElements[0].Value -eq 'Start-ADTProcess'
    }, $true)

    foreach ($cmd in $startAdtCmds) {
        $filePathParamFound = $false
        $filePathArg = $null
        $filePathArgMissing = $false
        $hasSplat = $false

        for ($i = 1; $i -lt $cmd.CommandElements.Count; $i++) {
            $el = $cmd.CommandElements[$i]

            if ($el -is [System.Management.Automation.Language.VariableExpressionAst] -and $el.Splatted) {
                $hasSplat = $true
            }

            if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($el.ParameterName -eq 'FilePath') {
                    $filePathParamFound = $true
                    if ($i + 1 -lt $cmd.CommandElements.Count) {
                        $filePathArg = $cmd.CommandElements[$i + 1]
                        if ($filePathArg -is [System.Management.Automation.Language.VariableExpressionAst] -and $filePathArg.Splatted) {
                            $hasSplat = $true
                        }
                    } else {
                        $filePathArgMissing = $true
                    }
                    break
                }

                continue
            }

            if (-not $filePathParamFound -and $null -eq $filePathArg) {
                $filePathArg = $el
            }
        }

        if ($hasSplat) {
            $errors += "Start-ADTProcess -FilePath must use a variable, not a splatted argument."
            continue
        }

        if ($filePathArgMissing) {
            $errors += "Start-ADTProcess -FilePath is missing an argument."
            continue
        }

        if ($null -ne $filePathArg -and $filePathArg -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
            $errors += "Start-ADTProcess -FilePath must use a variable, not a hardcoded string."
        }
    }

    # 4. Ensure try/catch wraps the main logic
    # TODO: The validator currently requires Close-ADTSession after the catch block rather than inside
    # finally. This is a workaround for an AST rule limitation, not a style preference. Relax this rule
    # to allow finally so generated scripts can use the cleaner pattern.
    $topLevelStatements = @()
    if ($ast.EndBlock) {
        $topLevelStatements = @($ast.EndBlock.Statements)
    }

    $openSessionIndex = -1
    $closeSessionIndex = -1

    for ($i = 0; $i -lt $topLevelStatements.Count; $i++) {
        $statement = $topLevelStatements[$i]
        $containsOpenSession = $statement.Find({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.CommandElements.Count -gt 0 -and
            $node.CommandElements[0].Value -eq 'Open-ADTSession'
        }, $true)

        if ($containsOpenSession) {
            $openSessionIndex = $i
            break
        }
    }

    if ($openSessionIndex -ge 0) {
        for ($i = $openSessionIndex + 1; $i -lt $topLevelStatements.Count; $i++) {
            $statement = $topLevelStatements[$i]
            $containsCloseSession = $statement.Find({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.CommandElements.Count -gt 0 -and
                $node.CommandElements[0].Value -eq 'Close-ADTSession'
            }, $true)

            if ($containsCloseSession) {
                $closeSessionIndex = $i
                break
            }
        }
    }

    $mainLogicWrappedInTryCatch = $false
    if ($openSessionIndex -ge 0 -and $closeSessionIndex -gt $openSessionIndex) {
        for ($i = $openSessionIndex + 1; $i -lt $closeSessionIndex; $i++) {
            if ($topLevelStatements[$i] -is [System.Management.Automation.Language.TryStatementAst]) {
                $mainLogicWrappedInTryCatch = $true
                break
            }
        }
    }

    if (-not $mainLogicWrappedInTryCatch) {
        $errors += "Main deployment logic must be wrapped in a try/catch block."
    }

    # 5. Confirm Import-Module uses relative path to $PSScriptRoot
    $importModuleCmds = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].CommandElements[0].Value -eq 'Import-Module'
    }, $true)

    foreach ($cmd in $importModuleCmds) {
        $hasPSScriptRoot = $false
        $isPathLike = $false

        for ($i = 1; $i -lt $cmd.CommandElements.Count; $i++) {
            $el = $cmd.CommandElements[$i]

            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                if ($el.Value -match '[/\\]') {
                    $isPathLike = $true
                }
            } elseif ($el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                if ($el.Value -match '[/\\]') {
                    $isPathLike = $true
                }
                if ($el.Value -match 'PSScriptRoot') {
                    $hasPSScriptRoot = $true
                }
            } elseif ($el -is [System.Management.Automation.Language.VariableExpressionAst]) {
                if ($el.VariablePath.UserPath -eq 'PSScriptRoot') {
                    $hasPSScriptRoot = $true
                }
            }
        }

        if ($isPathLike -and -not $hasPSScriptRoot) {
            $errors += "Import-Module must use paths relative to `$PSScriptRoot."
        }
    }

    # 6. Architecture-aware script validation (fully AST-based)
    $archAwareMemberAccesses = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.MemberExpressionAst] -and
        $args[0].Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $args[0].Member.Value -eq 'InstallerFilesByArchitecture'
    }, $true)

    if ($archAwareMemberAccesses.Count -gt 0) {
        $runtimeInfoAccesses = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $args[0].Static -eq $true -and
            $args[0].Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
            $args[0].Expression.TypeName.Name -like '*RuntimeInformation*'
        }, $true)

        if ($runtimeInfoAccesses.Count -eq 0) {
            $errors += "Architecture-aware scripts must query OS architecture via [System.Runtime.InteropServices.RuntimeInformation]."
        }

        $osArchAccesses = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $args[0].Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $args[0].Member.Value -eq 'OSArchitecture'
        }, $true)

        if ($osArchAccesses.Count -eq 0) {
            $errors += "Architecture-aware scripts must reference OSArchitecture when selecting installers."
        }

        $switchStatements = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.SwitchStatementAst]
        }, $true)

        if ($switchStatements.Count -eq 0) {
            $errors += "Architecture-aware scripts must use a switch statement to map OS architecture to installer paths."
        }

        $logEntries = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].CommandElements.Count -gt 0 -and
            $args[0].CommandElements[0].Value -eq 'Write-ADTLogEntry'
        }, $true)

        if ($logEntries.Count -eq 0) {
            $errors += "Architecture-aware scripts must call Write-ADTLogEntry when documenting installer selection or fallbacks."
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $PSBoundParameters.ContainsKey('ScriptCode')) {
        throw "ScriptCode is required when invoking Test-PSADTAst.ps1 directly."
    }

    Test-PSADTAst -ScriptCode $ScriptCode | ConvertTo-Json -Depth 3
}
