# Shared helper slice for Baseline -- error handling, classification, and user-facing error info.

function Remove-HandledErrorRecord
{
	<#
	.SYNOPSIS
	Removes a handled error from $Global:Error to keep execution summary clean.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)

	if (($null -eq $Global:Error) -or $Global:Error.Count -eq 0)
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
	<#
	.SYNOPSIS
	Tests whether an error message matches known ignorable patterns.
	#>
	param
	(
		[Parameter(Mandatory = $false)]
		[string]
		$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return $true }

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
		'|\".*\" was skipped because a required component is not available on this system\.' +
		'|No MSFT_ScheduledTask objects found with property ''TaskName'' equal to ''Disable LockScreen''' +
		'|A key in this path already exists\.' +
		'|You must specify an object for the Get-Member cmdlet' +
		'|Cannot bind argument to parameter .InputObject. because it is null' +
		'|The property .* cannot be found on this object' +
		'|The parameter is incorrect' +
		'|Unknown error \(0x' +
		'|Safe handle has been closed' +
		'|command that prompts the user failed because the host program' +
		'|Access is denied\.' +
		'|Security error\.' +
		'|The system cannot find the path specified\.' +
		'|The system cannot find the file specified\.'
	))
}

function Test-IgnorableErrorRecord
{
	<#
	.SYNOPSIS
	Tests whether an error record's exception message is ignorable.
	#>
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
	<#
	.SYNOPSIS
	Returns new non-ignorable error records added to $Global:Error since a baseline count.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[int]
		$BaselineCount
	)

	if (($null -eq $Global:Error) -or $Global:Error.Count -eq 0)
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
	# Temporarily suppresses progress bars (e.g. Invoke-WebRequest) by setting
	# $global:ProgressPreference. Uses global scope because PowerShell preference
	# variables must be set in the calling scope for cmdlets to observe them.
	# Note: background jobs started during $ScriptBlock inherit the silenced
	# preference; this is acceptable since Baseline only uses this synchronously.
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

function Get-BaselineErrorCatalog
{
	<#
	.SYNOPSIS
	Returns the catalog of Baseline error codes and user-friendly messages.
	#>
	return @{
		'GUI-STARTUP-001' = [pscustomobject]@{
			Title = "Baseline Couldn't Start"
			Message = 'Baseline could not finish starting one of the components it needs.'
			NextSteps = @(
				'Close Baseline and open it again.'
				'If this keeps happening, make sure the full Baseline folder is extracted and intact.'
				'Check the log file below for the failing step.'
			)
		}
		'GUI-STARTUP-002' = [pscustomobject]@{
			Title = "Baseline Couldn't Save Startup Settings"
			Message = 'Baseline could not determine where to store its startup settings.'
			NextSteps = @(
				'Move Baseline to a normal writable folder such as Desktop or Documents, then try again.'
				'Make sure you are not running it from inside a ZIP file or a temporary extraction view.'
				'Check the log file below if you need to see the exact failing path.'
			)
		}
		'GUI-STARTUP-003' = [pscustomobject]@{
			Title = "Baseline Couldn't Finish Setup"
			Message = 'Baseline hit a problem while preparing its first-run welcome experience.'
			NextSteps = @(
				'Close Baseline and open it again.'
				'If the problem keeps happening, make sure all Baseline files came from the same release and were extracted together.'
				'Use the log file below to see which startup step failed.'
			)
		}
		'GUI-STARTUP-004' = [pscustomobject]@{
			Title = 'Baseline Installation Looks Incomplete'
			Message = 'Baseline could not find one of the commands it needs during startup.'
			NextSteps = @(
				'Re-extract or re-download the full Baseline release.'
				'Make sure files from different versions are not mixed together in the same folder.'
				'After replacing the files, start Baseline again.'
			)
		}
		'GUI-STARTUP-005' = [pscustomobject]@{
			Title = "Baseline Couldn't Read Required Startup Data"
			Message = 'Baseline ran into missing or empty startup data while opening the app.'
			NextSteps = @(
				'Close Baseline and try again once.'
				'If it happens again, re-extract the release so all included data files are present.'
				'Review the log file below for the exact item that was missing.'
			)
		}
		'GUI-GENERIC-001' = [pscustomobject]@{
			Title = 'Baseline Hit a Problem'
			Message = 'Baseline ran into an unexpected problem.'
			NextSteps = @(
				'Close this message and try the action again.'
				'If the same error comes back, restart Baseline.'
				'Use the log file below if you need more detail.'
			)
		}
	}
}

function Get-BaselineExceptionMessageChain
{
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Exception]
		$Exception
	)

	$messages = [System.Collections.Generic.List[string]]::new()
	$currentException = $Exception
	$depth = 0

	while ($currentException -and $depth -lt 10)
	{
		$currentMessage = $null
		try { $currentMessage = [string]$currentException.Message } catch { $currentMessage = $null }

		if (-not [string]::IsNullOrWhiteSpace($currentMessage))
		{
			$alreadyAdded = $false
			foreach ($existingMessage in $messages)
			{
				if ($existingMessage -eq $currentMessage)
				{
					$alreadyAdded = $true
					break
				}
			}

			if (-not $alreadyAdded)
			{
				[void]$messages.Add($currentMessage)
			}
		}

		try { $currentException = $currentException.InnerException } catch { $currentException = $null }
		$depth++
	}

	return ($messages -join [Environment]::NewLine)
}

function Resolve-BaselineErrorCode
{
	<#
	.SYNOPSIS
	Maps an exception to a Baseline error code by matching the exception message chain.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Exception]
		$Exception,

		[string]
		$Context = ''
	)

	$messageChain = Get-BaselineExceptionMessageChain -Exception $Exception

	switch -Wildcard ($messageChain)
	{
		'*Get-GuiFirstRunWelcomeMarkerPath returned an empty path*' { return 'GUI-STARTUP-002' }
		'*First-run marker directory could not be derived from path*' { return 'GUI-STARTUP-002' }
		'*Captured first-run marker path is empty*' { return 'GUI-STARTUP-002' }
		'*Show-ThemedDialog did not resolve to a scriptblock*' { return 'GUI-STARTUP-003' }
		'*Show-FirstRunWelcomeDialog did not resolve to a scriptblock*' { return 'GUI-STARTUP-003' }
		'*Complete-GuiFirstRunWelcome did not resolve to a scriptblock*' { return 'GUI-STARTUP-003' }
		'*Close-LoadingSplashWindow did not resolve to a scriptblock*' { return 'GUI-STARTUP-003' }
		'*Hide-ConsoleWindow did not resolve to a scriptblock*' { return 'GUI-STARTUP-003' }
		'*First-run welcome failed*' { return 'GUI-STARTUP-003' }
		"*The expression after '&' in a pipeline element produced an object that was not valid*" { return 'GUI-STARTUP-003' }
		'*Set-GuiPresetSelection not found*' { return 'GUI-STARTUP-004' }
		'*Set-GuiStatusText not found*' { return 'GUI-STARTUP-004' }
		'*Get-UxRecommendedPresetName not found*' { return 'GUI-STARTUP-004' }
		'*Get-UxFirstRunWelcomeMessage not found*' { return 'GUI-STARTUP-004' }
		'*Get-GuiFirstRunWelcomeMarkerPath not found*' { return 'GUI-STARTUP-004' }
		'*Show-HelpDialog not found*' { return 'GUI-STARTUP-004' }
		'*Show-ThemedDialog not found*' { return 'GUI-STARTUP-004' }
		'*Show-FirstRunWelcomeDialog not found*' { return 'GUI-STARTUP-004' }
		'*Close-LoadingSplashWindow not found*' { return 'GUI-STARTUP-004' }
		'*Hide-ConsoleWindow not found*' { return 'GUI-STARTUP-004' }
		'*not recognized as the name of a cmdlet*' { return 'GUI-STARTUP-004' }
		'*Cannot index into a null array*' { return 'GUI-STARTUP-005' }
		'*Cannot bind argument to parameter*because it is null*' { return 'GUI-STARTUP-005' }
		'*You cannot call a method on a null-valued expression*' { return 'GUI-STARTUP-005' }
	}

	if ($Context -like '*Startup*' -or $Context -like '*GUI construction*' -or $Context -like '*GUI module import*')
	{
		return 'GUI-STARTUP-001'
	}

	return 'GUI-GENERIC-001'
}

function Resolve-BaselineErrorStageDescription
{
	<#
	.SYNOPSIS
	Converts an internal error context into short user-facing wording.
	#>
	param (
		[string]$Context = ''
	)

	if ([string]::IsNullOrWhiteSpace($Context))
	{
		return $null
	}

	switch -Wildcard ($Context)
	{
		'*GUI startup*' { return 'while starting the app.' }
		'*GUI module import*' { return 'while loading the GUI files.' }
		'*GUI construction*' { return 'while opening the main window.' }
		'*First-run*' { return 'while preparing the first-run experience.' }
		'*InitialTabBuild*' { return 'while preparing the first tab.' }
		'*SelectionChanged*' { return 'while changing tabs.' }
		'*Build-TabContent*' { return 'while rendering the current view.' }
		'*Preview*' { return 'while preparing the preview.' }
		'*Run*' { return 'while preparing or running the selected actions.' }
		default { return $null }
	}
}

function Get-BaselineErrorInfo
{
	<#
	.SYNOPSIS
	Resolves an exception to a structured error info object with code, title, and message.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Exception]
		$Exception,

		[string]
		$Context = 'GUI'
	)

	$catalog = Get-BaselineErrorCatalog
	$errorCode = Resolve-BaselineErrorCode -Exception $Exception -Context $Context
	$catalogEntry = if ($catalog.ContainsKey($errorCode)) { $catalog[$errorCode] } else { $catalog['GUI-GENERIC-001'] }
	$errorTitle = if ($catalogEntry -and $catalogEntry.PSObject.Properties['Title']) { [string]$catalogEntry.Title } else { 'Baseline Hit a Problem' }
	$errorMessage = if ($catalogEntry -and $catalogEntry.PSObject.Properties['Message']) { [string]$catalogEntry.Message } else { 'Baseline ran into an unexpected problem.' }
	$nextSteps = @()
	if ($catalogEntry -and $catalogEntry.PSObject.Properties['NextSteps'])
	{
		$nextSteps = @($catalogEntry.NextSteps | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
	}
	$stageDescription = Resolve-BaselineErrorStageDescription -Context $Context

	return [pscustomobject]@{
		Code = $errorCode
		Context = $Context
		StageDescription = $stageDescription
		NextSteps = $nextSteps
		Message = $errorMessage
		Title = $errorTitle
	}
}

function Format-BaselineErrorDialogMessage
{
	<#
	.SYNOPSIS
	Formats error info into a human-readable dialog message with guidance and reference info.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[object]
		$ErrorInfo,

		[string]
		$LogPath,

		[switch]
		$IncludeLogPath
	)

	$messageLines = [System.Collections.Generic.List[string]]::new()
	$friendlyMessage = if ($ErrorInfo -and $ErrorInfo.PSObject.Properties['Message']) { [string]$ErrorInfo.Message } else { 'Baseline ran into an unexpected problem.' }
	$errorCode = if ($ErrorInfo -and $ErrorInfo.PSObject.Properties['Code']) { [string]$ErrorInfo.Code } else { 'GUI-GENERIC-001' }
	$stageDescription = if ($ErrorInfo -and $ErrorInfo.PSObject.Properties['StageDescription']) { [string]$ErrorInfo.StageDescription } else { $null }
	$nextSteps = if ($ErrorInfo -and $ErrorInfo.PSObject.Properties['NextSteps']) { @($ErrorInfo.NextSteps | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) } else { @() }

	[void]$messageLines.Add($friendlyMessage)

	if (-not [string]::IsNullOrWhiteSpace($stageDescription))
	{
		[void]$messageLines.Add('')
		[void]$messageLines.Add(("This happened {0}" -f $stageDescription))
	}

	if ($nextSteps.Count -gt 0)
	{
		[void]$messageLines.Add('')
		[void]$messageLines.Add('Try this:')
		foreach ($nextStep in $nextSteps)
		{
			[void]$messageLines.Add(("- {0}" -f [string]$nextStep))
		}
	}

	if (-not [string]::IsNullOrWhiteSpace($errorCode))
	{
		[void]$messageLines.Add('')
		[void]$messageLines.Add("Reference: $errorCode")
	}

	if ($IncludeLogPath -and -not [string]::IsNullOrWhiteSpace($LogPath))
	{
		[void]$messageLines.Add('')
		[void]$messageLines.Add('Log file:')
		[void]$messageLines.Add($LogPath)
	}

	return ($messageLines -join [Environment]::NewLine)
}
