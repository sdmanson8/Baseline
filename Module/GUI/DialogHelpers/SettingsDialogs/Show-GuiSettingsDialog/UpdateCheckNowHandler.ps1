if ($btnSettingsCheckNow)
		{
			$btnSettingsCheckNow.Add_Click({
				$originalContent = $btnSettingsCheckNow.Content
				try
				{
					$btnSettingsCheckNow.IsEnabled = $false
					$btnSettingsCheckNow.Content = $settingsCheckingNowLabel
					$settingsUpdateState.Status = 'Not checked'
					if ($txtUpdateStatusValue) { $txtUpdateStatusValue.Text = $settingsCheckingNowLabel }
					if (-not (Get-Command -Name 'Invoke-BaselineUpdateCheck' -CommandType Function -ErrorAction SilentlyContinue)) { return }
					$updateBranch = [string](& $getUpdateBranchSelection)
					$includePrerelease = if ($chkIncludePrereleaseUpdates) { [bool]$chkIncludePrereleaseUpdates.IsChecked } else { $false }
					$checkResult = Invoke-BaselineUpdateCheck -CurrentVersion $currentVersionText -UpdateBranch $updateBranch -IncludePrerelease:$includePrerelease
					if ($checkResult)
					{
						$settingsUpdateState.LastCheckedUtc = $checkResult.LastCheckedUtc
						$settingsUpdateState.Status = [string]$checkResult.Status
						$settingsUpdateState.LatestVersion = [string]$checkResult.LatestVersion
						$settingsUpdateState.Message = [string]$checkResult.Message
					}
				}
				catch
				{
					$settingsUpdateState.Status = 'Failed'
					$settingsUpdateState.Message = [string]$_.Exception.Message
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.CheckNow'
				}
				finally
				{
					$btnSettingsCheckNow.Content = $originalContent
					$btnSettingsCheckNow.IsEnabled = $true
					& $refreshUpdateDisplay
				}
			}.GetNewClosure())
		}

		$defaultLogDirectory = if ($Current.ContainsKey('DefaultLogFileDirectory') -and -not [string]::IsNullOrWhiteSpace([string]$Current.DefaultLogFileDirectory))
		{
			[string]$Current.DefaultLogFileDirectory
		}
		elseif (Get-Command -Name 'Get-BaselineLogDirectory' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[string](Get-BaselineLogDirectory)
		}
		else
		{
			[System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'Baseline', 'UserState', 'Logs')
		}
