# Rollback checkpoint: the completion body below was the tail of Build-AppsViewCards.
function Complete-AppsViewCardsBuild {
    param([hashtable]$Context)
    foreach ($entry in $Context.Values.GetEnumerator()) { Set-Variable -Name $entry.Key -Value $entry.Value -Scope Local }


	if (-not $cacheReady)
	{
		if ($Script:TxtAppsProgressText)
		{
			$Script:TxtAppsProgressText.Text = $cacheRefreshPrompt
		}
		Update-AppsSelectionSummary
		return
	}

	if ($Script:TxtAppsProgressText)
	{
		$filterActive = ($Script:AppsCategoryFilter -and $Script:AppsCategoryFilter -ne 'All') -or ($activeStatusFilter -and $activeStatusFilter -ne 'All')
		$summaryText = if ($filterActive)
		{
			if ($updateAvailableCount -gt 0)
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryFilteredWithUpdates' -Fallback 'Installed: {0}/{1} | Updates available: {2} | Showing: {3}/{1}'), $installedCount, $allCatalog.Count, $updateAvailableCount, $catalog.Count)
			}
			else
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryFiltered' -Fallback 'Installed: {0}/{1} | Showing: {2}/{1}'), $installedCount, $allCatalog.Count, $catalog.Count)
			}
		}
		else
		{
			if ($updateAvailableCount -gt 0)
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryAllWithUpdates' -Fallback 'Installed: {0}/{1} | Updates available: {2}'), $installedCount, $allCatalog.Count, $updateAvailableCount)
			}
			else
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryAll' -Fallback 'Installed: {0}/{1}'), $installedCount, $allCatalog.Count)
			}
		}
		$Script:TxtAppsProgressText.Text = $summaryText
	}
	$Script:AppsViewBuildSignature = $renderSignature
	Update-AppsSelectionSummary

}

function Invoke-AppsViewCardsBuildStep {
    param([hashtable]$Context)
    if (-not [object]::ReferenceEquals($Script:AppsCardBuildContext, $Context)) { return }
    if (-not [object]::ReferenceEquals($Script:AppsWrapPanel, $Context.Panel)) { return }
    try {
        foreach ($entry in $Context.Values.GetEnumerator()) { Set-Variable -Name $entry.Key -Value $entry.Value -Scope Local }
        $sortedCatalog = @($Context.Catalog[$Context.Position])
        . (Join-Path $PSScriptRoot 'Build-AppsViewCards/Build-AppsViewCards.ps1')
        $Context.Values.installedCount = $installedCount
        $Context.Values.updateAvailableCount = $updateAvailableCount
        $Context.Position++
        if ($Context.Position -lt $Context.Catalog.Count) {
            $null = $Context.Panel.Dispatcher.BeginInvoke($Context.Action, [System.Windows.Threading.DispatcherPriority]::Background)
        }
        else {
            Complete-AppsViewCardsBuild -Context $Context
            $Script:AppsCardBuildContext = $null
            Stop-GuiPerfScope -Scope $Context.Perf
        }
    }
    catch {
        $Script:AppsCardBuildContext = $null
        Stop-GuiPerfScope -Scope $Context.Perf -ExtraNote 'failed'
        Write-GuiRuntimeWarning -Context 'Apps.CardBuild' -Message $_.Exception.Message
    }
}