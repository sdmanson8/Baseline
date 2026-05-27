# Pre-flight validation checks that run before execution begins.
# Catches system-level problems early instead of mid-run.

<#
    .SYNOPSIS
#>

function New-PreflightCheckResult
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Warning')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('System', 'Storage', 'Services', 'Security', 'Recovery')]
        [string]$Category,

        [object[]]$RemediationActions = @(),

        [object]$Details
    )

    $result = [pscustomobject]@{
        Name     = $Name
        Key      = $Key
        Status   = $Status
        Message  = $Message
        Category = $Category
    }

    if ($RemediationActions -and @($RemediationActions).Count -gt 0)
    {
        $result | Add-Member -NotePropertyName RemediationActions -NotePropertyValue @($RemediationActions) -Force
    }

    if ($null -ne $Details)
    {
        $result | Add-Member -NotePropertyName Details -NotePropertyValue $Details -Force
    }

    return $result
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Builds a structured risk category record surfaced in preflight, preview,
    and remote-console dialogs. Each category carries a status, tone, the
    remediation steps the operator should take, and a documentation pointer
    that the UI can hyperlink.
#>

function New-BaselineRiskCategory
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Passed','Warning','Failed')][string]$Status,
        [Parameter(Mandatory)][string]$Summary,
        [string[]]$RemediationActions = @(),
        [string]$DocumentationPath,
        [string]$LogHint,
        [object]$Details
    )

    $tone = switch ($Status)
    {
        'Failed'  { 'Danger'; break }
        'Warning' { 'Caution'; break }
        default   { 'Muted' }
    }

    $record = [pscustomobject]@{
        Key                = $Key
        Name               = $Name
        Status             = $Status
        Tone               = $tone
        Summary            = $Summary
        RemediationActions = @($RemediationActions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        DocumentationPath  = $DocumentationPath
        LogHint            = $LogHint
    }
    if ($null -ne $Details)
    {
        $record | Add-Member -NotePropertyName Details -NotePropertyValue $Details -Force
    }
    return $record
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Translates raw preflight checks and rollout history into the structured
    risk category list consumed by the preflight dialog, remote console, and
    preview summary. Categories are ordered so operator-facing UI can render
    them deterministically.
#>

function Get-BaselineRiskCategoryList
{
    [CmdletBinding()]
    param (
        [object]$ManagedPolicyCheck,
        [object]$PendingRebootCheck,
        [object]$WinRMCheck,
        [object]$HostTaintCheck,
        [switch]$IncludePartialSuccessHistory
    )

    $categories = [System.Collections.Generic.List[object]]::new()

    # --- Managed endpoint policy ----------------------------------------
    if ($ManagedPolicyCheck)
    {
        $mpStatus = [string]$ManagedPolicyCheck.Status
        $mpRemediation = @()
        if ($ManagedPolicyCheck.PSObject.Properties['RemediationActions'] -and $ManagedPolicyCheck.RemediationActions)
        {
            $mpRemediation = @($ManagedPolicyCheck.RemediationActions)
        }
        $mpSummary = if ($mpStatus -eq 'Passed')
        {
            (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryManagedPassed' -Fallback 'No managed-endpoint conflicts detected.')
        }
        else
        {
            [string]$ManagedPolicyCheck.Message
        }
        $mpDetails = if ($ManagedPolicyCheck.PSObject.Properties['Details']) { $ManagedPolicyCheck.Details } else { $null }
        [void]$categories.Add((New-BaselineRiskCategory `
            -Key 'ManagedEndpointPolicy' `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryManagedName' -Fallback 'Managed endpoint policy') `
            -Status $mpStatus `
            -Summary $mpSummary `
            -RemediationActions $mpRemediation `
            -DocumentationPath 'dev_docs/Remediation/ManagedEndpoints.md' `
            -LogHint (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogHintPolicy' -Fallback 'Review managed-policy entries in the support bundle (PolicyConflictSignals).') `
            -Details $mpDetails))
    }

    # --- Host taint / third-party tweaker detection --------------------
    if ($HostTaintCheck)
    {
        $hostStatus = [string]$HostTaintCheck.Status
        $hostRemediation = @()
        if ($HostTaintCheck.PSObject.Properties['RemediationActions'] -and $HostTaintCheck.RemediationActions)
        {
            $hostRemediation = @($HostTaintCheck.RemediationActions)
        }

        [void]$categories.Add((New-BaselineRiskCategory `
            -Key 'HostTaint' `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryHostTaintName' -Fallback 'Host integrity') `
            -Status $hostStatus `
            -Summary ([string]$HostTaintCheck.Message) `
            -RemediationActions $hostRemediation `
            -DocumentationPath 'dev_docs/Remediation/HostIntegrity.md' `
            -LogHint (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogHintHostTaint' -Fallback 'Review InitialActions warnings and attach a support bundle before remediation.') `
            -Details $(if ($HostTaintCheck.PSObject.Properties['Details']) { $HostTaintCheck.Details } else { $null })))
    }

    # --- Pending reboot --------------------------------------------------
    if ($PendingRebootCheck)
    {
        $prStatus = [string]$PendingRebootCheck.Status
        $prRemediation = @()
        if ($PendingRebootCheck.PSObject.Properties['RemediationActions'] -and $PendingRebootCheck.RemediationActions)
        {
            $prRemediation = @($PendingRebootCheck.RemediationActions)
        }
        $prSummary = if ($prStatus -eq 'Passed')
        {
            (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryRebootPassed' -Fallback 'No pending reboot detected.')
        }
        else
        {
            [string]$PendingRebootCheck.Message
        }
        $prDetails = if ($PendingRebootCheck.PSObject.Properties['Details']) { $PendingRebootCheck.Details } else { $null }
        [void]$categories.Add((New-BaselineRiskCategory `
            -Key 'PendingReboot' `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryRebootName' -Fallback 'Pending reboot') `
            -Status $prStatus `
            -Summary $prSummary `
            -RemediationActions $prRemediation `
            -DocumentationPath 'dev_docs/Remediation/PendingReboot.md' `
            -LogHint (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogHintReboot' -Fallback 'Pending-reboot reasons are recorded under PreflightChecks in the log.') `
            -Details $prDetails))
    }

    # --- WinRM variability ---------------------------------------------
    if ($WinRMCheck)
    {
        $wrStatus = [string]$WinRMCheck.Status
        $isPartial = $false
        $details = $null
        if ($WinRMCheck.PSObject.Properties['Details'] -and $WinRMCheck.Details)
        {
            $details = $WinRMCheck.Details
            if ($details -is [System.Collections.IDictionary])
            {
                if ($details.Contains('PartialCoverage')) { $isPartial = [bool]$details['PartialCoverage'] }
            }
            elseif ($details.PSObject.Properties['PartialCoverage'])
            {
                $isPartial = [bool]$details.PartialCoverage
            }
        }
        $wrKey = if ($isPartial) { 'WinRMVariability' } else { 'WinRMReachability' }
        $wrName = if ($isPartial) {
            (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryWinRMVariabilityName' -Fallback 'WinRM reachability variability')
        } else {
            (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryWinRMName' -Fallback 'WinRM reachability')
        }
        $wrRemediation = @()
        if ($WinRMCheck.PSObject.Properties['RemediationActions'] -and $WinRMCheck.RemediationActions)
        {
            $wrRemediation = @($WinRMCheck.RemediationActions)
        }
        $wrSummary = if ($wrStatus -eq 'Passed')
        {
            (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryWinRMPassed' -Fallback 'All targets reachable via WinRM.')
        }
        else
        {
            [string]$WinRMCheck.Message
        }
        [void]$categories.Add((New-BaselineRiskCategory `
            -Key $wrKey `
            -Name $wrName `
            -Status $wrStatus `
            -Summary $wrSummary `
            -RemediationActions $wrRemediation `
            -DocumentationPath 'dev_docs/Remediation/WinRMReachability.md' `
            -LogHint (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogHintWinRM' -Fallback 'See WinRM detail lines in the remote-console log and support bundle transcripts.') `
            -Details $details))
    }

    # --- Partial-success rollout risk (history driven) ------------------
    if ($IncludePartialSuccessHistory)
    {
        $risk = Get-BaselinePartialSuccessRolloutRisk
        if ($risk)
        {
            [void]$categories.Add($risk)
        }
    }

    return @($categories)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Inspects recent rollout outcomes and, when partial-success outcomes are
    present, returns a risk category flagging the rollout risk so the next
    run surfaces it before the operator continues.
#>

function Get-BaselinePartialSuccessRolloutRisk
{
    [CmdletBinding()]
    param ()

    $cmd = Get-Command -Name 'Get-BaselineRemoteRolloutOutcomes' -CommandType Function -ErrorAction SilentlyContinue
    if (-not $cmd)
    {
        return $null
    }

    $outcomes = @()
    try
    {
        $since = [datetime]::UtcNow.AddDays(-7)
        $outcomes = @(& $cmd -Since $since -MaxRecords 25)
    }
    catch
    {
        Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Get-BaselinePartialSuccessRolloutRisk.LoadOutcomes'
        return $null
    }

    if (-not $outcomes -or $outcomes.Count -eq 0)
    {
        return $null
    }

    $partial = @($outcomes | Where-Object { [string]$_.Outcome -eq 'PartialSuccess' })
    if ($partial.Count -eq 0)
    {
        return (New-BaselineRiskCategory `
            -Key 'PartialSuccessRolloutRisk' `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryPartialName' -Fallback 'Partial-success rollout risk') `
            -Status 'Passed' `
            -Summary (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryPartialPassed' -Fallback 'No partial-success rollouts recorded in the last 7 days.') `
            -DocumentationPath 'dev_docs/Remediation/PartialSuccess.md')
    }

    $latest = $partial | Sort-Object -Property RecordedUtc -Descending | Select-Object -First 1
    $summary = ((Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryPartialSummary' -Fallback '{0} recent rollout(s) ended in partial success (latest: {1}, run {2}).') -f $partial.Count, $latest.Operation, $latest.RunId)
    $logHintTemplate = Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogHintPartial' -Fallback 'Use RunId {0} in the orchestration history to locate the failed sub-steps.'
    $logHint = ($logHintTemplate -f [string]$latest.RunId)
    return (New-BaselineRiskCategory `
        -Key 'PartialSuccessRolloutRisk' `
        -Name (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryPartialName' -Fallback 'Partial-success rollout risk') `
        -Status 'Warning' `
        -Summary $summary `
        -RemediationActions @(
            'Review the partial-success items from the referenced run before re-running the same operation.',
            'Confirm the target(s) left in a partial state have been remediated or excluded from the next rollout.',
            'If the partial-success is expected (e.g., package cleanup), annotate the run ID in the audit bundle.'
        ) `
        -DocumentationPath 'dev_docs/Remediation/PartialSuccess.md' `
        -LogHint $logHint `
        -Details ([ordered]@{
            PartialOutcomeCount = $partial.Count
            LatestRunId         = [string]$latest.RunId
            LatestOperation     = [string]$latest.Operation
            LatestRecordedUtc   = $latest.RecordedUtc
        }))
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Produces a single-line summary suitable for status cards when one or
    more risk categories are active. Uses localized labels where available.
#>

function Get-BaselineRiskCategorySummaryText
{
    [CmdletBinding()]
    param (
        [object[]]$Categories = @()
    )

    $active = @($Categories | Where-Object { [string]$_.Status -ne 'Passed' })
    if ($active.Count -eq 0)
    {
        return (Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryNone' -Fallback 'No policy conflict signals detected.')
    }
    $names = @($active | ForEach-Object { [string]$_.Name })
    return ((Get-UxLocalizedString -Key 'GuiPreflightRiskCategorySummary' -Fallback 'Risk categories flagged: {0}.') -f ($names -join ', '))
}

<#
    .SYNOPSIS
#>

function Get-BaselinePreflightContract
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    $items = @($Results | Where-Object { $null -ne $_ })
    $passedCount = @($items | Where-Object { [string]$_.Status -eq 'Passed' }).Count
    $warningCount = @($items | Where-Object { [string]$_.Status -eq 'Warning' }).Count
    $failedCount = @($items | Where-Object { [string]$_.Status -eq 'Failed' }).Count

    $adminCheck = if ($items.Count -gt 0) { $items[0] } else { $null }
    $managedPolicyCheck = if ($items.Count -gt 6) { $items[6] } else { $null }
    $pendingRebootCheck = if ($items.Count -gt 7) { $items[7] } else { $null }
    $winrmCheck = if ($items.Count -gt 8) { $items[8] } else { $null }
    $hostTaintCheck = $null
    foreach ($item in $items)
    {
        if ($item -and $item.PSObject.Properties['Key'] -and [string]$item.Key -eq 'HostTaint')
        {
            $hostTaintCheck = $item
            break
        }
    }

    $policyConflictChecks = @($managedPolicyCheck, $pendingRebootCheck | Where-Object { $null -ne $_ })
    $policyConflictCount = @($policyConflictChecks | Where-Object { [string]$_.Status -ne 'Passed' }).Count
    $policyConflictStatus = if (@($policyConflictChecks | Where-Object { [string]$_.Status -eq 'Failed' }).Count -gt 0) { 'Failed' } elseif ($policyConflictCount -gt 0) { 'Warning' } else { 'Passed' }

    $reachableTargets = @()
    $unreachableTargets = @()
    $targetCount = 0
    $serviceStatus = $null
    if ($winrmCheck -and $winrmCheck.PSObject.Properties['Details'] -and $winrmCheck.Details)
    {
        if ($winrmCheck.Details -is [System.Collections.IDictionary])
        {
            $targetCount = if ($winrmCheck.Details.Contains('TargetCount')) { [int]$winrmCheck.Details['TargetCount'] } else { 0 }
            $reachableTargets = if ($winrmCheck.Details.Contains('ReachableTargets')) { @($winrmCheck.Details['ReachableTargets']) } else { @() }
            $unreachableTargets = if ($winrmCheck.Details.Contains('UnreachableTargets')) { @($winrmCheck.Details['UnreachableTargets']) } else { @() }
            $serviceStatus = if ($winrmCheck.Details.Contains('ServiceStatus')) { [string]$winrmCheck.Details['ServiceStatus'] } else { $null }
        }
        else
        {
            $targetCount = if ($winrmCheck.Details.PSObject.Properties['TargetCount']) { [int]$winrmCheck.Details.TargetCount } else { 0 }
            $reachableTargets = if ($winrmCheck.Details.PSObject.Properties['ReachableTargets']) { @($winrmCheck.Details.ReachableTargets) } else { @() }
            $unreachableTargets = if ($winrmCheck.Details.PSObject.Properties['UnreachableTargets']) { @($winrmCheck.Details.UnreachableTargets) } else { @() }
            $serviceStatus = if ($winrmCheck.Details.PSObject.Properties['ServiceStatus']) { [string]$winrmCheck.Details.ServiceStatus } else { $null }
        }
    }

    $environmentClassification = if ($failedCount -gt 0) { 'Unsupported' } elseif ($warningCount -gt 0) { 'AttentionRequired' } else { 'Supported' }
    $topLevelStatus = if ($failedCount -gt 0) { 'Failed' } elseif ($warningCount -gt 0) { 'Warning' } else { 'Passed' }

    $riskCategories = @(Get-BaselineRiskCategoryList -ManagedPolicyCheck $managedPolicyCheck -PendingRebootCheck $pendingRebootCheck -WinRMCheck $winrmCheck -HostTaintCheck $hostTaintCheck -IncludePartialSuccessHistory)
    $categoryIssueCount = @($riskCategories | Where-Object { [string]$_.Status -ne 'Passed' }).Count

    return [pscustomobject]@{
        Status = $topLevelStatus
        SupportedEnvironmentClassification = [pscustomobject]@{
            Status       = $environmentClassification
            PassedCount   = $passedCount
            WarningCount  = $warningCount
            FailedCount   = $failedCount
            Summary       = ('Environment classification: {0} (Passed={1}, Warning={2}, Failed={3})' -f $environmentClassification, $passedCount, $warningCount, $failedCount)
        }
        WinRMReachability = if ($winrmCheck) {
            [pscustomobject]@{
                Status            = [string]$winrmCheck.Status
                Check             = $winrmCheck
                TargetCount       = $targetCount
                ReachableTargets  = @($reachableTargets)
                UnreachableTargets = @($unreachableTargets)
                ServiceStatus     = $serviceStatus
                Summary           = [string]$winrmCheck.Message
            }
        } else { $null }
        Credentials = if ($adminCheck) {
            [pscustomobject]@{
                Status      = [string]$adminCheck.Status
                Check       = $adminCheck
                Summary     = [string]$adminCheck.Message
                IsElevated  = if ($adminCheck.PSObject.Properties['Details'] -and $adminCheck.Details) {
                    if ($adminCheck.Details -is [System.Collections.IDictionary]) {
                        if ($adminCheck.Details.Contains('IsAdministrator')) { [bool]$adminCheck.Details['IsAdministrator'] } else { $null }
                    }
                    elseif ($adminCheck.Details.PSObject.Properties['IsAdministrator']) { [bool]$adminCheck.Details.IsAdministrator }
                    else { $null }
                } else { $null }
            }
        } else { $null }
        PolicyConflictSignals = [pscustomobject]@{
            Status                = $policyConflictStatus
            ManagedPolicyEnvironment = $managedPolicyCheck
            PendingReboot         = $pendingRebootCheck
            Checks                = @($policyConflictChecks)
            ConflictCount         = $policyConflictCount
            Categories            = @($riskCategories)
            CategoryIssueCount    = $categoryIssueCount
            Summary               = if ($categoryIssueCount -gt 0) { (Get-BaselineRiskCategorySummaryText -Categories $riskCategories) } elseif ($policyConflictCount -gt 0) { 'Policy conflict signals detected.' } else { 'No policy conflict signals detected.' }
        }
        HostIntegrity = if ($hostTaintCheck) {
            [pscustomobject]@{
                Status  = [string]$hostTaintCheck.Status
                Check   = $hostTaintCheck
                Summary = [string]$hostTaintCheck.Message
                Details = if ($hostTaintCheck.PSObject.Properties['Details']) { $hostTaintCheck.Details } else { $null }
            }
        } else { $null }
        RiskCategories = @($riskCategories)
        AllResults = $items
        PassedCount = $passedCount
        WarningCount = $warningCount
        FailedCount = $failedCount
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightHostTaint
{
    $assessment = $Global:BaselineHostTaint
    if ($null -eq $assessment)
    {
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameHostTaint' -Fallback 'Host integrity') -Key 'HostTaint' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightHostTaintPassed' -Fallback 'No host-tamper assessment is currently flagged.') -Category 'Security' -Details ([ordered]@{ Level = 'None'; Detected = @(); BackdoorFound = $false; AdvisoryUrls = @() }))
    }

    $level = if ($assessment.PSObject.Properties['Level']) { [string]$assessment.Level } else { 'None' }
    $detected = @(if ($assessment.PSObject.Properties['Detected']) { $assessment.Detected | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } })
    $advisoryUrls = @(if ($assessment.PSObject.Properties['AdvisoryUrls']) { $assessment.AdvisoryUrls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } })
    $backdoorFound = if ($assessment.PSObject.Properties['BackdoorFound']) { [bool]$assessment.BackdoorFound } else { $false }
    $detectedText = if ($detected.Count -gt 0) { $detected -join ', ' } else { 'none' }

    $details = [ordered]@{
        Level         = $level
        Detected      = @($detected)
        BackdoorFound = $backdoorFound
        AdvisoryUrls  = @($advisoryUrls)
    }

    if ($level -eq 'Blocked')
    {
        return (New-PreflightCheckResult `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightNameHostTaint' -Fallback 'Host integrity') `
            -Key 'HostTaint' `
            -Status 'Failed' `
            -Message ((Get-UxLocalizedString -Key 'GuiPreflightHostTaintBlocked' -Fallback 'Potentially compromised host detected: {0}. Baseline will not apply system changes on this host.') -f $detectedText) `
            -Category 'Security' `
            -RemediationActions @(
                (Get-UxLocalizedString -Key 'GuiPreflightHostTaintBlockedAction1' -Fallback 'Do not apply additional tweaks on this Windows installation.')
                (Get-UxLocalizedString -Key 'GuiPreflightHostTaintBlockedAction2' -Fallback 'Reinstall Windows using genuine installation media before running Baseline again.')
                (Get-UxLocalizedString -Key 'GuiPreflightHostTaintBlockedAction3' -Fallback 'Use the support bundle only for diagnostics; do not treat this host as trusted.')
            ) `
            -Details $details)
    }

    if ($level -eq 'Warning')
    {
        return (New-PreflightCheckResult `
            -Name (Get-UxLocalizedString -Key 'GuiPreflightNameHostTaint' -Fallback 'Host integrity') `
            -Key 'HostTaint' `
            -Status 'Warning' `
            -Message ((Get-UxLocalizedString -Key 'GuiPreflightHostTaintWarning' -Fallback 'Third-party Windows tweaker traces detected: {0}. Review before applying more changes.') -f $detectedText) `
            -Category 'Security' `
            -RemediationActions @(
                (Get-UxLocalizedString -Key 'GuiPreflightHostTaintWarningAction1' -Fallback 'Review the detected tool list and confirm the host is still trusted.')
                (Get-UxLocalizedString -Key 'GuiPreflightHostTaintWarningAction2' -Fallback 'Export a support bundle if Baseline behavior looks inconsistent.')
            ) `
            -Details $details)
    }

    return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameHostTaint' -Fallback 'Host integrity') -Key 'HostTaint' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightHostTaintPassed' -Fallback 'No host-tamper assessment is currently flagged.') -Category 'Security' -Details $details)
}

<#
    .SYNOPSIS
#>

function Test-PreflightAdminElevation
{
    try
    {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameAdmin' -Fallback 'Administrator') -Key 'AdminElevation' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightAdminPassed' -Fallback 'Running as administrator') -Category 'Security' -Details ([ordered]@{ IsAdministrator = $true }))
        }
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameAdmin' -Fallback 'Administrator') -Key 'AdminElevation' -Status 'Failed' -Message (Get-UxLocalizedString -Key 'GuiPreflightAdminFailed' -Fallback 'Not running as administrator') -Category 'Security' -Details ([ordered]@{ IsAdministrator = $false }))
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightAdminElevation:catch560' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameAdmin' -Fallback 'Administrator') -Key 'AdminElevation' -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightAdminError' -Fallback 'Could not verify elevation: {0}') -f $_.Exception.Message) -Category 'Security')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightDiskSpace
{
    $minFreeBytes = 500MB
    try
    {
        $systemDriveLetter = $env:SystemDrive[0]
        $volume = Get-Volume -DriveLetter $systemDriveLetter -ErrorAction Stop
        $freeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)

        if ($volume.SizeRemaining -ge $minFreeBytes)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameDisk' -Fallback 'Disk space') -Status 'Passed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightDiskPassed' -Fallback '{0} GB free') -f $freeGB) -Category 'Storage')
        }
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameDisk' -Fallback 'Disk space') -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightDiskFailed' -Fallback 'Only {0} GB free on {1}: (minimum 500 MB required)') -f $freeGB, $systemDriveLetter) -Category 'Storage')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightDiskSpace:catch585' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameDisk' -Fallback 'Disk space') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightDiskError' -Fallback 'Could not verify disk space: {0}') -f $_.Exception.Message) -Category 'Storage')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightVSS
{
    try
    {
        $vssSvc = Get-Service -Name VSS -ErrorAction Stop
        if ($vssSvc.Status -eq 'Running')
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameVSS' -Fallback 'Volume Shadow Copy') -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightServiceRunning' -Fallback 'Service is running') -Category 'Services')
        }
        if ($vssSvc.StartType -eq 'Disabled')
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameVSS' -Fallback 'Volume Shadow Copy') -Status 'Warning' -Message (Get-UxLocalizedString -Key 'GuiPreflightVSSDisabled' -Fallback 'Service is disabled (will be enabled and started)') -Category 'Services')
        }
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameVSS' -Fallback 'Volume Shadow Copy') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightVSSNotRunning' -Fallback 'Service not running (status: {0}, will be started)') -f $vssSvc.Status) -Category 'Services')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightVSS:catch610' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameVSS' -Fallback 'Volume Shadow Copy') -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightVSSError' -Fallback 'VSS service not found: {0}') -f $_.Exception.Message) -Category 'Services')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightEventLog
{
    try
    {
        $eventLogSvc = Get-Service -Name EventLog -ErrorAction Stop
        if ($eventLogSvc.Status -eq 'Running')
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameEventLog' -Fallback 'EventLog service') -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightServiceRunning' -Fallback 'Service is running') -Category 'Services')
        }
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameEventLog' -Fallback 'EventLog service') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightEventLogStatus' -Fallback 'Service is {0}') -f $eventLogSvc.Status) -Category 'Services')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightEventLog:catch631' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameEventLog' -Fallback 'EventLog service') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightEventLogError' -Fallback 'Could not query EventLog service: {0}') -f $_.Exception.Message) -Category 'Services')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightWMI
{
    try
    {
        $null = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWMI' -Fallback 'WMI health') -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightWMIPassed' -Fallback 'CIM/WMI responding') -Category 'System')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightWMI:catch648' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWMI' -Fallback 'WMI health') -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightWMIFailed' -Fallback 'CIM/WMI query failed: {0}') -f $_.Exception.Message) -Category 'System')
    }
}

function Test-PreflightSystemRestore
{
    try
    {
        $systemDriveLetter = $env:SystemDrive[0]
        $systemDriveUniqueID = (Get-Volume | Where-Object { $_.DriveLetter -eq $systemDriveLetter }).UniqueID
        $systemProtection = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients" -ErrorAction Ignore)."{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}") | Where-Object { $_ -match [regex]::Escape($systemDriveUniqueID) }

        if ($null -ne $systemProtection)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestore' -Fallback 'System Restore') -Status 'Passed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightRestoreEnabled' -Fallback 'Enabled for {0}') -f $env:SystemDrive) -Category 'System')
        }

        # CIM fallback: the SPP\Clients registry check can return null on newer Windows 11 builds
        # even when System Protection is already on.
        $srpEnabled = $false
        try
        {
            $srpStatus = Get-CimInstance -ClassName SystemRestoreConfig -Namespace 'root\default' -ErrorAction Stop
            if ($srpStatus -and $srpStatus.RPSessionInterval -eq 1) { $srpEnabled = $true }
        }
        catch { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.TestPreflightSystemRestore.LoadSrpStatus'; $srpEnabled = $false }

        if ($srpEnabled)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestore' -Fallback 'System Restore') -Status 'Passed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightRestoreEnabled' -Fallback 'Enabled for {0}') -f $env:SystemDrive) -Category 'System')
        }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestore' -Fallback 'System Restore') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightRestoreNotEnabled' -Fallback 'Not enabled for {0}') -f $env:SystemDrive) -Category 'System')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightSystemRestore:catch684' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestore' -Fallback 'System Restore') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightRestoreError' -Fallback 'Could not verify System Protection: {0}') -f $_.Exception.Message) -Category 'System')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightManagedPolicyEnvironment
{
    try
    {
        $domainJoined = $false
        try
        {
            $domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
        }
        catch
        {
            Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.TestPreflightManagedPolicyEnvironment.LoadDomainJoined'
            $domainJoined = $false
        }

        $policyPaths = @(
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System',
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
            'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
            'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
            'HKCU:\SOFTWARE\Policies\Microsoft\Windows\System',
            'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
        )

        $activePolicies = [System.Collections.Generic.List[string]]::new()
        foreach ($path in $policyPaths)
        {
            try
            {
                if (Test-Path -LiteralPath $path)
                {
                    [void]$activePolicies.Add($path)
                }
            }
            catch { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.TestPreflightManagedPolicyEnvironment.TestPathPolicy' }
        }

        if (-not $domainJoined -and $activePolicies.Count -eq 0)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePolicies' -Fallback 'Managed endpoint policy') -Key 'ManagedPolicyEnvironment' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightPoliciesPassed' -Fallback 'No domain join or active policy hives detected') -Category 'Security' -Details ([ordered]@{ DomainJoined = $domainJoined; ActivePolicyHives = @(); ConflictSignals = @() }))
        }

        $details = [System.Collections.Generic.List[string]]::new()
        $remediation = [System.Collections.Generic.List[string]]::new()
        $structuredRemediation = [System.Collections.Generic.List[string]]::new()
        if ($domainJoined)
        {
            [void]$details.Add('Domain joined')
            [void]$remediation.Add('Review the connected target with the remote console and confirm the GPO scope before applying changes.')
            [void]$structuredRemediation.Add('Confirm the target is in the expected OU and policy scope.')
            [void]$structuredRemediation.Add('Capture a gpresult report or equivalent policy summary for the endpoint.')
        }
        if ($activePolicies.Count -gt 0)
        {
            [void]$details.Add(('Active policy hives: {0}' -f ($activePolicies -join ', ')))
            [void]$remediation.Add('Export the relevant policy hives or document the enforced settings before a high-risk run.')
            [void]$structuredRemediation.Add('Export the listed policy hives and attach them to the support bundle.')
        }
        [void]$remediation.Add('Use the Troubleshooting Guide and support bundle if the result needs escalation.')
        [void]$structuredRemediation.Add('Generate an incident reproduction pack from the support bundle after any failed remediation attempt.')

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePolicies' -Fallback 'Managed endpoint policy') -Key 'ManagedPolicyEnvironment' -Status 'Warning' -Message (($details -join '; ') + '. ' + ($remediation -join ' ')) -Category 'Security' -RemediationActions @($structuredRemediation) -Details ([ordered]@{ DomainJoined = $domainJoined; ActivePolicyHives = @($activePolicies); ConflictSignals = @($details); RemediationActions = @($structuredRemediation) }))
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightManagedPolicyEnvironment:catch758' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePolicies' -Fallback 'Managed endpoint policy') -Key 'ManagedPolicyEnvironment' -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightPoliciesError' -Fallback 'Could not evaluate policy environment: {0}') -f $_.Exception.Message) -Category 'Security')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightPendingReboot
{
    try
    {
        $reasons = [System.Collections.Generic.List[string]]::new()

        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
        {
            [void]$reasons.Add('Component Based Servicing')
        }
        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\Auto Update\RebootRequired')
        {
            [void]$reasons.Add('Windows Update')
        }
        $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
        if ($sessionManager -and $sessionManager.PSObject.Properties['PendingFileRenameOperations'] -and $sessionManager.PendingFileRenameOperations) { [void]$reasons.Add('Pending file rename operations') }

        $windowsUpdateAutoUpdate = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -ErrorAction SilentlyContinue
        if ($windowsUpdateAutoUpdate -and $windowsUpdateAutoUpdate.PSObject.Properties['PostRebootReporting'] -and $windowsUpdateAutoUpdate.PostRebootReporting) { [void]$reasons.Add('Windows Update post-reboot reporting') }

        if ($reasons.Count -eq 0)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePendingReboot' -Fallback 'Pending reboot') -Key 'PendingReboot' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightPendingRebootClear' -Fallback 'No pending reboot detected') -Category 'System' -Details ([ordered]@{ PendingReasons = @() }))
        }

        $msg = ((Get-UxLocalizedString -Key 'GuiPreflightPendingRebootDetected' -Fallback 'Pending reboot: {0}. Restart before applying tweaks to avoid mid-run failures.') -f ($reasons -join '; '))
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePendingReboot' -Fallback 'Pending reboot') -Key 'PendingReboot' -Status 'Warning' -Message $msg -Category 'System' -RemediationActions @('Restart Windows before retrying.', 'Re-run preflight after reboot to confirm.') -Details ([ordered]@{ PendingReasons = @($reasons) }))
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightPendingReboot:catch796' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNamePendingReboot' -Fallback 'Pending reboot') -Key 'PendingReboot' -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightPendingRebootError' -Fallback 'Could not evaluate reboot state: {0}') -f $_.Exception.Message) -Category 'System')
    }
}

<#
    .SYNOPSIS
#>

function Test-PreflightWinRMReachability
{
    [CmdletBinding()]
    param (
        [string[]]$Targets = @()
    )

    if (-not $Targets -or $Targets.Count -eq 0)
    {
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightWinRMNoTargets' -Fallback 'No remote targets configured') -Category 'Services' -Details ([ordered]@{ TargetCount = 0; ReachableTargets = @(); UnreachableTargets = @(); ServiceStatus = $null }))
    }

    try
    {
        $svc = Get-Service -Name 'WinRM' -ErrorAction Stop
        if ($svc.Status -ne 'Running')
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightWinRMServiceStopped' -Fallback 'WinRM service is {0}; remote operations require it to be running.') -f $svc.Status) -Category 'Services' -RemediationActions @('Run: Start-Service WinRM', 'Run: Enable-PSRemoting -SkipNetworkProfileCheck -Force on each target.') -Details ([ordered]@{ TargetCount = @($Targets).Count; ReachableTargets = @(); UnreachableTargets = @($Targets); ServiceStatus = [string]$svc.Status }))
        }
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightWinRMReachability:catch826' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Failed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightWinRMQueryError' -Fallback 'Could not query WinRM service: {0}') -f $_.Exception.Message) -Category 'Services')
    }

    $unreachable = [System.Collections.Generic.List[string]]::new()
    $reachable = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $Targets)
    {
        if ([string]::IsNullOrWhiteSpace([string]$target)) { continue }
        try
        {
            Test-WSMan -ComputerName $target -ErrorAction Stop | Out-Null
            [void]$reachable.Add([string]$target)
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightWinRMReachability:catch841' -Severity Debug }

            [void]$unreachable.Add(('{0}: {1}' -f $target, $_.Exception.Message))
        }
    }

    if ($unreachable.Count -eq 0)
    {
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Passed' -Message ((Get-UxLocalizedString -Key 'GuiPreflightWinRMReachable' -Fallback '{0} target(s) reachable via WinRM') -f $Targets.Count) -Category 'Services' -Details ([ordered]@{ TargetCount = @($Targets).Count; ReachableTargets = @($Targets); UnreachableTargets = @(); PartialCoverage = $false; ServiceStatus = 'Running' }))
    }

    # Mixed reachability -> partial coverage warning, not an outright failure.
    if ($reachable.Count -gt 0)
    {
        $msgPartial = ((Get-UxLocalizedString -Key 'GuiPreflightWinRMPartialCoverage' -Fallback 'Partial WinRM coverage: {0} of {1} target(s) reachable. Unreachable: {2}') -f $reachable.Count, @($Targets).Count, ($unreachable -join ' | '))
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Warning' -Message $msgPartial -Category 'Services' -RemediationActions @('Confirm DNS resolution and routing for the unreachable target(s).', 'Scope the rollout to reachable targets or stage the unreachable ones separately.', 'Validate WinRM listeners and firewall rules on the unreachable target(s).') -Details ([ordered]@{ TargetCount = @($Targets).Count; ReachableTargets = @($reachable); UnreachableTargets = @($unreachable); PartialCoverage = $true; ServiceStatus = 'Running' }))
    }

    $msg = ((Get-UxLocalizedString -Key 'GuiPreflightWinRMUnreachable' -Fallback 'Unreachable target(s): {0}') -f ($unreachable -join ' | '))
    return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameWinRM' -Fallback 'WinRM reachability') -Key 'WinRMReachability' -Status 'Failed' -Message $msg -Category 'Services' -RemediationActions @('Verify network reachability and DNS resolution.', 'Confirm WinRM listeners (winrm e winrm/config/listener) on each target.', 'Check firewall: Enable-NetFirewallRule -DisplayGroup ''Windows Remote Management''.') -Details ([ordered]@{ TargetCount = @($Targets).Count; ReachableTargets = @(); UnreachableTargets = @($unreachable); PartialCoverage = $false; ServiceStatus = 'Running' }))
}

<#
    .SYNOPSIS
#>

function Test-PreflightRestorePointCreation
{
    try
    {
        $createCommand = Get-Command -Name 'CreateRestorePoint' -CommandType Function -ErrorAction SilentlyContinue
        if (-not $createCommand)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestorePoint' -Fallback 'Restore Point') -Status 'Warning' -Message (Get-UxLocalizedString -Key 'GuiPreflightRestorePointNotAvailable' -Fallback 'CreateRestorePoint function not available') -Category 'Recovery')
        }

        $created = [bool](& $createCommand)
        if ($created)
        {
            return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestorePoint' -Fallback 'Restore Point') -Status 'Passed' -Message (Get-UxLocalizedString -Key 'GuiPreflightRestorePointCreated' -Fallback 'Restore point created successfully') -Category 'Recovery')
        }
        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestorePoint' -Fallback 'Restore Point') -Status 'Warning' -Message (Get-UxLocalizedString -Key 'GuiPreflightRestorePointFalse' -Fallback 'Restore point creation returned false (System Protection may be disabled or insufficient disk space)') -Category 'Recovery')
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PreflightChecks.Test-PreflightRestorePointCreation:catch884' -Severity Debug }

        return (New-PreflightCheckResult -Name (Get-UxLocalizedString -Key 'GuiPreflightNameRestorePoint' -Fallback 'Restore Point') -Status 'Warning' -Message ((Get-UxLocalizedString -Key 'GuiPreflightRestorePointError' -Fallback 'Restore point creation failed: {0}') -f $_.Exception.Message) -Category 'Recovery')
    }
}

<#
    .SYNOPSIS
#>

function Invoke-PreflightChecks
{
    <#
    .SYNOPSIS
        Runs all pre-flight validation checks before execution begins.
    .DESCRIPTION
        Returns an object with Passed (bool), CriticalFailures (array),
        Warnings (array), and AllResults (array of check results).
        Also attempts to create a restore point as part of pre-flight.
    #>
    [CmdletBinding()]
    param (
        [string[]]$RemoteTargets = @()
    )

    if (Get-Command -Name 'Test-IsDesignModeUX' -CommandType Function -ErrorAction SilentlyContinue)
    {
        if (Test-IsDesignModeUX)
        {
            return [pscustomobject]@{
                Passed                              = $true
                Status                              = 'Passed'
                CriticalFailures                    = @()
                Warnings                            = @()
                AllResults                          = @()
                WinRMReachability                   = $null
                Credentials                         = $null
                PolicyConflictSignals               = $null
                HostIntegrity                       = $null
                RiskCategories                      = @()
                SupportedEnvironmentClassification  = $null
            }
        }
    }

    $allResults = @(
        Test-PreflightAdminElevation
        Test-PreflightDiskSpace
        Test-PreflightVSS
        Test-PreflightEventLog
        Test-PreflightWMI
        Test-PreflightSystemRestore
        Test-PreflightManagedPolicyEnvironment
        Test-PreflightPendingReboot
        Test-PreflightWinRMReachability -Targets $RemoteTargets
        Test-PreflightHostTaint
    )

    $criticalFailures = @($allResults | Where-Object { $_.Status -eq 'Failed' })
    $warnings = @($allResults | Where-Object { $_.Status -eq 'Warning' })
    $passed = ($criticalFailures.Count -eq 0) -and ($warnings.Count -eq 0)
    $contract = Get-BaselinePreflightContract -Results $allResults

    [pscustomobject]@{
        Passed           = $passed
        Status           = if ($criticalFailures.Count -gt 0) { 'Failed' } elseif ($warnings.Count -gt 0) { 'Warning' } else { 'Passed' }
        CriticalFailures = $criticalFailures
        Warnings         = $warnings
        AllResults       = $allResults
        WinRMReachability = $contract.WinRMReachability
        Credentials       = $contract.Credentials
        PolicyConflictSignals = $contract.PolicyConflictSignals
        HostIntegrity    = $contract.HostIntegrity
        RiskCategories    = @($contract.RiskCategories)
        SupportedEnvironmentClassification = $contract.SupportedEnvironmentClassification
    }
}

<#
    .SYNOPSIS
#>

function Show-PreflightResultsDialog
{
    <#
    .SYNOPSIS
        Displays pre-flight check results and returns the user's choice.
    .DESCRIPTION
        If all passed, returns 'Continue'. If critical failures exist, shows dialog
        with only 'Cancel'. If warnings only, shows 'Cancel' and 'Run Anyway'.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Results
    )

    if ($Results.Passed)
    {
        return 'Continue'
    }

    # Build the formatted message
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add((Get-UxLocalizedString -Key 'GuiPreflightResultsHeading' -Fallback 'Pre-flight check results:'))
    $lines.Add('')

    if ($Results.SupportedEnvironmentClassification -and $Results.SupportedEnvironmentClassification.Summary)
    {
        $lines.Add($Results.SupportedEnvironmentClassification.Summary)
    }
    if ($Results.WinRMReachability -and $Results.WinRMReachability.Summary)
    {
        $lines.Add(('WinRM reachability: {0}' -f $Results.WinRMReachability.Summary))
    }
    if ($Results.PolicyConflictSignals -and $Results.PolicyConflictSignals.Summary)
    {
        $lines.Add(('Policy signals: {0}' -f $Results.PolicyConflictSignals.Summary))
    }

    $categories = @()
    if ($Results.PSObject.Properties['RiskCategories'] -and $Results.RiskCategories)
    {
        $categories = @($Results.RiskCategories | Where-Object { $_ -and [string]$_.Status -ne 'Passed' })
    }
    elseif ($Results.PolicyConflictSignals -and $Results.PolicyConflictSignals.PSObject.Properties['Categories'])
    {
        $categories = @($Results.PolicyConflictSignals.Categories | Where-Object { $_ -and [string]$_.Status -ne 'Passed' })
    }
    if ($categories.Count -gt 0)
    {
        $lines.Add('')
        $lines.Add((Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryHeading' -Fallback 'Risk categories:'))
        foreach ($cat in $categories)
        {
            $marker = if ([string]$cat.Status -eq 'Failed') { [char]0x2717 } else { [char]0x26A0 }
            $lines.Add(('{0} {1}: {2}' -f $marker, $cat.Name, $cat.Summary))
            if ($cat.RemediationActions -and @($cat.RemediationActions).Count -gt 0)
            {
                foreach ($action in $cat.RemediationActions)
                {
                    if (-not [string]::IsNullOrWhiteSpace([string]$action))
                    {
                        $lines.Add(('    ' + [char]0x2192 + ' {0}' -f [string]$action))
                    }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$cat.DocumentationPath))
            {
                $docLabel = Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryDocsLabel' -Fallback 'Remediation guide'
                $lines.Add(('    {0}: {1}' -f $docLabel, [string]$cat.DocumentationPath))
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$cat.LogHint))
            {
                $logLabel = Get-UxLocalizedString -Key 'GuiPreflightRiskCategoryLogsLabel' -Fallback 'Logs'
                $lines.Add(('    {0}: {1}' -f $logLabel, [string]$cat.LogHint))
            }
        }
    }

    if ($lines.Count -gt 2)
    {
        $lines.Add('')
    }

    $passedLabel = Get-UxLocalizedString -Key 'GuiPreflightStatusPassed' -Fallback 'Passed'
    $adminPassedMsg = Get-UxLocalizedString -Key 'GuiPreflightAdminPassed' -Fallback 'Running as administrator'
    $wmiPassedMsg = Get-UxLocalizedString -Key 'GuiPreflightWMIPassed' -Fallback 'CIM/WMI responding'
    $serviceRunningMsg = Get-UxLocalizedString -Key 'GuiPreflightServiceRunning' -Fallback 'Service is running'

    foreach ($check in $Results.AllResults)
    {
        switch ($check.Status)
        {
            'Passed'
            {
                $detailSuffix = ''
                # Include detail for disk space even on pass
                if ($check.Message -and $check.Message -ne $adminPassedMsg -and
                    $check.Message -ne $wmiPassedMsg -and $check.Message -ne $serviceRunningMsg)
                {
                    $detailSuffix = " ($($check.Message))"
                }
                $lines.Add([char]0x2713 + " $($check.Name): $passedLabel$detailSuffix")
            }
            'Failed'
            {
                $lines.Add([char]0x2717 + " $($check.Name): $($check.Message)")
            }
            'Warning'
            {
                $lines.Add([char]0x26A0 + " $($check.Name): $($check.Message)")
            }
        }
    }

    $issueCount = $Results.CriticalFailures.Count + $Results.Warnings.Count
    $lines.Add('')

    if ($Results.CriticalFailures.Count -gt 0)
    {
        $lines.Add((Get-UxLocalizedString -Key 'GuiPreflightMustResolve' -Fallback '{0} issue(s) must be resolved before continuing.') -f $issueCount)
    }
    else
    {
        $lines.Add((Get-UxLocalizedString -Key 'GuiPreflightRequiresAttention' -Fallback '{0} issue(s) requires attention before continuing.') -f $issueCount)
    }

    $message = $lines -join "`n"
    $dialogTitle = Get-UxLocalizedString -Key 'GuiPreflightDialogTitle' -Fallback 'Pre-flight Checks'
    $cancelLabel = Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel'
    $continueAnywayLabel = Get-UxLocalizedString -Key 'GuiPreflightContinueAnyway' -Fallback 'Run Anyway'

    if ($Results.CriticalFailures.Count -gt 0)
    {
        Show-ThemedDialog -Title $dialogTitle -Message $message -Buttons @($cancelLabel)
        return 'Cancel'
    }

    # Warnings only - allow the user to continue
    $choice = Show-ThemedDialog -Title $dialogTitle -Message $message -Buttons @($cancelLabel, $continueAnywayLabel) -DestructiveButton $continueAnywayLabel
    return $choice
}
