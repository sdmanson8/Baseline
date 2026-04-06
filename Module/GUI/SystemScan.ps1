# System scan: environment detection, state comparison, and recommendation engine

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
				$currentState = [bool](& $entry.Detect)
			}
			catch
			{
				return $false
			}

			return ($currentState -ne [bool]$entry.Default)
		}

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

		function Get-GuiEnvironmentRecommendationData
		{
			$signalLabels = [System.Collections.Generic.List[string]]::new()
			$recommendations = [System.Collections.Generic.List[object]]::new()

			$gpuVendors = [System.Collections.Generic.List[string]]::new()
			try
			{
				$controllers = @()
				if (Get-Command -Name 'Get-CimInstance' -ErrorAction SilentlyContinue)
				{
					$controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
				}
				elseif (Get-Command -Name 'Get-WmiObject' -ErrorAction SilentlyContinue)
				{
					$controllers = @(Get-WmiObject -Class Win32_VideoController -ErrorAction Stop)
				}

				foreach ($controller in @($controllers))
				{
					$controllerName = [string]$controller.Name
					if ([string]::IsNullOrWhiteSpace($controllerName)) { continue }
					if ($controllerName -match '(?i)nvidia' -and -not ($gpuVendors -contains 'NVIDIA')) { [void]$gpuVendors.Add('NVIDIA') }
					if ($controllerName -match '(?i)amd|radeon' -and -not ($gpuVendors -contains 'AMD')) { [void]$gpuVendors.Add('AMD') }
					if ($controllerName -match '(?i)intel' -and -not ($gpuVendors -contains 'Intel')) { [void]$gpuVendors.Add('Intel') }
				}
			}
			catch
			{
				LogWarning "GUI GPU detection failed during system scan: $($_.Exception.Message)"
			}

			if ($gpuVendors.Count -gt 0)
			{
				[void]$signalLabels.Add(("GPU: {0}" -f (($gpuVendors | Select-Object -Unique) -join '/')))
			}

			$programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LocalAppData) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
			$gamingCandidateBasePaths = @(
				$env:ProgramFiles,
				${env:ProgramFiles(x86)},
				$env:LocalAppData,
				$(if (-not [string]::IsNullOrWhiteSpace([string]$env:LocalAppData)) { Join-Path $env:LocalAppData 'Programs' } else { $null })
			) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
			$xboxGameBarInstalled = $false
			try
			{
				if (Get-Command -Name 'Get-AppxPackage' -ErrorAction SilentlyContinue)
				{
					$xboxGameBarInstalled = @(
						Get-AppxPackage -Name Microsoft.XboxGamingOverlay, Microsoft.GamingServices -ErrorAction SilentlyContinue
					).Count -gt 0
				}
			}
			catch
			{
				$xboxGameBarInstalled = $false
			}
			if ($xboxGameBarInstalled)
			{
				[void]$signalLabels.Add('Xbox components')
			}

			$gameLaunchers = @(Get-GuiDetectedToolLabels -Candidates @(
				@{ Label = 'Steam'; Paths = @('Steam\steam.exe') }
				@{ Label = 'Epic'; Paths = @('Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe') }
				@{ Label = 'GOG'; Paths = @('GOG Galaxy\GalaxyClient.exe') }
				@{ Label = 'Battle.net'; Paths = @('Battle.net\Battle.net Launcher.exe') }
				@{ Label = 'EA app'; Paths = @('Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe', 'EA Games\EA Desktop\EA Desktop\EADesktop.exe') }
				@{ Label = 'Ubisoft Connect'; Paths = @('Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe') }
				@{ Label = 'Riot Client'; Paths = @('Riot Games\Riot Client\RiotClientServices.exe') }
			) -BasePaths $gamingCandidateBasePaths)
			if ($gameLaunchers.Count -gt 0)
			{
				[void]$signalLabels.Add(("Launchers: {0}" -f (($gameLaunchers | Select-Object -Unique) -join ', ')))
			}

			$gamingCompanionTools = @(Get-GuiDetectedToolLabels -Candidates @(
				@{ Label = 'Discord'; Paths = @('Discord\Update.exe') }
				@{ Label = 'OBS Studio'; Paths = @('obs-studio\bin\64bit\obs64.exe') }
				@{ Label = 'Streamlabs'; Paths = @('Programs\Streamlabs Desktop\Streamlabs Desktop.exe', 'Programs\streamlabs-desktop\StreamlabsOBS.exe') }
				@{ Label = 'XSplit'; Paths = @('SplitMediaLabs\XSplit Broadcaster\x64\Broadcaster.exe') }
			) -BasePaths $gamingCandidateBasePaths)
			if ($gamingCompanionTools.Count -gt 0)
			{
				[void]$signalLabels.Add(("Gaming tools: {0}" -f (($gamingCompanionTools | Select-Object -Unique) -join ', ')))
			}

			$gamingPeripheralSuites = @(Get-GuiDetectedToolLabels -Candidates @(
				@{ Label = 'Logitech G HUB'; Paths = @('LGHUB\lghub.exe') }
				@{ Label = 'SteelSeries GG'; Paths = @('SteelSeries\GG\SteelSeriesGG.exe') }
				@{ Label = 'Corsair iCUE'; Paths = @('Corsair\CORSAIR iCUE Software\iCUE Launcher.exe') }
				@{ Label = 'MSI Afterburner'; Paths = @('MSI Afterburner\MSIAfterburner.exe') }
			) -BasePaths $gamingCandidateBasePaths)
			if ($gamingPeripheralSuites.Count -gt 0)
			{
				[void]$signalLabels.Add(("Peripheral suites: {0}" -f (($gamingPeripheralSuites | Select-Object -Unique) -join ', ')))
			}

			$windowsTerminalInstalled = $false
			try
			{
				if (Get-Command -Name 'Get-AppxPackage' -ErrorAction SilentlyContinue)
				{
					$windowsTerminalInstalled = @(Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue).Count -gt 0
				}
			}
			catch
			{
				$windowsTerminalInstalled = $false
			}
			if ($windowsTerminalInstalled)
			{
				[void]$signalLabels.Add('Windows Terminal')
			}

			$powerShell7Installed = [bool](Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue)
			if (-not $powerShell7Installed)
			{
				$powerShell7Installed = [bool](Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue)
			}
			if ($powerShell7Installed)
			{
				[void]$signalLabels.Add('PowerShell 7')
			}

			$officeInstalled = $false
			try
			{
				$officeInstalled = (
					(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue) -or
					(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WINWORD.EXE' -ErrorAction SilentlyContinue)
				)
			}
			catch
			{
				$officeInstalled = $false
			}
			if ($officeInstalled)
			{
				[void]$signalLabels.Add('Microsoft Office')
			}

			$oneDriveInstalled = Test-GuiAnyPathExists -Paths @(
				(Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
				(Join-Path $env:LocalAppData 'Microsoft\OneDrive\OneDrive.exe'),
				(Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
			)
			if ($oneDriveInstalled)
			{
				[void]$signalLabels.Add('OneDrive')
			}

			$mappedNetworkDriveCount = 0
			try
			{
				$mappedNetworkDriveCount = @(
					Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
						Where-Object { $_.Root -and $_.Root.StartsWith('\\') }
				).Count
			}
			catch
			{
				$mappedNetworkDriveCount = 0
			}
			if ($mappedNetworkDriveCount -gt 0)
			{
				[void]$signalLabels.Add(("{0} mapped network drive{1}" -f $mappedNetworkDriveCount, $(if ($mappedNetworkDriveCount -eq 1) { '' } else { 's' })))
			}

			$domainJoined = $false
			try
			{
				if (Get-Command -Name 'Get-CimInstance' -ErrorAction SilentlyContinue)
				{
					$domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
				}
			}
			catch
			{
				$domainJoined = $false
			}
			if ($domainJoined)
			{
				[void]$signalLabels.Add('Domain joined')
			}

			$winReEnabled = $null
			try
			{
				$reagentcCommand = Get-Command -Name 'reagentc.exe' -ErrorAction SilentlyContinue
				if ($reagentcCommand)
				{
					$reagentOutput = & $reagentcCommand.Source /info 2>$null | Out-String
					if ($reagentOutput -match 'Windows RE status:\s+Enabled')
					{
						$winReEnabled = $true
					}
					elseif ($reagentOutput -match 'Windows RE status:\s+Disabled')
					{
						$winReEnabled = $false
					}
				}
			}
			catch
			{
				$winReEnabled = $null
			}
			if ($null -eq $winReEnabled)
			{
				[void]$signalLabels.Add('WinRE status unknown')
			}
			elseif ($winReEnabled)
			{
				[void]$signalLabels.Add('WinRE enabled')
			}
			else
			{
				[void]$signalLabels.Add('WinRE disabled')
			}

			$privacyPending = @(
				'ActivityHistory', 'AdvertisingID', 'DiagTrackService', 'DeliveryOptimization',
				'LanguageListAccess', 'SharedExperiences', 'TailoredExperiences',
				'Powershell7Telemetry', 'LockWidgets'
			) | Where-Object { Test-GuiManifestToggleNeedsAttention -FunctionName $_ }

			$workstationPending = @(
				'Win32LongPathLimit', 'TaskbarEndTask', 'FileExtensions',
				'WindowsManageDefaultPrinter', 'QuickAccessFrequentFolders', 'QuickAccessRecentFiles'
			) | Where-Object { Test-GuiManifestToggleNeedsAttention -FunctionName $_ }

			$recoveryPending = @(
				'AdvancedStartupShortcut', 'AutoRebootOnCrash', 'RegistryBackup',
				'EventViewerCustomView', 'F8BootMenu', 'RestartNotification', 'BootRecovery'
			) | Where-Object { Test-GuiManifestToggleNeedsAttention -FunctionName $_ }

			$gameModeEvidence = [System.Collections.Generic.List[string]]::new()
			if ($gpuVendors.Count -gt 0)
			{
				[void]$gameModeEvidence.Add(("GPU: {0}" -f (($gpuVendors | Select-Object -Unique) -join '/')))
			}
			if ($xboxGameBarInstalled)
			{
				[void]$gameModeEvidence.Add('Xbox components')
			}
			if ($gameLaunchers.Count -gt 0)
			{
				[void]$gameModeEvidence.Add(("launchers: {0}" -f (($gameLaunchers | Select-Object -Unique) -join ', ')))
			}
			if ($gamingCompanionTools.Count -gt 0)
			{
				[void]$gameModeEvidence.Add(("gaming tools: {0}" -f (($gamingCompanionTools | Select-Object -Unique) -join ', ')))
			}
			if ($gamingPeripheralSuites.Count -gt 0)
			{
				[void]$gameModeEvidence.Add(("peripheral suites: {0}" -f (($gamingPeripheralSuites | Select-Object -Unique) -join ', ')))
			}

			if (($gpuVendors.Count -gt 0) -and ($xboxGameBarInstalled -or $gameLaunchers.Count -gt 0 -or $gamingCompanionTools.Count -gt 0 -or $gamingPeripheralSuites.Count -gt 0))
			{
				$gameModeEvidenceText = Get-GuiEnvironmentSummaryText -Items @($gameModeEvidence) -MaxItems 4
				[void]$recommendations.Add([pscustomobject]@{
					Name = 'Game Mode'
					Reason = if ([string]::IsNullOrWhiteSpace([string]$gameModeEvidenceText))
					{
						'Detected gaming-related software or components on this PC. This only changes the recommendation copy and does not alter Game Mode profile defaults or queued actions automatically.'
					}
					else
					{
						"Detected gaming-related signals: $gameModeEvidenceText. This only changes the recommendation copy and does not alter Game Mode profile defaults or queued actions automatically."
					}
				})
			}

			if ($workstationPending.Count -ge 2 -or (($windowsTerminalInstalled -or $powerShell7Installed -or $officeInstalled -or $domainJoined -or $mappedNetworkDriveCount -gt 0) -and $workstationPending.Count -ge 1))
			{
				[void]$recommendations.Add([pscustomobject]@{
					Name = 'Workstation'
					Reason = ("{0} workstation-oriented tweak{1} are still away from the preferred state." -f $workstationPending.Count, $(if ($workstationPending.Count -eq 1) { '' } else { 's' }))
				})
			}

			if ($privacyPending.Count -ge 2 -or (($oneDriveInstalled -or $xboxGameBarInstalled) -and $privacyPending.Count -ge 1))
			{
				[void]$recommendations.Add([pscustomobject]@{
					Name = 'Privacy'
					Reason = ("{0} privacy-oriented setting{1} still differ from the preferred state." -f $privacyPending.Count, $(if ($privacyPending.Count -eq 1) { '' } else { 's' }))
				})
			}

			if ($recoveryPending.Count -ge 1 -or ($null -ne $winReEnabled -and -not $winReEnabled))
			{
				$recoveryReason = if ($null -ne $winReEnabled -and -not $winReEnabled)
				{
					'Windows Recovery Environment looks disabled, so the recovery helper profile is worth applying before deeper changes.'
				}
				else
				{
					("{0} recovery helper{1} are still missing or disabled." -f $recoveryPending.Count, $(if ($recoveryPending.Count -eq 1) { '' } else { 's' }))
				}
				[void]$recommendations.Add([pscustomobject]@{
					Name = 'Recovery'
					Reason = $recoveryReason
				})
			}

			$signalSummary = Get-GuiEnvironmentSummaryText -Items @($signalLabels)
			$recommendationNames = @($recommendations | ForEach-Object { [string]$_.Name })
			$summaryTextParts = @()
			if (-not [string]::IsNullOrWhiteSpace([string]$signalSummary))
			{
				$summaryTextParts += "Environment: $signalSummary."
			}
			if ($recommendationNames.Count -gt 0)
			{
				$summaryTextParts += "Recommended profiles: $($recommendationNames -join ', ')."
				$summaryTextParts += 'Recommendations stay advisory only and do not change selections or defaults automatically.'
			}

			return [pscustomobject]@{
				Signals = @($signalLabels)
				Recommendations = @($recommendations)
				SummaryText = ($summaryTextParts -join ' ')
			}
		}

		$Script:ScanEnabled = $true
		Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiScanningSystem' -Fallback 'Scanning system state...') -Tone 'accent'
		$null = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'RenderRefresh' -Synchronous -Action {}

		$matchCount = 0
		$scannable  = 0
		$sessionApplied = 0

		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			if ($sctl) { $sctl.IsEnabled = $true }
		}

		for ($si = 0; $si -lt $Script:TweakManifest.Count; $si++)
		{
			$st   = $Script:TweakManifest[$si]
			$sctl = $Script:Controls[$si]

			if (-not $sctl) { continue }

			if ($Script:AppliedTweaks.Contains($st.Function))
			{
				$sctl.IsEnabled = $false
				if ((Test-GuiObjectField -Object $sctl -FieldName 'IsChecked')) { $sctl.IsChecked = $false }
				$matchCount++
				$sessionApplied++
				continue
			}

			if ($st.Scannable -eq $false -or -not $st.Detect) { continue }
			$scannable++

			$currentlyOn = $false
			try { $currentlyOn = [bool](& $st.Detect) } catch { $currentlyOn = $false }

			if ($currentlyOn -eq [bool]$st.Default)
			{
				$sctl.IsEnabled = $false
				if ((Test-GuiObjectField -Object $sctl -FieldName 'IsChecked')) { $sctl.IsChecked = $false }
				$matchCount++
			}
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

