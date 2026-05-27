	$Script:CurrentPrimaryTab = $null
	$Script:SubTabControls = @{}


	. (Join-Path $Script:GuiExtractedRoot 'PresetUI.ps1')


	<#
	    .SYNOPSIS
	#>

	function Add-TabSectionsToPanel
	{
		param (
			[object]$BuildContext,
			[switch]$CooperativeYield,
			[int]$YieldEveryNRows = 3,
			[System.Windows.Threading.DispatcherPriority]$YieldDispatcherPriority = [System.Windows.Threading.DispatcherPriority]::Background,
			[object]$BuildGeneration = $null,
			[string]$BuildToken = $null,
			[switch]$BackgroundBuild
		)

		$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Start-GuiPerfScope'
		$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Stop-GuiPerfScope'
		$__perf = if ($startGuiPerfScopeScript) { & $startGuiPerfScopeScript -Name 'BuildTabContent.AddTabSectionsToPanel' -Note $BuildContext.PrimaryTab } else { $null }
		$primaryTab = [string]$BuildContext.PrimaryTab
		$aborted = $false
		$dispatcher = $null
		if ($CooperativeYield)
		{
			try { $dispatcher = $BuildContext.MainPanel.Dispatcher } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.Add-TabSectionsToPanel:catch25' -Severity Debug }
				$dispatcher = $null
			}
		}
		$rowCounter = 0

		try
		{
			foreach ($subKey in $BuildContext.CategoryTweaks.Keys)
			{
				if (-not (Test-TabContentHydrationCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration -BuildToken $BuildToken -BackgroundBuild:$BackgroundBuild))
				{
					$aborted = $true
					return $false
				}

				try
				{
					$indexes = $BuildContext.CategoryTweaks[$subKey]
				}
				catch
				{
					throw "Build-TabContent/ResolveSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
				}

				$showSectionHeader = $BuildContext.IsSearchResultsTab -or ($BuildContext.CategoryTweaks.Count -gt 1) -or ([string]$subKey -ne 'General')
				if ($showSectionHeader)
				{
					try
					{
						[void]($BuildContext.MainPanel.Children.Add((New-SectionHeader -Text $subKey)))
					}
					catch
					{
						throw "Build-TabContent/SectionHeader for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
					}
				}

				$cautionTweaksList = [System.Collections.Generic.List[object]]::new()
				foreach ($index in $indexes)
				{
					if (-not (Test-TabContentHydrationCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration -BuildToken $BuildToken -BackgroundBuild:$BackgroundBuild))
					{
						$aborted = $true
						return $false
					}

					try
					{
						$tweak = $Script:TweakManifest[$index]
					}
					catch
					{
						throw "Build-TabContent/ResolveTweak for tab '$($BuildContext.PrimaryTab)' at index $index failed: $($_.Exception.Message)"
					}

					if ($tweak.Caution)
					{
						[void]$cautionTweaksList.Add($tweak)
					}

					try
					{
						$row = Build-TweakRow -Index $index -Tweak $tweak -BrushConverter $BuildContext.BrushConverter
					}
					catch
					{
						throw "Build-TabContent/Row for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
					}

					if ($row)
					{
						try
						{
							[void]($BuildContext.MainPanel.Children.Add($row))
						}
						catch
						{
							throw "Build-TabContent/AddRow for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
						}

						if ($dispatcher)
						{
							$rowCounter++
							if ($rowCounter -ge $YieldEveryNRows)
							{
								$rowCounter = 0
								try { $dispatcher.Invoke($YieldDispatcherPriority, [System.Action]{}) }
								catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.AddRow.DispatcherYield' }
								if (-not (Test-TabContentHydrationCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration -BuildToken $BuildToken -BackgroundBuild:$BackgroundBuild))
								{
									$aborted = $true
									return $false
								}
							}
						}
					}
				}

				if ($cautionTweaksList.Count -gt 0)
				{
					try
					{
						$cautionSection = New-CautionSection -CautionTweaks @($cautionTweaksList)
					}
					catch
					{
						throw "Build-TabContent/CautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
					}

					if ($cautionSection)
					{
						try
						{
							[void]($BuildContext.MainPanel.Children.Add($cautionSection))
						}
						catch
						{
							throw "Build-TabContent/AddCautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
						}
					}
				}
			}

			return $true
		}
		finally
		{
			if ($stopGuiPerfScopeScript)
			{
				if ($aborted) { & $stopGuiPerfScopeScript -Scope $__perf -ExtraNote ($primaryTab + ':aborted') }
				else { & $stopGuiPerfScopeScript -Scope $__perf }
			}
		}
	}

	function New-TabSectionsRenderPlan
	{
		param ([object]$BuildContext)

		$renderPlan = [System.Collections.Generic.List[object]]::new()
		foreach ($subKey in $BuildContext.CategoryTweaks.Keys)
		{
			try
			{
				$indexes = $BuildContext.CategoryTweaks[$subKey]
			}
			catch
			{
				throw "Build-TabContent/ResolveSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
			}

			$showSectionHeader = $BuildContext.IsSearchResultsTab -or ($BuildContext.CategoryTweaks.Count -gt 1) -or ([string]$subKey -ne 'General')
			if ($showSectionHeader)
			{
				[void]$renderPlan.Add([pscustomobject]@{
					Kind = 'Header'
					Section = [string]$subKey
					Text = [string]$subKey
				})
			}

			$cautionTweaksList = [System.Collections.Generic.List[object]]::new()
			foreach ($index in $indexes)
			{
				try
				{
					$tweak = $Script:TweakManifest[$index]
				}
				catch
				{
					throw "Build-TabContent/ResolveTweak for tab '$($BuildContext.PrimaryTab)' at index $index failed: $($_.Exception.Message)"
				}

				if ($tweak.Caution)
				{
					[void]$cautionTweaksList.Add($tweak)
				}
				[void]$renderPlan.Add([pscustomobject]@{
					Kind = 'Row'
					Section = [string]$subKey
					Index = [int]$index
					Tweak = $tweak
				})
			}

			if ($cautionTweaksList.Count -gt 0)
			{
				[void]$renderPlan.Add([pscustomobject]@{
					Kind = 'Caution'
					Section = [string]$subKey
					CautionTweaks = @($cautionTweaksList)
				})
			}
		}

		return @($renderPlan)
	}

	function Add-TabRenderPlanItem
	{
		param (
			[object]$BuildContext,
			[object]$RenderItem
		)

		if (-not $RenderItem) { return $false }
		switch ([string]$RenderItem.Kind)
		{
			'Header'
			{
				try
				{
					[void]($BuildContext.MainPanel.Children.Add((New-SectionHeader -Text ([string]$RenderItem.Text))))
				}
				catch
				{
					throw "Build-TabContent/SectionHeader for tab '$($BuildContext.PrimaryTab)' section '$([string]$RenderItem.Section)' failed: $($_.Exception.Message)"
				}
				return $false
			}
			'Row'
			{
				$index = [int]$RenderItem.Index
				$tweak = $RenderItem.Tweak
				try
				{
					$row = Build-TweakRow -Index $index -Tweak $tweak -BrushConverter $BuildContext.BrushConverter
				}
				catch
				{
					throw "Build-TabContent/Row for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
				}

				if ($row)
				{
					try
					{
						[void]($BuildContext.MainPanel.Children.Add($row))
					}
					catch
					{
						throw "Build-TabContent/AddRow for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
					}
					return $true
				}
				return $false
			}
			'Caution'
			{
				try
				{
					$cautionSection = New-CautionSection -CautionTweaks $RenderItem.CautionTweaks
				}
				catch
				{
					throw "Build-TabContent/CautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$RenderItem.Section)' failed: $($_.Exception.Message)"
				}

				if ($cautionSection)
				{
					try
					{
						[void]($BuildContext.MainPanel.Children.Add($cautionSection))
					}
					catch
					{
						throw "Build-TabContent/AddCautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$RenderItem.Section)' failed: $($_.Exception.Message)"
					}
				}
				return $false
			}
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Save-TabContentCacheEntry
	{
		param (
			[object]$BuildContext,
			[int[]]$AllTabIndexes,
			[switch]$CacheOnly
		)

		if (-not $CacheOnly)
		{
			Show-TabContentBuildPanel -BuildContext $BuildContext
			try
			{
				if ($Script:UpdateGuiBackToTopButtonScript)
				{
					& $Script:UpdateGuiBackToTopButtonScript -Source 'BuildTabContent.SaveTabContentCacheEntry.UpdateBackToTopButton'
				}
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.SaveTabContentCacheEntry.UpdateBackToTopButton' -Severity Debug
			}
		}
		$controlRefs = @{}
		foreach ($index in @($AllTabIndexes))
		{
			if ($Script:Controls.ContainsKey($index) -and $Script:Controls[$index])
			{
				$controlRefs[[int]$index] = $Script:Controls[$index]
			}
		}
		$Script:TabContentCache[$BuildContext.PrimaryTab] = @{
			PrimaryTab = $BuildContext.PrimaryTab
			Panel = $BuildContext.MainPanel
			ControlRefs = $controlRefs
			PresetStatusBadge = $Script:PresetStatusBadge
			FilterGeneration = $Script:FilterGeneration
		}
	}

	function Show-TabContentBuildPanel
	{
		param (
			[object]$BuildContext
		)

		$ContentScroll.Content = $BuildContext.MainPanel
		$Script:VisibleTabContentPrimaryTab = [string]$BuildContext.PrimaryTab
		try
		{
			if ($Script:UpdateGuiBackToTopButtonScript)
			{
				& $Script:UpdateGuiBackToTopButtonScript
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.ShowTabContentBuildPanel.UpdateBackToTopButton'
		}
	}

	function Test-TabContentBuildStillCurrent
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$PrimaryTab,
			[object]$BuildGeneration
		)

		if ($null -ne $BuildGeneration -and [int]$Script:TabContentBuildGeneration -ne [int]$BuildGeneration)
		{
			return $false
		}

		$currentPrimaryMatches = ([string]$Script:CurrentPrimaryTab -eq $PrimaryTab)
		$visiblePrimaryMatches = ([string]$Script:VisibleTabContentPrimaryTab -eq $PrimaryTab)
		if (-not $currentPrimaryMatches -and -not $visiblePrimaryMatches)
		{
			return $false
		}

		if ($PrimaryTab -eq 'Gaming')
		{
			return [bool]$Script:GamingModeActive
		}

		if ($PrimaryTab -eq 'Updates')
		{
			return [bool]$Script:UpdatesModeActive
		}

		if ([bool]$Script:AppsModeActive -or [bool]$Script:DeploymentMediaModeActive -or [bool]$Script:GamingModeActive -or [bool]$Script:UpdatesModeActive)
		{
			return $false
		}

		return $true
	}

	if (-not ($Script:TabContentBuildTokens -is [hashtable]))
	{
		$Script:TabContentBuildTokens = @{}
	}
	if (-not ($Script:TabContentBackgroundBuildTokens -is [hashtable]))
	{
		$Script:TabContentBackgroundBuildTokens = @{}
	}

	function Resolve-TabContentBuildPrimaryTab
	{
		param ([string]$PrimaryTab)

		if (-not [string]::IsNullOrWhiteSpace([string]$PrimaryTab))
		{
			return ([string]$PrimaryTab).Trim()
		}

		if ([bool]$Script:GamingModeActive) { return 'Gaming' }
		if ([bool]$Script:UpdatesModeActive) { return 'Updates' }

		$searchText = if ($null -eq $Script:SearchText) { '' } else { ([string]$Script:SearchText).Trim() }
		if (-not [string]::IsNullOrWhiteSpace($searchText) -and -not [string]::IsNullOrWhiteSpace([string]$Script:SearchResultsTabTag))
		{
			return [string]$Script:SearchResultsTabTag
		}

		if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$PrimaryTabs.SelectedItem.Tag))
		{
			return [string]$PrimaryTabs.SelectedItem.Tag
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab))
		{
			return [string]$Script:CurrentPrimaryTab
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:LastStandardPrimaryTab))
		{
			return [string]$Script:LastStandardPrimaryTab
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:StartupHydratePrimaryTab))
		{
			return [string]$Script:StartupHydratePrimaryTab
		}

		if ($PrimaryTabs)
		{
			foreach ($tabItem in $PrimaryTabs.Items)
			{
				if (($tabItem -is [System.Windows.Controls.TabItem]) -and -not [string]::IsNullOrWhiteSpace([string]$tabItem.Tag))
				{
					$tabTag = [string]$tabItem.Tag
					if ($tabTag -ne [string]$Script:SearchResultsTabTag)
					{
						return $tabTag
					}
				}
			}
		}

		return $null
	}

	function Test-GuiVisibleTabContentCurrent
	{
		param (
			[string]$PrimaryTab
		)

		if ([bool]$Script:AppsModeActive -or [bool]$Script:DeploymentMediaModeActive)
		{
			return $true
		}

		$resolvedPrimaryTab = Resolve-TabContentBuildPrimaryTab -PrimaryTab $PrimaryTab
		if ([string]::IsNullOrWhiteSpace([string]$resolvedPrimaryTab))
		{
			return $false
		}

		if (-not $ContentScroll -or -not $ContentScroll.Content)
		{
			return $false
		}

		return ([string]$Script:VisibleTabContentPrimaryTab -eq [string]$resolvedPrimaryTab)
	}

	function Test-TabContentBuildTokenCurrent
	{
		param (
			[string]$PrimaryTab,
			[string]$BuildToken
		)

		if ([string]::IsNullOrWhiteSpace([string]$PrimaryTab) -or [string]::IsNullOrWhiteSpace([string]$BuildToken))
		{
			return $false
		}

		return (
			$Script:TabContentBuildTokens -is [hashtable] -and
			$Script:TabContentBuildTokens.ContainsKey($PrimaryTab) -and
			[string]$Script:TabContentBuildTokens[$PrimaryTab] -eq [string]$BuildToken
		)
	}

	function Clear-TabContentBuildToken
	{
		param (
			[string]$PrimaryTab,
			[string]$BuildToken
		)

		if ([string]::IsNullOrWhiteSpace([string]$PrimaryTab) -or [string]::IsNullOrWhiteSpace([string]$BuildToken))
		{
			return
		}

		if (Test-TabContentBuildTokenCurrent -PrimaryTab $PrimaryTab -BuildToken $BuildToken)
		{
			[void]$Script:TabContentBuildTokens.Remove($PrimaryTab)
		}
		if (
			$Script:TabContentBackgroundBuildTokens -is [hashtable] -and
			$Script:TabContentBackgroundBuildTokens.ContainsKey($PrimaryTab) -and
			[string]$Script:TabContentBackgroundBuildTokens[$PrimaryTab] -eq [string]$BuildToken
		)
		{
			[void]$Script:TabContentBackgroundBuildTokens.Remove($PrimaryTab)
		}
	}

	function Stop-GuiTabContentBackgroundBuilds
	{
		if (-not ($Script:TabContentBackgroundBuildTokens -is [hashtable]))
		{
			$Script:TabContentBackgroundBuildTokens = @{}
			return
		}

		foreach ($entry in @($Script:TabContentBackgroundBuildTokens.GetEnumerator()))
		{
			$tab = [string]$entry.Key
			$token = [string]$entry.Value
			if (
				$Script:TabContentBuildTokens -is [hashtable] -and
				$Script:TabContentBuildTokens.ContainsKey($tab) -and
				[string]$Script:TabContentBuildTokens[$tab] -eq $token
			)
			{
				[void]$Script:TabContentBuildTokens.Remove($tab)
			}
		}
		$Script:TabContentBackgroundBuildTokens.Clear()
	}

	function Test-GuiIdleTabPrebuildAllowed
	{
		if ([bool]$Script:AppsModeActive -or [bool]$Script:DeploymentMediaModeActive -or [bool]$Script:GamingModeActive -or [bool]$Script:UpdatesModeActive)
		{
			return $false
		}
		if (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try
			{
				if (Test-GuiRunInProgress) { return $false }
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.TestGuiIdleTabPrebuildAllowed.RunState'
				return $false
			}
		}

		return $true
	}

	function Test-TabContentHydrationCurrent
	{
		param (
			[string]$PrimaryTab,
			[object]$BuildGeneration = $null,
			[string]$BuildToken = $null,
			[switch]$BackgroundBuild
		)

		if (-not [string]::IsNullOrWhiteSpace([string]$BuildToken) -and -not (Test-TabContentBuildTokenCurrent -PrimaryTab $PrimaryTab -BuildToken $BuildToken))
		{
			return $false
		}

		if ($BackgroundBuild -and -not (Test-GuiIdleTabPrebuildAllowed))
		{
			return $false
		}

		if (-not $BackgroundBuild -and $null -ne $BuildGeneration -and -not (Test-TabContentBuildStillCurrent -PrimaryTab $PrimaryTab -BuildGeneration $BuildGeneration))
		{
			return $false
		}

		return $true
	}

	function Start-GuiIdleTabPrebuilds
	{
		param (
			[string]$PrimaryTab,
			[switch]$SkipIdlePrebuild
		)

		if ($SkipIdlePrebuild -or -not $PrimaryTabs -or -not $PrimaryTabs.Dispatcher -or -not (Test-GuiIdleTabPrebuildAllowed))
		{
			Stop-GuiTabContentBackgroundBuilds
			return
		}

		if ($Script:TweakManifest -and -not $Script:StartupOrchestratorRan)
		{
			$invokeBaselineStartupOrchestratorScript = Get-GuiFunctionCapture -Name 'Invoke-BaselineStartupOrchestrator'
			$Script:StartupOrchestratorDispatcher = $PrimaryTabs.Dispatcher
			$orchestratorBody = {
				try
				{
					$mr = $null
					if ($Script:GuiExtractedRoot) { $mr = Split-Path -Path $Script:GuiExtractedRoot -Parent }
					if ($invokeBaselineStartupOrchestratorScript)
					{
						& $invokeBaselineStartupOrchestratorScript -TweakManifest $Script:TweakManifest -ModuleRoot $mr -BaselineVersion ([string]$Script:CurrentBaselineVersion) -Dispatcher $Script:StartupOrchestratorDispatcher
					}
				}
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.UpdateView.StartupOrchestrator' }
			}
			$mod = $ExecutionContext.SessionState.Module
			if ($mod) { $orchestratorBody = $mod.NewBoundScriptBlock($orchestratorBody) }
			$null = $PrimaryTabs.Dispatcher.BeginInvoke(
				[System.Action]$orchestratorBody,
				[System.Windows.Threading.DispatcherPriority]::ApplicationIdle
			)
		}
	}

	function Complete-TabContentBuild
	{
		param (
			[object]$BuildContext,
			[int[]]$AllTabIndexes,
			[object]$BuildGeneration,
			[string]$BuildToken,
			[switch]$BackgroundBuild,
			[switch]$SkipIdlePrebuild,
			[switch]$AlreadyDisplayed
		)

		$primaryTab = [string]$BuildContext.PrimaryTab
		try
		{
			if ($BackgroundBuild)
			{
				Save-TabContentCacheEntry -BuildContext $BuildContext -AllTabIndexes $AllTabIndexes -CacheOnly
				return
			}

			$displayBuiltContent = Test-TabContentBuildStillCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration
			Save-TabContentCacheEntry -BuildContext $BuildContext -AllTabIndexes $AllTabIndexes -CacheOnly:($AlreadyDisplayed -or -not $displayBuiltContent)
			if (-not $displayBuiltContent)
			{
				return
			}

			try
			{
				Update-MainContentPanelWidth -Panel $BuildContext.MainPanel
			}
			catch
			{
				throw "Build-TabContent/UpdatePanelWidth for tab '$primaryTab' failed: $($_.Exception.Message)"
			}
			try
			{
				Restore-CurrentTabScrollOffset -TabKey $primaryTab
			}
			catch
			{
				throw "Build-TabContent/RestoreScrollOffset for tab '$primaryTab' failed: $($_.Exception.Message)"
			}

			Invoke-GuiStartupReadySignal
			if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Update-GuiScopedRunActionAvailability
			}

			Start-GuiIdleTabPrebuilds -PrimaryTab $primaryTab -SkipIdlePrebuild:$SkipIdlePrebuild
		}
		finally
		{
			if (-not [string]::IsNullOrWhiteSpace($BuildToken))
			{
				Clear-TabContentBuildToken -PrimaryTab $primaryTab -BuildToken $BuildToken
			}
		}
	}

	function Start-ProgressiveTabSectionsHydration
	{
		param (
			[object]$BuildContext,
			[int[]]$AllTabIndexes,
			[object]$BuildGeneration,
			[string]$BuildToken,
			[switch]$BackgroundBuild,
			[switch]$SkipIdlePrebuild
		)

		$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Start-GuiPerfScope'
		$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Stop-GuiPerfScope'
		$__perf = if ($startGuiPerfScopeScript) { & $startGuiPerfScopeScript -Name 'BuildTabContent.ProgressiveHydration' -Note $BuildContext.PrimaryTab } else { $null }
		$renderPlan = @(New-TabSectionsRenderPlan -BuildContext $BuildContext)
		$dispatcher = $BuildContext.MainPanel.Dispatcher
		$state = [pscustomobject]@{
			Position = 0
			RenderPlan = $renderPlan
			Action = $null
		}
		$priority = if ($BackgroundBuild) { [System.Windows.Threading.DispatcherPriority]::ApplicationIdle } else { [System.Windows.Threading.DispatcherPriority]::Loaded }
		$primaryTab = [string]$BuildContext.PrimaryTab
		$chunkAction = $null
		$chunkAction = {
			try
			{
				if (-not (Test-TabContentHydrationCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration -BuildToken $BuildToken -BackgroundBuild:$BackgroundBuild))
				{
					if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf -ExtraNote ($primaryTab + ':aborted') }
					Clear-TabContentBuildToken -PrimaryTab $primaryTab -BuildToken $BuildToken
					return
				}
				if (-not $BackgroundBuild -and -not (Test-TabContentBuildStillCurrent -PrimaryTab $primaryTab -BuildGeneration $BuildGeneration))
				{
					if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf -ExtraNote ($primaryTab + ':stale') }
					Clear-TabContentBuildToken -PrimaryTab $primaryTab -BuildToken $BuildToken
					return
				}

				$chunkWatch = [System.Diagnostics.Stopwatch]::StartNew()
				$rowsAdded = 0
				while ($state.Position -lt $state.RenderPlan.Count)
				{
					$renderItem = $state.RenderPlan[$state.Position]
					$state.Position++
					$rowAdded = Add-TabRenderPlanItem -BuildContext $BuildContext -RenderItem $renderItem
					if ($rowAdded)
					{
						$rowsAdded++
					}

					if ($rowsAdded -ge 1 -or $chunkWatch.ElapsedMilliseconds -ge 35)
					{
						break
					}
				}

				if ($state.Position -lt $state.RenderPlan.Count)
				{
					$null = $dispatcher.BeginInvoke($state.Action, $priority)
					return
				}

				Complete-TabContentBuild -BuildContext $BuildContext -AllTabIndexes $AllTabIndexes -BuildGeneration $BuildGeneration -BuildToken $BuildToken -BackgroundBuild:$BackgroundBuild -SkipIdlePrebuild:$SkipIdlePrebuild -AlreadyDisplayed:((-not $BackgroundBuild))
				if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf }
			}
			catch
			{
				if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf -ExtraNote ($primaryTab + ':failed') }
				Clear-TabContentBuildToken -PrimaryTab $primaryTab -BuildToken $BuildToken
				Write-GuiRuntimeWarning -Context ('BuildTabContent.ProgressiveHydration:{0}' -f $primaryTab) -Message $_.Exception.Message
			}
		}.GetNewClosure()

		$mod = $ExecutionContext.SessionState.Module
		if ($mod) { $chunkAction = $mod.NewBoundScriptBlock($chunkAction) }
		$state.Action = [System.Action]$chunkAction
		if ($BackgroundBuild)
		{
			$null = $dispatcher.BeginInvoke($state.Action, $priority)
		}
		else
		{
			$state.Action.Invoke()
		}
	}

	# Keep the startup splash release contract in one place so cached and
	# freshly built startup tabs behave the same.
	function Invoke-GuiStartupReadySignal
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[object]$MainForm = $Script:MainForm,
			[object]$Splash = $Global:LoadingSplash
		)

	try
	{
		$startupSplashAbortRequested = $false
		if ($Splash -is [hashtable])
		{
			if (Get-Command -Name 'Test-GuiStartupSplashAbortRequested' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$startupSplashAbortRequested = [bool](Test-GuiStartupSplashAbortRequested -Splash $Splash)
			}
			elseif ($Splash.ContainsKey('AbortRequested') -and [bool]$Splash.AbortRequested) { $startupSplashAbortRequested = $true }
			elseif ($Splash.ContainsKey('UserClosed') -and [bool]$Splash.UserClosed) { $startupSplashAbortRequested = $true }
			elseif ($Splash.ContainsKey('GuiReady') -and [bool]$Splash.GuiReady) { $startupSplashAbortRequested = $false }
			elseif ($Splash.ContainsKey('ProgrammaticClose') -and [bool]$Splash.ProgrammaticClose) { $startupSplashAbortRequested = $false }
			elseif ($Splash.ContainsKey('IsAlive') -and $Splash.ContainsKey('WasRendered') -and [bool]$Splash.WasRendered -and (-not [bool]$Splash.IsAlive)) { $startupSplashAbortRequested = $true }
		}
		if ($startupSplashAbortRequested)
		{
			if (Get-Command -Name 'Stop-GuiStartupSplashAbortProcess' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Stop-GuiStartupSplashAbortProcess -Message 'BuildTabContent aborted before GuiReady because startup splash was closed'
			}
			[System.Environment]::Exit(0)
			try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.Invoke-GuiStartupReadySignal:catch219' -Severity Debug }
			 }
			return
		}

		# Signal GuiReady NOW - the foreground tab is built. The
		# ContentRendered splash handoff owns the first visible transition
		# because WPF requires the window to stay hidden until ShowDialog().
			if ($Splash -and $Splash -is [hashtable])
			{
				$completeStartupSplashStepCommand = Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
				if ($completeStartupSplashStepCommand)
				{
					& $completeStartupSplashStepCommand -Splash $Splash -StepId 'finalize' -Status 'completed' -SubAction '' | Out-Null
				}
				$Splash.GuiReady = $true
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.UpdateView.SignalGuiReady' }
	}

	# Helper for Dispatcher.BeginInvoke tab pre-builds. The returned closure keeps
	# the requested tab tag while the module-bound scriptblock keeps sibling GUI
	# functions and $Script: state resolvable.
	<#
	    .SYNOPSIS
	#>

	function New-TabPreBuildAction
	{
		param ([string]$Tag)
		$capturedTag = $Tag
		$sb = {
			try
			{
				$buildInProgress = ($Script:TabContentBuildTokens -is [hashtable] -and $Script:TabContentBuildTokens.ContainsKey($capturedTag))
				if (-not (Test-GuiRunInProgress) -and -not $buildInProgress -and -not ($Script:TabContentCache -and $Script:TabContentCache.ContainsKey($capturedTag)))
				{
					Build-TabContent -PrimaryTab $capturedTag -BackgroundBuild
				}
			}
			catch
			{
				Write-GuiRuntimeWarning -Context ('TabPreBuild:{0}' -f $capturedTag) -Message $_.Exception.Message
			}
		}.GetNewClosure()
		$mod = $ExecutionContext.SessionState.Module
		if ($mod) { $sb = $mod.NewBoundScriptBlock($sb) }
		return $sb
	}

	<#
	    .SYNOPSIS
	#>

	function Build-TabContent
	{
		param (
			[string]$PrimaryTab,
			[switch]$BackgroundBuild,
			[switch]$SkipIdlePrebuild
		)

		$PrimaryTab = Resolve-TabContentBuildPrimaryTab -PrimaryTab $PrimaryTab
		if ([string]::IsNullOrWhiteSpace([string]$PrimaryTab))
		{
			throw "Build-TabContent requires a non-empty primary tab and no active GUI tab could be resolved."
		}

		$buildGeneration = $null
		if (-not $BackgroundBuild)
		{
			if ($null -eq $Script:TabContentBuildGeneration)
			{
				$Script:TabContentBuildGeneration = 0
			}
			$Script:TabContentBuildGeneration = [int]$Script:TabContentBuildGeneration + 1
			$buildGeneration = [int]$Script:TabContentBuildGeneration
			$Script:CurrentPrimaryTab = $PrimaryTab
			$Script:PresetStatusBadge = $null
			if (Get-Command -Name 'Update-PrimaryTabHeaders' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { Update-PrimaryTabHeaders } catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.Update-PrimaryTabHeaders' }
			}
			if (Restore-CachedTabContent -PrimaryTab $PrimaryTab)
			{
				Invoke-GuiStartupReadySignal
				if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Update-GuiScopedRunActionAvailability
				}
				return
			}
		}
		elseif ($Script:TabContentCache.ContainsKey($PrimaryTab))
		{
			return
		}

		if ($PrimaryTab -eq 'Customizations')
		{
			try
			{
				$customPanel = New-GuiStartupManagerTabContent
			}
			catch
			{
				throw "Build-TabContent/CustomizationsPanel for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
			if (-not $customPanel)
			{
				throw "Build-TabContent/CustomizationsPanel for tab '$PrimaryTab' failed: no panel was returned."
			}

			$customBuildContext = [pscustomobject]@{
				PrimaryTab = $PrimaryTab
				MainPanel  = $customPanel
			}

			try
			{
				Save-TabContentCacheEntry -BuildContext $customBuildContext -AllTabIndexes @() -CacheOnly:$BackgroundBuild
			}
			catch
			{
				throw "Build-TabContent/AssignContent for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}

			if ($Script:TabContentCache -and $Script:TabContentCache.ContainsKey($PrimaryTab))
			{
				$Script:TabContentCache[$PrimaryTab].PresetStatusBadge = $null
				$Script:TabContentCache[$PrimaryTab].FilterGeneration = $null
			}

			if (-not $BackgroundBuild)
			{
				try
				{
					Update-MainContentPanelWidth -Panel $customPanel
				}
				catch
				{
					throw "Build-TabContent/UpdatePanelWidth for tab '$PrimaryTab' failed: $($_.Exception.Message)"
				}
				try
				{
					Restore-CurrentTabScrollOffset -TabKey $PrimaryTab
				}
				catch
				{
					throw "Build-TabContent/RestoreScrollOffset for tab '$PrimaryTab' failed: $($_.Exception.Message)"
				}

				Invoke-GuiStartupReadySignal

				Start-GuiIdleTabPrebuilds -PrimaryTab $PrimaryTab -SkipIdlePrebuild:$SkipIdlePrebuild
			}

			return
		}

		if ($Script:TabContentBuildTokens -isnot [hashtable])
		{
			$Script:TabContentBuildTokens = @{}
		}
		if ($BackgroundBuild -and $Script:TabContentBuildTokens.ContainsKey($PrimaryTab))
		{
			return
		}
		$buildToken = [guid]::NewGuid().ToString('N')
		$Script:TabContentBuildTokens[$PrimaryTab] = $buildToken
		if ($BackgroundBuild)
		{
			$Script:TabContentBackgroundBuildTokens[$PrimaryTab] = $buildToken
		}

		try
		{
			$buildContext = New-TabContentBuildContext -PrimaryTab $PrimaryTab
		}
		catch
		{
			throw "Build-TabContent/Preamble for tab '$PrimaryTab' failed: $($_.Exception.Message)"
		}

		Add-TabContentLeadPanel -BuildContext $buildContext
		$contentAlreadyDisplayed = $false
		if ($PrimaryTab -eq 'Gaming' -and -not $BackgroundBuild)
		{
			if (Test-TabContentBuildStillCurrent -PrimaryTab $PrimaryTab -BuildGeneration $buildGeneration)
			{
				try
				{
					Show-TabContentBuildPanel -BuildContext $buildContext
					$contentAlreadyDisplayed = $true
				}
				catch
				{
					throw "Build-TabContent/AssignLeadContent for tab '$PrimaryTab' failed: $($_.Exception.Message)"
				}

				try { $buildContext.MainPanel.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [System.Action]{}) }
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTabContent.GamingLeadPanel.RenderYield' }
			}
		}

		$activeFilterItems = Get-ActiveTabFilterItems -BuildContext $buildContext
		if ($activeFilterItems.Count -gt 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-ActiveFiltersBanner -BuildContext $buildContext -ActiveFilterItems $activeFilterItems)))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/ActiveFiltersBanner' -Message ("Active filters banner failed for tab '{0}': {1}" -f $PrimaryTab, $_.Exception.Message)
			}
		}

		if ($buildContext.CategoryTweaks.Count -eq 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-EmptyTabStateCard -BuildContext $buildContext -HasActiveFilters:($activeFilterItems.Count -gt 0))))
			}
			catch
			{
				throw "Build-TabContent/EmptyState for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
		}

		try
		{
			$allTabIndexes = Get-TabContentIndexArray -CategoryTweaks $buildContext.CategoryTweaks
		}
		catch
		{
			throw "Build-TabContent/CollectTabIndexes for tab '$PrimaryTab' failed: $($_.Exception.Message)"
		}

		if ($allTabIndexes.Count -gt 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-TabSelectionBar -AllTabIndexes $allTabIndexes)))
			}
			catch
			{
				throw "Build-TabContent/SelectionBar for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
		}

		if ($allTabIndexes.Count -gt 0)
		{
			if ($contentAlreadyDisplayed -and -not $BackgroundBuild -and (Test-TabContentBuildStillCurrent -PrimaryTab $PrimaryTab -BuildGeneration $buildGeneration))
			{
				try
				{
					Update-MainContentPanelWidth -Panel $buildContext.MainPanel
					Invoke-GuiStartupReadySignal
				}
				catch
				{
					throw "Build-TabContent/AssignProgressiveContent for tab '$PrimaryTab' failed: $($_.Exception.Message)"
				}
			}

			if ($BackgroundBuild)
			{
				Start-ProgressiveTabSectionsHydration -BuildContext $buildContext -AllTabIndexes $allTabIndexes -BuildGeneration $buildGeneration -BuildToken $buildToken -BackgroundBuild -SkipIdlePrebuild:$SkipIdlePrebuild
			}
			else
			{
				try
				{
					$hydrated = Add-TabSectionsToPanel -BuildContext $buildContext -CooperativeYield -YieldEveryNRows 2 -YieldDispatcherPriority ([System.Windows.Threading.DispatcherPriority]::Background) -BuildGeneration $buildGeneration -BuildToken $buildToken
					if (-not $hydrated)
					{
						Clear-TabContentBuildToken -PrimaryTab $PrimaryTab -BuildToken $buildToken
						return
					}
					Complete-TabContentBuild -BuildContext $buildContext -AllTabIndexes $allTabIndexes -BuildGeneration $buildGeneration -BuildToken $buildToken -SkipIdlePrebuild:$SkipIdlePrebuild -AlreadyDisplayed:$contentAlreadyDisplayed
				}
				catch
				{
					Clear-TabContentBuildToken -PrimaryTab $PrimaryTab -BuildToken $buildToken
					throw "Build-TabContent/HydrateRows for tab '$PrimaryTab' failed: $($_.Exception.Message)"
				}
			}
			return
		}

		Complete-TabContentBuild -BuildContext $buildContext -AllTabIndexes $allTabIndexes -BuildGeneration $buildGeneration -BuildToken $buildToken -BackgroundBuild:$BackgroundBuild -SkipIdlePrebuild:$SkipIdlePrebuild
	}
