# Execution summary dialog helpers for Baseline UI.

<#
    .SYNOPSIS
#>

function Show-ExecutionSummaryDialog
{
	param(
		[object[]]$Results,
		[string]$Title = 'Execution Summary',
		[string]$SummaryText,
		[string]$LogPath,
		[object[]]$SummaryCards = @(),
		[string[]]$Buttons = @('Close')
	)

	$dialogStrings = @{}
	if (Get-Command -Name 'Get-UxExecutionSummaryDialogStrings' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$dialogStrings = Get-UxExecutionSummaryDialogStrings
	}

	return (GUICommon\Show-GuiCommonExecutionSummaryDialog `
		-Theme $Script:CurrentTheme `
		-ApplyButtonChrome ${function:Set-ButtonChrome} `
		-OwnerWindow $Form `
		-Results $Results `
		-Title $Title `
		-SummaryText $SummaryText `
		-LogPath $LogPath `
		-SummaryCards $SummaryCards `
		-Buttons $Buttons `
		-Strings $dialogStrings `
		-UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
}
