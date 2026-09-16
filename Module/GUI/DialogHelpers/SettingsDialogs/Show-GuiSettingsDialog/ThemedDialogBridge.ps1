$settingsApplyButtonChrome = $Script:SetButtonChromeScript
if ($settingsApplyButtonChrome -isnot [scriptblock])
{
	throw 'Set-ButtonChrome proxy is not initialized.'
}

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
				-ApplyButtonChrome $settingsApplyButtonChrome `
				-OwnerWindow $dlg `
				-Title $Title `
				-Message $Message `
				-Buttons $Buttons `
				-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
				-AccentButton $AccentButton `
				-DestructiveButton $DestructiveButton)
		}.GetNewClosure()
