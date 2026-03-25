# Shared helper slice for Baseline.

function Remove-HandledErrorRecord
{
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)

	if (-not $Global:Error)
	{
		return
	}

	for ($Index = $Global:Error.Count - 1; $Index -ge 0; $Index--)
	{
		$Candidate = $Global:Error[$Index]
		if ($null -eq $Candidate)
		{
			continue
		}

		$SameType = $Candidate.Exception.GetType().FullName -eq $ErrorRecord.Exception.GetType().FullName
		$SameMessage = $Candidate.Exception.Message -eq $ErrorRecord.Exception.Message
		$SamePath = $Candidate.InvocationInfo.PSCommandPath -eq $ErrorRecord.InvocationInfo.PSCommandPath
		$SameLine = $Candidate.InvocationInfo.ScriptLineNumber -eq $ErrorRecord.InvocationInfo.ScriptLineNumber

		if ($SameType -and $SameMessage -and $SamePath -and $SameLine)
		{
			$Global:Error.RemoveAt($Index)
		}
	}
}

function Test-IgnorableErrorMessage
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Message
	)

	return ($Message -match (
		'Property .* does not exist' +
		'|Cannot find path' +
		'|Cannot find a process with the name' +
		'|The process \".*\" not found' +
		'|The operation completed successfully\.' +
		'|The system was unable to find the specified registry key or value\.' +
		'|The registry key at the specified path does not exist\.' +
		'|Cannot find any service with service name' +
		'|No package found for ''Microsoft Edge' +
		'|Function \".*\" skipped\.' +
		'|No MSFT_ScheduledTask objects found with property ''TaskName'' equal to ''Disable LockScreen''' +
		'|A key in this path already exists\.' +
		'|Access is denied\.' +
		'|You must specify an object for the Get-Member cmdlet' +
		'|Cannot bind argument to parameter .InputObject. because it is null' +
		'|The property .* cannot be found on this object' +
		'|The parameter is incorrect' +
		'|Security error\.' +
		'|Unknown error \(0x'
	))
}

function Test-IgnorableErrorRecord
{
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)

	if (-not $ErrorRecord -or -not $ErrorRecord.Exception)
	{
		return $false
	}

	return Test-IgnorableErrorMessage -Message $ErrorRecord.Exception.Message
}

function Get-NewUnhandledErrorRecords
{
	param
	(
		[Parameter(Mandatory = $true)]
		[int]
		$BaselineCount
	)

	if (-not $Global:Error)
	{
		return @()
	}

	$currentCount = $Global:Error.Count
	if ($currentCount -le $BaselineCount)
	{
		return @()
	}

	$newCount = $currentCount - $BaselineCount
	$records = [System.Collections.Generic.List[object]]::new()

	for ($Index = 0; $Index -lt $newCount; $Index++)
	{
		$record = $Global:Error[$Index]
		if ($null -eq $record)
		{
			continue
		}

		if (-not (Test-IgnorableErrorRecord -ErrorRecord $record))
		{
			$records.Add($record) | Out-Null
		}
	}

	return $records
}

function Invoke-SilencedProgress
{
	param
	(
		[Parameter(Mandatory = $true)]
		[scriptblock]
		$ScriptBlock
	)

	$previousProgressPreference = $global:ProgressPreference
	try
	{
		$global:ProgressPreference = 'SilentlyContinue'
		& $ScriptBlock
	}
	finally
	{
		$global:ProgressPreference = $previousProgressPreference
	}
}
