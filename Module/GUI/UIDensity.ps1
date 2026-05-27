# GUI density preferences and layout tokens.

function Normalize-BaselineUiDensity
{
	param ([string]$Density)

	$raw = if ([string]::IsNullOrWhiteSpace($Density)) { 'Comfort' } else { [string]$Density }
	switch -Regex ($raw.Trim())
	{
		'^(Comfort|Comfortable)$' { return 'Comfort' }
		'^Compact$' { return 'Compact' }
		'^(High|HighDensity|High Density)$' { return 'High' }
		default { return 'Comfort' }
	}
}

function Get-BaselineUiDensity
{
	$stored = if (-not [string]::IsNullOrWhiteSpace([string]$Script:UIDensity))
	{
		[string]$Script:UIDensity
	}
	elseif (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
	{
		[string](Get-BaselineUserPreference -Key 'UIDensity' -Default 'Comfort')
	}
	else
	{
		'Comfort'
	}

	$Script:UIDensity = Normalize-BaselineUiDensity -Density $stored
	return $Script:UIDensity
}

function Get-BaselineUiDensityTokens
{
	param ([string]$Density = (Get-BaselineUiDensity))

	$normalized = Normalize-BaselineUiDensity -Density $Density
	switch ($normalized)
	{
		'Compact'
		{
			return @{
				Density          = 'Compact'
				RowCardMargin    = [System.Windows.Thickness]::new(6, 2, 6, 4)
				RowCardPadding   = [System.Windows.Thickness]::new(10, 7, 10, 7)
				CheckBoxRight    = [System.Windows.Thickness]::new(0, 0, 8, 0)
				StatusRow        = [System.Windows.Thickness]::new(24, 0, 0, 0)
				BadgeSpacing     = [System.Windows.Thickness]::new(4, 0, 0, 0)
				DescIndent       = [System.Windows.Thickness]::new(24, 1, 6, 0)
				MetaIndent       = [System.Windows.Thickness]::new(24, 5, 0, 0)
				BlastIndent      = [System.Windows.Thickness]::new(24, 3, 6, 0)
				WhyIndent        = [System.Windows.Thickness]::new(24, 2, 0, 0)
				DescFlush        = [System.Windows.Thickness]::new(0, 1, 0, 0)
				MetaFlush        = [System.Windows.Thickness]::new(0, 5, 0, 0)
				BlastFlush       = [System.Windows.Thickness]::new(0, 3, 0, 0)
				WhyFlush         = [System.Windows.Thickness]::new(0, 2, 0, 0)
				NameFontSize     = 11.5
				LabelFontSize    = 10.5
				DetailFontSize   = 9.75
				NameLineHeight   = 15
				LabelLineHeight  = 14
				DetailLineHeight = 13
				RowIconSize      = 14
			}
		}
		'High'
		{
			return @{
				Density          = 'High'
				RowCardMargin    = [System.Windows.Thickness]::new(4, 1, 4, 2)
				RowCardPadding   = [System.Windows.Thickness]::new(7, 4, 7, 4)
				CheckBoxRight    = [System.Windows.Thickness]::new(0, 0, 6, 0)
				StatusRow        = [System.Windows.Thickness]::new(20, 0, 0, 0)
				BadgeSpacing     = [System.Windows.Thickness]::new(3, 0, 0, 0)
				DescIndent       = [System.Windows.Thickness]::new(20, 0, 4, 0)
				MetaIndent       = [System.Windows.Thickness]::new(20, 3, 0, 0)
				BlastIndent      = [System.Windows.Thickness]::new(20, 2, 4, 0)
				WhyIndent        = [System.Windows.Thickness]::new(20, 1, 0, 0)
				DescFlush        = [System.Windows.Thickness]::new(0, 0, 0, 0)
				MetaFlush        = [System.Windows.Thickness]::new(0, 3, 0, 0)
				BlastFlush       = [System.Windows.Thickness]::new(0, 2, 0, 0)
				WhyFlush         = [System.Windows.Thickness]::new(0, 1, 0, 0)
				NameFontSize     = 11
				LabelFontSize    = 10
				DetailFontSize   = 9
				NameLineHeight   = 13
				LabelLineHeight  = 12
				DetailLineHeight = 11
				RowIconSize      = 13
			}
		}
		default
		{
			return @{
				Density          = 'Comfort'
				RowCardMargin    = [System.Windows.Thickness]::new(8, 5, 8, 7)
				RowCardPadding   = [System.Windows.Thickness]::new(16, 12, 16, 12)
				CheckBoxRight    = [System.Windows.Thickness]::new(0, 0, 12, 0)
				StatusRow        = [System.Windows.Thickness]::new(30, 2, 0, 0)
				BadgeSpacing     = [System.Windows.Thickness]::new(6, 0, 0, 0)
				DescIndent       = [System.Windows.Thickness]::new(30, 4, 8, 0)
				MetaIndent       = [System.Windows.Thickness]::new(30, 8, 0, 0)
				BlastIndent      = [System.Windows.Thickness]::new(30, 6, 8, 0)
				WhyIndent        = [System.Windows.Thickness]::new(30, 5, 0, 0)
				DescFlush        = [System.Windows.Thickness]::new(0, 4, 0, 0)
				MetaFlush        = [System.Windows.Thickness]::new(0, 8, 0, 0)
				BlastFlush       = [System.Windows.Thickness]::new(0, 6, 0, 0)
				WhyFlush         = [System.Windows.Thickness]::new(0, 5, 0, 0)
				NameFontSize     = 12
				LabelFontSize    = 11
				DetailFontSize   = 10
				NameLineHeight   = 17
				LabelLineHeight  = 16
				DetailLineHeight = 15
				RowIconSize      = 16
			}
		}
	}
}

function Set-BaselineUiDensity
{
	param ([string]$Density)

	$normalized = Normalize-BaselineUiDensity -Density $Density
	if ([string]$Script:UIDensity -eq $normalized) { return }

	$Script:UIDensity = $normalized
	if (Get-Command -Name 'Set-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-BaselineUserPreference -Key 'UIDensity' -Value $normalized
	}

	$Script:RowContextShared = $null
	$Script:RowContextSharedTheme = $null
	$Script:RowContextSharedDensity = $null
	if (Get-Command -Name 'Set-TweakRowFactoryDensityTokens' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-TweakRowFactoryDensityTokens
	}
	if (Get-Command -Name 'Clear-TabContentCache' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Clear-TabContentCache
	}
	if (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-CurrentTabContent -SkipIdlePrebuild
	}
}
