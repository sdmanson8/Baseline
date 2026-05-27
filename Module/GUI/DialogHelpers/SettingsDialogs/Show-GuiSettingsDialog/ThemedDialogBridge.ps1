$settingsShowThemedDialog = {
			param(
				[string]$Title,
				[string]$Message,
				[string[]]$Buttons = @('OK'),
				[string]$AccentButton = $null,
				[string]$DestructiveButton = $null
			)

			return (GUICommon\Show-GuiCommonThemedDialog `
				-Theme $theme `
				-ApplyButtonChrome ${function:Set-ButtonChrome} `
				-OwnerWindow $dlg `
				-Title $Title `
				-Message $Message `
				-Buttons $Buttons `
				-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
				-AccentButton $AccentButton `
				-DestructiveButton $DestructiveButton)
		}.GetNewClosure()
