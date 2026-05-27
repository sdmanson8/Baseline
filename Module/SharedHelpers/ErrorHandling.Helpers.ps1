# Shared helpers for Baseline -- error handling, classification, and user-facing error info.

<#
    .SYNOPSIS
#>

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

<#
    .SYNOPSIS
#>

function Test-IgnorableErrorMessage
{
	<#
	.SYNOPSIS
	Tests whether an error message matches known ignorable patterns.

	.DESCRIPTION
	Each pattern below is annotated with its provenance and the failure mode it
	protects against. Patterns were collected empirically across Win 10/11 SKUs
	while running tweak regions; new entries should keep the same documentation
	style so the rule list does not become an undocumented allowlist.
	#>
	param
	(
		[Parameter(Mandatory = $false)]
		[string]
		$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

	$ignorablePatterns = @(
		# Why: Service/process kill helpers run unconditionally; absence of the target
		# means the tweak's goal (process not running) is already satisfied.
		'Cannot find a process with the name'
		'The process \".*\" not found'

		# Why: Win32 APIs return success-coded exceptions when no work was needed
		# (e.g. service already in desired state).
		'The operation completed successfully\.'

		# Why: Registry tweaks address keys that may not exist on every SKU; missing
		# means the policy is already at default and no change is required.
		'The system was unable to find the specified registry key or value\.'
		'The registry key at the specified path does not exist\.'

		# Why: Service-name lookups for SKU-specific services (e.g. Xbox, Maps) fail
		# cleanly on SKUs where the service is not installed.
		'Cannot find any service with service name'

		# Why: Edge removal path is intentionally tolerant — Microsoft has shipped
		# multiple Edge package layouts; missing package on this SKU is benign.
		'No package found for ''Microsoft Edge'

		# Why: Tweak orchestrator emits these after deciding a tweak is not applicable
		# (e.g. wrong SKU). Skips are an intended outcome, not a failure.
		'Function \".*\" skipped\.'
		'\".*\" was skipped because a required component is not available on this system\.'

		# Why: Specific scheduled-task lookup that fails on SKUs where the task was
		# never created — observed during Disable LockScreen tweak on Pro builds.
		'No MSFT_ScheduledTask objects found with property ''TaskName'' equal to ''Disable LockScreen'''

		# Why: New-Item over an existing registry key emits this; idempotent re-runs
		# are expected behaviour for our tweaks.
		'A key in this path already exists\.'

		# Why: Disposed runspace handles surface this on cleanup paths; not a tweak
		# failure, just late teardown.
		'Safe handle has been closed'

		# Why: Custom non-interactive PSHost rejects prompts. Tweaks that try to prompt
		# are intentionally short-circuited; we surface them via dedicated logs, not
		# the error stream.
		'command that prompts the user failed because the host program'

	)

	$combinedPattern = ($ignorablePatterns -join '|')
	return ($Message -match $combinedPattern)
}

<#
    .SYNOPSIS
#>

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

	$targetText = if ($null -ne $ErrorRecord.TargetObject) { [string]$ErrorRecord.TargetObject } else { '' }
	$messageText = [string]$ErrorRecord.Exception.Message
	$registryPrefixes = @(
		'HKLM:\',
		'HKCU:\',
		'HKCR:\',
		'HKU:\',
		'HKCC:\',
		'HKEY_LOCAL_MACHINE\',
		'HKEY_CURRENT_USER\',
		'HKEY_CLASSES_ROOT\',
		'HKEY_USERS\',
		'HKEY_CURRENT_CONFIG\'
	)
	$registryAbsence = $false
	foreach ($registryPrefix in $registryPrefixes)
	{
		if ($targetText.StartsWith($registryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
			$messageText.IndexOf($registryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
		{
			$registryAbsence = $true
			break
		}
	}
	if ($registryAbsence -and ([string]$ErrorRecord.CategoryInfo.Category -in @('ObjectNotFound', 'InvalidArgument', 'InvalidOperation')))
	{
		return $true
	}

	return Test-IgnorableErrorMessage -Message $ErrorRecord.Exception.Message
}

<#
    .SYNOPSIS
    Returns new global error records that are not classified as ignorable.
#>
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

<#
    .SYNOPSIS
#>

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

<#
    .SYNOPSIS
#>

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
				'If this keeps happening, make sure the full Baseline folder is complete and intact.'
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

<#
    .SYNOPSIS
#>

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
		try { $currentMessage = [string]$currentException.Message } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ErrorHandling.Helpers.Get-BaselineExceptionMessageChain:catch341' -Severity Debug }
		 $currentMessage = $null }

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

		try { $currentException = $currentException.InnerException } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ErrorHandling.Helpers.Get-BaselineExceptionMessageChain:catch361' -Severity Debug }
		 $currentException = $null }
		$depth++
	}

	return ($messages -join [Environment]::NewLine)
}

<#
    .SYNOPSIS
#>

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

<#
    .SYNOPSIS
#>

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

<#
    .SYNOPSIS
#>

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

<#
    .SYNOPSIS
#>

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

