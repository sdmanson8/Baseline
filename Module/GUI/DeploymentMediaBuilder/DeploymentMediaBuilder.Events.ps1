# DeploymentMediaBuilder.Events.ps1
# Inline view event handlers and initialization.

function Set-GuiDeploymentMediaBuilderIsoValidationMessage
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Message,

		[string]$Summary = 'ISO detection is waiting for a valid source ISO.'
	)

	$resetStartStateScript = ${function:Reset-GuiDeploymentMediaBuilderStartState}
	$setStatusScript = ${function:Set-GuiDeploymentMediaBuilderStatus}

	$Script:DeploymentMediaDetectedIsoInfo = $null
	$Script:DeploymentMediaDetectedEditionLookup = @{}
	if ($Script:CmbDeploymentMediaDetectedEdition)
	{
		$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
		$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
	}
	& $resetStartStateScript
	if ($Script:TxtDeploymentMediaDetectedIsoSummary)
	{
		$Script:TxtDeploymentMediaDetectedIsoSummary.Text = $Summary
	}
	if ($Script:TxtDeploymentMediaPlanPreview)
	{
		$Script:TxtDeploymentMediaPlanPreview.Text = $Message
	}
	& $setStatusScript -Message $Message -Tone 'warning' -ShowBanner
}

function Clear-GuiDeploymentMediaBuilderDetectedIsoState
{
	[CmdletBinding()]
	param (
		[string]$Summary = 'No ISO inspected yet.',
		[string]$Preview = '',
		[switch]$ResetPlan
	)

	$Script:DeploymentMediaDetectedIsoInfo = $null
	$Script:DeploymentMediaDetectedEditionLookup = @{}
	if ($Script:CmbDeploymentMediaDetectedEdition)
	{
		$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
		$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
	}
	if ($ResetPlan)
	{
		Reset-GuiDeploymentMediaBuilderStartState
	}
	if ($Script:TxtDeploymentMediaDetectedIsoSummary)
	{
		$Script:TxtDeploymentMediaDetectedIsoSummary.Text = [string]$Summary
	}
	if ($Script:TxtDeploymentMediaPlanPreview -and -not [string]::IsNullOrWhiteSpace($Preview))
	{
		$Script:TxtDeploymentMediaPlanPreview.Text = [string]$Preview
	}
	Update-GuiDeploymentMediaBuilderPreviewAvailability
}

function Test-GuiDeploymentMediaBuilderIsoInfoPayload
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[object]$IsoInfo
	)

	if (-not $IsoInfo) { return $false }
	if (-not $IsoInfo.PSObject.Properties['SourceIso']) { return $false }
	if (-not $IsoInfo.PSObject.Properties['ImagePath']) { return $false }
	if (-not $IsoInfo.PSObject.Properties['ImageKind']) { return $false }
	if (-not $IsoInfo.PSObject.Properties['Editions']) { return $false }
	return (@($IsoInfo.Editions).Count -gt 0)
}

function Get-GuiDeploymentMediaBuilderSelectedMicrosoftIsoOption
{
	[CmdletBinding()]
	param ()

	if ($Script:CmbDeploymentMediaMicrosoftIso -and $Script:CmbDeploymentMediaMicrosoftIso.SelectedItem -and $Script:CmbDeploymentMediaMicrosoftIso.SelectedItem.Tag)
	{
		return $Script:CmbDeploymentMediaMicrosoftIso.SelectedItem.Tag
	}

	if (Get-Command -Name 'Get-GuiDeploymentMediaMicrosoftIsoOptions' -CommandType Function -ErrorAction SilentlyContinue)
	{
		return @(Get-GuiDeploymentMediaMicrosoftIsoOptions | Select-Object -First 1)[0]
	}

	return $null
}

function Test-GuiDeploymentMediaMicrosoftAutomatedDownloadBlocked
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

	return ($Message -match 'automated ISO download request' -or $Message -match 'ErrorSettings\.SentinelReject' -or $Message -match 'Sentinel marked this request as rejected')
}

function Show-GuiDeploymentMediaMicrosoftIsoFailureDialog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ErrorRecord,
		[AllowNull()]
		[object]$Option,
		[Parameter(Mandatory = $true)]
		[scriptblock]$ShowDialog
	)

	$message = [string]$ErrorRecord.Exception.Message
	if ($Option -and [string]$Option.AcquisitionMode -eq 'UUPLocal')
	{
		$workspace = ''
		$pageUrl = [string]$Option.PageUrl
		try
		{
			$plan = New-GuiDeploymentMediaUupAssemblyPlan -Option $Option
			$workspace = [string]$plan.WorkspaceRoot
		}
		catch
		{
			LogDebug ('UUP failure dialog could not resolve workspace plan. Product="{0}"; ExceptionType="{1}"; Message="{2}"' -f $(if ($Option) { [string]$Option.ProductName } else { '' }), $_.Exception.GetType().FullName, $_.Exception.Message)
			$workspace = ''
		}
		$uupMessage = @(
			'UUP ISO assembly failed.',
			'',
			$message
		)
		if (-not [string]::IsNullOrWhiteSpace($workspace))
		{
			$uupMessage += @('', ('UUP workspace: {0}' -f $workspace))
		}
		$buttons = @('OK')
		$accentButton = 'OK'
		if (-not [string]::IsNullOrWhiteSpace($pageUrl))
		{
			$buttons = @('OK', 'Open UUP Website')
			$accentButton = 'Open UUP Website'
		}
		$choice = & $ShowDialog -Title 'UUP ISO Assembly' -Message ($uupMessage -join [Environment]::NewLine) -Buttons $buttons -AccentButton $accentButton
		if ($choice -eq 'Open UUP Website')
		{
			try
			{
				Start-Process -FilePath $pageUrl -ErrorAction Stop | Out-Null
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DownloadMicrosoftIso.OpenUupWebsite' -Severity Warning
			}
		}
		return
	}

	$pageUrl = if ($Option) { [string]$Option.PageUrl } else { '' }
	if ([string]::IsNullOrWhiteSpace($pageUrl))
	{
		[void](& $ShowDialog -Title 'Deployment Media Builder' -Message ("Microsoft ISO acquisition failed.`n`n{0}" -f $message) -Buttons @('OK') -AccentButton 'OK')
		return
	}

	$reasonMessage = $message
	if (-not (Test-GuiDeploymentMediaMicrosoftAutomatedDownloadBlocked -Message $message))
	{
		$reasonMessage = ('The automated ISO acquisition workflow did not complete.{0}{0}{1}' -f [Environment]::NewLine, $message)
	}
	$manualMessage = @(
		$reasonMessage,
		'',
		'Open the official Microsoft download page, download the ISO manually, then select it as the source ISO in Deployment Media Builder.'
	) -join [Environment]::NewLine
	$choice = & $ShowDialog -Title 'Deployment Media Builder' -Message $manualMessage -Buttons @('OK', 'Open Microsoft Download Page') -AccentButton 'Open Microsoft Download Page'
	if ($choice -ne 'Open Microsoft Download Page') { return }

	try
	{
		Start-Process -FilePath $pageUrl -ErrorAction Stop | Out-Null
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DownloadMicrosoftIso.OpenMicrosoftDownloadPage' -Severity Warning
		[void](& $ShowDialog -Title 'Deployment Media Builder' -Message ("Failed to open the Microsoft download page.`n`n{0}`n`n{1}" -f $pageUrl, $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Show-GuiDeploymentMediaOscdimgInstallPrompt
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ErrorRecord,
		[Parameter(Mandatory = $true)]
		[scriptblock]$ShowDialog
	)

	$pageUrl = Get-GuiDeploymentMediaOscdimgInstallPageUrl
	$message = @(
		'Baseline could not install Microsoft OSCDIMG automatically.',
		'',
		[string]$ErrorRecord.Exception.Message,
		'',
		'Open the Microsoft.OSCDIMG install page, install the package, then run Start ISO Build again.'
	) -join [Environment]::NewLine

	$choice = & $ShowDialog -Title 'Deployment Media Builder' -Message $message -Buttons @('OK', 'Open Install Page') -AccentButton 'Open Install Page'
	if ([string]$choice -ne 'Open Install Page') { return }

	try
	{
		if (-not (Invoke-UserLaunch -FilePath $pageUrl -Description 'Microsoft OSCDIMG install page'))
		{
			[void](& $ShowDialog -Title 'Deployment Media Builder' -Message ("Failed to open the Microsoft.OSCDIMG install page.`n`n{0}" -f $pageUrl) -Buttons @('OK') -AccentButton 'OK')
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.OscdimgInstallPageLaunch' -Severity Warning
		}
		[void](& $ShowDialog -Title 'Deployment Media Builder' -Message ("Failed to open the Microsoft.OSCDIMG install page.`n`n{0}`n`n{1}" -f $pageUrl, $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Invoke-GuiDeploymentMediaBuilderDownloadMicrosoftIso
{
	[CmdletBinding()]
	param ()

	if ($Script:DeploymentMediaBuilderOperation)
	{
		[void](Stop-GuiDeploymentMediaBuilderBackgroundOperation)
		return
	}

	$selectedOption = Get-GuiDeploymentMediaBuilderSelectedMicrosoftIsoOption
	if (-not $selectedOption)
	{
		Set-GuiDeploymentMediaBuilderStatus -Message 'No Microsoft ISO acquisition option is available.' -Tone 'warning' -ShowBanner
		return
	}

	$resetStartStateScript = ${function:Reset-GuiDeploymentMediaBuilderStartState}
	$setControlsEnabledScript = ${function:Set-GuiDeploymentMediaBuilderControlsEnabled}
	$setStatusScript = ${function:Set-GuiDeploymentMediaBuilderStatus}
	$writeErrorLogScript = ${function:Write-GuiDeploymentMediaBuilderErrorLog}
	$showDialogScript = ${function:Show-ThemedDialog}
	$clearDetectedIsoStateScript = ${function:Clear-GuiDeploymentMediaBuilderDetectedIsoState}
	$testIsoInfoPayloadScript = ${function:Test-GuiDeploymentMediaBuilderIsoInfoPayload}
	$showMicrosoftIsoFailureDialogScript = ${function:Show-GuiDeploymentMediaMicrosoftIsoFailureDialog}

	try
	{
		switch ([string]$selectedOption.AcquisitionMode)
		{
			'ManualPage'
			{
				Start-Process -FilePath ([string]$selectedOption.PageUrl) -ErrorAction Stop | Out-Null
				& $setStatusScript -Message ('Opened the official Microsoft download page for {0}. Download the ISO manually, then import it as the source ISO.' -f $selectedOption.ProductName) -Tone 'muted' -ShowBanner
				return
			}
			'UUPLocal'
			{
				$null = New-GuiDeploymentMediaUupAssemblyPlan -Option $selectedOption
			}
			'MediaCreationTool' { }
			default
			{
				& $setStatusScript -Message ('Unsupported ISO acquisition mode: {0}' -f $selectedOption.AcquisitionMode) -Tone 'error' -ShowBanner
				return
			}
		}

		$destinationDirectory = Get-GuiDeploymentMediaMicrosoftIsoDefaultDirectory
		$operationName = 'Microsoft ISO acquisition'
		$operationStartMessage = 'Starting official Microsoft ISO acquisition...'
		$confirmTitle = 'Official Microsoft ISO Download'
		$confirmButton = 'Start Microsoft Tool'
		$confirmMessage = @(
			('Baseline will download and verify Microsoft''s Media Creation Tool for {0}, then launch the official Microsoft window.' -f $selectedOption.ProductName),
			'',
			'In the Microsoft window, choose "ISO file" and save the ISO to this watched folder:',
			$destinationDirectory,
			'',
			'Baseline will watch that folder, validate the completed ISO, and import it as the source ISO.'
		) -join [Environment]::NewLine
		if ([string]$selectedOption.AcquisitionMode -eq 'UUPLocal')
		{
			$uupPlan = New-GuiDeploymentMediaUupAssemblyPlan -Option $selectedOption
			$operationName = 'UUP ISO assembly'
			$operationStartMessage = 'Starting UUP website-assisted ISO assembly...'
			$confirmTitle = 'UUP ISO Assembly'
			$confirmButton = 'Open UUP Website'
			$confirmMessage = @(
				'Baseline will open the UUP package generator website, watch for the downloaded ZIP package, extract it, run the Windows command script in a visible console window, then validate and import the completed ISO.',
				'',
				('Workspace: {0}' -f $uupPlan.WorkspaceRoot),
				('Website: {0}' -f $uupPlan.SourcePageUrl),
				('Command scripts: {0}' -f (@($uupPlan.CommandScriptNames) -join ', ')),
				('Output label: {0}' -f $uupPlan.OutputLabel),
				'',
				'On the website, choose a build and select "Download and convert to ISO". Save the ZIP to Downloads or the UUP workspace.'
			) -join [Environment]::NewLine
		}
		$confirm = & $showDialogScript -Title $confirmTitle -Message $confirmMessage -Buttons @('Cancel', $confirmButton) -AccentButton $confirmButton
		if ($confirm -ne $confirmButton) { return }

		$dialogPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Dialog'
		$executionPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Execution'
		$processHelperPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'ProcessHelper'
		$worker = {
			param (
				[hashtable]$Context,
				[hashtable]$Sync
			)

			$null = . ([string]$Context.ProcessHelperPath)
			$null = . ([string]$Context.DialogPath)
			$null = . ([string]$Context.ExecutionPath)
			if ([string]$Context.Option.AcquisitionMode -eq 'UUPLocal')
			{
				$Sync.Status = ('Preparing UUP website-assisted ISO assembly for {0}.' -f $Context.Option.ProductName)
			}
			else
			{
				$Sync.Status = ('Preparing official Microsoft ISO acquisition for {0}.' -f $Context.Option.ProductName)
			}
			return Save-GuiDeploymentMediaMicrosoftLatestIso -Option $Context.Option -DestinationDirectory ([string]$Context.DestinationDirectory) -CancellationState $Sync -TimeoutSeconds ([int]$Context.TimeoutSeconds)
		}
		$statusCallback = {
			param ([string]$Message)
			if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = $Message }
			& $setStatusScript -Message $Message -Tone 'muted' -ShowBanner
		}.GetNewClosure()
		$completedCallback = {
			param ([object]$Result)
			$downloadResult = $Result
			if ($Script:TxtDeploymentMediaSourceIso)
			{
				$Script:TxtDeploymentMediaSourceIso.Text = [string]$downloadResult.Path
			}
			$Script:DeploymentMediaDetectedIsoInfo = $null
			$Script:DeploymentMediaDetectedEditionLookup = @{}
			if ($Script:CmbDeploymentMediaDetectedEdition)
			{
				$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
				$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
			}
			& $resetStartStateScript
			$summary = ('Imported {0} ({1}, {2}) from Microsoft Media Creation Tool output. Run Detect Editions to inspect available images.' -f $downloadResult.ProductName, $downloadResult.Architecture, $downloadResult.Language)
			if ([string]$downloadResult.AcquisitionMode -eq 'UUPLocal')
			{
				$summary = ('Imported {0} ({1}, {2}) from UUP local assembly. Run Detect Editions to inspect available images.' -f $downloadResult.ProductName, $downloadResult.Architecture, $downloadResult.Language)
			}
			if ($Script:TxtDeploymentMediaDetectedIsoSummary) { $Script:TxtDeploymentMediaDetectedIsoSummary.Text = $summary }
			if ($Script:TxtDeploymentMediaPlanPreview)
			{
				if ([string]$downloadResult.AcquisitionMode -eq 'UUPLocal')
				{
					$Script:TxtDeploymentMediaPlanPreview.Text = ('UUP ISO imported:{0}{1}{0}SHA256: {2}{0}Package ZIP: {3}{0}Command script: {4}{0}Command script SHA256: {5}{0}Transparency manifest: {6}{0}{0}Run Detect Editions before previewing or building.' -f [Environment]::NewLine, $downloadResult.Path, $downloadResult.Sha256, $downloadResult.PackageArchivePath, $downloadResult.CommandScriptPath, $downloadResult.CommandScriptSha256, $downloadResult.TransparencyManifestPath)
				}
				else
				{
					$Script:TxtDeploymentMediaPlanPreview.Text = ('Official Microsoft ISO imported:{0}{1}{0}SHA256: {2}{0}Media Creation Tool SHA256: {3}{0}{0}Run Detect Editions before previewing or building.' -f [Environment]::NewLine, $downloadResult.Path, $downloadResult.Sha256, $downloadResult.ToolSha256)
				}
			}
			& $setStatusScript -Message $(if ([string]$downloadResult.AcquisitionMode -eq 'UUPLocal') { 'UUP ISO imported. Run Detect Editions to continue.' } else { 'Microsoft ISO imported. Run Detect Editions to continue.' }) -Tone 'success' -ShowBanner
		}.GetNewClosure()
		$failedCallback = {
			param ([object]$ErrorRecord)
			$isCancelled = ($ErrorRecord.Exception -is [System.OperationCanceledException])
			& $resetStartStateScript
			if ($Script:TxtDeploymentMediaDetectedIsoSummary) { $Script:TxtDeploymentMediaDetectedIsoSummary.Text = $(if ($isCancelled) { ('{0} cancelled.' -f $operationName) } else { ('{0} failed.' -f $operationName) }) }
			if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = ('{0} {1}: {2}' -f $operationName, $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message) }
			& $setStatusScript -Message ('{0} {1}: {2}' -f $operationName, $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message) -Tone $(if ($isCancelled) { 'warning' } else { 'error' }) -ShowBanner
			if (-not $isCancelled)
			{
				& $writeErrorLogScript -ErrorRecord $ErrorRecord -Prefix ('{0} failed' -f $operationName) -Source 'DeploymentMediaBuilderView.DownloadMicrosoftIso.LogError'
				& $showMicrosoftIsoFailureDialogScript -ErrorRecord $ErrorRecord -Option $selectedOption -ShowDialog $showDialogScript
			}
		}.GetNewClosure()
		$finallyCallback = { & $setControlsEnabledScript -Enabled:$true }.GetNewClosure()

		$Script:DeploymentMediaDetectedIsoInfo = $null
		$Script:DeploymentMediaDetectedEditionLookup = @{}
		if ($Script:CmbDeploymentMediaDetectedEdition)
		{
			$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
			$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
		}
		& $resetStartStateScript
		& $setControlsEnabledScript -Enabled:$false
		& $setStatusScript -Message $operationStartMessage -Tone 'muted' -ShowBanner
		$started = Start-GuiDeploymentMediaBuilderBackgroundOperation -Name $operationName -Worker $worker -Context @{ DialogPath = $dialogPath; ExecutionPath = $executionPath; ProcessHelperPath = $processHelperPath; Option = $selectedOption; DestinationDirectory = $destinationDirectory; TimeoutSeconds = 28800 } -TimeoutSeconds 28800 -StatusCallback $statusCallback -CompletedCallback $completedCallback -FailedCallback $failedCallback -FinallyCallback $finallyCallback
		if (-not $started)
		{
			& $setControlsEnabledScript -Enabled:$true
		}
		else
		{
			& $setControlsEnabledScript -Enabled:$false
		}
	}
	catch
	{
		LogDebug ('Microsoft ISO acquisition startup failed before background operation dispatch. ExceptionType="{0}"; Message="{1}"' -f $_.Exception.GetType().FullName, $_.Exception.Message)
		& $resetStartStateScript
		& $setControlsEnabledScript -Enabled:$true
		if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = ('Microsoft ISO acquisition failed: {0}' -f $_.Exception.Message) }
		& $setStatusScript -Message ('Microsoft ISO acquisition failed: {0}' -f $_.Exception.Message) -Tone 'error' -ShowBanner
		& $writeErrorLogScript -ErrorRecord $_ -Prefix 'Microsoft ISO acquisition failed' -Source 'DeploymentMediaBuilderView.DownloadMicrosoftIso.StartLogError'
		& $showMicrosoftIsoFailureDialogScript -ErrorRecord $_ -Option $selectedOption -ShowDialog $showDialogScript
	}
}

function Invoke-GuiDeploymentMediaBuilderDetectIso
{
	[CmdletBinding()]
	param ()

	if (-not $Script:TxtDeploymentMediaSourceIso) { return }

	$setIsoValidationMessageScript = ${function:Set-GuiDeploymentMediaBuilderIsoValidationMessage}
	$resetStartStateScript = ${function:Reset-GuiDeploymentMediaBuilderStartState}
	$setControlsEnabledScript = ${function:Set-GuiDeploymentMediaBuilderControlsEnabled}
	$setStatusScript = ${function:Set-GuiDeploymentMediaBuilderStatus}
	$writeErrorLogScript = ${function:Write-GuiDeploymentMediaBuilderErrorLog}
	$showDialogScript = ${function:Show-ThemedDialog}
	$clearDetectedIsoStateScript = ${function:Clear-GuiDeploymentMediaBuilderDetectedIsoState}
	$testIsoInfoPayloadScript = ${function:Test-GuiDeploymentMediaBuilderIsoInfoPayload}
	$setDetectedIsoInfoScript = ${function:Set-GuiDeploymentMediaBuilderDetectedIsoInfo}
	$getSourceIsoPathScript = ${function:Get-GuiDeploymentMediaBuilderSourceIsoPath}
	$writeDebugLogScript = ${function:Write-GuiDeploymentMediaBuilderViewDebugLog}

	try
	{
		$sourceIso = & $getSourceIsoPathScript
		if ([string]::IsNullOrWhiteSpace($sourceIso))
		{
			& $writeDebugLogScript -Message 'Deployment media ISO detection blocked because the source ISO path is empty.' -Source 'DeploymentMediaBuilderView.DetectIso.Blocked.EmptySource'
			& $setIsoValidationMessageScript -Message 'Select a Windows ISO before detecting editions.' -Summary 'No ISO selected.'
			return
		}
		if ([System.IO.Path]::GetExtension($sourceIso) -ne '.iso')
		{
			& $writeDebugLogScript -Message ('Deployment media ISO detection blocked because the source extension is not .iso. Source="{0}"' -f $sourceIso) -Source 'DeploymentMediaBuilderView.DetectIso.Blocked.InvalidExtension'
			& $setIsoValidationMessageScript -Message 'Source ISO must be an .iso file.' -Summary 'The selected source is not an ISO file.'
			return
		}
		if (-not (Test-Path -LiteralPath $sourceIso -PathType Leaf -ErrorAction SilentlyContinue))
		{
			& $writeDebugLogScript -Message ('Deployment media ISO detection blocked because the source file does not exist. Source="{0}"' -f $sourceIso) -Source 'DeploymentMediaBuilderView.DetectIso.Blocked.MissingFile'
			& $setIsoValidationMessageScript -Message ('Source ISO does not exist: {0}' -f $sourceIso) -Summary 'The selected ISO path does not exist.'
			return
		}

		$dialogPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Dialog'
		$executionPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Execution'
		& $writeDebugLogScript -Message ('Deployment media ISO detection request accepted. SourceIso="{0}"; DialogPath="{1}"; ExecutionPath="{2}"' -f $sourceIso, $dialogPath, $executionPath) -Source 'DeploymentMediaBuilderView.DetectIso.Accepted'
		$worker = {
			param (
				[hashtable]$Context,
				[hashtable]$Sync
			)

			$null = . ([string]$Context.DialogPath)
			$null = . ([string]$Context.ExecutionPath)
			$sourceIso = [string]$Context.SourceIso
			$Sync.Status = ('Detecting editions in {0}.' -f $sourceIso)
			return Get-GuiDeploymentMediaIsoImageInfo -SourceIso $sourceIso -CancellationState $Sync
		}
		$statusCallback = {
			param ([string]$Message)
			if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = $Message }
			& $setStatusScript -Message $Message -Tone 'muted' -ShowBanner
		}.GetNewClosure()
		$completedCallback = {
			param ([object]$Result)
			$isoInfo = $Result
			& $writeDebugLogScript -Message ('Deployment media ISO detection worker returned. PayloadType="{0}"; HasEditions={1}' -f $(if ($isoInfo) { $isoInfo.GetType().FullName } else { '<null>' }), [bool]($isoInfo -and $isoInfo.PSObject.Properties['Editions'])) -Source 'DeploymentMediaBuilderView.DetectIso.WorkerReturned'
			if (-not (& $testIsoInfoPayloadScript -IsoInfo $isoInfo))
			{
				& $clearDetectedIsoStateScript -Summary 'ISO detection did not return any Windows editions.' -Preview 'ISO detection completed without usable edition data. Run Detect Editions again or select a different ISO.' -ResetPlan
				& $setStatusScript -Message 'ISO detection completed without usable edition data.' -Tone 'error' -ShowBanner
				try { LogError 'Deployment media ISO detection completed without usable edition data.' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DetectIso.EmptyResultLog' -Severity Warning }
				return
			}
			$editionItemCount = & $setDetectedIsoInfoScript -IsoInfo $isoInfo
			& $writeDebugLogScript -Message ('Deployment media ISO detection payload accepted. SourceIso="{0}"; ImageKind="{1}"; ImagePath="{2}"; EditionCount={3}; SelectableItems={4}' -f $(if ($isoInfo.PSObject.Properties['SourceIso']) { [string]$isoInfo.SourceIso } else { '' }), $(if ($isoInfo.PSObject.Properties['ImageKind']) { [string]$isoInfo.ImageKind } else { '' }), $(if ($isoInfo.PSObject.Properties['ImagePath']) { [string]$isoInfo.ImagePath } else { '' }), @($isoInfo.Editions).Count, $editionItemCount) -Source 'DeploymentMediaBuilderView.DetectIso.PayloadAccepted'
			if ($editionItemCount -lt 1)
			{
				& $clearDetectedIsoStateScript -Summary 'ISO detection did not return any selectable Windows editions.' -Preview 'ISO detection completed, but no selectable Windows editions were returned. Run Detect Editions again or select a different ISO.' -ResetPlan
				& $setStatusScript -Message 'ISO detection completed without selectable Windows editions.' -Tone 'error' -ShowBanner
				try { LogError 'Deployment media ISO detection completed without selectable Windows editions.' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DetectIso.NoSelectableEditionsLog' -Severity Warning }
				return
			}
			try { LogDebug ('Deployment media edition dropdown populated. Items={0}; SelectedIndex={1}' -f $editionItemCount, $(if ($Script:CmbDeploymentMediaDetectedEdition) { $Script:CmbDeploymentMediaDetectedEdition.SelectedIndex } else { -1 })) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DetectIso.DropdownLog' -Severity Warning }
			if ($Script:TxtDeploymentMediaDetectedIsoSummary)
			{
				$Script:TxtDeploymentMediaDetectedIsoSummary.Text = ('Detected {0}: {1}. Editions: {2}.' -f $isoInfo.ImageKind, $isoInfo.ImagePath, @($isoInfo.Editions).Count)
			}
			if ($Script:TxtDeploymentMediaPlanPreview)
			{
				$Script:TxtDeploymentMediaPlanPreview.Text = ('Detected {0}: {1}{2}Edition count: {3}' -f $isoInfo.ImageKind, $isoInfo.ImagePath, [Environment]::NewLine, @($isoInfo.Editions).Count)
			}
			& $resetStartStateScript
			& $setStatusScript -Message 'ISO editions detected. Preview or Start ISO Build when ready.' -Tone 'success' -ShowBanner
			try { LogInfo ('Deployment media ISO editions detected. Source={0}; Image={1}; Editions={2}' -f $isoInfo.SourceIso, $isoInfo.ImagePath, @($isoInfo.Editions).Count) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DetectIso.SuccessLog' -Severity Warning }
		}.GetNewClosure()
		$failedCallback = {
			param ([object]$ErrorRecord)
			$isCancelled = ($ErrorRecord.Exception -is [System.OperationCanceledException])
			& $writeDebugLogScript -Message ('Deployment media ISO detection worker failed. SourceIso="{0}"; Cancelled={1}; ExceptionType="{2}"; Message="{3}"' -f $sourceIso, [bool]$isCancelled, $ErrorRecord.Exception.GetType().FullName, $ErrorRecord.Exception.Message) -Source 'DeploymentMediaBuilderView.DetectIso.Failed'
			$Script:DeploymentMediaDetectedIsoInfo = $null
			$Script:DeploymentMediaDetectedEditionLookup = @{}
			if ($Script:CmbDeploymentMediaDetectedEdition)
			{
				$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
				$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
			}
			& $resetStartStateScript
			if ($Script:TxtDeploymentMediaDetectedIsoSummary) { $Script:TxtDeploymentMediaDetectedIsoSummary.Text = $(if ($isCancelled) { 'ISO detection cancelled.' } else { 'ISO detection failed.' }) }
			if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = ('ISO detection {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message) }
			& $setStatusScript -Message ('ISO detection {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message) -Tone $(if ($isCancelled) { 'warning' } else { 'error' }) -ShowBanner
			if (-not $isCancelled)
			{
				& $writeErrorLogScript -ErrorRecord $ErrorRecord -Prefix 'Deployment media ISO detection failed' -Source 'DeploymentMediaBuilderView.DetectIso.LogError'
				[void](& $showDialogScript -Title 'Deployment Media Builder' -Message ("ISO detection failed.`n`n{0}" -f $ErrorRecord.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()
		$finallyCallback = { & $setControlsEnabledScript -Enabled:$true }.GetNewClosure()

		$Script:DeploymentMediaDetectedIsoInfo = $null
		$Script:DeploymentMediaDetectedEditionLookup = @{}
		if ($Script:CmbDeploymentMediaDetectedEdition)
		{
			$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
			$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
		}
		& $resetStartStateScript
		& $setControlsEnabledScript -Enabled:$false
		& $setStatusScript -Message 'Detecting ISO editions...' -Tone 'muted' -ShowBanner
		try { LogInfo ('Deployment media ISO edition detection started. Source={0}' -f $sourceIso) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.DetectIso.StartLog' -Severity Warning }
		$started = Start-GuiDeploymentMediaBuilderBackgroundOperation -Name 'Deployment media ISO detection' -Worker $worker -Context @{ DialogPath = $dialogPath; ExecutionPath = $executionPath; SourceIso = $sourceIso } -TimeoutSeconds 900 -StatusCallback $statusCallback -CompletedCallback $completedCallback -FailedCallback $failedCallback -FinallyCallback $finallyCallback
		& $writeDebugLogScript -Message ('Deployment media ISO detection background start result. SourceIso="{0}"; Started={1}' -f $sourceIso, [bool]$started) -Source 'DeploymentMediaBuilderView.DetectIso.StartResult'
		if (-not $started)
		{
			& $setControlsEnabledScript -Enabled:$true
		}
		else
		{
			& $setControlsEnabledScript -Enabled:$false
		}
	}
	catch
	{
		LogDebug ('Deployment media ISO detection setup failed before background operation dispatch. ExceptionType="{0}"; Message="{1}"' -f $_.Exception.GetType().FullName, $_.Exception.Message)
		$Script:DeploymentMediaDetectedIsoInfo = $null
		$Script:DeploymentMediaDetectedEditionLookup = @{}
		if ($Script:CmbDeploymentMediaDetectedEdition)
		{
			$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
			$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
		}
		& $resetStartStateScript
		if ($Script:TxtDeploymentMediaDetectedIsoSummary) { $Script:TxtDeploymentMediaDetectedIsoSummary.Text = 'ISO detection failed.' }
		if ($Script:TxtDeploymentMediaPlanPreview) { $Script:TxtDeploymentMediaPlanPreview.Text = ('ISO detection failed: {0}' -f $_.Exception.Message) }
		& $setStatusScript -Message ('ISO detection failed: {0}' -f $_.Exception.Message) -Tone 'error' -ShowBanner
		& $writeErrorLogScript -ErrorRecord $_ -Prefix 'Deployment media ISO detection failed' -Source 'DeploymentMediaBuilderView.DetectIso.LogError'
		[void](& $showDialogScript -Title 'Deployment Media Builder' -Message ("ISO detection failed.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Invoke-GuiDeploymentMediaBuilderPreviewPlan
{
	[CmdletBinding()]
	param ()

	$previewState = Test-GuiDeploymentMediaBuilderPreviewPrerequisites
	if (-not [bool]$previewState.Ready)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media build plan preview blocked. Reason="{0}"; SourceIso="{1}"; HasDetectedIso={2}; SourceMatchesDetectedIso={3}; SelectedEdition="{4}"; EditionIndexText="{5}"' -f [string]$previewState.Message, (Get-GuiDeploymentMediaBuilderSourceIsoPath), [bool]$Script:DeploymentMediaDetectedIsoInfo, (Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso), $(if ($Script:CmbDeploymentMediaDetectedEdition -and $Script:CmbDeploymentMediaDetectedEdition.SelectedItem) { [string]$Script:CmbDeploymentMediaDetectedEdition.SelectedItem.DisplayName } else { '' }), $(if ($Script:TxtDeploymentMediaEditionIndex) { [string]$Script:TxtDeploymentMediaEditionIndex.Text } else { '' })) -Source 'DeploymentMediaBuilderView.PreviewPlan.Blocked'
		Update-GuiDeploymentMediaBuilderPreviewAvailability
		Set-GuiDeploymentMediaBuilderStatus -Message ([string]$previewState.Message) -Tone 'warning' -ShowBanner
		[void](Show-ThemedDialog -Title 'Deployment Media Builder' -Message ([string]$previewState.Message) -Buttons @('OK') -AccentButton 'OK')
		return
	}

	$plan = Get-GuiDeploymentMediaBuilderPlan
	$Script:DeploymentMediaCurrentPlan = $plan
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media build plan preview generated. IsValid={0}; ErrorCount={1}; OutputMode="{2}"; SourceIso="{3}"; EditionIndex={4}; EditionName="{5}"; WorkingDirectory="{6}"' -f [bool]$plan.IsValid, @($plan.Errors).Count, [string]$plan.OutputMode, [string]$plan.SourceIso, [int]$plan.EditionIndex, [string]$plan.EditionName, [string]$plan.WorkingDirectory) -Source 'DeploymentMediaBuilderView.PreviewPlan.Generated'
	Update-GuiDeploymentMediaBuilderPreviewAvailability
	[void](Show-GuiDeploymentMediaBuildPlanPreviewDialog -Plan $plan)

	if ([bool]$plan.IsValid)
	{
		Set-GuiDeploymentMediaBuilderStatus -Message 'Build plan validated. Preview and Start ISO Build are available independently.' -Tone 'success' -ShowBanner
	}
	else
	{
		Set-GuiDeploymentMediaBuilderStatus -Message 'Build plan needs required inputs before Preview or Start ISO Build can run.' -Tone 'warning' -ShowBanner
	}
}

function Invoke-GuiDeploymentMediaBuilderStartBuild
{
	[CmdletBinding()]
	param ()

	if ($Script:DeploymentMediaBuilderOperation)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media Start ISO Build click routed to cancellation. ActiveOperation="{0}"' -f [string]$Script:DeploymentMediaBuilderOperation.Name) -Source 'DeploymentMediaBuilderView.StartBuild.CancelActiveOperation'
		if ($Script:DeploymentMediaBuildProgressDialog)
		{
			Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $Script:DeploymentMediaBuildProgressDialog -Text 'Cancellation requested from the Start ISO Build button.' -Level 'WARNING'
		}
		[void](Stop-GuiDeploymentMediaBuilderBackgroundOperation)
		return
	}

	$plan = Get-GuiDeploymentMediaBuilderPlan
	$Script:DeploymentMediaCurrentPlan = $plan
	if (-not [bool]$plan.IsValid)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media build start blocked by invalid plan. ErrorCount={0}; SourceIso="{1}"; OutputMode="{2}"; EditionIndex={3}; EditionName="{4}"' -f @($plan.Errors).Count, [string]$plan.SourceIso, [string]$plan.OutputMode, [int]$plan.EditionIndex, [string]$plan.EditionName) -Source 'DeploymentMediaBuilderView.StartBuild.InvalidPlan'
		if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.IsEnabled = $false }
		Set-GuiDeploymentMediaBuilderStatus -Message 'Complete required deployment media inputs before starting.' -Tone 'warning' -ShowBanner
		return
	}

	$confirm = Show-ThemedDialog -Title 'Deployment Media Builder' -Message "Start ISO Build will copy the selected Microsoft ISO into a working folder, apply the requested setup customizations, produce the selected output, and save an auditable build report. Confirm that the source ISO, edition, and output target are correct before continuing." -Buttons @('Cancel', 'Start ISO Build') -AccentButton 'Start ISO Build'
	if ($confirm -ne 'Start ISO Build')
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media build confirmation dismissed. DialogResult="{0}"; SourceIso="{1}"' -f [string]$confirm, [string]$plan.SourceIso) -Source 'DeploymentMediaBuilderView.StartBuild.ConfirmationDismissed'
		return
	}

	$setControlsEnabledScript = ${function:Set-GuiDeploymentMediaBuilderControlsEnabled}
	$setStatusScript = ${function:Set-GuiDeploymentMediaBuilderStatus}
	$writeErrorLogScript = ${function:Write-GuiDeploymentMediaBuilderErrorLog}
	$showDialogScript = ${function:Show-ThemedDialog}
	$convertPlanTextScript = ${function:Convert-GuiDeploymentMediaBuildPlanToText}
	$setProgressStateScript = ${function:Set-GuiDeploymentMediaBuilderProgressState}
	$writeDebugLogScript = ${function:Write-GuiDeploymentMediaBuilderViewDebugLog}
	$showBuildDialogScript = ${function:Show-GuiDeploymentMediaBuildProgressDialog}
	$setBuildDialogProgressScript = ${function:Set-GuiDeploymentMediaBuildDialogProgressState}
	$addBuildDialogProgressLogScript = ${function:Add-GuiDeploymentMediaBuildDialogProgressLog}
	$addBuildDialogLogScript = ${function:Add-GuiDeploymentMediaBuildDialogLogLine}
	$completeBuildDialogScript = ${function:Complete-GuiDeploymentMediaBuildProgressDialog}
	$testOscdimgDependencyErrorScript = ${function:Test-GuiDeploymentMediaOscdimgDependencyError}
	$showOscdimgInstallPromptScript = ${function:Show-GuiDeploymentMediaOscdimgInstallPrompt}
	$buildDialog = $null

	try
	{
		$dialogPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Dialog'
		$executionPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'Execution'
		$processHelperPath = Resolve-GuiDeploymentMediaBuilderSupportPath -Name 'ProcessHelper'
		$selectedTweaks = $null
		if ([bool]$plan.IncludeBaselineTweaks)
		{
			$selectedTweaks = @(Get-GuiDeploymentMediaSelectedTweaksForSetup)
		}
		& $writeDebugLogScript -Message ('Deployment media build start accepted. SourceIso="{0}"; EditionIndex={1}; EditionName="{2}"; OutputMode="{3}"; IncludeBaselineTweaks={4}; SelectedTweaks={5}; DialogPath="{6}"; ExecutionPath="{7}"; ProcessHelperPath="{8}"' -f [string]$plan.SourceIso, [int]$plan.EditionIndex, [string]$plan.EditionName, [string]$plan.OutputMode, [bool]$plan.IncludeBaselineTweaks, $(if ($null -ne $selectedTweaks) { @($selectedTweaks).Count } else { 0 }), $dialogPath, $executionPath, $processHelperPath) -Source 'DeploymentMediaBuilderView.StartBuild.Accepted'

		$Script:DeploymentMediaBuildInProgress = $true
		$buildDialog = & $showBuildDialogScript -Plan $plan
		$Script:DeploymentMediaBuildProgressDialog = $buildDialog
		& $addBuildDialogLogScript -Dialog $buildDialog -Text ('Source ISO: {0}' -f [string]$plan.SourceIso)
		& $addBuildDialogLogScript -Dialog $buildDialog -Text ('Selected edition: {0}' -f $(if ([string]::IsNullOrWhiteSpace([string]$plan.EditionName)) { ('Image index {0}' -f [int]$plan.EditionIndex) } else { ('{0}: {1}' -f [int]$plan.EditionIndex, [string]$plan.EditionName) }))
		& $addBuildDialogLogScript -Dialog $buildDialog -Text ('Output mode: {0}' -f [string]$plan.OutputMode)
		& $setControlsEnabledScript -Enabled:$false
		& $setProgressStateScript -Message 'Deployment media build started.' -Indeterminate
		& $setBuildDialogProgressScript -Dialog $buildDialog -Message 'Deployment media build started.' -Indeterminate
		& $setStatusScript -Message 'Build running.' -Tone 'muted'

		$worker = {
			param (
				[hashtable]$Context,
				[hashtable]$Sync
			)

			$null = . ([string]$Context.ProcessHelperPath)
			$null = . ([string]$Context.DialogPath)
			$null = . ([string]$Context.ExecutionPath)

			$progressCallback = {
				param([object]$Progress)

				if ($Progress -and $Progress.PSObject.Properties['Message'])
				{
					$Sync.Status = [string]$Progress.Message
					$Sync.ProgressPayload = $Progress
				}
				else
				{
					$Sync.Status = [string]$Progress
					$Sync.ProgressPayload = $null
				}
			}.GetNewClosure()

			$buildParameters = @{
				Plan = $Context.Plan
				ProgressCallback = $progressCallback
				CancellationState = $Sync
				GlobalTimeoutSeconds = [int]$Context.GlobalTimeoutSeconds
			}
			if ($Context.ContainsKey('SelectedTweaks'))
			{
				$buildParameters['SelectedTweaks'] = @($Context.SelectedTweaks)
			}

			$buildResult = Invoke-GuiDeploymentMediaBuild @buildParameters
			if ($null -eq $buildResult)
			{
				throw 'Deployment media build completed without returning a build result.'
			}
			return $buildResult
		}
		$statusCallback = {
			param ([object]$Progress)

			$message = if ($Progress -and $Progress.PSObject.Properties['Message']) { [string]$Progress.Message } else { [string]$Progress }
			& $setProgressStateScript -Progress $Progress -Message $message
			& $setBuildDialogProgressScript -Dialog $buildDialog -Progress $Progress -Message $message
			& $addBuildDialogProgressLogScript -Dialog $buildDialog -Progress $Progress -Message $message
		}.GetNewClosure()
		$completedCallback = {
			param ([object]$Result)
			$buildResult = $Result
			if (-not $buildResult)
			{
				throw 'Deployment media build completed without returning a build result.'
			}

			$outputPath = if ($buildResult.PSObject.Properties['OutputPath']) { [string]$buildResult.OutputPath } else { '' }
			$reportPath = if ($buildResult.PSObject.Properties['ReportPath']) { [string]$buildResult.ReportPath } else { '' }
			$buildRoot = if ($buildResult.PSObject.Properties['BuildRoot']) { [string]$buildResult.BuildRoot } else { '' }
			if ([string]::IsNullOrWhiteSpace($outputPath) -or [string]::IsNullOrWhiteSpace($reportPath))
			{
				throw ('Deployment media build returned an incomplete result. OutputPath="{0}"; ReportPath="{1}".' -f $outputPath, $reportPath)
			}

			& $writeDebugLogScript -Message ('Deployment media build completed. OutputPath="{0}"; ReportPath="{1}"; BuildRoot="{2}"' -f $outputPath, $reportPath, $buildRoot) -Source 'DeploymentMediaBuilderView.StartBuild.Completed'
			$Script:DeploymentMediaCurrentPlan = $plan
			if ($Script:TxtDeploymentMediaPlanPreview)
			{
				$Script:TxtDeploymentMediaPlanPreview.Text = (& $convertPlanTextScript -Plan $plan) + [Environment]::NewLine + [Environment]::NewLine + ('Build output: {0}' -f $outputPath) + [Environment]::NewLine + ('Build report saved: {0}' -f $reportPath)
			}
			$completeMessage = ('Build complete. Report: {0}' -f $reportPath)
			& $setProgressStateScript -Hide
			& $completeBuildDialogScript -Dialog $buildDialog -Message $completeMessage -Level 'SUCCESS'
			& $setStatusScript -Message $completeMessage -Tone 'success' -ShowBanner
		}.GetNewClosure()
		$failedCallback = {
			param ([object]$ErrorRecord)
			$isCancelled = ($ErrorRecord.Exception -is [System.OperationCanceledException])
			& $writeDebugLogScript -Message ('Deployment media build failed. Cancelled={0}; ExceptionType="{1}"; Message="{2}"; SourceIso="{3}"; OutputMode="{4}"' -f [bool]$isCancelled, $ErrorRecord.Exception.GetType().FullName, $ErrorRecord.Exception.Message, [string]$plan.SourceIso, [string]$plan.OutputMode) -Source 'DeploymentMediaBuilderView.StartBuild.Failed'
			if ($Script:TxtDeploymentMediaPlanPreview)
			{
				$Script:TxtDeploymentMediaPlanPreview.Text = (& $convertPlanTextScript -Plan $plan) + [Environment]::NewLine + [Environment]::NewLine + ('Build {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message)
			}
			$failureMessage = ('Build {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message)
			& $setProgressStateScript -Hide
			& $completeBuildDialogScript -Dialog $buildDialog -Message $failureMessage -Level $(if ($isCancelled) { 'WARNING' } else { 'ERROR' }) -Failed
			& $setStatusScript -Message $failureMessage -Tone $(if ($isCancelled) { 'warning' } else { 'error' }) -ShowBanner
			if (-not $isCancelled)
			{
				& $writeErrorLogScript -ErrorRecord $ErrorRecord -Prefix 'Deployment media build failed' -Source 'DeploymentMediaBuilderView.StartBuild.LogError'
				if (& $testOscdimgDependencyErrorScript -ErrorRecord $ErrorRecord)
				{
					& $showOscdimgInstallPromptScript -ErrorRecord $ErrorRecord -ShowDialog $showDialogScript
				}
				else
				{
					[void](& $showDialogScript -Title 'Deployment Media Builder' -Message ("Deployment media build failed.`n`n{0}" -f $ErrorRecord.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}
		}.GetNewClosure()
		$finallyCallback = {
			$Script:DeploymentMediaBuildInProgress = $false
			& $setControlsEnabledScript -Enabled:$true
			& $writeDebugLogScript -Message 'Deployment media build finalizer restored controls and cleared build-in-progress state.' -Source 'DeploymentMediaBuilderView.StartBuild.Finalizer'
		}.GetNewClosure()

		$context = @{
			DialogPath = $dialogPath
			ExecutionPath = $executionPath
			ProcessHelperPath = $processHelperPath
			Plan = $plan
			GlobalTimeoutSeconds = 28800
		}
		if ($null -ne $selectedTweaks)
		{
			$context['SelectedTweaks'] = @($selectedTweaks)
		}

		$started = Start-GuiDeploymentMediaBuilderBackgroundOperation -Name 'Deployment media build' -Worker $worker -Context $context -TimeoutSeconds 28800 -StatusCallback $statusCallback -CompletedCallback $completedCallback -FailedCallback $failedCallback -FinallyCallback $finallyCallback
		& $writeDebugLogScript -Message ('Deployment media build background start result. Started={0}; SourceIso="{1}"; OutputMode="{2}"' -f [bool]$started, [string]$plan.SourceIso, [string]$plan.OutputMode) -Source 'DeploymentMediaBuilderView.StartBuild.StartResult'
		if (-not $started)
		{
			$Script:DeploymentMediaBuildInProgress = $false
			& $setProgressStateScript -Hide
			& $completeBuildDialogScript -Dialog $buildDialog -Message 'Deployment media build could not start because another operation is active.' -Level 'WARNING' -Failed
			& $setControlsEnabledScript -Enabled:$true
		}
		else
		{
			& $setControlsEnabledScript -Enabled:$false
		}
	}
	catch
	{
		LogDebug ('Deployment media build setup failed before background operation dispatch. ExceptionType="{0}"; Message="{1}"' -f $_.Exception.GetType().FullName, $_.Exception.Message)
		$Script:DeploymentMediaBuildInProgress = $false
		& $setControlsEnabledScript -Enabled:$true
		if ($Script:TxtDeploymentMediaPlanPreview)
		{
			$Script:TxtDeploymentMediaPlanPreview.Text = (& $convertPlanTextScript -Plan $plan) + [Environment]::NewLine + [Environment]::NewLine + ('Build failed: {0}' -f $_.Exception.Message)
		}
		& $setProgressStateScript -Message ('Build failed: {0}' -f $_.Exception.Message) -Failed
		& $completeBuildDialogScript -Dialog $buildDialog -Message ('Build failed: {0}' -f $_.Exception.Message) -Level 'ERROR' -Failed
		& $setStatusScript -Message ('Build failed: {0}' -f $_.Exception.Message) -Tone 'error' -ShowBanner
		& $writeErrorLogScript -ErrorRecord $_ -Prefix 'Deployment media build failed' -Source 'DeploymentMediaBuilderView.StartBuild.LogError'
		if (& $testOscdimgDependencyErrorScript -ErrorRecord $_)
		{
			& $showOscdimgInstallPromptScript -ErrorRecord $_ -ShowDialog $showDialogScript
		}
		else
		{
			[void](& $showDialogScript -Title 'Deployment Media Builder' -Message ("Deployment media build failed.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}
}

function Initialize-GuiDeploymentMediaBuilderView
{
	[CmdletBinding()]
	param ()

	if ($Script:DeploymentMediaBuilderViewInitialized) { return }
	if (-not $Script:DeploymentMediaView) { return }

	$Script:DeploymentMediaBuilderViewInitialized = $true
	if ($Script:TxtDeploymentMediaWorkingDirectory -and [string]::IsNullOrWhiteSpace([string]$Script:TxtDeploymentMediaWorkingDirectory.Text))
	{
		$Script:TxtDeploymentMediaWorkingDirectory.Text = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\Working'
	}
	if ($Script:CmbDeploymentMediaOutputMode -and $Script:CmbDeploymentMediaOutputMode.SelectedIndex -lt 0)
	{
		$Script:CmbDeploymentMediaOutputMode.SelectedIndex = 0
	}

	$resetStartStateScript = ${function:Reset-GuiDeploymentMediaBuilderStartState}
	$setStatusScript = ${function:Set-GuiDeploymentMediaBuilderStatus}
	$fileDialogScript = ${function:Show-GuiDeploymentMediaBuilderFileDialog}
	$folderDialogScript = ${function:Show-GuiDeploymentMediaBuilderFolderDialog}
	$unattendGeneratorScript = Get-GuiRuntimeCommand -Name 'Show-GuiDeploymentMediaUnattendGeneratorDialog' -CommandType 'Function'
	$downloadMicrosoftIsoScript = ${function:Invoke-GuiDeploymentMediaBuilderDownloadMicrosoftIso}
	$detectIsoScript = ${function:Invoke-GuiDeploymentMediaBuilderDetectIso}
	$previewPlanScript = ${function:Invoke-GuiDeploymentMediaBuilderPreviewPlan}
	$startBuildScript = ${function:Invoke-GuiDeploymentMediaBuilderStartBuild}
	$syncTextScript = ${function:Sync-GuiDeploymentMediaBuilderViewText}
	$initializeProgressChromeScript = ${function:Initialize-GuiDeploymentMediaBuilderProgressChrome}
	$syncEditionSelectionScript = ${function:Sync-GuiDeploymentMediaBuilderEditionSelection}
	$updatePreviewAvailabilityScript = ${function:Update-GuiDeploymentMediaBuilderPreviewAvailability}
	$clearDetectedIsoStateScript = ${function:Clear-GuiDeploymentMediaBuilderDetectedIsoState}
	$testIsoInfoPayloadScript = ${function:Test-GuiDeploymentMediaBuilderIsoInfoPayload}
	$sourceMatchesDetectedIsoScript = ${function:Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso}
	$getSourceIsoPathScript = ${function:Get-GuiDeploymentMediaBuilderSourceIsoPath}
	$sourceIsoTextBox = $Script:TxtDeploymentMediaSourceIso
	$autounattendTextBox = $Script:TxtDeploymentMediaAutounattend
	$workingDirectoryTextBox = $Script:TxtDeploymentMediaWorkingDirectory
	$driverSourceTextBox = $Script:TxtDeploymentMediaDriverSource
	$usbTargetRootTextBox = $Script:TxtDeploymentMediaUsbTargetRoot

	$markPlanDirty = {
		& $resetStartStateScript
		& $setStatusScript -Message 'Inputs changed. Preview is optional; Start ISO Build is available when required inputs validate.' -Tone 'muted'
		& $updatePreviewAvailabilityScript
	}.GetNewClosure()

	$markSourceIsoChanged = {
		if ((& $testIsoInfoPayloadScript -IsoInfo $Script:DeploymentMediaDetectedIsoInfo) -and (& $sourceMatchesDetectedIsoScript))
		{
			& $resetStartStateScript
			& $updatePreviewAvailabilityScript
			return
		}

		& $clearDetectedIsoStateScript -Summary 'Source ISO changed. Run Detect Editions before previewing or building.' -Preview 'Run Detect Editions for the selected ISO. Preview is optional before Start ISO Build.' -ResetPlan
		& $setStatusScript -Message 'Run Detect Editions for the selected ISO before previewing or building.' -Tone 'muted'
	}.GetNewClosure()

	if ($Script:TxtDeploymentMediaSourceIso)
	{
		Register-GuiEventHandler -Source $Script:TxtDeploymentMediaSourceIso -EventName 'TextChanged' -Handler $markSourceIsoChanged | Out-Null
	}

	foreach ($textBox in @(
		$Script:TxtDeploymentMediaEditionIndex,
		$Script:TxtDeploymentMediaWorkingDirectory,
		$Script:TxtDeploymentMediaUsbTargetRoot,
		$Script:TxtDeploymentMediaAutounattend,
		$Script:TxtDeploymentMediaDriverSource
	))
	{
		if ($textBox)
		{
			Register-GuiEventHandler -Source $textBox -EventName 'TextChanged' -Handler $markPlanDirty | Out-Null
		}
	}

	if ($Script:CmbDeploymentMediaDetectedEdition)
	{
		Register-GuiEventHandler -Source $Script:CmbDeploymentMediaDetectedEdition -EventName 'SelectionChanged' -Handler ({
			& $syncEditionSelectionScript
			& $markPlanDirty
		}.GetNewClosure()) | Out-Null
	}

	foreach ($selector in @($Script:CmbDeploymentMediaOutputMode))
	{
		if ($selector)
		{
			Register-GuiEventHandler -Source $selector -EventName 'SelectionChanged' -Handler $markPlanDirty | Out-Null
		}
	}

	foreach ($checkBox in @($Script:ChkDeploymentMediaBootDrivers, $Script:ChkDeploymentMediaBaselineTweaks))
	{
		if ($checkBox)
		{
			Register-GuiEventHandler -Source $checkBox -EventName 'Checked' -Handler $markPlanDirty | Out-Null
			Register-GuiEventHandler -Source $checkBox -EventName 'Unchecked' -Handler $markPlanDirty | Out-Null
		}
	}

	if ($Script:BtnDeploymentMediaBrowseIso)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaBrowseIso -EventName 'Click' -Handler ({
			$path = & $fileDialogScript -Filter 'Windows ISO (*.iso)|*.iso'
			if ($path -and $sourceIsoTextBox)
			{
				$sourceIsoTextBox.Text = $path
				& $setStatusScript -Message 'ISO selected. Run Detect Editions to inspect available images.' -Tone 'muted'
			}
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaDownloadMicrosoftIso)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaDownloadMicrosoftIso -EventName 'Click' -Handler ({ & $downloadMicrosoftIsoScript }.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaBrowseAutounattend)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaBrowseAutounattend -EventName 'Click' -Handler ({
			$path = & $fileDialogScript -Filter 'Answer files (*.xml)|*.xml'
			if ($path -and $autounattendTextBox) { $autounattendTextBox.Text = $path }
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaCreateAutounattend)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaCreateAutounattend -EventName 'Click' -Handler ({
			if (-not $unattendGeneratorScript) { throw 'Show-GuiDeploymentMediaUnattendGeneratorDialog not found.' }
			& $unattendGeneratorScript -TargetTextBox $autounattendTextBox
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaBrowseWorking)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaBrowseWorking -EventName 'Click' -Handler ({
			$path = & $folderDialogScript -Description 'Select the deployment media working directory.'
			if ($path -and $workingDirectoryTextBox) { $workingDirectoryTextBox.Text = $path }
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaBrowseDrivers)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaBrowseDrivers -EventName 'Click' -Handler ({
			$path = & $folderDialogScript -Description 'Select the deployment driver source directory.'
			if ($path -and $driverSourceTextBox) { $driverSourceTextBox.Text = $path }
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaBrowseUsbTarget)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaBrowseUsbTarget -EventName 'Click' -Handler ({
			$path = & $folderDialogScript -Description 'Select the removable drive root.'
			if ($path -and $usbTargetRootTextBox) { $usbTargetRootTextBox.Text = [System.IO.Path]::GetPathRoot($path) }
		}.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaDetectIso)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaDetectIso -EventName 'Click' -Handler ({ & $detectIsoScript }.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaPreviewPlan)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaPreviewPlan -EventName 'Click' -Handler ({ & $previewPlanScript }.GetNewClosure()) | Out-Null
	}
	if ($Script:BtnDeploymentMediaStartBuild)
	{
		Register-GuiEventHandler -Source $Script:BtnDeploymentMediaStartBuild -EventName 'Click' -Handler ({ & $startBuildScript }.GetNewClosure()) | Out-Null
	}

	Initialize-GuiDeploymentMediaMicrosoftIsoOptionList
	& $syncTextScript
	& $initializeProgressChromeScript
	if (-not (& $testIsoInfoPayloadScript -IsoInfo $Script:DeploymentMediaDetectedIsoInfo))
	{
		& $clearDetectedIsoStateScript -Summary 'No ISO inspected yet.' -Preview 'Choose or import a Windows ISO, then run Detect Editions. Preview is optional before Start ISO Build.' -ResetPlan
		$sourceIso = & $getSourceIsoPathScript
		if ([string]::IsNullOrWhiteSpace($sourceIso))
		{
			& $setStatusScript -Message 'Choose an ISO and detect editions to begin.' -Tone 'muted'
		}
		else
		{
			& $setStatusScript -Message 'Run Detect Editions for the selected ISO before previewing or building.' -Tone 'muted'
		}
	}
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media builder view initialized. SourceIso="{0}"; WorkingDirectory="{1}"; OutputMode="{2}"; HasDetectedIso={3}; EditionComboEnabled={4}; EditionItems={5}; PreviewEnabled={6}; StartEnabled={7}' -f (& $getSourceIsoPathScript), $(if ($Script:TxtDeploymentMediaWorkingDirectory) { [string]$Script:TxtDeploymentMediaWorkingDirectory.Text } else { '' }), (Get-GuiDeploymentMediaBuilderOutputMode), [bool]$Script:DeploymentMediaDetectedIsoInfo, $(if ($Script:CmbDeploymentMediaDetectedEdition) { [bool]$Script:CmbDeploymentMediaDetectedEdition.IsEnabled } else { $false }), $(if ($Script:CmbDeploymentMediaDetectedEdition) { [int]$Script:CmbDeploymentMediaDetectedEdition.Items.Count } else { 0 }), $(if ($Script:BtnDeploymentMediaPreviewPlan) { [bool]$Script:BtnDeploymentMediaPreviewPlan.IsEnabled } else { $false }), $(if ($Script:BtnDeploymentMediaStartBuild) { [bool]$Script:BtnDeploymentMediaStartBuild.IsEnabled } else { $false })) -Source 'DeploymentMediaBuilderView.Initialize.Completed'
}
