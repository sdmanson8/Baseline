# DeploymentMediaBuilder.UI.ps1
# Inline view state, status, and background-operation helpers.

function Get-GuiDeploymentMediaBuilderOutputMode
{
	[CmdletBinding()]
	param ()

	if ($Script:CmbDeploymentMediaOutputMode -and $Script:CmbDeploymentMediaOutputMode.SelectedItem)
	{
		$selectedItem = $Script:CmbDeploymentMediaOutputMode.SelectedItem
		if ($selectedItem -and $selectedItem.PSObject.Properties['Content'])
		{
			return [string]$selectedItem.Content
		}
		return [string]$selectedItem
	}

	return 'Create ISO'
}

function Get-GuiDeploymentMediaSharedProgressBarStateCommand
{
	[CmdletBinding()]
	[OutputType([scriptblock])]
	param ()

	if ($Script:DeploymentMediaSharedProgressBarStateScript -is [scriptblock])
	{
		return $Script:DeploymentMediaSharedProgressBarStateScript
	}

	$captured = $null
	if (Get-Command -Name 'Get-GuiFunctionCapture' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$captured = Get-GuiFunctionCapture -Name 'Set-SharedProgressBarState'
	}
	if (-not $captured)
	{
		$command = Get-Command -Name 'Set-SharedProgressBarState' -CommandType Function -ErrorAction SilentlyContinue
		if ($command -and $command.ScriptBlock)
		{
			$scriptBlock = $command.ScriptBlock
			$captured = {
				& $scriptBlock @args
			}.GetNewClosure()
		}
	}
	if (-not $captured)
	{
		throw 'Set-SharedProgressBarState not found.'
	}

	$Script:DeploymentMediaSharedProgressBarStateScript = $captured
	return $Script:DeploymentMediaSharedProgressBarStateScript
}

function Get-GuiDeploymentMediaBuilderEditionName
{
	[CmdletBinding()]
	param ()

	$selectedEdition = Get-GuiDeploymentMediaBuilderSelectedEdition
	if ($selectedEdition -and $selectedEdition.PSObject.Properties['Name'])
	{
		return [string]$selectedEdition.Name
	}

	return ''
}

function Convert-GuiDeploymentMediaBuilderInputPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[string]$Path
	)

	$candidate = ([string]$Path).Trim()
	if ([string]::IsNullOrWhiteSpace($candidate)) { return '' }
	$candidate = $candidate.Trim('"')
	if ([string]::IsNullOrWhiteSpace($candidate)) { return '' }

	try { return [System.IO.Path]::GetFullPath($candidate) }
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.ConvertInputPath.GetFullPath' -Severity Warning
		}
		return $candidate
	}
}

function Get-GuiDeploymentMediaBuilderSourceIsoPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if (-not $Script:TxtDeploymentMediaSourceIso) { return '' }
	return Convert-GuiDeploymentMediaBuilderInputPath -Path ([string]$Script:TxtDeploymentMediaSourceIso.Text)
}

function Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso
{
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	if (-not $Script:DeploymentMediaDetectedIsoInfo) { return $false }
	if (-not $Script:DeploymentMediaDetectedIsoInfo.PSObject.Properties['SourceIso']) { return $false }

	$sourceIso = Get-GuiDeploymentMediaBuilderSourceIsoPath
	$detectedSourceIso = Convert-GuiDeploymentMediaBuilderInputPath -Path ([string]$Script:DeploymentMediaDetectedIsoInfo.SourceIso)
	if ([string]::IsNullOrWhiteSpace($sourceIso) -or [string]::IsNullOrWhiteSpace($detectedSourceIso)) { return $false }

	return [string]::Equals($sourceIso, $detectedSourceIso, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-GuiDeploymentMediaBuilderSelectedEdition
{
	[CmdletBinding()]
	param ()

	if (-not $Script:CmbDeploymentMediaDetectedEdition -or -not $Script:CmbDeploymentMediaDetectedEdition.SelectedItem)
	{
		return $null
	}

	$selectedItem = $Script:CmbDeploymentMediaDetectedEdition.SelectedItem
	if ($selectedItem -is [System.Windows.Controls.ComboBoxItem] -and $selectedItem.Tag)
	{
		return $selectedItem.Tag
	}

	if ($selectedItem.PSObject.Properties['Edition'] -and $selectedItem.Edition)
	{
		return $selectedItem.Edition
	}

	$selectedKey = [string]$selectedItem
	if (
		-not [string]::IsNullOrWhiteSpace($selectedKey) -and
		$Script:DeploymentMediaDetectedEditionLookup -and
		$Script:DeploymentMediaDetectedEditionLookup.ContainsKey($selectedKey)
	)
	{
		return $Script:DeploymentMediaDetectedEditionLookup[$selectedKey]
	}

	if ($Script:DeploymentMediaDetectedIsoInfo -and $Script:DeploymentMediaDetectedIsoInfo.PSObject.Properties['Editions'])
	{
		$editionIndex = 0
		if ($selectedItem.PSObject.Properties['Index'])
		{
			[void][int]::TryParse([string]$selectedItem.Index, [ref]$editionIndex)
		}
		elseif ($Script:TxtDeploymentMediaEditionIndex)
		{
			[void][int]::TryParse([string]$Script:TxtDeploymentMediaEditionIndex.Text, [ref]$editionIndex)
		}

		foreach ($edition in @($Script:DeploymentMediaDetectedIsoInfo.Editions))
		{
			if ($edition.PSObject.Properties['Index'] -and [int]$edition.Index -eq $editionIndex)
			{
				return $edition
			}
		}
	}

	return $null
}

function New-GuiDeploymentMediaBuilderEditionItem
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Edition
	)

	if (-not $Edition.PSObject.Properties['Index'])
	{
		return $null
	}

	$index = 0
	if (-not [int]::TryParse([string]$Edition.Index, [ref]$index) -or $index -lt 1)
	{
		return $null
	}

	$name = ''
	if ($Edition.PSObject.Properties['Name'])
	{
		$name = [string]$Edition.Name
	}
	if ([string]::IsNullOrWhiteSpace($name) -and $Edition.PSObject.Properties['ImageName'])
	{
		$name = [string]$Edition.ImageName
	}
	if ([string]::IsNullOrWhiteSpace($name))
	{
		$name = 'Windows image'
	}

	$architecture = ''
	if ($Edition.PSObject.Properties['Architecture'])
	{
		$architecture = [string]$Edition.Architecture
	}

	$displayName = ('{0}: {1}' -f $index, $name)
	if (-not [string]::IsNullOrWhiteSpace($architecture))
	{
		$displayName = ('{0} ({1})' -f $displayName, $architecture)
	}

	return [pscustomobject]@{
		DisplayName  = $displayName
		Index        = $index
		Name         = $name
		Architecture = $architecture
		Edition      = $Edition
	}
}

function Set-GuiDeploymentMediaBuilderDetectedIsoInfo
{
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$IsoInfo
	)

	$Script:DeploymentMediaDetectedIsoInfo = $IsoInfo
	return (Set-GuiDeploymentMediaBuilderDetectedEditionItems -IsoInfo $IsoInfo)
}

function Set-GuiDeploymentMediaBuilderDetectedEditionItems
{
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$IsoInfo
	)

	$Script:DeploymentMediaDetectedEditionLookup = @{}
	if (-not $Script:CmbDeploymentMediaDetectedEdition)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message 'Deployment media edition binding skipped because the edition ComboBox is not available.' -Source 'DeploymentMediaBuilderView.EditionBinding.NoCombo'
		return 0
	}

	$Script:CmbDeploymentMediaDetectedEdition.ItemsSource = $null
	$Script:CmbDeploymentMediaDetectedEdition.Items.Clear()
	$Script:CmbDeploymentMediaDetectedEdition.DisplayMemberPath = 'DisplayName'
	$Script:CmbDeploymentMediaDetectedEdition.SelectedValuePath = 'Index'

	if (-not $IsoInfo -or -not $IsoInfo.PSObject.Properties['Editions'])
	{
		$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $false
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message 'Deployment media edition binding received no usable ISO info payload.' -Source 'DeploymentMediaBuilderView.EditionBinding.NoPayload'
		return 0
	}

	$items = [System.Collections.Generic.List[object]]::new()
	foreach ($edition in @($IsoInfo.Editions))
	{
		$item = New-GuiDeploymentMediaBuilderEditionItem -Edition $edition
		if (-not $item) { continue }

		$Script:DeploymentMediaDetectedEditionLookup[[string]$item.DisplayName] = $edition
		$Script:DeploymentMediaDetectedEditionLookup[[string]$item.Index] = $edition
		[void]$items.Add($item)
	}

	$Script:CmbDeploymentMediaDetectedEdition.ItemsSource = @($items.ToArray())
	$itemCount = @($items.ToArray()).Count
	$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = ($itemCount -gt 0)
	if ($itemCount -gt 0)
	{
		$Script:CmbDeploymentMediaDetectedEdition.SelectedIndex = 0
		Sync-GuiDeploymentMediaBuilderEditionSelection
	}
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media edition binding completed. ImageKind="{0}"; ImagePath="{1}"; SourceIso="{2}"; Items={3}; ComboItems={4}; IsEnabled={5}; SelectedIndex={6}; TextIndex="{7}"' -f $(if ($IsoInfo.PSObject.Properties['ImageKind']) { [string]$IsoInfo.ImageKind } else { '' }), $(if ($IsoInfo.PSObject.Properties['ImagePath']) { [string]$IsoInfo.ImagePath } else { '' }), $(if ($IsoInfo.PSObject.Properties['SourceIso']) { [string]$IsoInfo.SourceIso } else { '' }), $itemCount, [int]$Script:CmbDeploymentMediaDetectedEdition.Items.Count, [bool]$Script:CmbDeploymentMediaDetectedEdition.IsEnabled, [int]$Script:CmbDeploymentMediaDetectedEdition.SelectedIndex, $(if ($Script:TxtDeploymentMediaEditionIndex) { [string]$Script:TxtDeploymentMediaEditionIndex.Text } else { '' })) -Source 'DeploymentMediaBuilderView.EditionBinding.Completed'

	return [int]$itemCount
}

function Sync-GuiDeploymentMediaBuilderEditionSelection
{
	[CmdletBinding()]
	param ()

	$selectedEdition = Get-GuiDeploymentMediaBuilderSelectedEdition
	if ($selectedEdition -and $selectedEdition.PSObject.Properties['Index'] -and $Script:TxtDeploymentMediaEditionIndex)
	{
		$Script:TxtDeploymentMediaEditionIndex.Text = [string]$selectedEdition.Index
	}
}

function Get-GuiDeploymentMediaBuilderPlan
{
	[CmdletBinding()]
	param ()

	$editionIndex = 1
	if ($Script:TxtDeploymentMediaEditionIndex)
	{
		if (-not [int]::TryParse([string]$Script:TxtDeploymentMediaEditionIndex.Text, [ref]$editionIndex))
		{
			$editionIndex = 0
		}
	}

	return New-GuiDeploymentMediaBuildPlan `
		-SourceIso (Get-GuiDeploymentMediaBuilderSourceIsoPath) `
		-WorkingDirectory $(if ($Script:TxtDeploymentMediaWorkingDirectory) { [string]$Script:TxtDeploymentMediaWorkingDirectory.Text } else { '' }) `
		-EditionIndex $editionIndex `
		-EditionName (Get-GuiDeploymentMediaBuilderEditionName) `
		-AutounattendPath $(if ($Script:TxtDeploymentMediaAutounattend) { [string]$Script:TxtDeploymentMediaAutounattend.Text } else { '' }) `
		-DriverSource $(if ($Script:TxtDeploymentMediaDriverSource) { [string]$Script:TxtDeploymentMediaDriverSource.Text } else { '' }) `
		-UsbTargetRoot $(if ($Script:TxtDeploymentMediaUsbTargetRoot) { [string]$Script:TxtDeploymentMediaUsbTargetRoot.Text } else { '' }) `
		-IsoImageInfo $Script:DeploymentMediaDetectedIsoInfo `
		-OutputMode (Get-GuiDeploymentMediaBuilderOutputMode) `
		-InjectBootDrivers:([bool]($Script:ChkDeploymentMediaBootDrivers -and $Script:ChkDeploymentMediaBootDrivers.IsChecked)) `
		-IncludeBaselineTweaks:([bool]($Script:ChkDeploymentMediaBaselineTweaks -and $Script:ChkDeploymentMediaBaselineTweaks.IsChecked))
}

function Test-GuiDeploymentMediaBuilderPreviewPrerequisites
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ()

	$sourceIso = Get-GuiDeploymentMediaBuilderSourceIsoPath
	if ([string]::IsNullOrWhiteSpace($sourceIso))
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 1: choose or import a Windows ISO before previewing or building.' }
	}
	if ([System.IO.Path]::GetExtension($sourceIso) -ne '.iso')
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 1: the source path must point to an .iso file.' }
	}
	if (-not (Test-Path -LiteralPath $sourceIso -PathType Leaf -ErrorAction SilentlyContinue))
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 1: the selected ISO path does not exist.' }
	}
	if (-not $Script:DeploymentMediaDetectedIsoInfo)
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 2: run Detect Editions for the selected ISO.' }
	}
	if (-not (Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso))
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 2: run Detect Editions again after changing the source ISO.' }
	}
	if (-not $Script:CmbDeploymentMediaDetectedEdition -or -not $Script:CmbDeploymentMediaDetectedEdition.SelectedItem)
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 2: select a detected Windows edition.' }
	}

	$editionIndex = 0
	if (-not $Script:TxtDeploymentMediaEditionIndex -or -not [int]::TryParse([string]$Script:TxtDeploymentMediaEditionIndex.Text, [ref]$editionIndex) -or $editionIndex -lt 1)
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 2: choose a valid image index.' }
	}

	$workingDirectory = ''
	if ($Script:TxtDeploymentMediaWorkingDirectory)
	{
		$workingDirectory = ([string]$Script:TxtDeploymentMediaWorkingDirectory.Text).Trim()
	}
	if ([string]::IsNullOrWhiteSpace($workingDirectory))
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 3: choose a working directory.' }
	}
	if (-not [System.IO.Path]::IsPathRooted($workingDirectory))
	{
		return [pscustomobject]@{ Ready = $false; Message = 'Step 3: the working directory must be an absolute path.' }
	}

	if ((Get-GuiDeploymentMediaBuilderOutputMode) -eq 'Create USB')
	{
		$usbTargetRoot = ''
		if ($Script:TxtDeploymentMediaUsbTargetRoot)
		{
			$usbTargetRoot = ([string]$Script:TxtDeploymentMediaUsbTargetRoot.Text).Trim()
		}
		if ([string]::IsNullOrWhiteSpace($usbTargetRoot))
		{
			return [pscustomobject]@{ Ready = $false; Message = 'Step 3: choose a USB target root for Create USB output.' }
		}
	}

	return [pscustomobject]@{ Ready = $true; Message = 'Ready to preview or start the build.' }
}

function Update-GuiDeploymentMediaBuilderPreviewAvailability
{
	[CmdletBinding()]
	param (
		[bool]$ControlsEnabled = $true
	)

	if (-not $Script:BtnDeploymentMediaPreviewPlan -and -not $Script:BtnDeploymentMediaStartBuild) { return }

	$state = Test-GuiDeploymentMediaBuilderPreviewPrerequisites
	$ready = $ControlsEnabled -and -not $Script:DeploymentMediaBuilderOperation -and [bool]$state.Ready
	$actionReady = $false
	$actionMessage = [string]$state.Message
	if ($ready)
	{
		try
		{
			$plan = Get-GuiDeploymentMediaBuilderPlan
			$actionReady = [bool]$plan.IsValid
			if ($actionReady)
			{
				$actionMessage = 'Ready to preview or start ISO build.'
			}
			elseif (@($plan.Errors).Count -gt 0)
			{
				$actionMessage = @($plan.Errors) -join [Environment]::NewLine
			}
		}
		catch
		{
			$actionReady = $false
			$actionMessage = $_.Exception.Message
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.UpdateActionAvailability.Plan' -Severity Warning
		}
	}
	if ($Script:BtnDeploymentMediaPreviewPlan)
	{
		$Script:BtnDeploymentMediaPreviewPlan.IsEnabled = $actionReady
		$Script:BtnDeploymentMediaPreviewPlan.ToolTip = $actionMessage
	}
	if ($Script:BtnDeploymentMediaStartBuild)
	{
		if ($Script:DeploymentMediaBuilderOperation)
		{
			$Script:BtnDeploymentMediaStartBuild.IsEnabled = $true
		}
		else
		{
			$Script:BtnDeploymentMediaStartBuild.IsEnabled = $actionReady
			$Script:BtnDeploymentMediaStartBuild.ToolTip = $actionMessage
		}
	}

	$diagnosticKey = ('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $actionReady, $ControlsEnabled, [bool]$Script:DeploymentMediaBuilderOperation, [bool]$state.Ready, [string]$actionMessage, (Get-GuiDeploymentMediaBuilderSourceIsoPath), $(if ($Script:BtnDeploymentMediaStartBuild) { [bool]$Script:BtnDeploymentMediaStartBuild.IsEnabled } else { $false }))
	$lastDiagnosticKey = ''
	$lastDiagnosticKeyVariable = Get-Variable -Scope Script -Name DeploymentMediaLastPreviewAvailabilityKey -ErrorAction SilentlyContinue
	if ($lastDiagnosticKeyVariable) { $lastDiagnosticKey = [string]$lastDiagnosticKeyVariable.Value }
	if ($lastDiagnosticKey -ne $diagnosticKey)
	{
		$Script:DeploymentMediaLastPreviewAvailabilityKey = $diagnosticKey
		try
		{
			$detectedSource = if ($Script:DeploymentMediaDetectedIsoInfo -and $Script:DeploymentMediaDetectedIsoInfo.PSObject.Properties['SourceIso']) { [string]$Script:DeploymentMediaDetectedIsoInfo.SourceIso } else { '' }
			$editionItems = if ($Script:CmbDeploymentMediaDetectedEdition) { [int]$Script:CmbDeploymentMediaDetectedEdition.Items.Count } else { 0 }
			$selectedEdition = if ($Script:CmbDeploymentMediaDetectedEdition) { [int]$Script:CmbDeploymentMediaDetectedEdition.SelectedIndex } else { -1 }
			LogDebug ('Deployment media action availability changed. Ready={0}; ControlsEnabled={1}; OperationActive={2}; PrerequisitesReady={3}; Reason="{4}"; SourceIso="{5}"; DetectedSourceIso="{6}"; EditionItems={7}; SelectedEditionIndex={8}; StartEnabled={9}' -f $actionReady, $ControlsEnabled, [bool]$Script:DeploymentMediaBuilderOperation, [bool]$state.Ready, [string]$actionMessage, (Get-GuiDeploymentMediaBuilderSourceIsoPath), $detectedSource, $editionItems, $selectedEdition, $(if ($Script:BtnDeploymentMediaStartBuild) { [bool]$Script:BtnDeploymentMediaStartBuild.IsEnabled } else { $false }))
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.UpdatePreviewAvailability.Log' -Severity Warning
		}
	}
}

function Set-GuiDeploymentMediaBuilderStatus
{
	[CmdletBinding()]
	param (
		[string]$Message = '',
		[ValidateSet('muted', 'success', 'warning', 'error')]
		[string]$Tone = 'muted',
		[switch]$ShowBanner
	)

	$theme = $Script:CurrentTheme
	$color = if ($theme) { [string]$theme.TextSecondary } else { '#CDD6EA' }
	switch ($Tone)
	{
		'success' { if ($theme) { $color = [string]$theme.LogSuccess } }
		'warning' { if ($theme) { $color = [string]$theme.LogWarning } }
		'error' { if ($theme) { $color = [string]$theme.LogError } }
	}

	$brush = $null
	try { $brush = ConvertTo-GuiBrush -Color $color -Context 'DeploymentMediaBuilderView.Status' }
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.SetStatus.ConvertBrush' -Severity Warning
		$brush = $null
	}

	$inlineStatusText = if ($ShowBanner) { '' } else { [string]$Message }
	if ($Script:TxtDeploymentMediaSelectionStatus)
	{
		$Script:TxtDeploymentMediaSelectionStatus.Text = $inlineStatusText
		if ($brush) { $Script:TxtDeploymentMediaSelectionStatus.Foreground = $brush }
	}
	if ($Script:TxtDeploymentMediaBuildStatus)
	{
		$Script:TxtDeploymentMediaBuildStatus.Text = [string]$Message
		if ($brush) { $Script:TxtDeploymentMediaBuildStatus.Foreground = $brush }
	}

	if ($Script:DeploymentMediaStatusBanner)
	{
		try
		{
			$bannerBackground = $null
			$bannerBorder = $null
			switch ($Tone)
			{
				'success'
				{
					if ($theme)
					{
						$bannerBackground = [string]$theme.LowRiskBadgeBg
						$bannerBorder = [string]$theme.LowRiskBadge
					}
				}
				'warning'
				{
					if ($theme)
					{
						$bannerBackground = [string]$theme.RiskMediumBadgeBg
						$bannerBorder = [string]$theme.RiskMediumBadge
					}
				}
				'error'
				{
					if ($theme)
					{
						$bannerBackground = [string]$theme.RiskHighBadgeBg
						$bannerBorder = [string]$theme.RiskHighBadge
					}
				}
				default
				{
					if ($theme)
					{
						$bannerBackground = [string]$theme.CardBg
						$bannerBorder = [string]$theme.CardBorder
					}
				}
			}
			if (-not [string]::IsNullOrWhiteSpace($bannerBackground))
			{
				$Script:DeploymentMediaStatusBanner.Background = ConvertTo-GuiBrush -Color $bannerBackground -Context 'DeploymentMediaBuilderView.StatusBanner.Background'
			}
			if (-not [string]::IsNullOrWhiteSpace($bannerBorder))
			{
				$Script:DeploymentMediaStatusBanner.BorderBrush = ConvertTo-GuiBrush -Color $bannerBorder -Context 'DeploymentMediaBuilderView.StatusBanner.Border'
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.SetStatus.BannerBrush' -Severity Warning
		}
		$Script:DeploymentMediaStatusBanner.Visibility = if ($ShowBanner -and -not [string]::IsNullOrWhiteSpace([string]$Message)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
	}
}

function Format-GuiDeploymentMediaBuilderByteProgressText
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[long]$CompletedBytes,
		[long]$TotalBytes,
		[string]$Operation = 'Copying deployment media',
		[long]$RemainingSeconds = -1
	)

	$safeCompleted = [Math]::Max([int64]0, [int64]$CompletedBytes)
	$safeTotal = [Math]::Max([int64]1, [int64]$TotalBytes)
	$completedGb = $safeCompleted / 1GB
	$totalGb = $safeTotal / 1GB
	$pct = if ($TotalBytes -le 0)
	{
		if ($CompletedBytes -ge $TotalBytes) { 100.0 } else { 0.0 }
	}
	else
	{
		[Math]::Round(($safeCompleted / [double]$safeTotal) * 100, 1)
	}
	$remainingText = if ($RemainingSeconds -ge 0)
	{
		$remaining = [TimeSpan]::FromSeconds([double]$RemainingSeconds)
		if ($remaining.TotalHours -ge 1) { '{0:00}:{1:00}:{2:00}' -f [int]$remaining.TotalHours, $remaining.Minutes, $remaining.Seconds }
		else { '{0:00}:{1:00}' -f $remaining.Minutes, $remaining.Seconds }
	}
	else
	{
		'calculating'
	}

	return ('{0}: {1:N2}/{2:N2} GB ({3:N1}%). Time remaining: {4}.' -f $Operation, $completedGb, $totalGb, $pct, $remainingText)
}

function Set-GuiDeploymentMediaBuilderProgressState
{
	[CmdletBinding()]
	param (
		[object]$Progress,
		[string]$Message = '',
		[switch]$Indeterminate,
		[switch]$Hide,
		[switch]$Failed,
		[switch]$Complete
	)

	if (-not $Script:DeploymentMediaProgressPanel) { return }

	if ($Hide)
	{
		$Script:DeploymentMediaProgressPanel.Visibility = [System.Windows.Visibility]::Collapsed
		if ($Script:DeploymentMediaProgressBar)
		{
			$Script:DeploymentMediaProgressBar.IsIndeterminate = $false
			$Script:DeploymentMediaProgressBar.Maximum = 1
			$Script:DeploymentMediaProgressBar.Value = 0
		}
		if ($Script:TxtDeploymentMediaProgressText) { $Script:TxtDeploymentMediaProgressText.Text = '' }
		return
	}

	$Script:DeploymentMediaProgressPanel.Visibility = [System.Windows.Visibility]::Visible
	$displayText = [string]$Message
	$completedUnits = 0
	$totalUnits = 0
	$isByteProgress = $false

	if ($Progress -and $Progress.PSObject.Properties['IsByteProgress'] -and [bool]$Progress.IsByteProgress)
	{
		$isByteProgress = $true
		$completedBytes = if ($Progress.PSObject.Properties['CompletedBytes']) { [int64]$Progress.CompletedBytes } else { [int64]0 }
		$totalBytes = if ($Progress.PSObject.Properties['TotalBytes']) { [int64]$Progress.TotalBytes } else { [int64]0 }
		$remainingSeconds = if ($Progress.PSObject.Properties['RemainingSeconds']) { [int64]$Progress.RemainingSeconds } else { [int64]-1 }
		$operation = if ($Progress.PSObject.Properties['Operation'] -and -not [string]::IsNullOrWhiteSpace([string]$Progress.Operation)) { [string]$Progress.Operation } else { 'Copying deployment media' }
		$displayText = if ($Progress.PSObject.Properties['DisplayText'] -and -not [string]::IsNullOrWhiteSpace([string]$Progress.DisplayText))
		{
			[string]$Progress.DisplayText
		}
		else
		{
			Format-GuiDeploymentMediaBuilderByteProgressText -CompletedBytes $completedBytes -TotalBytes $totalBytes -Operation $operation -RemainingSeconds $remainingSeconds
		}
		$totalUnits = 10000
		$safeTotalBytes = [Math]::Max([int64]1, $totalBytes)
		$clampedCompletedBytes = [Math]::Min([Math]::Max([int64]0, $completedBytes), $safeTotalBytes)
		$completedUnits = [int][Math]::Floor(($clampedCompletedBytes / [double]$safeTotalBytes) * $totalUnits)
		if ($totalBytes -le 0 -and $completedBytes -ge $totalBytes) { $completedUnits = $totalUnits }
		if ($completedUnits -gt $totalUnits) { $completedUnits = $totalUnits }
	}
	elseif ($Progress -and $Progress.PSObject.Properties['Message'])
	{
		$displayText = [string]$Progress.Message
	}

	if ([string]::IsNullOrWhiteSpace($displayText))
	{
		$displayText = if ($Complete) { 'Deployment media operation completed.' } elseif ($Failed) { 'Deployment media operation failed.' } else { 'Working...' }
	}

	if ($Script:DeploymentMediaProgressBar)
	{
		$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand
		if ($isByteProgress -and $totalUnits -gt 0)
		{
			& $setSharedProgressBarState -ProgressBar $Script:DeploymentMediaProgressBar -Completed $completedUnits -Total $totalUnits | Out-Null
		}
		elseif ($Complete)
		{
			& $setSharedProgressBarState -ProgressBar $Script:DeploymentMediaProgressBar -Completed 1 -Total 1 | Out-Null
		}
		elseif ($Failed)
		{
			& $setSharedProgressBarState -ProgressBar $Script:DeploymentMediaProgressBar -Completed 0 -Total 1 | Out-Null
		}
		else
		{
			& $setSharedProgressBarState -ProgressBar $Script:DeploymentMediaProgressBar -CurrentAction $displayText -Indeterminate | Out-Null
		}
	}
	if ($Script:TxtDeploymentMediaProgressText)
	{
		$Script:TxtDeploymentMediaProgressText.Text = $displayText
	}
}

function Initialize-GuiDeploymentMediaBuilderProgressChrome
{
	[CmdletBinding()]
	param ()

	if ($Script:DeploymentMediaProgressBar)
	{
		try
		{
			$Script:DeploymentMediaProgressBar.Template = New-GuiExecutionProgressBarTemplate
			Set-SheenProgressBarTheme -ProgressBar $Script:DeploymentMediaProgressBar
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.InitializeProgressChrome' -Severity Warning }
	}
	Set-GuiDeploymentMediaBuilderProgressState -Hide
}

function Get-GuiDeploymentMediaBuilderThemeValue
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[object]$Theme,
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[string]$Default
	)

	if ($Theme -and $Theme -is [System.Collections.IDictionary] -and $Theme.Contains($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Theme[$Name]))
	{
		return [string]$Theme[$Name]
	}
	if ($Theme -and $Theme.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string]$Theme.$Name))
	{
		return [string]$Theme.$Name
	}
	return $Default
}

function New-GuiDeploymentMediaBuildPlanPreviewResult
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[string]$Status = 'Preview',
		[string]$Detail = '',
		[string]$Group = 'Build plan',
		[int]$Order = 0,
		[string]$TypeLabel = 'Deployment media',
		[string]$TypeTone = 'Primary'
	)

	$groupSortOrder = switch ($Group)
	{
		'Validation' { 0; break }
		'Source' { 1; break }
		'Output' { 2; break }
		'Customizations' { 3; break }
		'Build steps' { 4; break }
		default { 9 }
	}

	return [pscustomobject]@{
		Name = $Name
		Status = $Status
		Detail = $Detail
		Order = $Order
		PreviewGroupHeader = $Group
		PreviewGroupSortOrder = $groupSortOrder
		TypeLabel = $TypeLabel
		TypeTone = $TypeTone
	}
}

function Show-GuiDeploymentMediaBuildPlanPreviewDialog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan
	)

	$errors = @($Plan.Errors)
	$sourceIsoName = if ([string]::IsNullOrWhiteSpace([string]$Plan.SourceIso)) { 'No source ISO selected' } else { [System.IO.Path]::GetFileName([string]$Plan.SourceIso) }
	$editionLabel = if ([string]::IsNullOrWhiteSpace([string]$Plan.EditionName)) { ('Image index {0}' -f [int]$Plan.EditionIndex) } else { ('{0}: {1}' -f [int]$Plan.EditionIndex, [string]$Plan.EditionName) }
	$detectedImage = ''
	if ($Plan.IsoImageInfo -and $Plan.IsoImageInfo.PSObject.Properties['ImagePath'])
	{
		$detectedImage = ('{0} ({1})' -f [string]$Plan.IsoImageInfo.ImagePath, [string]$Plan.IsoImageInfo.ImageKind)
	}

	$summaryCards = @(
		[pscustomobject]@{ Label = 'Validation'; Value = $(if ([bool]$Plan.IsValid) { 'Ready' } else { 'Blocked' }); Detail = $(if ([bool]$Plan.IsValid) { 'No blocking errors' } else { ('{0} issue(s)' -f $errors.Count) }); Tone = $(if ([bool]$Plan.IsValid) { 'Success' } else { 'Danger' }) },
		[pscustomobject]@{ Label = 'Source ISO'; Value = $sourceIsoName; Detail = [string]$Plan.SourceIso; Tone = 'Primary' },
		[pscustomobject]@{ Label = 'Edition'; Value = $editionLabel; Detail = $detectedImage; Tone = 'Primary' },
		[pscustomobject]@{ Label = 'Output'; Value = [string]$Plan.OutputMode; Detail = [string]$Plan.WorkingDirectory; Tone = 'Primary' }
	)

	$results = [System.Collections.Generic.List[object]]::new()
	if ($errors.Count -gt 0)
	{
		$order = 0
		foreach ($errorText in $errors)
		{
			$order++
			[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Blocking validation issue' -Status 'Failed' -Detail ([string]$errorText) -Group 'Validation' -Order $order -TypeLabel 'Validation' -TypeTone 'Danger'))
		}
	}
	else
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Validation passed' -Detail 'All required deployment media inputs are present.' -Group 'Validation' -Order 1 -TypeLabel 'Validation' -TypeTone 'Success'))
	}

	[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Source ISO' -Detail ([string]$Plan.SourceIso) -Group 'Source' -Order 1))
	if (-not [string]::IsNullOrWhiteSpace($detectedImage))
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Detected install image' -Detail $detectedImage -Group 'Source' -Order 2))
	}
	[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Selected Windows edition' -Detail $editionLabel -Group 'Source' -Order 3))
	[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Working directory' -Detail ([string]$Plan.WorkingDirectory) -Group 'Output' -Order 1))
	[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Output mode' -Detail ([string]$Plan.OutputMode) -Group 'Output' -Order 2))
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.UsbTargetRoot))
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'USB target' -Detail ([string]$Plan.UsbTargetRoot) -Group 'Output' -Order 3))
	}
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.AutounattendPath))
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Autounattend.xml' -Detail ([string]$Plan.AutounattendPath) -Group 'Customizations' -Order 1))
	}
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.DriverSource))
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Driver folder' -Detail ([string]$Plan.DriverSource) -Group 'Customizations' -Order 2))
	}
	if ([bool]$Plan.InjectBootDrivers)
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Boot driver injection' -Detail 'Storage and network drivers will also be injected into boot.wim.' -Group 'Customizations' -Order 3))
	}
	if ([bool]$Plan.IncludeBaselineTweaks)
	{
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name 'Baseline setup customizations' -Detail 'Selected Baseline setup customizations will be staged as an auditable first-logon plan.' -Group 'Customizations' -Order 4))
	}

	$stepOrder = 0
	foreach ($step in @($Plan.Steps))
	{
		$stepOrder++
		[void]$results.Add((New-GuiDeploymentMediaBuildPlanPreviewResult -Name ('Step {0}' -f $stepOrder) -Detail ([string]$step) -Group 'Build steps' -Order $stepOrder -TypeLabel 'Build step' -TypeTone 'Muted'))
	}

	return (Show-ExecutionSummaryDialog -Title 'Preview Build Plan' `
		-SummaryText $(if ([bool]$Plan.IsValid) { 'Review the deployment media build plan before starting the ISO build.' } else { 'Resolve the validation issues before starting the ISO build.' }) `
		-SummaryCards $summaryCards `
		-Results @($results.ToArray()) `
		-LogPath $Global:LogFilePath `
		-Buttons @('Close'))
}

function Add-GuiDeploymentMediaBuildDialogLogLine
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Dialog,
		[string]$Text,
		[string]$Level = 'INFO'
	)

	if (-not $Dialog -or -not $Dialog.LogBox -or -not $Dialog.LogBox.Document) { return }
	$cleanText = ([string]$Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
	if ([string]::IsNullOrWhiteSpace($cleanText)) { return }

	try
	{
		$theme = if ($Script:CurrentTheme) { $Script:CurrentTheme } else { @{} }
		$color = switch ([string]$Level)
		{
			'SUCCESS' { Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'ToggleOn' -Default '#10B981'; break }
			'WARNING' { Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'RiskMediumBadge' -Default '#D97706'; break }
			'ERROR' { Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'CautionText' -Default '#B91C1C'; break }
			default { Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextPrimary' -Default '#111827' }
		}
		$bc = if ($Script:SharedBrushConverter) { $Script:SharedBrushConverter } else { [System.Windows.Media.BrushConverter]::new() }
		$paragraph = New-Object System.Windows.Documents.Paragraph
		$paragraph.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
		$paragraph.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
		$paragraph.FontSize = 12
		$run = New-Object System.Windows.Documents.Run
		$run.Text = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $cleanText)
		$run.Foreground = $bc.ConvertFromString($color)
		[void]$paragraph.Inlines.Add($run)
		[void]$Dialog.LogBox.Document.Blocks.Add($paragraph)
		$Dialog.LogBox.ScrollToEnd()
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BuildDialog.AddLogLine' -Severity Warning
	}
}

function Add-GuiDeploymentMediaBuildDialogProgressLog
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Dialog,
		[object]$Progress,
		[string]$Message
	)

	if (-not $Dialog) { return }
	$logKey = ''
	$logText = [string]$Message
	if ($Progress -and $Progress.PSObject.Properties['IsByteProgress'] -and [bool]$Progress.IsByteProgress)
	{
		$completedBytes = if ($Progress.PSObject.Properties['CompletedBytes']) { [int64]$Progress.CompletedBytes } else { [int64]0 }
		$totalBytes = if ($Progress.PSObject.Properties['TotalBytes']) { [int64]$Progress.TotalBytes } else { [int64]0 }
		$operation = if ($Progress.PSObject.Properties['Operation'] -and -not [string]::IsNullOrWhiteSpace([string]$Progress.Operation)) { [string]$Progress.Operation } else { 'Copying deployment media' }
		$phase = ''
		if ($completedBytes -le 0)
		{
			$phase = 'started'
			$logText = ('{0} started.' -f $operation)
		}
		elseif ($totalBytes -gt 0 -and $completedBytes -ge $totalBytes)
		{
			$phase = 'completed'
			$logText = ('{0} completed.' -f $operation)
		}
		if ([string]::IsNullOrWhiteSpace($phase)) { return }
		$logKey = 'byte:{0}:{1}' -f $operation, $phase
	}
	else
	{
		if ([string]::IsNullOrWhiteSpace($logText)) { return }
		$logKey = 'message:{0}' -f $logText
	}

	if ($Dialog.LastLoggedStatusKey -eq $logKey) { return }
	$Dialog.LastLoggedStatusKey = $logKey
	Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $Dialog -Text $logText
}

function Set-GuiDeploymentMediaBuildDialogProgressState
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Dialog,
		[object]$Progress,
		[string]$Message = '',
		[switch]$Indeterminate,
		[switch]$Failed,
		[switch]$Complete
	)

	if (-not $Dialog -or -not $Dialog.ProgressBar) { return }

	$displayText = [string]$Message
	$completedUnits = 0
	$totalUnits = 0
	$isByteProgress = $false
	if ($Progress -and $Progress.PSObject.Properties['IsByteProgress'] -and [bool]$Progress.IsByteProgress)
	{
		$isByteProgress = $true
		$completedBytes = if ($Progress.PSObject.Properties['CompletedBytes']) { [int64]$Progress.CompletedBytes } else { [int64]0 }
		$totalBytes = if ($Progress.PSObject.Properties['TotalBytes']) { [int64]$Progress.TotalBytes } else { [int64]0 }
		$remainingSeconds = if ($Progress.PSObject.Properties['RemainingSeconds']) { [int64]$Progress.RemainingSeconds } else { [int64]-1 }
		$operation = if ($Progress.PSObject.Properties['Operation'] -and -not [string]::IsNullOrWhiteSpace([string]$Progress.Operation)) { [string]$Progress.Operation } else { 'Copying deployment media' }
		$displayText = if ($Progress.PSObject.Properties['DisplayText'] -and -not [string]::IsNullOrWhiteSpace([string]$Progress.DisplayText))
		{
			[string]$Progress.DisplayText
		}
		else
		{
			Format-GuiDeploymentMediaBuilderByteProgressText -CompletedBytes $completedBytes -TotalBytes $totalBytes -Operation $operation -RemainingSeconds $remainingSeconds
		}
		$totalUnits = 10000
		$safeTotalBytes = [Math]::Max([int64]1, $totalBytes)
		$clampedCompletedBytes = [Math]::Min([Math]::Max([int64]0, $completedBytes), $safeTotalBytes)
		$completedUnits = [int][Math]::Floor(($clampedCompletedBytes / [double]$safeTotalBytes) * $totalUnits)
		if ($totalBytes -le 0 -and $completedBytes -ge $totalBytes) { $completedUnits = $totalUnits }
		if ($completedUnits -gt $totalUnits) { $completedUnits = $totalUnits }
	}
	elseif ($Progress -and $Progress.PSObject.Properties['Message'])
	{
		$displayText = [string]$Progress.Message
	}

	if ([string]::IsNullOrWhiteSpace($displayText))
	{
		$displayText = if ($Complete) { 'Deployment media build completed.' } elseif ($Failed) { 'Deployment media build failed.' } else { 'Working...' }
	}

	if ($isByteProgress -and $totalUnits -gt 0)
	{
		$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand
		& $setSharedProgressBarState -ProgressBar $Dialog.ProgressBar -Completed $completedUnits -Total $totalUnits | Out-Null
	}
	elseif ($Complete)
	{
		$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand
		& $setSharedProgressBarState -ProgressBar $Dialog.ProgressBar -Completed 1 -Total 1 | Out-Null
	}
	elseif ($Failed)
	{
		$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand
		& $setSharedProgressBarState -ProgressBar $Dialog.ProgressBar -Completed 0 -Total 1 | Out-Null
	}
	else
	{
		$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand
		& $setSharedProgressBarState -ProgressBar $Dialog.ProgressBar -CurrentAction $displayText -Indeterminate | Out-Null
	}
	if ($Dialog.ProgressText) { $Dialog.ProgressText.Text = $displayText }
}

function Complete-GuiDeploymentMediaBuildProgressDialog
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Dialog,
		[string]$Message,
		[string]$Level = 'INFO',
		[switch]$Failed
	)

	if (-not $Dialog) { return }
	$Dialog.State = 'Complete'
	$Dialog.AllowClose = $true
	if ($Dialog.AbortButton)
	{
		$Dialog.AbortButton.Content = 'Close'
		$Dialog.AbortButton.IsEnabled = $true
		Set-ButtonChrome -Button $Dialog.AbortButton -Variant $(if ($Failed) { 'Secondary' } else { 'Primary' })
	}
	$completed = -not [bool]$Failed
	Set-GuiDeploymentMediaBuildDialogProgressState -Dialog $Dialog -Message $Message -Complete:$completed -Failed:([bool]$Failed)
	Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $Dialog -Text $Message -Level $Level
}

function Show-GuiDeploymentMediaBuildProgressDialog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan
	)

	$theme = if ($Script:CurrentTheme) { $Script:CurrentTheme } else { @{} }
	$bc = if ($Script:SharedBrushConverter) { $Script:SharedBrushConverter } else { [System.Windows.Media.BrushConverter]::new() }
	$dialogRef = @{ Dialog = $null }

	$window = New-Object System.Windows.Window
	$window.Title = 'Deployment Media Build'
	$window.Width = 780
	$window.Height = 540
	$window.MinWidth = 680
	$window.MinHeight = 460
	$window.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip
	$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
	$window.ShowInTaskbar = $false
	$window.WindowStyle = [System.Windows.WindowStyle]::None
	$window.AllowsTransparency = $true
	$window.Background = [System.Windows.Media.Brushes]::Transparent
	if ($Form) { try { $window.Owner = $Form } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BuildDialog.Owner' -Severity Warning } }

	$rootBorder = New-Object System.Windows.Controls.Border
	$rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	$rootBorder.Background = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'WindowBg' -Default '#FFFFFF'))
	$rootBorder.BorderBrush = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'BorderColor' -Default '#D8DEE8'))

	$dock = New-Object System.Windows.Controls.DockPanel
	$dock.LastChildFill = $true
	$titleBar = New-Object System.Windows.Controls.Border
	$titleBar.Background = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'HeaderBg' -Default '#F7F8FA'))
	$titleBar.BorderBrush = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'BorderColor' -Default '#D8DEE8'))
	$titleBar.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
	$titleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
	$titleBar.Padding = [System.Windows.Thickness]::new(12, 8, 8, 8)
	$titleGrid = New-Object System.Windows.Controls.Grid
	[void]$titleGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
	[void]$titleGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto }))
	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.Text = 'Deployment Media Build'
	$titleText.VerticalAlignment = 'Center'
	$titleText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$titleText.FontSize = 12
	$titleText.FontWeight = [System.Windows.FontWeights]::SemiBold
	$titleText.Foreground = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextPrimary' -Default '#111827'))
	[System.Windows.Controls.Grid]::SetColumn($titleText, 0)
	[void]$titleGrid.Children.Add($titleText)
	$closeButton = New-Object System.Windows.Controls.Button
	$closeButton.Content = 'x'
	$closeButton.Width = 32
	$closeButton.Height = 28
	$closeButton.Background = [System.Windows.Media.Brushes]::Transparent
	$closeButton.Foreground = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextPrimary' -Default '#111827'))
	$closeButton.BorderThickness = [System.Windows.Thickness]::new(0)
	$closeButton.Cursor = [System.Windows.Input.Cursors]::Hand
	$closeButton.Add_Click({
		$dialog = $dialogRef.Dialog
		if ($dialog -and [string]$dialog.State -eq 'Running')
		{
			[void](Stop-GuiDeploymentMediaBuilderBackgroundOperation)
			Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $dialog -Text 'Cancellation requested from the build dialog.' -Level 'WARNING'
			return
		}
		$window.Close()
	}.GetNewClosure())
	[System.Windows.Controls.Grid]::SetColumn($closeButton, 1)
	[void]$titleGrid.Children.Add($closeButton)
	$titleBar.Child = $titleGrid
	$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() }.GetNewClosure())
	[System.Windows.Controls.DockPanel]::SetDock($titleBar, [System.Windows.Controls.Dock]::Top)
	[void]$dock.Children.Add($titleBar)

	$footer = New-Object System.Windows.Controls.StackPanel
	$footer.Orientation = 'Horizontal'
	$footer.HorizontalAlignment = 'Right'
	$footer.Margin = [System.Windows.Thickness]::new(16, 10, 16, 14)
	$abortButton = New-Object System.Windows.Controls.Button
	$abortButton.Content = 'Abort'
	$abortButton.MinWidth = 104
	$abortButton.Height = 34
	$abortButton.Cursor = [System.Windows.Input.Cursors]::Hand
	Set-ButtonChrome -Button $abortButton -Variant 'Danger'
	$abortButton.Add_Click({
		$dialog = $dialogRef.Dialog
		if (-not $dialog) { return }
		if ([string]$dialog.State -eq 'Running')
		{
			$dialog.AbortButton.IsEnabled = $false
			$dialog.AbortButton.Content = 'Cancelling...'
			[void](Stop-GuiDeploymentMediaBuilderBackgroundOperation)
			Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $dialog -Text 'Cancellation requested by operator.' -Level 'WARNING'
			return
		}
		$dialog.AllowClose = $true
		$dialog.Window.Close()
	}.GetNewClosure())
	[void]$footer.Children.Add($abortButton)
	[System.Windows.Controls.DockPanel]::SetDock($footer, [System.Windows.Controls.Dock]::Bottom)
	[void]$dock.Children.Add($footer)

	$contentGrid = New-Object System.Windows.Controls.Grid
	$contentGrid.Margin = [System.Windows.Thickness]::new(18, 16, 18, 8)
	[void]$contentGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
	[void]$contentGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
	[void]$contentGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))

	$summary = New-Object System.Windows.Controls.TextBlock
	$summary.Text = ('{0} | {1} | {2}' -f [string]$Plan.OutputMode, $(if ([string]::IsNullOrWhiteSpace([string]$Plan.EditionName)) { ('Image index {0}' -f [int]$Plan.EditionIndex) } else { [string]$Plan.EditionName }), [string]$Plan.SourceIso)
	$summary.TextWrapping = 'Wrap'
	$summary.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$summary.FontSize = 12
	$summary.Foreground = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextSecondary' -Default '#4B5563'))
	$summary.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
	[System.Windows.Controls.Grid]::SetRow($summary, 0)
	[void]$contentGrid.Children.Add($summary)

	$progressStack = New-Object System.Windows.Controls.StackPanel
	$progressStack.Orientation = 'Vertical'
	$progressStack.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	$progressBar = New-Object System.Windows.Controls.ProgressBar
	$progressBar.Height = 12
	$progressBar.Minimum = 0
	$progressBar.Maximum = 1
	$progressBar.Value = 0
	$progressBar.IsIndeterminate = $true
	try
	{
		$progressBar.Template = New-GuiExecutionProgressBarTemplate
		Set-SheenProgressBarTheme -ProgressBar $progressBar
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BuildDialog.ProgressChrome' -Severity Warning }
	[void]$progressStack.Children.Add($progressBar)
	$progressText = New-Object System.Windows.Controls.TextBlock
	$progressText.Text = 'Deployment media build started.'
	$progressText.TextWrapping = 'Wrap'
	$progressText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$progressText.FontSize = 12
	$progressText.Foreground = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextMuted' -Default '#6B7280'))
	$progressText.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
	[void]$progressStack.Children.Add($progressText)
	[System.Windows.Controls.Grid]::SetRow($progressStack, 1)
	[void]$contentGrid.Children.Add($progressStack)

	$logBox = New-Object System.Windows.Controls.RichTextBox
	$logBox.IsReadOnly = $true
	$logBox.VerticalScrollBarVisibility = 'Auto'
	$logBox.HorizontalScrollBarVisibility = 'Disabled'
	$logBox.BorderThickness = [System.Windows.Thickness]::new(1)
	$logBox.Padding = [System.Windows.Thickness]::new(12)
	$logBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
	$logBox.FontSize = 12
	$logBox.Background = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'LogBg' -Default (Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'CardBg' -Default '#F9FAFB')))
	$logBox.Foreground = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'TextPrimary' -Default '#111827'))
	$logBox.BorderBrush = $bc.ConvertFromString((Get-GuiDeploymentMediaBuilderThemeValue -Theme $theme -Name 'CardBorder' -Default '#D8DEE8'))
	$flowDoc = New-Object System.Windows.Documents.FlowDocument
	$flowDoc.PagePadding = [System.Windows.Thickness]::new(0)
	$flowDoc.LineHeight = 1
	$logBox.Document = $flowDoc
	[System.Windows.Controls.Grid]::SetRow($logBox, 2)
	[void]$contentGrid.Children.Add($logBox)
	[void]$dock.Children.Add($contentGrid)

	$rootBorder.Child = $dock
	$window.Content = $rootBorder
	if (Get-Command -Name 'GUICommon\Set-GuiWindowChromeTheme' -ErrorAction SilentlyContinue)
	{
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $window -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
	}
	elseif (Get-Command -Name 'Set-GuiWindowChromeTheme' -CommandType Function -ErrorAction SilentlyContinue)
	{
		[void](Set-GuiWindowChromeTheme -Window $window -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
	}

	$window.Add_Closing({
		param($sender, $eventArgs)
		$dialog = $dialogRef.Dialog
		if ($dialog -and [string]$dialog.State -eq 'Running' -and -not [bool]$dialog.AllowClose)
		{
			$eventArgs.Cancel = $true
			[void](Stop-GuiDeploymentMediaBuilderBackgroundOperation)
			Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $dialog -Text 'Close requested while build was running; cancellation requested instead.' -Level 'WARNING'
		}
	}.GetNewClosure())

	$dialog = [pscustomobject]@{
		Window = $window
		ProgressBar = $progressBar
		ProgressText = $progressText
		LogBox = $logBox
		AbortButton = $abortButton
		State = 'Running'
		AllowClose = $false
		LastLoggedStatusKey = ''
	}
	$dialogRef.Dialog = $dialog
	$window.Show()
	Add-GuiDeploymentMediaBuildDialogLogLine -Dialog $dialog -Text 'Deployment media build dialog opened.'
	return $dialog
}

function Select-GuiDeploymentMediaBuilderWorkerPayload
{
	[CmdletBinding()]
	param (
		[object[]]$Result
	)

	$items = @($Result | Where-Object { $null -ne $_ })
	if ($items.Count -lt 1) { return $null }

	foreach ($item in @($items))
	{
		if (
			$item.PSObject.Properties['SourceIso'] -and
			$item.PSObject.Properties['ImagePath'] -and
			$item.PSObject.Properties['Editions']
		)
		{
			return $item
		}
	}
	foreach ($item in @($items))
	{
		if (
			$item.PSObject.Properties['Path'] -and
			$item.PSObject.Properties['AcquisitionMode']
		)
		{
			return $item
		}
	}
	foreach ($item in @($items))
	{
		if (
			$item.PSObject.Properties['OutputPath'] -and
			$item.PSObject.Properties['ReportPath']
		)
		{
			return $item
		}
	}

	return $items[$items.Count - 1]
}

function Write-GuiDeploymentMediaBuilderErrorLog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ErrorRecord,

		[Parameter(Mandatory = $true)]
		[string]$Prefix,

		[Parameter(Mandatory = $true)]
		[string]$Source
	)

	try { LogError (Format-BaselineErrorForLog -ErrorObject $ErrorRecord -Prefix $Prefix) }
	catch { Write-SwallowedException -ErrorRecord $_ -Source $Source -Severity Warning }
}

function Write-GuiDeploymentMediaBuilderViewDebugLog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Message,

		[string]$Source = 'DeploymentMediaBuilderView.DebugLog'
	)

	try { LogDebug $Message }
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source $Source -Severity Warning
		}
	}
}

function Resolve-GuiDeploymentMediaBuilderSupportPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Dialog', 'Execution', 'ProcessHelper')]
		[string]$Name
	)

	$candidates = [System.Collections.Generic.List[string]]::new()
	foreach ($root in @($Script:GuiExtractedRoot, $PSScriptRoot))
	{
		if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

		switch ($Name)
		{
			'Dialog' { [void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilderDialog.ps1')) }
			'Execution'
			{
				[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder\DeploymentMediaBuilder.Execution.ps1'))
				[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder.Execution.ps1'))
			}
			'ProcessHelper' { [void]$candidates.Add((Join-Path ([string]$root) '..\SharedHelpers\Process.Helpers.ps1')) }
		}
	}

	foreach ($candidate in @($candidates))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
		$fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
		if (Test-Path -LiteralPath $fullPath -PathType Leaf)
		{
			return $fullPath
		}
	}

	throw ('Required Deployment Media Builder support file was not found: {0}' -f $Name)
}

function Complete-GuiDeploymentMediaBuilderBackgroundOperation
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Operation
	)

	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation finalizing. Name="{0}"; TimedOut={1}; CancelRequested={2}; ForceRequested={3}; TerminalReported={4}; SyncDone={5}; SyncStatus="{6}"' -f [string]$Operation.Name, [bool]$Operation.TimedOut, [bool]$Operation.CancelRequested, [bool]$Operation.CancellationForceRequested, [bool]$Operation.TerminalReported, [bool]$Operation.Sync.Done, [string]$Operation.Sync.Status) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Finalize'

	if ([object]::ReferenceEquals($Script:DeploymentMediaBuilderOperation, $Operation))
	{
		$Script:DeploymentMediaBuilderOperation = $null
	}

	try { if ($Operation.PowerShell) { $Operation.PowerShell.Dispose() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BackgroundOperation.DisposePowerShell' -Severity Warning }
	try { if ($Operation.Timer) { $Operation.Timer.Stop() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BackgroundOperation.StopTimer' -Severity Warning }
	try { if ($Operation.Runspace) { $Operation.Runspace.Dispose() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BackgroundOperation.DisposeRunspace' -Severity Warning }

	if ($Operation.FinallyCallback)
	{
		& $Operation.FinallyCallback
	}

	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation finalized. Name="{0}"; ActiveOperation={1}' -f [string]$Operation.Name, [bool]$Script:DeploymentMediaBuilderOperation) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Finalized'
}

function Convert-GuiDeploymentMediaBuilderWorkerErrorRecord
{
	[CmdletBinding()]
	[OutputType([System.Management.Automation.ErrorRecord])]
	param (
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]$ErrorRecord,

		[string]$OperationName = 'Deployment media operation'
	)

	$exception = $ErrorRecord.Exception
	if ($exception -is [System.Management.Automation.MethodInvocationException] -and $exception.InnerException)
	{
		$innerException = $exception.InnerException
		if ($innerException -is [System.Management.Automation.RuntimeException] -and $innerException.ErrorRecord)
		{
			return $innerException.ErrorRecord
		}

		return (New-Object System.Management.Automation.ErrorRecord $innerException, 'DeploymentMediaBuilderWorkerFailed', ([System.Management.Automation.ErrorCategory]::OperationStopped), $OperationName)
	}

	return $ErrorRecord
}

function Stop-GuiDeploymentMediaBuilderBackgroundOperation
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[string]$Reason = 'Deployment media operation cancelled by operator.'
	)

	$operation = $Script:DeploymentMediaBuilderOperation
	if (-not $operation)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media cancellation ignored because no operation is active. Reason="{0}"' -f $Reason) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Cancel.NoActiveOperation'
		return $false
	}

	if ($operation.CancelRequested)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media cancellation request ignored because cancellation is already pending. Name="{0}"; Reason="{1}"' -f [string]$operation.Name, $Reason) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Cancel.AlreadyPending'
		Set-GuiDeploymentMediaBuilderStatus -Message 'Cancellation is already pending for the deployment media operation.' -Tone 'warning' -ShowBanner
		return $true
	}

	$operation.CancelRequested = $true
	$operation.CancelRequestedUtc = [DateTime]::UtcNow
	$operation.CancelEscalationUtc = $operation.CancelRequestedUtc.AddSeconds(30)
	if ($operation.Sync)
	{
		$operation.Sync.CancelRequested = $true
		$operation.Sync.CancelReason = $Reason
		$operation.Sync.RequestedUtc = $operation.CancelRequestedUtc
		$operation.Sync.Status = 'Cancelling deployment media operation...'
		$operation.Sync.ProgressPayload = $null
	}

	Set-GuiDeploymentMediaBuilderStatus -Message 'Cancelling deployment media operation...' -Tone 'warning' -ShowBanner
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media cancellation requested. Name="{0}"; Reason="{1}"; EscalationUtc="{2:o}"' -f [string]$operation.Name, $Reason, $operation.CancelEscalationUtc) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Cancel.Requested'
	return $true
}

function Start-GuiDeploymentMediaBuilderBackgroundOperation
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[scriptblock]$Worker,

		[hashtable]$Context = @{},

		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 7200,

		[scriptblock]$StatusCallback,
		[Parameter(Mandatory = $true)]
		[scriptblock]$CompletedCallback,
		[Parameter(Mandatory = $true)]
		[scriptblock]$FailedCallback,
		[scriptblock]$FinallyCallback
	)

	if ($Script:DeploymentMediaBuilderOperation)
	{
		Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation rejected because another operation is active. Requested="{0}"; Active="{1}"' -f $Name, [string]$Script:DeploymentMediaBuilderOperation.Name) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Start.AlreadyActive'
		Set-GuiDeploymentMediaBuilderStatus -Message 'A deployment media operation is already running.' -Tone 'warning' -ShowBanner
		return $false
	}

	$contextKeys = @()
	if ($Context) { $contextKeys = @($Context.Keys | ForEach-Object { [string]$_ } | Sort-Object) }
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation starting. Name="{0}"; TimeoutSeconds={1}; ContextKeys="{2}"' -f $Name, $TimeoutSeconds, ($contextKeys -join ',')) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Start'

	$syncHash = [hashtable]::Synchronized(@{
		Status = ''
		ProgressPayload = $null
		Done = $false
		CancelRequested = $false
		CancelReason = ''
		RequestedUtc = $null
		CurrentStage = ''
		StageStartedUtc = $null
	})

	$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
	$initialSessionState.ImportPSModule(@('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility'))
	$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialSessionState)
	$runspace.ApartmentState = 'STA'
	$runspace.ThreadOptions = 'ReuseThread'
	$runspace.Open()
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media runspace opened. Name="{0}"; ApartmentState="{1}"; ThreadOptions="{2}"' -f $Name, [string]$runspace.ApartmentState, [string]$runspace.ThreadOptions) -Source 'DeploymentMediaBuilderView.BackgroundOperation.RunspaceOpened'

	$ps = [System.Management.Automation.PowerShell]::Create()
	$ps.Runspace = $runspace

	$operationScript = {
		param (
			[scriptblock]$WorkerBlock,
			[hashtable]$WorkerContext,
			[hashtable]$Sync
		)

		$ErrorActionPreference = 'Stop'
		try
		{
			& $WorkerBlock -Context $WorkerContext -Sync $Sync
		}
		finally
		{
			$Sync.Done = $true
		}
	}

	$null = $ps.AddScript($operationScript).AddArgument($Worker).AddArgument($Context).AddArgument($syncHash)

	$asyncResult = $ps.BeginInvoke()
	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(150)
	$deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	$operation = [pscustomobject]@{
		Name = $Name
		PowerShell = $ps
		Runspace = $runspace
		AsyncResult = $asyncResult
		Timer = $timer
		Sync = $syncHash
		DeadlineUtc = $deadlineUtc
		TimeoutSeconds = $TimeoutSeconds
		TimedOut = $false
		TerminalReported = $false
		FinallyCallback = $FinallyCallback
		CancelRequested = $false
		CancelRequestedUtc = $null
		CancelEscalationUtc = $null
		CancellationForceRequested = $false
		LastStatus = ''
	}
	$Script:DeploymentMediaBuilderOperation = $operation
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation dispatched. Name="{0}"; AsyncCompleted={1}; DeadlineUtc="{2:o}"' -f $Name, [bool]$asyncResult.IsCompleted, $deadlineUtc) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Dispatched'

	$completeOperationScript = ${function:Complete-GuiDeploymentMediaBuilderBackgroundOperation}
	$convertWorkerErrorScript = ${function:Convert-GuiDeploymentMediaBuilderWorkerErrorRecord}
	$selectWorkerPayloadScript = ${function:Select-GuiDeploymentMediaBuilderWorkerPayload}
	$writeDebugLogScript = ${function:Write-GuiDeploymentMediaBuilderViewDebugLog}
	$writeSwallowedExceptionScript = Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue
	$timer.Add_Tick({
		$status = [string]$syncHash.Status
		$progressPayload = $syncHash.ProgressPayload
		$statusKey = $status
		$isByteProgress = $false
		if ($progressPayload -and $progressPayload.PSObject.Properties['IsByteProgress'] -and [bool]$progressPayload.IsByteProgress)
		{
			$isByteProgress = $true
			$completedBytes = if ($progressPayload.PSObject.Properties['CompletedBytes']) { [int64]$progressPayload.CompletedBytes } else { [int64]0 }
			$totalBytes = if ($progressPayload.PSObject.Properties['TotalBytes']) { [int64]$progressPayload.TotalBytes } else { [int64]0 }
			$statusKey = '{0}|{1}|{2}' -f $status, $completedBytes, $totalBytes
		}
		if ($StatusCallback -and -not [string]::IsNullOrWhiteSpace($status) -and $statusKey -ne [string]$operation.LastStatus)
		{
			$operation.LastStatus = $statusKey
			if (-not $isByteProgress)
			{
				& $writeDebugLogScript -Message ('Deployment media background operation status changed. Name="{0}"; Status="{1}"' -f [string]$operation.Name, $status) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Status'
			}
			if ($progressPayload) { & $StatusCallback $progressPayload }
			else { & $StatusCallback $status }
		}

		if (-not $operation.TimedOut -and -not $asyncResult.IsCompleted -and [DateTime]::UtcNow -ge $operation.DeadlineUtc)
		{
			$operation.TimedOut = $true
			$operation.CancelRequested = $true
			$operation.CancelRequestedUtc = [DateTime]::UtcNow
			$operation.CancelEscalationUtc = $operation.CancelRequestedUtc.AddSeconds(30)
			$syncHash.CancelRequested = $true
			$syncHash.CancelReason = ('{0} timed out after {1} second(s).' -f $Name, $TimeoutSeconds)
			$syncHash.RequestedUtc = $operation.CancelRequestedUtc
			$syncHash.Status = ('Cancelling {0} after timeout.' -f $Name)
			$syncHash.ProgressPayload = $null
			& $writeDebugLogScript -Message ('Deployment media background operation timeout reached. Name="{0}"; TimeoutSeconds={1}; DeadlineUtc="{2:o}"' -f $Name, $TimeoutSeconds, $operation.DeadlineUtc) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Timeout'
			$timeoutException = [System.TimeoutException]::new(('{0} timed out after {1} second(s).' -f $Name, $TimeoutSeconds))
			$timeoutRecord = New-Object System.Management.Automation.ErrorRecord $timeoutException, 'DeploymentMediaBuilderOperationTimeout', ([System.Management.Automation.ErrorCategory]::OperationTimeout), $Name
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				& $FailedCallback -ErrorRecord $timeoutRecord
			}
			return
		}

		if ($operation.CancelRequested -and -not $operation.CancellationForceRequested -and -not $asyncResult.IsCompleted -and $operation.CancelEscalationUtc -and [DateTime]::UtcNow -ge $operation.CancelEscalationUtc)
		{
			$operation.CancellationForceRequested = $true
			& $writeDebugLogScript -Message ('Deployment media background operation cancellation escalation reached. Name="{0}"; CancelRequestedUtc="{1:o}"; EscalationUtc="{2:o}"' -f $Name, $operation.CancelRequestedUtc, $operation.CancelEscalationUtc) -Source 'DeploymentMediaBuilderView.BackgroundOperation.CancelEscalation'
			try { $null = $ps.BeginStop($null, $null) }
			catch
			{
				& $writeDebugLogScript -Message ('Deployment media background operation BeginStop failed during cancellation escalation. Name="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Name, $_.Exception.GetType().FullName, $_.Exception.Message) -Source 'DeploymentMediaBuilderView.BackgroundOperation.BeginStopDebug'
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.BackgroundOperation.BeginStop' -Severity Warning
				}
			}
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				$cancelException = [System.OperationCanceledException]::new(('{0} cancellation did not complete within the grace period.' -f $Name))
				$cancelRecord = New-Object System.Management.Automation.ErrorRecord $cancelException, 'DeploymentMediaBuilderOperationCancelled', ([System.Management.Automation.ErrorCategory]::OperationStopped), $Name
				& $FailedCallback -ErrorRecord $cancelRecord
			}
			& $completeOperationScript -Operation $operation
			return
		}

		if (-not $asyncResult.IsCompleted)
		{
			return
		}

		$timer.Stop()
		try
		{
			$result = @($ps.EndInvoke($asyncResult))
			$streamErrors = @($ps.Streams.Error)
			& $writeDebugLogScript -Message ('Deployment media background operation completed worker invoke. Name="{0}"; ResultCount={1}; ErrorCount={2}; TerminalReported={3}' -f $Name, @($result).Count, @($streamErrors).Count, [bool]$operation.TerminalReported) -Source 'DeploymentMediaBuilderView.BackgroundOperation.EndInvoke'
			if (-not $operation.TerminalReported)
			{
				if (@($streamErrors).Count -gt 0)
				{
					$operation.TerminalReported = $true
					$streamErrorRecord = $streamErrors[$streamErrors.Count - 1]
					& $writeDebugLogScript -Message ('Deployment media background operation worker wrote error stream records. Name="{0}"; ErrorCount={1}; LastError="{2}"' -f $Name, @($streamErrors).Count, $streamErrorRecord.Exception.Message) -Source 'DeploymentMediaBuilderView.BackgroundOperation.ErrorStream'
					$workerErrorRecord = & $convertWorkerErrorScript -ErrorRecord $streamErrorRecord -OperationName $Name
					& $FailedCallback -ErrorRecord $workerErrorRecord
				}
				else
				{
					$payload = & $selectWorkerPayloadScript -Result $result
					& $writeDebugLogScript -Message ('Deployment media background operation selected payload. Name="{0}"; PayloadType="{1}"' -f $Name, $(if ($payload) { $payload.GetType().FullName } else { '<null>' })) -Source 'DeploymentMediaBuilderView.BackgroundOperation.Payload'
					if ($null -eq $payload)
					{
						$operation.TerminalReported = $true
						$missingPayloadMessage = ('{0} completed without returning a result payload.' -f $Name)
						& $writeDebugLogScript -Message $missingPayloadMessage -Source 'DeploymentMediaBuilderView.BackgroundOperation.MissingPayload'
						$missingPayloadException = [System.InvalidOperationException]::new($missingPayloadMessage)
						$missingPayloadRecord = New-Object System.Management.Automation.ErrorRecord $missingPayloadException, 'DeploymentMediaBuilderMissingWorkerPayload', ([System.Management.Automation.ErrorCategory]::InvalidData), $Name
						& $FailedCallback -ErrorRecord $missingPayloadRecord
					}
					else
					{
						& $CompletedCallback -Result $payload
					}
				}
			}
		}
		catch
		{
			& $writeDebugLogScript -Message ('Deployment media background operation EndInvoke raised. Name="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Name, $_.Exception.GetType().FullName, $_.Exception.Message) -Source 'DeploymentMediaBuilderView.BackgroundOperation.EndInvokeRaised'
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.UI.Start-GuiDeploymentMediaBuilderBackgroundOperation:catch370' -Severity Debug
			}
			& $writeDebugLogScript -Message ('Deployment media background operation worker failed. Name="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Name, $_.Exception.GetType().FullName, $_.Exception.Message) -Source 'DeploymentMediaBuilderView.BackgroundOperation.WorkerFailed'

			if (-not $operation.TerminalReported)
			{
				$workerErrorRecord = & $convertWorkerErrorScript -ErrorRecord $_ -OperationName $Name
				& $FailedCallback -ErrorRecord $workerErrorRecord
			}
		}
		finally
		{
			& $completeOperationScript -Operation $operation
		}
	}.GetNewClosure())
	$timer.Start()
	Write-GuiDeploymentMediaBuilderViewDebugLog -Message ('Deployment media background operation dispatcher timer started. Name="{0}"; IntervalMs={1}' -f $Name, [int]$timer.Interval.TotalMilliseconds) -Source 'DeploymentMediaBuilderView.BackgroundOperation.TimerStarted'

	return $true
}

function Set-GuiDeploymentMediaBuilderControlsEnabled
{
	[CmdletBinding()]
	param ([bool]$Enabled = $true)

	$controls = @(
		$Script:CmbDeploymentMediaMicrosoftIso,
		$Script:BtnDeploymentMediaDownloadMicrosoftIso,
		$Script:TxtDeploymentMediaSourceIso,
		$Script:BtnDeploymentMediaBrowseIso,
		$Script:BtnDeploymentMediaDetectIso,
		$Script:TxtDeploymentMediaEditionIndex,
		$Script:CmbDeploymentMediaDetectedEdition,
		$Script:TxtDeploymentMediaWorkingDirectory,
		$Script:BtnDeploymentMediaBrowseWorking,
		$Script:CmbDeploymentMediaOutputMode,
		$Script:TxtDeploymentMediaUsbTargetRoot,
		$Script:BtnDeploymentMediaBrowseUsbTarget,
		$Script:TxtDeploymentMediaAutounattend,
		$Script:BtnDeploymentMediaCreateAutounattend,
		$Script:BtnDeploymentMediaBrowseAutounattend,
		$Script:TxtDeploymentMediaDriverSource,
		$Script:BtnDeploymentMediaBrowseDrivers,
		$Script:ChkDeploymentMediaBootDrivers,
		$Script:ChkDeploymentMediaBaselineTweaks,
		$Script:BtnDeploymentMediaPreviewPlan
	)

	foreach ($control in $controls)
	{
		if ($control) { $control.IsEnabled = $Enabled }
	}
	if ($Script:CmbDeploymentMediaDetectedEdition)
	{
		$Script:CmbDeploymentMediaDetectedEdition.IsEnabled = $Enabled -and $Script:CmbDeploymentMediaDetectedEdition.Items.Count -gt 0
	}

	if ($Script:BtnDeploymentMediaStartBuild)
	{
		if ($Script:DeploymentMediaBuilderOperation)
		{
			Set-GuiDeploymentMediaBuilderStartButtonMode -CancellationMode
		}
		else
		{
			Set-GuiDeploymentMediaBuilderStartButtonMode
		}
	}
	Update-GuiDeploymentMediaBuilderPreviewAvailability -ControlsEnabled:$Enabled
}

function Set-GuiDeploymentMediaBuilderStartButtonMode
{
	[CmdletBinding()]
	param (
		[switch]$CancellationMode
	)

	if (-not $Script:BtnDeploymentMediaStartBuild) { return }

	if ($CancellationMode)
	{
		Set-GuiButtonIconContent -Button $Script:BtnDeploymentMediaStartBuild -IconName 'Clear' -Text (Get-UxLocalizedString -Key 'GuiDeploymentMediaCancelOperation' -Fallback 'Cancel Operation') -ToolTip (Get-UxLocalizedString -Key 'GuiDeploymentMediaCancelOperationTip' -Fallback 'Request cancellation and cleanup for the active deployment media operation.')
		Set-ButtonChrome -Button $Script:BtnDeploymentMediaStartBuild -Variant 'Secondary'
		return
	}

	Set-GuiButtonIconContent -Button $Script:BtnDeploymentMediaStartBuild -IconName 'RunTweaks' -Text (Get-UxLocalizedString -Key 'GuiDeploymentMediaStartBuild' -Fallback 'Start ISO Build') -ToolTip (Get-UxLocalizedString -Key 'GuiDeploymentMediaStartBuildTip' -Fallback 'Build the selected deployment media after required inputs validate. Preview is optional.')
	Set-ButtonChrome -Button $Script:BtnDeploymentMediaStartBuild -Variant 'Primary'
}

function Reset-GuiDeploymentMediaBuilderStartState
{
	[CmdletBinding()]
	param ()

	$Script:DeploymentMediaCurrentPlan = $null
	if (-not [bool]$Script:DeploymentMediaBuildInProgress)
	{
		Set-GuiDeploymentMediaBuilderProgressState -Hide
	}
	if ($Script:BtnDeploymentMediaStartBuild)
	{
		$Script:BtnDeploymentMediaStartBuild.IsEnabled = $false
	}
	Update-GuiDeploymentMediaBuilderPreviewAvailability
}

function Initialize-GuiDeploymentMediaMicrosoftIsoOptionList
{
	[CmdletBinding()]
	param ()

	if (-not $Script:CmbDeploymentMediaMicrosoftIso) { return }
	if ($Script:CmbDeploymentMediaMicrosoftIso.Items.Count -gt 0) { return }
	if (-not (Get-Command -Name 'Get-GuiDeploymentMediaMicrosoftIsoOptions' -CommandType Function -ErrorAction SilentlyContinue)) { return }

	foreach ($option in @(Get-GuiDeploymentMediaMicrosoftIsoOptions))
	{
		$item = New-Object System.Windows.Controls.ComboBoxItem
		$item.Content = [string]$option.Label
		$item.Tag = $option
		[void]$Script:CmbDeploymentMediaMicrosoftIso.Items.Add($item)
	}
	if ($Script:CmbDeploymentMediaMicrosoftIso.Items.Count -gt 0 -and $Script:CmbDeploymentMediaMicrosoftIso.SelectedIndex -lt 0)
	{
		$Script:CmbDeploymentMediaMicrosoftIso.SelectedIndex = 0
	}
}

function Set-GuiDeploymentMediaBuilderInitialText
{
	[CmdletBinding()]
	param ()

	if ($Script:TxtDeploymentMediaPlanPreview -and [string]::IsNullOrWhiteSpace([string]$Script:TxtDeploymentMediaPlanPreview.Text))
	{
		$Script:TxtDeploymentMediaPlanPreview.Text = 'Use the official Microsoft Media Creation Tool workflow, import an existing ISO, then run Detect Editions. Preview is optional before Start ISO Build.'
	}
	if ($Script:TxtDeploymentMediaDetectedIsoSummary -and [string]::IsNullOrWhiteSpace([string]$Script:TxtDeploymentMediaDetectedIsoSummary.Text))
	{
		$Script:TxtDeploymentMediaDetectedIsoSummary.Text = 'No ISO inspected yet.'
	}
}

function Sync-GuiDeploymentMediaBuilderViewText
{
	[CmdletBinding()]
	param ()

	if ($Script:BtnDeploymentMediaDetectIso)
	{
		Set-GuiButtonIconContent -Button $Script:BtnDeploymentMediaDetectIso -IconName 'Search' -Text (Get-UxLocalizedString -Key 'GuiDeploymentMediaDetectIso' -Fallback 'Detect Editions') -ToolTip (Get-UxLocalizedString -Key 'GuiDeploymentMediaDetectIsoTip' -Fallback 'Inspect the selected Windows ISO and list available image editions.') -IconSize 14 -Gap 6 -TextFontSize 11
		Set-ButtonChrome -Button $Script:BtnDeploymentMediaDetectIso -Variant 'Secondary' -Compact
	}
	if ($Script:BtnDeploymentMediaDownloadMicrosoftIso)
	{
		Set-GuiButtonIconContent -Button $Script:BtnDeploymentMediaDownloadMicrosoftIso -IconName 'ArrowDownload' -Text (Get-UxLocalizedString -Key 'GuiDeploymentMediaDownloadMicrosoftIso' -Fallback 'Start') -ToolTip (Get-UxLocalizedString -Key 'GuiDeploymentMediaDownloadMicrosoftIsoTip' -Fallback 'Start the selected ISO acquisition workflow. Media Creation Tool options launch the official Microsoft tool and auto-import the completed ISO.') -IconSize 14 -Gap 6 -TextFontSize 11
		Set-ButtonChrome -Button $Script:BtnDeploymentMediaDownloadMicrosoftIso -Variant 'Secondary' -Compact
	}
	if ($Script:BtnDeploymentMediaPreviewPlan)
	{
		Set-GuiButtonIconContent -Button $Script:BtnDeploymentMediaPreviewPlan -IconName 'PreviewRun' -Text (Get-UxLocalizedString -Key 'GuiDeploymentMediaPreviewPlan' -Fallback 'Preview Build Plan') -ToolTip (Get-UxLocalizedString -Key 'GuiDeploymentMediaPreviewPlanTip' -Fallback 'Show the exact setup media build plan. This is optional before starting.')
		Set-ButtonChrome -Button $Script:BtnDeploymentMediaPreviewPlan -Variant 'Preview'
	}
	if ($Script:BtnDeploymentMediaStartBuild)
	{
		Set-GuiDeploymentMediaBuilderStartButtonMode
	}

	foreach ($button in @(
		$Script:BtnDeploymentMediaBrowseIso,
		$Script:BtnDeploymentMediaBrowseWorking,
		$Script:BtnDeploymentMediaBrowseUsbTarget,
		$Script:BtnDeploymentMediaCreateAutounattend,
		$Script:BtnDeploymentMediaBrowseAutounattend,
		$Script:BtnDeploymentMediaBrowseDrivers
	))
	{
		if ($button)
		{
			Set-ButtonChrome -Button $button -Variant 'Secondary' -Compact
		}
	}

	foreach ($combo in @($Script:CmbDeploymentMediaMicrosoftIso, $Script:CmbDeploymentMediaDetectedEdition, $Script:CmbDeploymentMediaOutputMode))
	{
		if ($combo -and (Get-Command -Name 'Set-ChoiceComboStyle' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-ChoiceComboStyle -Combo $combo
		}
	}

	Set-GuiDeploymentMediaBuilderInitialText
	Update-GuiDeploymentMediaBuilderPreviewAvailability
	if (-not $Script:DeploymentMediaCurrentPlan)
	{
		Set-GuiDeploymentMediaBuilderStatus -Message 'Choose an ISO and detect editions to begin.' -Tone 'muted'
	}
}

function Show-GuiDeploymentMediaBuilderFileDialog
{
	[CmdletBinding()]
	param (
		[string]$Filter
	)

	$dialog = New-Object Microsoft.Win32.OpenFileDialog
	$dialog.Filter = $Filter
	if ($dialog.ShowDialog($Script:MainForm) -eq $true)
	{
		return $dialog.FileName
	}
	return $null
}

function Show-GuiDeploymentMediaBuilderFolderDialog
{
	[CmdletBinding()]
	param (
		[string]$Description = 'Select folder'
	)

	Add-Type -AssemblyName System.Windows.Forms
	$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
	$dialog.Description = $Description
	$dialog.ShowNewFolderButton = $true
	if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
	{
		return $dialog.SelectedPath
	}
	return $null
}

