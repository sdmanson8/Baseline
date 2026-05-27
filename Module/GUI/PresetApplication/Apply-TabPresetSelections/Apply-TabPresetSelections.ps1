for ($index = 0; $index -lt $totalCount; $index++)
		{
			$stats.ProcessedCount++
			if ($progressBar -and ($index % 50 -eq 0))
			{
				Set-SharedProgressBarState -ProgressBar $progressBar -Completed $index -Total $totalCount
				[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
			}
			$tweak = $Script:TweakManifest[$index]
			$control = $Script:Controls[$index]
			if (-not $control)
			{
				$stats.ControlMissingCount++
				continue
			}

			if (Get-Command -Name 'Test-GuiTweakAvailableOnCurrentSystem' -CommandType Function -ErrorAction SilentlyContinue)
			{
				if (-not (Test-GuiTweakAvailableOnCurrentSystem -Tweak $tweak))
				{
					Clear-GuiSelectableControlState -Control $control
					if ((Test-GuiObjectField -Object $control -FieldName 'IsEnabled'))
					{
						$control.IsEnabled = $false
					}
					if (Get-Command -Name 'Remove-GuiExplicitSelectionDefinition' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$tweak.Function)
					}
					$stats.HiddenCount++
					continue
				}
			}

			$isVisible = $true
			if ($tweak.VisibleIf)
			{
				try
				{
					$isVisible = [bool](& $tweak.VisibleIf)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\PresetApplication\Apply-TabPresetSelections\Apply-TabPresetSelections.ps1:42' -Severity Debug }

					$isVisible = $false
				}
			}

			if ($isVisible)
			{
				$stats.VisibleCount++
			}
			else
			{
				$stats.HiddenCount++
			}

			if ((Test-GuiObjectField -Object $control -FieldName 'IsEnabled'))
			{
				$control.IsEnabled = $isVisible
			}

			if (-not $isVisible)
			{
				Clear-GuiSelectableControlState -Control $control
				continue
			}

			switch ($tweak.Type)
			{
				'Toggle'
				{
					$stats.ToggleCount++
					$presetEntry = if ($PresetContext.UsesExplicitPreset -and $null -ne $PresetContext.PresetEntries[$tweak.Function]) { $PresetContext.PresetEntries[$tweak.Function] } else { $null }
					if ($PresetContext.UsesExplicitPreset)
					{
						$includeInPreset = ($null -ne $presetEntry)
						$targetChecked = ($includeInPreset -and [string]$presetEntry.State -eq 'On')
					}
					else
					{
						$includeInPreset = (& $TestTweakMatchesPresetTierScript -Tweak $tweak -Tier $PresetContext.PresetDefinition.Tier)
						$targetChecked = ($includeInPreset -and [bool]$tweak.Default)
					}

					$currentChecked = $false
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$currentChecked = [bool]$control.IsChecked
					}
					if ($currentChecked -ne [bool]$targetChecked)
					{
						$stats.StateChangeCount++
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$control.IsChecked = $targetChecked
					}

					if ($includeInPreset)
					{
						if ($PresetContext.UsesExplicitPreset)
						{
							[void]$Script:ExplicitPresetSelections.Add([string]$tweak.Function)
							$hasRunParam = if ($targetChecked) { -not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam) } else { -not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam) }
							if ($hasRunParam)
							{
								$stats.SelectedCount++
							}
						}
						elseif ($targetChecked)
						{
							$stats.SelectedCount++
						}
					}

					if ($tweak.LinkedWith -and $SyncLinkedStateCapture)
					{
						& $SyncLinkedStateCapture $tweak.LinkedWith $targetChecked
					}
				}
				'Action'
				{
					$stats.ActionCount++
					$presetEntry = if ($PresetContext.UsesExplicitPreset -and $null -ne $PresetContext.PresetEntries[$tweak.Function]) { $PresetContext.PresetEntries[$tweak.Function] } else { $null }
					if ($PresetContext.UsesExplicitPreset)
					{
						$includeInPreset = ($null -ne $presetEntry -and [bool]$presetEntry.Run)
						$targetChecked = $includeInPreset
					}
					else
					{
						$includeInPreset = (& $TestTweakMatchesPresetTierScript -Tweak $tweak -Tier $PresetContext.PresetDefinition.Tier)
						$targetChecked = ($includeInPreset -and [bool]$tweak.Default)
					}

					$currentChecked = $false
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$currentChecked = [bool]$control.IsChecked
					}
					if ($currentChecked -ne [bool]$targetChecked)
					{
						$stats.StateChangeCount++
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$control.IsChecked = $targetChecked
					}
					if ($targetChecked)
					{
						$stats.SelectedCount++
					}

					if ($tweak.LinkedWith -and $SyncLinkedStateCapture)
					{
						& $SyncLinkedStateCapture $tweak.LinkedWith $targetChecked
					}
				}
					'Choice'
					{
						$stats.ChoiceCount++
						$targetSelectedIndex = -1
						$choiceOptions = Get-GuiChoiceOptions -Options $tweak.Options
					$presetEntry = if ($PresetContext.UsesExplicitPreset -and $null -ne $PresetContext.PresetEntries[$tweak.Function]) { $PresetContext.PresetEntries[$tweak.Function] } else { $null }
					if ($PresetContext.UsesExplicitPreset)
					{
						$includeInPreset = ($null -ne $presetEntry)
						if ($includeInPreset)
						{
							$targetSelectedIndex = [array]::IndexOf($choiceOptions, [string]$presetEntry.Value)
						}
					}
					else
					{
						$includeInPreset = (& $TestTweakMatchesPresetTierScript -Tweak $tweak -Tier $PresetContext.PresetDefinition.Tier)
						if ($includeInPreset)
						{
							$targetSelectedIndex = [array]::IndexOf($choiceOptions, $tweak.Default)
						}
					}

					if ($targetSelectedIndex -ge $choiceOptions.Count)
					{
						$targetSelectedIndex = -1
					}

					$currentSelectedIndex = -1
					if ((Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						$currentSelectedIndex = [int]$control.SelectedIndex
					}
					if ($currentSelectedIndex -ne [int]$targetSelectedIndex)
					{
						$stats.StateChangeCount++
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						[int]$selectedIndex = $targetSelectedIndex
						$control.SelectedIndex = $selectedIndex
					}
						if ($targetSelectedIndex -ge 0)
						{
							$stats.SelectedCount++
						}
					}
					'NumericRange'
					{
						$stats.NumericRangeCount++
						$presetEntry = if ($PresetContext.UsesExplicitPreset -and $null -ne $PresetContext.PresetEntries[$tweak.Function]) { $PresetContext.PresetEntries[$tweak.Function] } else { $null }
						if ($PresetContext.UsesExplicitPreset)
						{
							$includeInPreset = ($null -ne $presetEntry)
							$targetChecked = $includeInPreset
						}
						else
						{
							$includeInPreset = (& $TestTweakMatchesPresetTierScript -Tweak $tweak -Tier $PresetContext.PresetDefinition.Tier)
							$targetChecked = [bool]$includeInPreset
						}

						$targetValueSource = if ($PresetContext.UsesExplicitPreset -and $null -ne $presetEntry)
						{
							$presetEntry
						}
						elseif (Test-GuiObjectField -Object $tweak -FieldName 'Default')
						{
							$tweak.Default
						}
						elseif (Test-GuiObjectField -Object $tweak -FieldName 'WinDefault')
						{
							$tweak.WinDefault
						}
						else
						{
							$null
						}

						$currentChecked = if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked')) { [bool]$control.IsChecked } else { $false }

						$currentACValue = if ((Test-GuiObjectField -Object $control -FieldName 'ACValue')) { $control.ACValue } else { $null }
						$currentDCValue = if ((Test-GuiObjectField -Object $control -FieldName 'DCValue')) { $control.DCValue } else { $null }
						if ($null -ne $targetValueSource)
						{
							$targetACValue = Get-GuiNumericRangeChannelValue -Value $targetValueSource -Channel 'AC' -NumericRange $tweak.NumericRange
							$targetDCValue = Get-GuiNumericRangeChannelValue -Value $targetValueSource -Channel 'DC' -NumericRange $tweak.NumericRange
						}
						else
						{
							$targetACValue = $null
							$targetDCValue = $null
						}

						$currentValueText = if ($null -ne $currentACValue -or $null -ne $currentDCValue)
						{
							Format-GuiPowerSchemeValueText -Value ([pscustomobject]@{ ACValue = $currentACValue; DCValue = $currentDCValue }) -NumericRange $tweak.NumericRange
						}
						else
						{
							$null
						}
						$targetValueText = if ($null -ne $targetACValue -or $null -ne $targetDCValue)
						{
							Format-GuiPowerSchemeValueText -Value ([pscustomobject]@{
								ACValue = $targetACValue
								DCValue = $targetDCValue
							}) -NumericRange $tweak.NumericRange
						}
						else
						{
							$null
						}

						if ((Test-GuiObjectField -Object $control -FieldName 'IsRestoring'))
						{
							$control.IsRestoring = $true
						}
						try
						{
							if ((Test-GuiObjectField -Object $control -FieldName 'CheckBox') -and $control.CheckBox)
							{
								$control.CheckBox.IsChecked = [bool]$targetChecked
							}
							elseif ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
							{
								$control.IsChecked = [bool]$targetChecked
							}

							if ((Test-GuiObjectField -Object $control -FieldName 'ACSlider') -and $control.ACSlider)
							{
								$control.ACSlider.IsEnabled = [bool]$targetChecked
								if ($null -ne $targetACValue)
								{
									$control.ACSlider.Value = [double]$targetACValue
								}
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'DCSlider') -and $control.DCSlider)
							{
								$control.DCSlider.IsEnabled = [bool]$targetChecked
								if ($null -ne $targetDCValue)
								{
									$control.DCSlider.Value = [double]$targetDCValue
								}
							}

							if ((Test-GuiObjectField -Object $control -FieldName 'ACValueText') -and $control.ACValueText)
							{
								$control.ACValueText.Text = if ($null -ne $targetACValue) { (Format-GuiNumericRangeValueText -Value $targetACValue -NumericRange $tweak.NumericRange) } else { '' }
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'DCValueText') -and $control.DCValueText)
							{
								$control.DCValueText.Text = if ($null -ne $targetDCValue) { (Format-GuiNumericRangeValueText -Value $targetDCValue -NumericRange $tweak.NumericRange) } else { '' }
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'SummaryText') -and $control.SummaryText)
							{
								$summaryValue = if ($null -ne $targetValueText) { $targetValueText } elseif ($null -ne $currentValueText) { $currentValueText } else { 'No numeric value selected' }
								$control.SummaryText.Text = (Get-UxLocalizedString -Key 'GuiNumericRangeSelectedValue' -Fallback 'Selected values: {0}' -FormatArgs @($summaryValue))
							}

							if ((Test-GuiObjectField -Object $control -FieldName 'ACValue'))
							{
								$control.ACValue = $targetACValue
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'DCValue'))
							{
								$control.DCValue = $targetDCValue
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'Value'))
							{
								if ($null -ne $targetACValue -or $null -ne $targetDCValue)
								{
									$control.Value = [pscustomobject]@{
										ACValue = $targetACValue
										DCValue = $targetDCValue
									}
								}
								else
								{
									$control.Value = $null
								}
							}
							if ((Test-GuiObjectField -Object $control -FieldName 'NumericValue'))
							{
								$control.NumericValue = if ($null -ne $targetACValue -and $null -eq $targetDCValue) { $targetACValue } elseif ($null -ne $targetDCValue -and $null -eq $targetACValue) { $targetDCValue } elseif ($null -ne $targetACValue -and $null -ne $targetDCValue -and [string]$targetACValue -eq [string]$targetDCValue) { $targetACValue } else { $null }
							}
						}
						finally
						{
							if ((Test-GuiObjectField -Object $control -FieldName 'IsRestoring'))
							{
								$control.IsRestoring = $false
							}
						}

						if ($currentChecked -ne [bool]$targetChecked -or [string]$currentValueText -ne [string]$targetValueText)
						{
							$stats.StateChangeCount++
						}

						if ([bool]$targetChecked)
						{
							$stats.SelectedCount++
						}
					}
				}
			}
