$windowsCapabilitiesThemeCallback = {
		param($Window, $Theme, $UseDarkMode)

		if ($Button)
		{
			try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsCapabilities.ThemeCallback.SetPopupActionButtonStyle' }
		}

		if ($TextBlockSelectAll -and $Window.Foreground)
		{
			$TextBlockSelectAll.Foreground = $Window.Foreground
		}
	}.GetNewClosure()
