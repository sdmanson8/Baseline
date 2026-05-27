$updateLanguageButtonText = {
			if (-not $txtSettingsLanguageDisplay) { return }
			$currentCode = [string]$settingsLanguageState.Code
			if ($currentCode -eq 'en') { $currentCode = 'en-US' }
			$matched = $languageEntries | Where-Object { [string]$_.Code -eq $currentCode } | Select-Object -First 1
			if ($matched)
			{
				$txtSettingsLanguageDisplay.Text = (& $formatLanguageDisplay $matched)
			}
			else
			{
				$txtSettingsLanguageDisplay.Text = $currentCode
			}
		}.GetNewClosure()

		$languageClickHandler = {
			param ($btnSender, $btnArgs)
			$null = $btnArgs
			$selectedCode = [string]$btnSender.Tag
			if ([string]::IsNullOrWhiteSpace($selectedCode)) { return }
			$settingsLanguageState.Code = $selectedCode
			& $updateLanguageButtonText
			if ($settingsLanguagePopup) { $settingsLanguagePopup.IsOpen = $false }
			if ($btnSettingsLanguage) { $btnSettingsLanguage.IsChecked = $false }
			if ($txtSettingsLanguageSearch) { $txtSettingsLanguageSearch.Text = '' }
			if ($languageUiState.Render) { & $languageUiState.Render '' }
		}.GetNewClosure()

		$renderLanguageList = {
			param ([string]$FilterText = '')
			if (-not $settingsLanguageListPanel) { return }
			$settingsLanguageListPanel.Children.Clear()

			$normalizedFilter = if ([string]::IsNullOrWhiteSpace([string]$FilterText)) { '' } else { ([string]$FilterText).Trim().ToLowerInvariant() }
			$filtered = if ([string]::IsNullOrWhiteSpace($normalizedFilter))
			{
				@($languageEntries)
			}
			else
			{
				@($languageEntries | Where-Object {
					$searchIndex = [string]$_.SearchIndex
					$searchIndex.IndexOf($normalizedFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
				})
			}

			if ($filtered.Count -eq 0)
			{
				$emptyState = [System.Windows.Controls.TextBlock]::new()
				$emptyState.Text = (& $getUxLocalizedStringCapture -Key 'GuiLanguageSearchNoResults' -Fallback 'No languages found.')
				$emptyState.Margin = [System.Windows.Thickness]::new(10, 8, 10, 6)
				$emptyState.FontSize = 12
				$emptyState.Foreground = $textMutedBrush
				[void]$settingsLanguageListPanel.Children.Add($emptyState)
				return
			}

			$templateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="{x:Type Button}">
	<Border x:Name="Bd" CornerRadius="4" Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
		<ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
	</Border>
	<ControlTemplate.Triggers>
		<Trigger Property="IsMouseOver" Value="True">
			<Setter TargetName="Bd" Property="Background" Value="$hoverColor"/>
		</Trigger>
	</ControlTemplate.Triggers>
</ControlTemplate>
"@
			$langTemplate = [Windows.Markup.XamlReader]::Parse($templateXaml)

			$currentCode = [string]$settingsLanguageState.Code
			foreach ($entry in $filtered)
			{
				$isActive = [string]$entry.Code -eq $currentCode
				$langBtn = [System.Windows.Controls.Button]::new()
				$langBtn.Tag = [string]$entry.Code
				$langBtn.Cursor = [System.Windows.Input.Cursors]::Hand
				$langBtn.HorizontalContentAlignment = 'Left'
				$langBtn.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
				$langBtn.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
				$langBtn.BorderThickness = [System.Windows.Thickness]::new(0)
				$langBtn.Background = if ($isActive) { $activeBrush } else { [System.Windows.Media.Brushes]::Transparent }
				$langBtn.Foreground = $textPrimaryBrush
				$langBtn.FocusVisualStyle = $null
				$langBtn.ClickMode = [System.Windows.Controls.ClickMode]::Press
				$langBtn.Template = $langTemplate

				$langStack = [System.Windows.Controls.StackPanel]::new()
				$langStack.Orientation = 'Vertical'

				$nativeBlock = [System.Windows.Controls.TextBlock]::new()
				$nativeBlock.Text = [string]$entry.NativeName
				$nativeBlock.FontSize = 12
				$nativeBlock.Foreground = if ($isActive) { $accentBrush } else { $textPrimaryBrush }
				$nativeBlock.FontWeight = if ($isActive) { [System.Windows.FontWeights]::Bold } else { [System.Windows.FontWeights]::Normal }
				[void]$langStack.Children.Add($nativeBlock)

				if ([string]$entry.NativeName -ne [string]$entry.EnglishName)
				{
					$engBlock = [System.Windows.Controls.TextBlock]::new()
					$engBlock.Text = [string]$entry.EnglishName
					$engBlock.FontSize = 10
					$engBlock.Foreground = $textMutedBrush
					[void]$langStack.Children.Add($engBlock)
				}

				$langBtn.Content = $langStack
				$langBtn.Add_Click($languageClickHandler)
				[void]$settingsLanguageListPanel.Children.Add($langBtn)
			}
		}.GetNewClosure()
