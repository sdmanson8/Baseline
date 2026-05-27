try
		{
			$Script:CategoryFilter = $desiredCategory
			if ($CmbCategoryFilter)
			{
				if ($Script:CategoryFilterInternalValues -and $Script:CategoryFilterInternalValues.Contains($desiredCategory))
				{
					$found = $Script:CategoryFilterInternalValues.IndexOf($desiredCategory)
					if ($found -ge 0) { $CmbCategoryFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbCategoryFilter.SelectedIndex = $idx
					$Script:CategoryFilter = 'All'
				}
			}
			$Script:AppsFilterUiUpdating = $true
			try
			{
				$Script:AppsCategoryFilter = $desiredAppsCategory
				if ($Script:AppsCategoryTabs -and $Script:AppsCategoryFilterInternalValues -and $Script:AppsCategoryFilterInternalValues.Count -gt 0)
				{
					if ($Script:AppsCategoryFilterInternalValues.Contains($desiredAppsCategory))
					{
						$found = $Script:AppsCategoryFilterInternalValues.IndexOf($desiredAppsCategory)
						if ($found -ge 0) { $Script:AppsCategoryTabs.SelectedIndex = [int]$found }
					}
					else
					{
						$Script:AppsCategoryTabs.SelectedIndex = 0
						$Script:AppsCategoryFilter = if ($Script:AppsCategoryFilterInternalValues.Count -gt 0) { [string]$Script:AppsCategoryFilterInternalValues[0] } else { 'Browsers' }
					}
				}
				$Script:AppsStatusFilter = $desiredAppsStatus
				if ($CmbAppsStatusFilter -and $Script:AppsStatusFilterInternalValues -and $Script:AppsStatusFilterInternalValues.Count -gt 0)
				{
					if ($Script:AppsStatusFilterInternalValues.Contains($desiredAppsStatus))
					{
						$foundStatus = $Script:AppsStatusFilterInternalValues.IndexOf($desiredAppsStatus)
						if ($foundStatus -ge 0) { $CmbAppsStatusFilter.SelectedIndex = [int]$foundStatus }
					}
					else
					{
						$CmbAppsStatusFilter.SelectedIndex = 0
						$Script:AppsStatusFilter = 'All'
					}
				}
			}
			finally
			{
				$Script:AppsFilterUiUpdating = $false
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
