# Preset button builders, selection state, policy checks, and tab-level preset application

	function New-PresetButton
	{
		param(
			[object]$Label,
			[ValidateSet('Primary', 'Danger', 'DangerSubtle', 'Secondary', 'Subtle')]
			[string]$Variant = 'Secondary',
			[switch]$Compact,
			[switch]$Muted
		)

		$button = New-Object System.Windows.Controls.Button
		$button.Content = $Label
		$button.Padding = if ($Compact) { [System.Windows.Thickness]::new(10, 4, 10, 4) } else { [System.Windows.Thickness]::new(12, 6, 12, 6) }
		$button.Margin = [System.Windows.Thickness]::new(3, 0, 3, 0)
		$button.FontSize = 11
		Set-ButtonChrome -Button $button -Variant $Variant -Compact:$Compact -Muted:$Muted
		return $button
	}

	function New-PresetButtonContent
	{
		param(
			[Parameter(Mandatory = $true)]
			[string]$PrimaryText,
			[string]$SecondaryText
		)

		if ([string]::IsNullOrWhiteSpace($SecondaryText))
		{
			return $PrimaryText
		}

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'
		$stack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

		$primary = New-Object System.Windows.Controls.TextBlock
		$primary.Text = $PrimaryText
		$primary.TextAlignment = [System.Windows.TextAlignment]::Center
		$primary.FontWeight = [System.Windows.FontWeights]::SemiBold
		$primary.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		[void]($stack.Children.Add($primary))

		$secondary = New-Object System.Windows.Controls.TextBlock
		$secondary.Text = $SecondaryText
		$secondary.TextAlignment = [System.Windows.TextAlignment]::Center
		$secondary.FontSize = 9
		$secondary.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		$secondary.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		[void]($stack.Children.Add($secondary))

		return $stack
	}

	function New-WhyThisMattersButton
	{
		<#
		.SYNOPSIS
		Returns a secondary outline button that toggles a hint border, or $null if no hint text.
		The caller must add the returned .Tag (Border) to the parent layout.
		#>
			param (
				[object]$Tweak,
				[int]$LeftIndent = 28
			)

		$whyThisMatters = Get-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters'
		$hintText = if ($Tweak -and -not [string]::IsNullOrWhiteSpace([string]$whyThisMatters)) {
			[string]$whyThisMatters
		} else { $null }
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersButton'
		if (-not $Script:WhyThisMattersButtonTemplate)
		{
			$linkTemplateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type Button}">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="5"
            Padding="{TemplateBinding Padding}"
            SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center"
                          VerticalAlignment="Center"
                          RecognizesAccessKey="True" />
    </Border>
</ControlTemplate>
'@
			$linkTemplateReader = New-Object System.Xml.XmlNodeReader ([xml]$linkTemplateXaml)
			$Script:WhyThisMattersButtonTemplate = [System.Windows.Markup.XamlReader]::Load($linkTemplateReader)
		}

		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$btn.FontSize = 10
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$btn.Background = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderThickness = [System.Windows.Thickness]::new(0)
		$btn.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$btn.Cursor = [System.Windows.Input.Cursors]::Hand
		$btn.VerticalAlignment = 'Center'
		$btn.HorizontalAlignment = 'Right'
		$btn.FocusVisualStyle = $null
		$btn.ToolTip = 'Show why this tweak matters'
		$btn.Template = $Script:WhyThisMattersButtonTemplate

		# Expandable hint border (stored in Tag for caller to add to layout)
		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)
		$hintBorder.Margin = [System.Windows.Thickness]::new($LeftIndent, 3, 8, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock

		$btn.Tag = $hintBorder

		$btnRef = $btn
		$borderRef = $hintBorder
		$hoverBg = $bc.ConvertFromString($Script:CurrentTheme.TabHoverBg)
		$pressBg = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$normalFg = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$activeFg = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$detailsLabel = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$hideDetailsLabel = Get-UxLocalizedString -Key 'GuiHideDetails' -Fallback 'Hide details'
		$null = Register-GuiEventHandler -Source $btn -EventName 'MouseEnter' -Handler ({
			$btnRef.Background = $hoverBg
			$btnRef.Foreground = $activeFg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'MouseLeave' -Handler ({
			$btnRef.Background = [System.Windows.Media.Brushes]::Transparent
			$btnRef.Foreground = $normalFg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'PreviewMouseLeftButtonDown' -Handler ({
			$btnRef.Background = $pressBg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'Click' -Handler ({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$btnRef.Content = if ($isVisible) { $detailsLabel } else { $hideDetailsLabel }
			$btnRef.Foreground = if ($isVisible) { $normalFg } else { $activeFg }
		}.GetNewClosure())

		return $btn
	}

	function New-WhyThisMattersBlock
	{
		param (
			[object]$Tweak,
			[int]$LeftIndent = 0
		)

		$whyThisMatters = Get-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters'
		$hintText = if ($Tweak -and -not [string]::IsNullOrWhiteSpace([string]$whyThisMatters)) {
			[string]$whyThisMatters
		}
		else {
			$null
		}
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersToggle'
		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'
		$stack.Margin = [System.Windows.Thickness]::new($LeftIndent, 6, 8, 0)

		$toggle = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details') -Variant 'Subtle' -Compact -Muted
		$toggle.Margin = [System.Windows.Thickness]::new(0)
		$toggle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
		$toggle.ToolTip = 'Show why this tweak matters'
		[void]($stack.Children.Add($toggle))
		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
		$hintBorder.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock
		[void]($stack.Children.Add($hintBorder))
		$toggleRef = $toggle
		$borderRef = $hintBorder
		$detailsLabel = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$hideDetailsLabel = Get-UxLocalizedString -Key 'GuiHideDetails' -Fallback 'Hide details'
		$null = Register-GuiEventHandler -Source $toggle -EventName 'Click' -Handler ({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$toggleRef.Content = if ($isVisible) { $detailsLabel } else { $hideDetailsLabel }
		}.GetNewClosure())

		return $stack
	}

	function Get-PrimaryTabManifestIndexes
	{
		param ([string]$PrimaryTab)

		$indexes = @()
		if ([string]::IsNullOrWhiteSpace($PrimaryTab)) { return $indexes }

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			if ($CategoryToPrimary[$Script:TweakManifest[$i].Category] -eq $PrimaryTab)
			{
				$indexes += $i
			}
		}

		return $indexes
	}

	function Get-PresetTierRank
	{
		param ([string]$Tier)

		$normalizedTier = if ([string]::IsNullOrWhiteSpace($Tier)) { 'Basic' } else { [string]$Tier }
		# 'safe' is a legacy alias for 'basic' (renamed in v2.0). 'aggressive' is an alias for 'advanced'.
		switch -Regex ($normalizedTier.Trim())
		{
			'^\s*(aggressive|advanced)\s*$' { return 4 }
			'^\s*balanced\s*$'              { return 3 }
			'^\s*(basic|safe)\s*$'          { return 2 }
			'^\s*minimal\s*$'               { return 1 }
			default                         { return 2 }
		}
	}

	function Get-GuiPresetPolicyIssues
	{
		param (
			[string]$PresetName,
			[object[]]$PresetEntries,
			[hashtable]$ManifestByFunction = @{}
		)

		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		switch -Regex ($normalizedPresetName.Trim())
		{
			'^\s*(basic|safe)\s*$'          { $normalizedPresetName = 'Basic'; break }
			'^\s*minimal\s*$'               { $normalizedPresetName = 'Minimal'; break }
			'^\s*balanced\s*$'              { $normalizedPresetName = 'Balanced'; break }
			'^\s*(advanced|aggressive)\s*$' { $normalizedPresetName = 'Advanced'; break }
		}

		$basicAllowlistedActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach (
			$approvedFunction in @(
				'CheckWinGet'
				'Update-Powershell'
				'Update-DesktopRegistry'
				'Disable-AutoRun'
				'DismissMSAccount'
				'DismissSmartScreenFilter'
				'Repair-Windows11SMBUpdateIssue'
				'UnpinTaskbarShortcuts'
			)
		)
		{
			[void]$basicAllowlistedActions.Add($approvedFunction)
		}

		$issues = [System.Collections.Generic.List[object]]::new()
		foreach ($presetEntry in @($PresetEntries))
		{
			if (-not $presetEntry) { continue }

			$commandLine = ''
			if ((Test-GuiObjectField -Object $presetEntry -FieldName 'RawLine') -and -not [string]::IsNullOrWhiteSpace([string]$presetEntry.RawLine))
			{
				$commandLine = [string]$presetEntry.RawLine
			}
			elseif (-not [string]::IsNullOrWhiteSpace([string]$presetEntry.FunctionName))
			{
				$commandLine = '{0} {1}' -f [string]$presetEntry.FunctionName, [string]$presetEntry.ArgumentText
			}

			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $ManifestByFunction.ContainsKey($functionName))
			{
				continue
			}

			$tweak = $ManifestByFunction[$functionName]
			$riskValue = [string]$tweak.Risk
			$typeValue = [string]$tweak.Type
			$presetTierValue = [string]$tweak.PresetTier
			$workflowSensitivityValue = [string]$tweak.WorkflowSensitivity
			$restorableValue = $null
			if ((Test-GuiObjectField -Object $tweak -FieldName 'Restorable'))
			{
				$restorableValue = $tweak.Restorable
			}
			$isRemovalOperation = ($functionName -match '^(?i)(uninstall|remove|delete)')
			if (-not $isRemovalOperation -and $typeValue -eq 'Choice')
			{
				$optionValues = @($tweak.Options | ForEach-Object { [string]$_ })
				if ($optionValues | Where-Object { $_ -match '^(?i)(uninstall|remove|delete)$' })
				{
					$isRemovalOperation = $true
				}
			}
			$issueReason = $null

			switch ($normalizedPresetName)
			{
				'Basic'
				{
					if ($riskValue -eq 'High' -or $presetTierValue -eq 'Advanced' -or $workflowSensitivityValue -eq 'High')
					{
						$issueReason = 'Basic cannot include high-risk, advanced-tier, or strongly workflow-sensitive changes.'
					}
					elseif ($presetTierValue -eq 'Balanced')
					{
						$issueReason = 'Basic cannot include balanced-tier changes.'
					}
					elseif ($typeValue -eq 'Action' -and $null -ne $restorableValue -and -not [bool]$restorableValue -and -not $basicAllowlistedActions.Contains($functionName))
					{
						$issueReason = 'Basic cannot include non-restorable action items unless explicitly allowlisted.'
					}
					elseif ($isRemovalOperation -and -not $basicAllowlistedActions.Contains($functionName))
					{
						$issueReason = 'Basic cannot include removal-style actions unless explicitly allowlisted.'
					}
				}
				'Balanced'
				{
					if ($riskValue -eq 'High' -or $presetTierValue -eq 'Advanced' -or $workflowSensitivityValue -eq 'High')
					{
						$issueReason = 'Balanced cannot include high-risk, advanced-tier, or strongly workflow-sensitive changes.'
					}
					elseif ($isRemovalOperation)
					{
						$issueReason = 'Balanced cannot include removal-style actions.'
					}
				}
			}

			if ($issueReason)
			{
				[void]$issues.Add([pscustomobject]@{
					PresetName = $normalizedPresetName
					Function = $functionName
					Command = $commandLine
					Type = $typeValue
					Risk = $riskValue
					PresetTier = $presetTierValue
					WorkflowSensitivity = $workflowSensitivityValue
					Restorable = $restorableValue
					Reason = $issueReason
				})
			}
		}

		return [pscustomobject]@{
			PresetName = $normalizedPresetName
			IsCompliant = ($issues.Count -eq 0)
			Issues = [object[]]$issues
		}
	}

	function ConvertTo-GuiPresetName
	{
		param ([string]$PresetName)

		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		switch -Regex ($normalizedPresetName.Trim())
		{
			'^\s*minimal\s*$'               { return 'Minimal' }
			'^\s*balanced\s*$'              { return 'Balanced' }
			'^\s*(basic|safe)\s*$'          { return 'Basic' }
			'^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
			default                         { return 'Basic' }
		}
	}

	function Initialize-GuiSelectionStateStores
	{
		if (-not $Script:ExplicitPresetSelections)
		{
			$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
				[System.StringComparer]::OrdinalIgnoreCase
			)
		}
		if (-not $Script:ExplicitPresetSelectionDefinitions)
		{
			$Script:ExplicitPresetSelectionDefinitions = @{}
		}
	}

	function Copy-GuiExplicitSelectionDefinition
	{
		param (
			[object]$Definition,
			[string]$FunctionName = $null,
			[string]$Source = $null
		)

		if (-not $Definition) { return $null }

		$resolvedFunction = if (-not [string]::IsNullOrWhiteSpace([string]$FunctionName))
		{
			[string]$FunctionName
		}
		elseif ((Test-GuiObjectField -Object $Definition -FieldName 'Function') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Function))
		{
			[string]$Definition.Function
		}
		else
		{
			$null
		}
		if ([string]::IsNullOrWhiteSpace($resolvedFunction)) { return $null }

		$copy = [ordered]@{
			Function = $resolvedFunction
			Type = if ((Test-GuiObjectField -Object $Definition -FieldName 'Type')) { [string]$Definition.Type } else { $null }
		}

		if ((Test-GuiObjectField -Object $Definition -FieldName 'State') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.State))
		{
			$copy.State = [string]$Definition.State
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'Value'))
		{
			$copy.Value = if ($null -eq $Definition.Value) { $null } else { [string]$Definition.Value }
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'Run'))
		{
			$copy.Run = [bool]$Definition.Run
		}

		$resolvedSource = if (-not [string]::IsNullOrWhiteSpace([string]$Source))
		{
			[string]$Source
		}
		elseif ((Test-GuiObjectField -Object $Definition -FieldName 'Source') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Source))
		{
			[string]$Definition.Source
		}
		else
		{
			$null
		}
		if (-not [string]::IsNullOrWhiteSpace($resolvedSource))
		{
			$copy.Source = $resolvedSource
		}

		return [pscustomobject]$copy
	}

	function Get-GuiExplicitSelectionDefinition
	{
		param ([string]$FunctionName)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return $null }
		if (-not $Script:ExplicitPresetSelectionDefinitions.ContainsKey([string]$FunctionName)) { return $null }
		return $Script:ExplicitPresetSelectionDefinitions[[string]$FunctionName]
	}

	function Set-GuiExplicitSelectionDefinition
	{
		param (
			[Parameter(Mandatory = $true)][string]$FunctionName,
			[Parameter(Mandatory = $true)][object]$Definition
		)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return }

		$copy = Copy-GuiExplicitSelectionDefinition -Definition $Definition -FunctionName ([string]$FunctionName)
		if (-not $copy) { return }

		$Script:ExplicitPresetSelectionDefinitions[[string]$FunctionName] = $copy
		[void]$Script:ExplicitPresetSelections.Add([string]$FunctionName)
	}

	function Remove-GuiExplicitSelectionDefinition
	{
		param ([string]$FunctionName)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return }

		[void]($Script:ExplicitPresetSelectionDefinitions.Remove([string]$FunctionName))
		[void]($Script:ExplicitPresetSelections.Remove([string]$FunctionName))
	}

	function Resolve-GuiPresetFilePath
	{
		param([Parameter(Mandatory = $true)][string]$PresetName)

		if ([string]::IsNullOrWhiteSpace($PresetName)) { return $null }

		$candidateRoots = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiPresetDirectoryPath))
		{
			$candidateRoots += $Script:GuiPresetDirectoryPath
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
		{
			$candidateRoots += (Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Data\Presets')
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot))
		{
			$candidateRoots += (Join-Path -Path $PSScriptRoot -ChildPath 'Data\Presets')
			$candidateRoots += (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Data\Presets')
		}

		foreach ($root in $candidateRoots | Select-Object -Unique)
		{
			if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

			$jsonPath = Join-Path -Path $root -ChildPath ("{0}.json" -f $PresetName)
			if (Test-Path -LiteralPath $jsonPath -PathType Leaf -ErrorAction SilentlyContinue)
			{
				return $jsonPath
			}

			$path = Join-Path -Path $root -ChildPath ("{0}.txt" -f $PresetName)
			if (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue)
			{
				return $path
			}
		}

		return $null
	}

	function Get-GuiPresetEntries
	{
		param([Parameter(Mandatory = $true)][string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$presetPath = Resolve-GuiPresetFilePath -PresetName $PresetName
		if ([string]::IsNullOrWhiteSpace([string]$presetPath))
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Preset '{0}' could not be resolved to a JSON or TXT file." -f $PresetName)
			}
			throw "Preset file '$PresetName.json' or '$PresetName.txt' was not found under Data\Presets."
		}

		if ($writeGuiPresetDebugScript)
		{
			$presetFormat = if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase)) { 'JSON' } else { 'Text' }
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Loading preset '{0}' from '{1}' ({2})." -f $PresetName, $presetPath, $presetFormat)
		}

		$entries = New-Object System.Collections.Generic.List[object]
		$addParsedLine = {
			param([string]$Line)

			$trimmed = ([string]$Line).Trim()
			if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
			if ($trimmed.StartsWith('#')) { return }

			$parts = @($trimmed -split '\s+', 2)
			$functionName = $parts[0].Trim()
			if ([string]::IsNullOrWhiteSpace($functionName)) { return }

			$argumentText = ''
			if ($parts.Count -gt 1) { $argumentText = $parts[1].Trim() }

			[void]($entries.Add([pscustomobject]@{
				FunctionName = $functionName
				ArgumentText = $argumentText
				RawLine      = $trimmed
			}))
		}

		if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase))
		{
			$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
			$rawEntries = [System.Collections.Generic.List[object]]::new()
			if ($presetData -and (Test-GuiObjectField -Object $presetData -FieldName 'Entries'))
			{
				foreach ($e in $presetData.Entries) { if ($null -ne $e) { [void]$rawEntries.Add($e) } }
			}
			elseif ($presetData -is [System.Collections.IEnumerable] -and -not ($presetData -is [string]))
			{
				foreach ($e in $presetData) { if ($null -ne $e) { [void]$rawEntries.Add($e) } }
			}

			foreach ($rawEntry in $rawEntries)
			{
				if ($null -eq $rawEntry) { continue }

				if ($rawEntry -is [string])
				{
					& $addParsedLine $rawEntry
					continue
				}

				$commandLine = $null
				if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Command') -and -not [string]::IsNullOrWhiteSpace([string]$rawEntry.Command))
				{
					$commandLine = [string]$rawEntry.Command
				}
				else
				{
					$functionName = $null
					if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Function')) { $functionName = [string]$rawEntry.Function }
					$typeName = $null
					if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Type')) { $typeName = [string]$rawEntry.Type }

					switch -Regex ($typeName)
					{
						'^Toggle$'
						{
							$state = $null
							if ((Test-GuiObjectField -Object $rawEntry -FieldName 'State')) { $state = [string]$rawEntry.State } elseif ((Test-GuiObjectField -Object $rawEntry -FieldName 'Value')) { $state = [string]$rawEntry.Value }
							if ($state -match '^(?i:on|true|1)$')
							{
								$commandLine = '{0} -Enable' -f $functionName
							}
							elseif ($state -match '^(?i:off|false|0)$')
							{
								$commandLine = '{0} -Disable' -f $functionName
							}
							elseif ($functionName)
							{
								$commandLine = $functionName
							}
						}
						'^Choice$'
						{
							$choiceValue = $null
							if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Value')) { $choiceValue = [string]$rawEntry.Value } elseif ((Test-GuiObjectField -Object $rawEntry -FieldName 'SelectedValue')) { $choiceValue = [string]$rawEntry.SelectedValue }
							if (-not [string]::IsNullOrWhiteSpace($choiceValue) -and $functionName)
							{
								$commandLine = '{0} -{1}' -f $functionName, $choiceValue
							}
						}
						'^Action$'
						{
							if ($functionName)
							{
								$commandLine = $functionName
							}
						}
						default
						{
							if ($functionName)
							{
								$commandLine = $functionName
							}
						}
					}
				}

				& $addParsedLine $commandLine
			}
		}
		else
		{
			foreach ($rawLine in [System.IO.File]::ReadAllLines($presetPath))
			{
				& $addParsedLine $rawLine
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Loaded {0} preset entr{1} from '{2}'." -f $entries.Count, $(if ($entries.Count -eq 1) { 'y' } else { 'ies' }), $presetPath)
		}

		return ,($entries.ToArray())
	}

	function Get-GuiSelectionDefinitionFromCommands
	{
		param (
			[Parameter(Mandatory = $true)][string]$Name,
			[string[]]$CommandLines = @(),
			[string]$SourcePath,
			[string]$ModeKind = 'Preset',
			[string]$StatusMessagePrefix = 'Preset applied',
			[string]$RestoreGuidance = $null,
			[string]$Summary = $null
		)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$manifestByFunction = @{}
		foreach ($tweak in @($Script:TweakManifest))
		{
			if ($tweak -and -not [string]::IsNullOrWhiteSpace([string]$tweak.Function))
			{
				$manifestByFunction[[string]$tweak.Function] = $tweak
			}
		}

		$selectionMap = @{}
		$unmatchedEntries = [System.Collections.Generic.List[object]]::new()
		$lineNumber = 0
		foreach ($rawCommandLine in @($CommandLines))
		{
			$lineNumber++
			$commandLine = [string]$rawCommandLine
			if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $manifestByFunction.ContainsKey($functionName))
			{
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = "No manifest entry matches '$functionName'."
				})
				continue
			}

			$tweak = $manifestByFunction[$functionName]
			$argName = $null
			if ($tokens.Count -gt 1 -and $tokens[1].StartsWith('-'))
			{
				$argName = $tokens[1].Substring(1)
			}

			$matchedEntry = $null
			switch ([string]$tweak.Type)
			{
				'Toggle'
				{
					$state = $null
					if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam) -and $argName -eq [string]$tweak.OnParam)
					{
						$state = 'On'
					}
					elseif (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam) -and $argName -eq [string]$tweak.OffParam)
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Enable' -or $argName -eq 'Show')
					{
						$state = 'On'
					}
					elseif ($argName -eq 'Disable' -or $argName -eq 'Hide')
					{
						$state = 'Off'
					}

					if ($state)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Toggle'
							State = $state
						}
					}
				}
				'Choice'
				{
					$optList = if ($null -ne $tweak.Options -and $tweak.Options -is [System.Collections.IEnumerable] -and -not ($tweak.Options -is [string])) { [string[]]$tweak.Options } elseif ($null -ne $tweak.Options) { [string[]]@([string]$tweak.Options) } else { [string[]]@() }
					if (-not [string]::IsNullOrWhiteSpace([string]$argName) -and $optList -contains $argName)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Choice'
							Value = $argName
						}
					}
				}
				'Action'
				{
					$matchedEntry = [pscustomobject]@{
						Function = $functionName
						Type = 'Action'
						Run = $true
					}
				}
			}

			if ($matchedEntry)
			{
				$selectionMap[$functionName] = $matchedEntry
			}
			else
			{
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = "Command did not map cleanly onto tweak type '$([string]$tweak.Type)'."
				})
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiSelectionDefinitionFromCommands' -Message ("Selection definition '{0}' resolved to {1} matched entr{2} and {3} unmatched entr{4}." -f $Name, $selectionMap.Count, $(if ($selectionMap.Count -eq 1) { 'y' } else { 'ies' }), $unmatchedEntries.Count, $(if ($unmatchedEntries.Count -eq 1) { 'y' } else { 'ies' }))
		}

		return [pscustomobject]@{
			Name = $Name
			Tier = $Name
			SelectionMode = 'Explicit'
			Entries = $selectionMap
			UnmatchedEntries = [object[]]$unmatchedEntries.ToArray()
			PolicyIssues = @()
			SourcePath = $SourcePath
			ModeKind = $ModeKind
			StatusMessagePrefix = $StatusMessagePrefix
			RestoreGuidance = $RestoreGuidance
			Summary = $Summary
		}
	}

	function Set-GuiPresetSelection
	{
		param([Parameter(Mandatory = $true)][string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Received preset request '{0}' on current tab '{1}'." -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
		}
		if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab) -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Ignoring preset '{0}' because there is no active primary tab or the search-results tab is selected." -f $PresetName)
			}
			return
		}

		$setTabPresetScript = ${function:Set-TabPreset}
		if (-not $setTabPresetScript)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Could not dispatch preset '{0}' because Set-TabPreset is unavailable." -f $PresetName)
			}
			return
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Dispatching preset '{0}' to Set-TabPreset for tab '{1}'." -f $PresetName, $Script:CurrentPrimaryTab)
		}
		try
		{
			& $setTabPresetScript -PrimaryTab $Script:CurrentPrimaryTab -PresetTier $PresetName
		}
		catch
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Set-TabPreset failed for preset '{0}' on tab '{1}': {2}" -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }), $_.Exception.Message)
			}
			throw
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Completed preset dispatch for '{0}'." -f $PresetName)
		}
	}

	function Set-GuiScenarioProfileSelection
	{
		param([Parameter(Mandatory = $true)][string]$ProfileName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab) -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			return
		}

		$setTabPresetScript = ${function:Set-TabPreset}
		if (-not $setTabPresetScript)
		{
			return
		}

		$scenarioDefinition = @(
			Get-ScenarioProfileDefinitions |
				Where-Object { [string]$_.Name -eq [string]$ProfileName } |
				Select-Object -First 1
		)
		if (-not $scenarioDefinition)
		{
			throw "Scenario profile '$ProfileName' was not found."
		}

		$commandList = @(Get-ScenarioProfileCommandList -Manifest $Script:TweakManifest -ProfileName $ProfileName)
		if (-not $commandList -or $commandList.Count -eq 0)
		{
			throw "Scenario profile '$ProfileName' did not resolve to any commands."
		}

		$selectionDefinition = Get-GuiSelectionDefinitionFromCommands `
			-Name ([string]$scenarioDefinition.Name) `
			-CommandLines $commandList `
			-SourcePath ("ScenarioProfile::{0}" -f [string]$scenarioDefinition.Name) `
			-ModeKind 'Scenario' `
			-StatusMessagePrefix 'Scenario mode applied' `
			-RestoreGuidance $(if ([string]$scenarioDefinition.Name -eq 'Recovery') { 'Recovery mode adds a restore point action plus recovery and startup helpers before you need them.' } else { $null }) `
			-Summary ([string]$scenarioDefinition.Summary)

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiScenarioProfileSelection' -Message ("Dispatching scenario profile '{0}' with {1} command(s)." -f $ProfileName, $commandList.Count)
		}

		& $setTabPresetScript -PrimaryTab $Script:CurrentPrimaryTab -PresetTier $ProfileName -SelectionDefinition $selectionDefinition
	}

	function Test-TweakMatchesPresetTier
	{
		param (
			[hashtable]$Tweak,
			[string]$Tier
		)

		if (-not $Tweak) { return $false }
		$getPresetTierRankScript = ${function:Get-PresetTierRank}
		if (-not $getPresetTierRankScript) { return $false }
		return ((& $getPresetTierRankScript -Tier $Tweak.PresetTier) -le (& $getPresetTierRankScript -Tier $Tier))
	}

	function Get-GuiPresetCommandsPath
	{
		param ([string]$PresetName)

		$convertToGuiPresetNameScript = ${function:ConvertTo-GuiPresetName}
		$normalizedPresetName = if ($convertToGuiPresetNameScript)
		{
			& $convertToGuiPresetNameScript -PresetName $PresetName
		}
		else
		{
			if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		}
		$presetDirectory = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'Data\Presets'
		if (-not (Test-Path -LiteralPath $presetDirectory))
		{
			return $null
		}

		$jsonPath = Join-Path -Path $presetDirectory -ChildPath ("{0}.json" -f $normalizedPresetName)
		if (Test-Path -LiteralPath $jsonPath)
		{
			return $jsonPath
		}

		$candidatePath = Join-Path -Path $presetDirectory -ChildPath ("{0}.txt" -f $normalizedPresetName)
		if (Test-Path -LiteralPath $candidatePath)
		{
			return $candidatePath
		}

		return $null
	}

	function Import-GuiPresetSelectionMap
	{
		param ([string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$getGuiPresetCommandsPathScript = ${function:Get-GuiPresetCommandsPath}
		$presetCommandsPath = $null
		if ($getGuiPresetCommandsPathScript)
		{
			$presetCommandsPath = & $getGuiPresetCommandsPathScript -PresetName $PresetName
		}
		if ([string]::IsNullOrWhiteSpace($presetCommandsPath) -or -not (Test-Path -LiteralPath $presetCommandsPath))
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Preset '{0}' resolved to no file path." -f $PresetName)
			}
			return [pscustomobject]@{
				Path = $null
				Entries = @{}
				UnmatchedEntries = @()
				PolicyIssues = @()
			}
		}

		$manifestByFunction = @{}
		foreach ($tweak in $Script:TweakManifest)
		{
			if ($tweak -and -not [string]::IsNullOrWhiteSpace([string]$tweak.Function))
			{
				$manifestByFunction[[string]$tweak.Function] = $tweak
			}
		}

		$getGuiPresetPolicyIssuesScript = ${function:Get-GuiPresetPolicyIssues}
		$selectionMap = @{}
		$unmatchedEntries = [System.Collections.Generic.List[object]]::new()
		$lineNumber = 0
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Parsing preset map for '{0}' from '{1}'." -f $PresetName, $presetCommandsPath)
		}
		$presetEntryList = Get-GuiPresetEntries -PresetName $PresetName
		if ($null -eq $presetEntryList) { $presetEntryList = @() }
		foreach ($presetEntry in $presetEntryList)
		{
			$lineNumber++
			$commandLine = ''
			if ((Test-GuiObjectField -Object $presetEntry -FieldName 'RawLine') -and -not [string]::IsNullOrWhiteSpace([string]$presetEntry.RawLine)) { $commandLine = [string]$presetEntry.RawLine }
			if ([string]::IsNullOrWhiteSpace($commandLine))
			{
				$commandLine = '{0} {1}' -f [string]$presetEntry.FunctionName, [string]$presetEntry.ArgumentText
			}
			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $manifestByFunction.ContainsKey($functionName))
			{
				$reason = "No manifest entry matches '$functionName'."
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = $reason
				})
				if ($writeGuiPresetDebugScript)
				{
					& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason)
				}
				continue
			}

			$tweak = $manifestByFunction[$functionName]
			$argName = $null
			if ($tokens.Count -gt 1 -and $tokens[1].StartsWith('-')) { $argName = $tokens[1].Substring(1) }
			$matchedEntry = $null
			$reason = $null
			$debugMessage = $null

			switch ($tweak.Type)
			{
				'Toggle'
				{
					$state = $null
					if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam) -and $argName -eq [string]$tweak.OnParam)
					{
						$state = 'On'
					}
					elseif (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam) -and $argName -eq [string]$tweak.OffParam)
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Enable')
					{
						$state = 'On'
					}
					elseif ($argName -eq 'Disable' -or $argName -eq 'Hide')
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Show')
					{
						$state = 'On'
					}

					if ($state)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Toggle'
							State = $state
						}
						$debugMessage = "Line {0}: {1} -> Toggle {2}." -f $lineNumber, $commandLine, $state
					}
					else
					{
						$expectedArgs = [System.Collections.Generic.List[string]]::new()
						if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam)) { [void]$expectedArgs.Add("-$([string]$tweak.OnParam)") }
						if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam)) { [void]$expectedArgs.Add("-$([string]$tweak.OffParam)") }
						if (-not ($expectedArgs -contains '-Enable')) { [void]$expectedArgs.Add('-Enable') }
						if (-not ($expectedArgs -contains '-Disable')) { [void]$expectedArgs.Add('-Disable') }
						if (-not ($expectedArgs -contains '-Show')) { [void]$expectedArgs.Add('-Show') }
						if (-not ($expectedArgs -contains '-Hide')) { [void]$expectedArgs.Add('-Hide') }

						$reason = if ([string]::IsNullOrWhiteSpace($argName))
						{
							"Missing toggle argument. Expected one of: $($expectedArgs -join ', ')."
						}
						else
						{
							"Toggle argument '-$argName' does not map to '$functionName'. Expected one of: $($expectedArgs -join ', ')."
						}

						[void]$unmatchedEntries.Add([pscustomobject]@{
							LineNumber = $lineNumber
							Command = $commandLine
							Function = $functionName
							Reason = $reason
						})
						$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
					}
				}
				'Choice'
				{
					$optList = if ($null -ne $tweak.Options -and $tweak.Options -is [System.Collections.IEnumerable] -and -not ($tweak.Options -is [string])) { [string[]]$tweak.Options } elseif ($null -ne $tweak.Options) { [string[]]@([string]$tweak.Options) } else { [string[]]@() }
					if (-not [string]::IsNullOrWhiteSpace([string]$argName) -and $optList -contains $argName)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Choice'
							Value = $argName
						}
						$debugMessage = "Line {0}: {1} -> Choice '{2}'." -f $lineNumber, $commandLine, $argName
					}
					else
					{
						$availableOptions = [string[]]($optList | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
						$reason = if ([string]::IsNullOrWhiteSpace([string]$argName))
						{
							"Missing choice value. Expected one of: $($availableOptions -join ', ')."
						}
						else
						{
							"Choice value '$argName' does not match '$functionName'. Expected one of: $($availableOptions -join ', ')."
						}

						[void]$unmatchedEntries.Add([pscustomobject]@{
							LineNumber = $lineNumber
							Command = $commandLine
							Function = $functionName
							Reason = $reason
						})
						$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
					}
				}
				'Action'
				{
					$matchedEntry = [pscustomobject]@{
						Function = $functionName
						Type = 'Action'
						Run = $true
					}
					$debugMessage = "Line {0}: {1} -> Action run." -f $lineNumber, $commandLine
				}
				default
				{
					$reason = "Unsupported tweak type '$($tweak.Type)'."
					[void]$unmatchedEntries.Add([pscustomobject]@{
						LineNumber = $lineNumber
						Command = $commandLine
						Function = $functionName
						Reason = $reason
					})
					$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
				}
			}

			if ($matchedEntry)
			{
				$selectionMap[$functionName] = $matchedEntry
			}

			if ($writeGuiPresetDebugScript -and $debugMessage)
			{
				& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message $debugMessage
			}
		}

		$policyIssues = @()
		if ($getGuiPresetPolicyIssuesScript)
		{
			$policyValidation = & $getGuiPresetPolicyIssuesScript -PresetName $PresetName -PresetEntries $presetEntryList -ManifestByFunction $manifestByFunction
			if ($policyValidation -and (Test-GuiObjectField -Object $policyValidation -FieldName 'Issues') -and $null -ne $policyValidation.Issues)
			{
				$policyIssues = [object[]]$policyValidation.Issues
			}
			if ($writeGuiPresetDebugScript -and $policyIssues.Count -gt 0)
			{
				$policyMessage = "Preset policy validation for '{0}' found {1} issue$(if ($policyIssues.Count -eq 1) { '' } else { 's' })." -f $PresetName, $policyIssues.Count
				& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message $policyMessage
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Completed preset map parse for '{0}'. Matched={1}, Unmatched={2}." -f $PresetName, $selectionMap.Count, $unmatchedEntries.Count)
		}

		$unmatchedArray = [object[]]$unmatchedEntries.ToArray()
		return [pscustomobject]@{
			Path = $presetCommandsPath
			Entries = $selectionMap
			UnmatchedEntries = $unmatchedArray
			PolicyIssues = $policyIssues
		}
	}

	function Get-GuiPresetDefinition
	{
		param ([string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$convertToGuiPresetNameScript = ${function:ConvertTo-GuiPresetName}
		$importGuiPresetSelectionMapScript = ${function:Import-GuiPresetSelectionMap}
		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		if ($convertToGuiPresetNameScript)
		{
			$normalizedPresetName = [string](& $convertToGuiPresetNameScript -PresetName $PresetName)
		}
		$presetSelectionData = $null
		if ($importGuiPresetSelectionMapScript)
		{
			$presetSelectionData = & $importGuiPresetSelectionMapScript -PresetName $normalizedPresetName
		}
		if (-not $presetSelectionData)
		{
			$presetSelectionData = [pscustomobject]@{
				Path = $null
				Entries = @{}
				UnmatchedEntries = ([object[]]@())
				PolicyIssues = ([object[]]@())
			}
		}
		$explicitSelections = @{}
		if ($presetSelectionData -and (Test-GuiObjectField -Object $presetSelectionData -FieldName 'Entries')) { $explicitSelections = $presetSelectionData.Entries }
		$unmatchedEntries = [object[]]@()
		if ($presetSelectionData -and (Test-GuiObjectField -Object $presetSelectionData -FieldName 'UnmatchedEntries') -and $null -ne $presetSelectionData.UnmatchedEntries) { $unmatchedEntries = [object[]]$presetSelectionData.UnmatchedEntries }
		$policyIssues = [object[]]@()
		if ($presetSelectionData -and (Test-GuiObjectField -Object $presetSelectionData -FieldName 'PolicyIssues') -and $null -ne $presetSelectionData.PolicyIssues) { $policyIssues = [object[]]$presetSelectionData.PolicyIssues }
		$sourcePath = $null
		if ($presetSelectionData -and (Test-GuiObjectField -Object $presetSelectionData -FieldName 'Path')) { $sourcePath = [string]$presetSelectionData.Path }
		$selectionMode = 'Tier'
		if (-not [string]::IsNullOrWhiteSpace($sourcePath)) { $selectionMode = 'Explicit' }

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetDefinition' -Message ("Resolved preset '{0}' -> normalized '{1}', mode={2}, source='{3}', entries={4}, unmatched={5}." -f $PresetName, $normalizedPresetName, $selectionMode, $(if ($sourcePath) { $sourcePath } else { '<none>' }), $explicitSelections.Count, $unmatchedEntries.Count)
		}

		return [pscustomobject]@{
			Name = $normalizedPresetName
			Tier = $normalizedPresetName
			SelectionMode = $selectionMode
			Entries = $explicitSelections
			UnmatchedEntries = $unmatchedEntries
			PolicyIssues = $policyIssues
			SourcePath = $sourcePath
		}
	}

	function Set-FilterSelections
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Risk = 'All',
			[string]$Category = 'All',
			[bool]$SelectedOnly = $false,
			[bool]$HighRiskOnly = $false,
			[bool]$RestorableOnly = $false,
			[bool]$GamingOnly = $false
		)

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:RiskFilter = if ([string]::IsNullOrWhiteSpace($Risk)) { 'All' } else { $Risk }
			if ($CmbRiskFilter)
			{
				if ($CmbRiskFilter.Items.Contains($Script:RiskFilter))
				{
					$found = $CmbRiskFilter.Items.IndexOf($Script:RiskFilter)
					if ($found -ge 0) { $CmbRiskFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbRiskFilter.SelectedIndex = $idx
					$Script:RiskFilter = 'All'
				}
			}

			$Script:CategoryFilter = if ([string]::IsNullOrWhiteSpace($Category)) { 'All' } else { $Category }
			if ($CmbCategoryFilter)
			{
				if ($CmbCategoryFilter.Items.Contains($Script:CategoryFilter))
				{
					$found = $CmbCategoryFilter.Items.IndexOf($Script:CategoryFilter)
					if ($found -ge 0) { $CmbCategoryFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbCategoryFilter.SelectedIndex = $idx
					$Script:CategoryFilter = 'All'
				}
			}

			$Script:SelectedOnlyFilter = [bool]$SelectedOnly
			if ($ChkSelectedOnly) { $ChkSelectedOnly.IsChecked = $Script:SelectedOnlyFilter }

			$Script:HighRiskOnlyFilter = [bool]$HighRiskOnly
			if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsChecked = $Script:HighRiskOnlyFilter }

			$Script:RestorableOnlyFilter = [bool]$RestorableOnly
			if ($ChkRestorableOnly) { $ChkRestorableOnly.IsChecked = $Script:RestorableOnlyFilter }

			$Script:GamingOnlyFilter = [bool]$GamingOnly
			if ($ChkGamingOnly) { $ChkGamingOnly.IsChecked = $Script:GamingOnlyFilter }
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	function Clear-InvisibleSelectionState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$testTweakVisibleInCurrentModeScript = ${function:Test-TweakVisibleInCurrentMode}
		if (-not $testTweakVisibleInCurrentModeScript -or -not $Script:TweakManifest -or -not $Script:Controls)
		{
			return 0
		}

		$clearedCount = 0
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$tweak = $Script:TweakManifest[$i]
			if (-not $tweak) { continue }
			if (& $testTweakVisibleInCurrentModeScript -Tweak $tweak) { continue }

			$control = $Script:Controls[$i]
			$wasSelected = $false

			switch ($tweak.Type)
			{
				'Toggle'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
					{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						IsChecked = $false
						IsEnabled = $false
					}
				}
				'Choice'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'SelectedIndex') -and [int]$control.SelectedIndex -ge 0)
					{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						SelectedIndex = [int]-1
						IsEnabled = $false
					}
				}
				'Action'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
					{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						IsChecked = $false
						IsEnabled = $false
					}
				}
			}

			Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$tweak.Function)

			if ($wasSelected)
			{
				$clearedCount++
			}
		}

		return $clearedCount
	}

