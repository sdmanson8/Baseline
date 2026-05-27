
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
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:PresetManagementRoot))
		{
			$candidateRoots += (Join-Path -Path $Script:PresetManagementRoot -ChildPath 'Data\Presets')
			$candidateRoots += (Join-Path -Path (Split-Path -Path $Script:PresetManagementRoot -Parent) -ChildPath 'Data\Presets')
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

	<#
	    .SYNOPSIS
	#>

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
			$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
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
							'^Date$'
							{
								$runFlag = $null
								if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Run'))
							{
								$runFlag = [bool]$rawEntry.Run
							}
							elseif ((Test-GuiObjectField -Object $rawEntry -FieldName 'State'))
							{
								$runFlag = ([string]$rawEntry.State -match '^(?i:on|true|1)$')
							}

							$dateValue = $null
							if ((Test-GuiObjectField -Object $rawEntry -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$rawEntry.Value))
							{
								$dateValue = [string]$rawEntry.Value
							}

							if ($runFlag -eq $false)
							{
								$commandLine = '{0} -Disable' -f $functionName
							}
							elseif (-not [string]::IsNullOrWhiteSpace($dateValue) -and $functionName)
							{
								$commandLine = '{0} -Enable -StartDate {1}' -f $functionName, $dateValue
							}
							elseif ($functionName)
							{
									$commandLine = '{0} -Enable' -f $functionName
								}
							}
							'^NumericRange$'
							{
								$argumentText = $null
								if ((Test-GuiObjectField -Object $rawEntry -FieldName 'ArgumentText') -and -not [string]::IsNullOrWhiteSpace([string]$rawEntry.ArgumentText))
								{
									$argumentText = [string]$rawEntry.ArgumentText
								}
								else
								{
									$argumentText = Get-GuiPresetNumericRangeArgumentText -Entry $rawEntry
								}

								if (-not [string]::IsNullOrWhiteSpace($argumentText) -and $functionName)
								{
									$commandLine = '{0} {1}' -f $functionName, $argumentText
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
		$presetDirectory = Join-Path -Path (Split-Path $Script:PresetManagementRoot -Parent) -ChildPath 'Data\Presets'
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

	<#
	    .SYNOPSIS
	#>

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
					'NumericRange'
					{
						$acValue = $null
						$dcValue = $null
						$scalarValue = $null

						for ($i = 1; $i -lt $tokens.Count; $i++)
						{
							$token = [string]$tokens[$i]
							if (-not $token.StartsWith('-'))
							{
								continue
							}

							$tokenName = $token.TrimStart('-')
							$tokenValue = if ($i + 1 -lt $tokens.Count) { [string]$tokens[$i + 1] } else { $null }
							switch ($tokenName)
							{
								'Value' { $scalarValue = $tokenValue }
								'NumericValue' { $scalarValue = $tokenValue }
								'ACValue' { $acValue = $tokenValue }
								'DCValue' { $dcValue = $tokenValue }
							}
						}

						$numericSelection = [ordered]@{
							Function = $functionName
							Type = 'NumericRange'
						}
						if ((Test-GuiObjectField -Object $tweak -FieldName 'NumericRange') -and (Test-GuiObjectField -Object $tweak.NumericRange -FieldName 'Units') -and -not [string]::IsNullOrWhiteSpace([string]$tweak.NumericRange.Units))
						{
							$numericSelection.Units = [string]$tweak.NumericRange.Units
						}

						if ($null -ne $acValue -or $null -ne $dcValue)
						{
							if ($null -ne $acValue)
							{
								$numericSelection.ACValue = $acValue
							}
							if ($null -ne $dcValue)
							{
								$numericSelection.DCValue = $dcValue
							}

							$channelValues = [ordered]@{}
							if ($null -ne $acValue)
							{
								$channelValues.ACValue = $acValue
							}
							if ($null -ne $dcValue)
							{
								$channelValues.DCValue = $dcValue
							}
							$numericSelection.Value = [pscustomobject]$channelValues
							$matchedEntry = [pscustomobject]$numericSelection
							$debugMessage = "Line {0}: {1} -> NumericRange {2}." -f $lineNumber, $commandLine, (Format-GuiPowerSchemeValueText -Value ([pscustomobject]$channelValues) -NumericRange $tweak.NumericRange)
						}
						elseif (-not [string]::IsNullOrWhiteSpace($scalarValue))
						{
							$numericSelection.Value = $scalarValue
							$numericSelection.NumericValue = $scalarValue
							$matchedEntry = [pscustomobject]$numericSelection
							$debugMessage = "Line {0}: {1} -> NumericRange {2}." -f $lineNumber, $commandLine, (Format-GuiNumericRangeValueText -Value $scalarValue -NumericRange $tweak.NumericRange)
						}
						else
						{
							$reason = "Missing numeric value. Expected -Value, -NumericValue, -ACValue, or -DCValue."
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

	<#
	    .SYNOPSIS
	#>

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

