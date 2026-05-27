# Operator policy safeguards for multi-target / production rollouts.
#
# These are the "guard rails" that sit between the operator console and the
# remote execution helpers. Each safeguard returns a structured decision
# (Allow / Block / Confirm) so the calling UI can surface a consistent
# explanation to the operator.

<#
    .SYNOPSIS
#>

function New-BaselineOperatorPolicy
{
	<#
		.SYNOPSIS
		Builds a default operator policy with conservative limits. The policy
		is a plain PSObject so it can be serialised, edited, and audited.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[int]$MaxTargetsPerRun = 25,
		[int]$MaxConcurrentTargets = 5,
		[string[]]$DeniedFunctions = @(),
		[string[]]$DeniedTargets = @(),
		[string[]]$AllowedTargets = @(),
		[hashtable]$ChangeWindow = @{}
	)

	[pscustomobject]@{
		MaxTargetsPerRun     = $MaxTargetsPerRun
		MaxConcurrentTargets = $MaxConcurrentTargets
		DeniedFunctions      = @($DeniedFunctions)
		DeniedTargets        = @($DeniedTargets)
		AllowedTargets       = @($AllowedTargets)
		ChangeWindow         = $ChangeWindow
		KillSwitchPath       = (Join-Path ([System.IO.Path]::GetTempPath()) 'BASELINE_KILL_SWITCH')
		CreatedAt            = [DateTimeOffset]::UtcNow
	}
}

<#
    .SYNOPSIS
#>

function Test-BaselineOperatorChangeWindow
{
	<#
		.SYNOPSIS
		Returns $true if the current local time falls inside the configured
		change window. An empty window is treated as "always allowed".
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$ChangeWindow
	)

	if (-not $ChangeWindow -or $ChangeWindow.Count -eq 0) { return $true }

	$now = [DateTime]::Now
	$dayOk = $true
	if ($ChangeWindow.ContainsKey('Days') -and @($ChangeWindow['Days']).Count -gt 0)
	{
		$dayOk = @($ChangeWindow['Days']) -contains $now.DayOfWeek.ToString()
	}

	$timeOk = $true
	if ($ChangeWindow.ContainsKey('StartTime') -and $ChangeWindow.ContainsKey('EndTime'))
	{
		try
		{
			$start = [TimeSpan]::Parse([string]$ChangeWindow['StartTime'])
			$end   = [TimeSpan]::Parse([string]$ChangeWindow['EndTime'])
			$cur   = $now.TimeOfDay
			if ($end -gt $start)
			{
				$timeOk = ($cur -ge $start -and $cur -le $end)
			}
			else
			{
				$timeOk = ($cur -ge $start -or $cur -le $end)
			}
		}
		catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'OperatorPolicy.Helpers.Test-BaselineOperatorChangeWindow:catch86' -Severity Debug }
		 $timeOk = $true }
	}

	return ($dayOk -and $timeOk)
}

<#
    .SYNOPSIS
#>

function Test-BaselineKillSwitch
{
	<# .SYNOPSIS Returns $true if the operator-defined kill switch file exists. #>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)
}

function Invoke-BaselineKillSwitch
{
	<#
		.SYNOPSIS
		Engages the kill switch by writing a sentinel file. Subsequent
		Test-BaselineOperatorRunPolicy calls will block until the file is
		removed (Clear-BaselineKillSwitch).
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[string]$Reason = 'manual'
	)

	$payload = [ordered]@{
		EngagedAt = [DateTimeOffset]::UtcNow.ToString('o')
		Reason    = $Reason
		User      = $env:USERNAME
	}
	$json = ConvertTo-Json -InputObject $payload -Depth 6
	[System.IO.File]::WriteAllText($Path, $json)
}

<#
    .SYNOPSIS
#>

function Clear-BaselineKillSwitch
{
	<# .SYNOPSIS Removes the kill switch sentinel. #>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)
	if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
}

function Test-BaselineOperatorRunPolicy
{
	<#
		.SYNOPSIS
		Evaluates a planned run against an operator policy and returns a
		structured decision: Decision (Allow|Block|Confirm), Reasons (string[]),
		ApprovedTargets (string[]), BlockedTargets (string[]).
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Policy,

		[Parameter(Mandatory = $true)]
		[string[]]$Targets,

		[string[]]$Functions = @(),

		[ValidateSet('RemoteApply', 'RemoteCompliance', 'ConnectivityTest', 'Unknown')]
		[string]$EnterpriseAction = 'Unknown',

		[switch]$Apply
	)

	$reasons = [System.Collections.Generic.List[string]]::new()
	$blocked = [System.Collections.Generic.List[string]]::new()
	$approved = [System.Collections.Generic.List[string]]::new()
	$decision = 'Allow'

	if (Test-BaselineKillSwitch -Path $Policy.KillSwitchPath)
	{
		[void]$reasons.Add('Kill switch is engaged. Run blocked until cleared.')
		$decision = 'Block'
	}

	if (Get-Command -Name 'Test-BaselineEnterpriseActionMaturityGate' -ErrorAction SilentlyContinue)
	{
		$featureName = if ($EnterpriseAction -ne 'Unknown') { $EnterpriseAction } elseif ($Apply) { 'RemoteApply' } else { 'RemoteCompliance' }
		try
		{
			$maturityGate = Test-BaselineEnterpriseActionMaturityGate -FeatureName $featureName
			if ($maturityGate -and -not [bool]$maturityGate.Allowed)
			{
				[void]$reasons.Add(('Maturity gate blocked {0}: current={1}, required={2}.' -f $featureName, [string]$maturityGate.CurrentMaturity, [string]$maturityGate.RequiredMaturity))
				$decision = 'Block'
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'OperatorPolicy.Helpers.Test-BaselineOperatorRunPolicy:catch198' -Severity Debug }

			[void]$reasons.Add(('Maturity gate evaluation failed for {0}: {1}' -f $featureName, $_.Exception.Message))
			if ($decision -ne 'Block') { $decision = 'Confirm' }
		}
	}

	if (-not (Test-BaselineOperatorChangeWindow -ChangeWindow $Policy.ChangeWindow))
	{
		[void]$reasons.Add('Current time is outside the configured change window.')
		if ($decision -ne 'Block') { $decision = 'Confirm' }
	}

	if ($Targets.Count -gt $Policy.MaxTargetsPerRun)
	{
		[void]$reasons.Add(("Target count {0} exceeds the per-run cap of {1}." -f $Targets.Count, $Policy.MaxTargetsPerRun))
		$decision = 'Block'
	}

	$deniedFunctionsHit = @()
	foreach ($fn in $Functions)
	{
		if ($Policy.DeniedFunctions -contains $fn) { $deniedFunctionsHit += $fn }
	}
	if ($deniedFunctionsHit.Count -gt 0)
	{
		[void]$reasons.Add(("Function(s) on the deny list: {0}" -f ($deniedFunctionsHit -join ', ')))
		$decision = 'Block'
	}

	foreach ($target in $Targets)
	{
		$isAllowedExplicit = ($Policy.AllowedTargets.Count -eq 0) -or ($Policy.AllowedTargets -contains $target)
		$isDenied = ($Policy.DeniedTargets -contains $target)

		if ($isDenied)
		{
			[void]$blocked.Add($target)
		}
		elseif (-not $isAllowedExplicit)
		{
			[void]$blocked.Add($target)
		}
		else
		{
			[void]$approved.Add($target)
		}
	}

	if ($blocked.Count -gt 0 -and $decision -eq 'Allow')
	{
		[void]$reasons.Add(("Blocked target(s): {0}" -f ($blocked -join ', ')))
		$decision = 'Confirm'
	}

	if ($Apply -and $approved.Count -gt 1 -and $decision -eq 'Allow')
	{
		[void]$reasons.Add('Multi-target apply requires operator confirmation.')
		$decision = 'Confirm'
	}

	[pscustomobject]@{
		Decision            = $decision
		Reasons             = $reasons.ToArray()
		ApprovedTargets     = $approved.ToArray()
		BlockedTargets      = $blocked.ToArray()
		MaxConcurrentTargets= $Policy.MaxConcurrentTargets
		EvaluatedAt         = [DateTimeOffset]::UtcNow
	}
}

<#
    .SYNOPSIS
#>

function Format-BaselineOperatorPolicyDecision
{
	<# .SYNOPSIS Renders a Test-BaselineOperatorRunPolicy result as text. #>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Decision
	)

	$sb = [System.Text.StringBuilder]::new()
	[void]$sb.AppendLine(("Decision: {0}" -f $Decision.Decision))
	if ($Decision.Reasons.Count -gt 0)
	{
		[void]$sb.AppendLine('Reasons:')
		foreach ($r in $Decision.Reasons) { [void]$sb.AppendLine(("  - {0}" -f $r)) }
	}
	if ($Decision.ApprovedTargets.Count -gt 0)
	{
		[void]$sb.AppendLine(("Approved targets ({0}): {1}" -f $Decision.ApprovedTargets.Count, ($Decision.ApprovedTargets -join ', ')))
	}
	if ($Decision.BlockedTargets.Count -gt 0)
	{
		[void]$sb.AppendLine(("Blocked targets ({0}): {1}" -f $Decision.BlockedTargets.Count, ($Decision.BlockedTargets -join ', ')))
	}
	[void]$sb.AppendLine(("Concurrency cap: {0}" -f $Decision.MaxConcurrentTargets))
	return $sb.ToString()
}
