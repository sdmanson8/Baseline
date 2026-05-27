	$refreshVisibleContent = {
		if ((& $Script:TestGuiRunInProgressScript) -or $Script:FilterUiUpdating) { return }
		if ($Script:DeploymentMediaModeActive) { return }
		# Bump the filter generation so stale tab caches are evicted on next visit
		# without the cost of clearing and rebuilding all tabs up front.
		$Script:FilterGeneration++
		# When search text is active, use the search sentinel tag so category
		# filters reflect cross-tab results.  Fall back to the selected real tab.
		$hasSearchText = -not [string]::IsNullOrWhiteSpace([string]$Script:SearchText)
		$targetTab = if ($Script:GamingModeActive) {
			'Gaming'
		}
		elseif ($hasSearchText) {
			$Script:SearchResultsTabTag
		}
		elseif ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}
		# Only invalidate the current tab and search results for immediate rebuild.
		# Other tabs carry a stale FilterGeneration and will be evicted lazily.
		if ($targetTab) { & $Script:ClearTabContentCacheScript $targetTab }
		if ($Script:SearchResultsTabTag -and $targetTab -ne $Script:SearchResultsTabTag)
		{
			& $Script:ClearTabContentCacheScript $Script:SearchResultsTabTag
		}
		& $Script:UpdateCategoryFilterListScript -PrimaryTab $targetTab
		& $Script:UpdateSearchResultsTabStateScript
	}

	# Search-only refresh: keeps regular tab caches so returning from search is instant.
	# Only the search-results tab entry is cleared; regular tabs were built without a
	# search filter and remain correct once search is cleared.
	$refreshSearchContent = {
		if ((& $Script:TestGuiRunInProgressScript) -or $Script:FilterUiUpdating) { return }
		if ($Script:DeploymentMediaModeActive) { return }
		if ($Script:AppsModeActive)
		{
			if (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Build-AppsViewCards
			}
			return
		}
		# Only evict search-related category filter cache entries; regular tab
		# entries remain valid since the search query doesn't affect their content.
		if ($Script:CategoryFilterListCache -and $Script:SearchResultsTabTag)
		{
			$staleKeys = @($Script:CategoryFilterListCache.Keys | Where-Object { [string]$_ -and ([string]$_).StartsWith("$($Script:SearchResultsTabTag)|") })
			foreach ($sk in $staleKeys) { [void]$Script:CategoryFilterListCache.Remove($sk) }
		}
		if ($Script:LastCategoryFilterPopulateKey -and $Script:SearchResultsTabTag -and $Script:LastCategoryFilterPopulateKey.StartsWith("$($Script:SearchResultsTabTag)|"))
		{
			$Script:LastCategoryFilterPopulateKey = $null
		}
		$Script:LastCategoryFilterSignature = $null
		if ($Script:TabContentCache -and $Script:SearchResultsTabTag -and $Script:TabContentCache.ContainsKey($Script:SearchResultsTabTag))
		{
			[void]$Script:TabContentCache.Remove($Script:SearchResultsTabTag)
		}
		# When search text is active, use the search sentinel tag so category
		# filters reflect cross-tab results (inline banner replaces the old
		# Search Results tab).  Fall back to the selected real tab otherwise.
		$hasSearchText = -not [string]::IsNullOrWhiteSpace([string]$Script:SearchText)
		$targetTab = if ($Script:GamingModeActive) {
			'Gaming'
		}
		elseif ($hasSearchText) {
			$Script:SearchResultsTabTag
		}
		elseif ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}
		& $Script:UpdateCategoryFilterListScript -PrimaryTab $targetTab
		& $Script:UpdateSearchResultsTabStateScript
	}
