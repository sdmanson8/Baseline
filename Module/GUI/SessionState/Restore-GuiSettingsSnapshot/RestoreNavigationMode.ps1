switch ($desiredNavigationMode)
		{
			'Apps'
			{
				if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiGamingMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiDeploymentMediaMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiUpdatesMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiAppsMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiAppsMode -Enable:$true
				}
			}
			'Gaming'
			{
				if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiDeploymentMediaMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiUpdatesMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiAppsMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiAppsMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiGamingMode -Enable:$true
				}
			}
			'Updates'
			{
				if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiGamingMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiDeploymentMediaMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiUpdatesMode -Enable:$true
				}
			}
			'DeploymentMedia'
			{
				if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiGamingMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiUpdatesMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiAppsMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiAppsMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiDeploymentMediaMode -Enable:$true
				}
			}
			default
			{
				if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiGamingMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiDeploymentMediaMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiUpdatesMode -Enable:$false
				}
				if (Get-Command -Name 'Set-GuiAppsMode' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Set-GuiAppsMode -Enable:$false
				}
			}
		}

		if ([string]::IsNullOrWhiteSpace($desiredSearch) -and $desiredTab)
		{
			if ($desiredTab -eq $Script:SearchResultsTabTag)
			{
				$restoreTag = if ($desiredLast) { $desiredLast } else { $Script:LastStandardPrimaryTab }
				$restoreTab = if ($restoreTag) { Get-PrimaryTabItem -Tag $restoreTag } else { $null }
				if (-not $restoreTab)
				{
					foreach ($tab in $PrimaryTabs.Items)
					{
						if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
						{
							$restoreTab = $tab
							break
						}
					}
				}
				if ($restoreTab -and $PrimaryTabs.SelectedItem -ne $restoreTab)
				{
					$PrimaryTabs.SelectedItem = $restoreTab
				}
			}
			else
			{
				$targetTab = Get-PrimaryTabItem -Tag $desiredTab
				if ($targetTab -and $PrimaryTabs.SelectedItem -ne $targetTab)
				{
					$PrimaryTabs.SelectedItem = $targetTab
				}
				elseif (-not $targetTab -and $PrimaryTabs)
				{
					foreach ($tab in $PrimaryTabs.Items)
					{
						if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
						{
							$PrimaryTabs.SelectedItem = $tab
							break
						}
					}
				}
			}
		}
