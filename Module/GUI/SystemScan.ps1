
# System scan: environment detection, state comparison, and recommendation engine

	<#
	    .SYNOPSIS
	#>

	function Invoke-GuiSystemScan
	{
		function Get-GuiEnvironmentSummaryText
		{
			param (
				[string[]]$Items,
				[int]$MaxItems = 5
			)

			$values = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
			if ($values.Count -eq 0)
			{
				return $null
			}

			if ($values.Count -le $MaxItems)
			{
				return ($values -join ', ')
			}

			return ('{0} +{1} more' -f (($values | Select-Object -First $MaxItems) -join ', '), ($values.Count - $MaxItems))
		}

		<#
		    .SYNOPSIS
		#>

		function Test-GuiManifestToggleNeedsAttention
		{
			param ([string]$FunctionName)

			$entry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function $FunctionName
			if (-not $entry -or [string]$entry.Type -ne 'Toggle' -or $entry.Scannable -eq $false -or -not $entry.Detect)
			{
				return $false
			}

			try
			{
				$currentState = [bool](Invoke-GuiDetectScriptblock -Detect $entry.Detect -DefaultValue ([bool]$entry.Default))
				if (Get-Command -Name 'Set-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-CachedDetection -Function $FunctionName -Value $currentState
				}
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScan.Test-GuiManifestToggleNeedsAttention.LoadCurrentState'
				return $false
			}

			return ($currentState -ne [bool]$entry.Default)
		}

		<#
		    .SYNOPSIS
		#>

		function Test-GuiAnyPathExists
		{
			param ([string[]]$Paths)

			foreach ($candidatePath in @($Paths))
			{
				if ([string]::IsNullOrWhiteSpace([string]$candidatePath)) { continue }
				if (Test-Path -LiteralPath $candidatePath -ErrorAction SilentlyContinue)
				{
					return $true
				}
			}

			return $false
		}

		<#
		    .SYNOPSIS
		#>

		function Set-GuiSystemScanControlEnabled
		{
			param (
				[object]$Control,
				[bool]$Enabled
			)

			if (-not $Control)
			{
				return
			}

			if ((Test-GuiObjectField -Object $Control -FieldName 'IsEnabled'))
			{
				$Control.IsEnabled = $Enabled
			}
		}

		<#
		    .SYNOPSIS
		#>

		function Get-GuiDetectedToolLabels
		{
			param (
				[Parameter(Mandatory = $true)]
				[object[]]$Candidates,

				[string[]]$BasePaths
			)

			$detectedLabels = [System.Collections.Generic.List[string]]::new()
			foreach ($candidate in @($Candidates))
			{
				if (-not $candidate) { continue }

				$candidateLabel = [string]$candidate.Label
				if ([string]::IsNullOrWhiteSpace($candidateLabel)) { continue }

				$candidatePaths = [System.Collections.Generic.List[string]]::new()
				foreach ($candidatePath in @($candidate.Paths))
				{
					$pathText = [string]$candidatePath
					if ([string]::IsNullOrWhiteSpace($pathText)) { continue }

					if ([System.IO.Path]::IsPathRooted($pathText))
					{
						[void]$candidatePaths.Add($pathText)
						continue
					}

					foreach ($basePath in @($BasePaths))
					{
						if ([string]::IsNullOrWhiteSpace([string]$basePath)) { continue }
						[void]$candidatePaths.Add((Join-Path $basePath $pathText))
					}
				}

				if (Test-GuiAnyPathExists -Paths @($candidatePaths))
				{
					[void]$detectedLabels.Add($candidateLabel)
				}
			}

			return @($detectedLabels | Select-Object -Unique)
		}

		<#
		    .SYNOPSIS
		#>

		. (Join-Path $PSScriptRoot 'SystemScan\Invoke-GuiSystemScan\Invoke-GuiSystemScan.ps1')

		$Script:ScanEnabled = $true
		if ($ChkScan -and -not $ChkScan.IsChecked)
		{
			$ChkScan.IsChecked = $true
		}
		Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiScanningSystem' -Fallback 'Scanning system state...') -Tone 'accent'
		$null = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'RenderRefresh' -Synchronous -Action {}

		$matchCount = 0
		$scannable  = 0
		$sessionApplied = 0

		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			Set-GuiSystemScanControlEnabled -Control $sctl -Enabled $true
		}

		for ($si = 0; $si -lt $Script:TweakManifest.Count; $si++)
		{
			$st   = $Script:TweakManifest[$si]
			$sctl = $Script:Controls[$si]

			if ($Script:AppliedTweaks.Contains($st.Function))
			{
				if ($sctl)
				{
					Set-GuiSystemScanControlEnabled -Control $sctl -Enabled $false
					if ((Test-GuiObjectField -Object $sctl -FieldName 'IsChecked')) { $sctl.IsChecked = $true }
					if (Get-Command -Name 'Remove-GuiExplicitSelectionDefinition' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$st.Function)
					}
				}
				if (Get-Command -Name 'Set-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-CachedDetection -Function ([string]$st.Function) -Value ([bool]$st.Default)
				}
				$matchCount++
				$sessionApplied++
				continue
			}

			if ($st.Scannable -eq $false -or -not $st.Detect) { continue }
			$scannable++

			$currentlyOn = $false
			try { $currentlyOn = [bool](Invoke-GuiDetectScriptblock -Detect $st.Detect -DefaultValue ([bool]$st.Default)) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScan.Invoke-GuiSystemScan:catch206' -Severity Debug }
			 $currentlyOn = $false }
			if (Get-Command -Name 'Set-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-CachedDetection -Function ([string]$st.Function) -Value $currentlyOn
			}

			if ($currentlyOn -eq [bool]$st.Default)
			{
				if ($sctl)
				{
					Set-GuiSystemScanControlEnabled -Control $sctl -Enabled $false
					if ((Test-GuiObjectField -Object $sctl -FieldName 'IsChecked')) { $sctl.IsChecked = $true }
					if (Get-Command -Name 'Remove-GuiExplicitSelectionDefinition' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$st.Function)
					}
				}
				$matchCount++
			}
		}

		if (Get-Command -Name 'Save-GuiDetectCache' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Save-GuiDetectCache
		}

		$scanMsg = if ($sessionApplied -gt 0) {
			"Scan complete - $matchCount tweaks disabled, including $sessionApplied already run in this session."
		} elseif ($matchCount -gt 0) {
			"Scan complete - $matchCount of $scannable tweaks already match their configured state."
		} else {
			"Scan complete - $scannable tweaks checked, none already applied."
		}

		$environmentData = Get-GuiEnvironmentRecommendationData
		$Script:EnvironmentRecommendationData = $environmentData
		$Script:EnvironmentSummaryText = if ($environmentData -and (Test-GuiObjectField -Object $environmentData -FieldName 'SummaryText')) { [string]$environmentData.SummaryText } else { $null }
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:EnvironmentSummaryText))
		{
			$scanMsg = "$scanMsg $($Script:EnvironmentSummaryText)"
		}

		Set-GuiStatusText -Text $scanMsg -Tone 'accent'
		$Script:PresetStatusMessage = $scanMsg
		if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:PresetStatusBadge.Child.Text = $Script:PresetStatusMessage
		}
		LogInfo $scanMsg

		if ($Script:CurrentPrimaryTab)
		{
			Clear-TabContentCache
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	}
