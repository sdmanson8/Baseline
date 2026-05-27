$Script:GuiState = New-ObservableState -Dispatcher $Form.Dispatcher -InitialValues @{
		StatusText       = ''
		StatusForeground = (Get-GuiCurrentTheme).TextSecondary
		RunInProgress    = $false
		ProgressCompleted = 0
		ProgressTotal    = 0
		ProgressAction   = ''
		RiskFilter           = $Script:RiskFilter
		CategoryFilter       = $Script:CategoryFilter
		SelectedOnlyFilter   = $Script:SelectedOnlyFilter
		HighRiskOnlyFilter   = $Script:HighRiskOnlyFilter
		RestorableOnlyFilter = $Script:RestorableOnlyFilter
		GamingOnlyFilter     = $Script:GamingOnlyFilter
	}
