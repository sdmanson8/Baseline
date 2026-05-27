
<#
	    .SYNOPSIS
	#>

	function Get-BaselineScrollBarStyleXaml
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[Parameter(Mandatory)]
			[hashtable]$Theme
		)

		if (Get-Command -Name 'GUICommon\Get-GuiSharedScrollBarStyleXaml' -ErrorAction SilentlyContinue)
		{
			return GUICommon\Get-GuiSharedScrollBarStyleXaml -Theme $Theme
		}

		throw 'Shared GUI scrollbar resources are not available.'
	}

	<#
	    .SYNOPSIS
	#>

	function Set-BaselineReadmeInlineTheme
	{
		param(
			[object]$Inline,
			[System.Windows.Media.Brush]$TextPrimaryBrush,
			[System.Windows.Media.Brush]$CodeBackgroundBrush,
			[System.Windows.Media.Brush]$CodeForegroundBrush,
			[System.Windows.Media.FontFamily]$MonoFont,
			[bool]$WithinCodeBlock = $false
		)

		if (-not $Inline) { return }

		$isCodeInline = (-not $WithinCodeBlock) -and $Inline.PSObject.Properties['Background'] -and ($null -ne $Inline.Background)
		if ($WithinCodeBlock -or $isCodeInline)
		{
			if ($Inline.PSObject.Properties['Background'])
			{
				$Inline.Background = if ($WithinCodeBlock) { [System.Windows.Media.Brushes]::Transparent } else { $CodeBackgroundBrush }
			}
			if ($Inline.PSObject.Properties['Foreground'])
			{
				$Inline.Foreground = $CodeForegroundBrush
			}
			if ($Inline.PSObject.Properties['FontFamily'])
			{
				$Inline.FontFamily = $MonoFont
			}
		}
		elseif ($Inline.PSObject.Properties['Foreground'])
		{
			$Inline.Foreground = $TextPrimaryBrush
		}

		if ($Inline.PSObject.Properties['Inlines'] -and $Inline.Inlines)
		{
			foreach ($childInline in @($Inline.Inlines))
			{
				Set-BaselineReadmeInlineTheme `
					-Inline $childInline `
					-TextPrimaryBrush $TextPrimaryBrush `
					-CodeBackgroundBrush $CodeBackgroundBrush `
					-CodeForegroundBrush $CodeForegroundBrush `
					-MonoFont $MonoFont `
					-WithinCodeBlock:$WithinCodeBlock
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-BaselineReadmeBlockTheme
	{
		param(
			[object]$Block,
			[System.Windows.Media.Brush]$TextPrimaryBrush,
			[System.Windows.Media.Brush]$CodeBackgroundBrush,
			[System.Windows.Media.Brush]$CodeForegroundBrush,
			[System.Windows.Media.Brush]$BorderBrush,
			[System.Windows.Media.FontFamily]$MonoFont
		)

		if (-not $Block) { return }

		$isCodeBlock = ($Block -is [System.Windows.Documents.Paragraph]) -and $Block.PSObject.Properties['Background'] -and ($null -ne $Block.Background)
		if ($isCodeBlock)
		{
			$Block.Background = $CodeBackgroundBrush
			$Block.Foreground = $CodeForegroundBrush
			$Block.FontFamily = $MonoFont
			if ($Block.PSObject.Properties['BorderBrush']) { $Block.BorderBrush = $BorderBrush }
			if ($Block.PSObject.Properties['BorderThickness']) { $Block.BorderThickness = [System.Windows.Thickness]::new(1) }
			if ($Block.PSObject.Properties['Padding']) { $Block.Padding = [System.Windows.Thickness]::new(8) }
		}
		elseif ($Block.PSObject.Properties['Foreground'])
		{
			$Block.Foreground = $TextPrimaryBrush
		}

		if ($Block -is [System.Windows.Documents.Paragraph])
		{
			foreach ($inline in @($Block.Inlines))
			{
				Set-BaselineReadmeInlineTheme `
					-Inline $inline `
					-TextPrimaryBrush $TextPrimaryBrush `
					-CodeBackgroundBrush $CodeBackgroundBrush `
					-CodeForegroundBrush $CodeForegroundBrush `
					-MonoFont $MonoFont `
					-WithinCodeBlock:$isCodeBlock
			}
		}

		if ($Block.PSObject.Properties['Blocks'] -and $Block.Blocks)
		{
			foreach ($childBlock in @($Block.Blocks))
			{
				Set-BaselineReadmeBlockTheme `
					-Block $childBlock `
					-TextPrimaryBrush $TextPrimaryBrush `
					-CodeBackgroundBrush $CodeBackgroundBrush `
					-CodeForegroundBrush $CodeForegroundBrush `
					-BorderBrush $BorderBrush `
					-MonoFont $MonoFont
			}
		}

		if ($Block -is [System.Windows.Documents.List])
		{
			foreach ($listItem in @($Block.ListItems))
			{
				foreach ($childBlock in @($listItem.Blocks))
				{
					Set-BaselineReadmeBlockTheme `
						-Block $childBlock `
						-TextPrimaryBrush $TextPrimaryBrush `
						-CodeBackgroundBrush $CodeBackgroundBrush `
						-CodeForegroundBrush $CodeForegroundBrush `
						-BorderBrush $BorderBrush `
						-MonoFont $MonoFont
				}
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-BaselineReadmeFlowDocumentTheme
	{
		param(
			[System.Windows.Documents.FlowDocument]$Document,
			[hashtable]$ActiveTheme,
			[object]$BrushConverter,
			[double]$ReadmeFontSize
		)

		if (-not $Document -or -not $ActiveTheme -or -not $BrushConverter) { return }

		# Markdig.Wpf resolves its code styles during ToFlowDocument(), so changing
		# resource keys after the document is created is too late. Force the final
		# theme onto the rendered document directly so inline code and fenced blocks
		# stay readable on both refresh and theme changes.
		$textPrimaryBrush = $BrushConverter.ConvertFromString($ActiveTheme.TextPrimary)
		$codeBackgroundBrush = $BrushConverter.ConvertFromString($ActiveTheme.HeaderBg)
		$codeForegroundBrush = $BrushConverter.ConvertFromString($ActiveTheme.TextPrimary)
		$borderBrush = $BrushConverter.ConvertFromString($ActiveTheme.BorderColor)
		$monoFont = [System.Windows.Media.FontFamily]::new('Consolas, Courier New')
		$uiFont = [System.Windows.Media.FontFamily]::new('Segoe UI')

		$Document.Background = [System.Windows.Media.Brushes]::Transparent
		$Document.Foreground = $textPrimaryBrush
		$Document.PagePadding = [System.Windows.Thickness]::new(0)
		$Document.FontFamily = $uiFont
		$Document.FontSize = [double]$ReadmeFontSize

		foreach ($topLevelBlock in @($Document.Blocks))
		{
			Set-BaselineReadmeBlockTheme `
				-Block $topLevelBlock `
				-TextPrimaryBrush $textPrimaryBrush `
				-CodeBackgroundBrush $codeBackgroundBrush `
				-CodeForegroundBrush $codeForegroundBrush `
				-BorderBrush $borderBrush `
				-MonoFont $monoFont
		}
	}

