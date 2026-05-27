if ($startupRestoreLastSession -and -not $Script:StartupIsFirstRun)
	{
		try
		{
			$startupSessionSnapshot = GUICommon\Read-GuiSessionStateDocument -AppName 'Baseline' -ExpectedSchema 'Baseline.GuiSettings'
			if ($startupSessionSnapshot)
			{
				$Script:StartupSessionSnapshot = $startupSessionSnapshot
				$Script:StartupRestoreSessionPending = $true
				$desiredTab = if (Test-GuiObjectField -Object $startupSessionSnapshot -FieldName 'CurrentPrimaryTab') { [string]$startupSessionSnapshot.CurrentPrimaryTab } else { $null }
				$desiredLast = if (Test-GuiObjectField -Object $startupSessionSnapshot -FieldName 'LastStandardPrimaryTab') { [string]$startupSessionSnapshot.LastStandardPrimaryTab } else { $null }
				if ((Test-GuiObjectField -Object $startupSessionSnapshot -FieldName 'UIDensity') -and -not [string]::IsNullOrWhiteSpace([string]$startupSessionSnapshot.UIDensity))
				{
					$Script:UIDensity = if (Get-Command -Name 'Normalize-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue) { Normalize-BaselineUiDensity -Density ([string]$startupSessionSnapshot.UIDensity) } else { [string]$startupSessionSnapshot.UIDensity }
				}
				if (-not [string]::IsNullOrWhiteSpace($desiredTab) -and $desiredTab -ne $Script:SearchResultsTabTag)
				{
					$Script:StartupHydratePrimaryTab = $desiredTab
				}
				elseif (-not [string]::IsNullOrWhiteSpace($desiredLast))
				{
					$Script:StartupHydratePrimaryTab = $desiredLast
				}
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveStartupSession.ReadAppDataSession'
			$Script:StartupSessionSnapshot = $null
			$Script:StartupRestoreSessionPending = $false
			$Script:StartupHydratePrimaryTab = 'Initial Setup'
		}
	}
