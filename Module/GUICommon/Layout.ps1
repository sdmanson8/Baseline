# Centralized GUI layout constants -- keeps magic numbers in one place for consistency.
$Script:GuiLayout = @{
	# Font sizes (px)
	FontSizeTitle         = 16
	FontSizeHeading       = 18
	FontSizeSection       = 14
	FontSizeBody          = 13
	FontSizeSubheading    = 12
	FontSizeLabel         = 11
	FontSizeSmall         = 10
	FontSizeTiny          = 9

	# Main window dimensions (px)
	WindowMinWidth        = 940
	WindowMinHeight       = 660

	# Dialog dimensions (px)
	DialogDefaultWidth    = 440
	DialogLargeWidth      = 760
	DialogLargeHeight     = 620
	DialogLargeMinWidth   = 680
	DialogLargeMinHeight  = 520
	HelpDialogWidth       = 580
	HelpDialogHeight      = 620
	HelpDialogMinWidth    = 420
	HelpDialogMinHeight   = 400
	LogDialogWidth        = 780
	LogDialogHeight       = 640
	LogDialogMinWidth     = 500
	LogDialogMinHeight    = 300

	# Button dimensions (px)
	ButtonMinWidth        = 112
	ButtonHeight          = 34
	ButtonLargeHeight     = 40
	ButtonAbortMinWidth   = 104

	# Progress section (px)
	ProgressBarHeight     = 18
	ProgressBarMinWidth   = 200
	ProgressColumnWidth   = 124
	PopupProgressBarHeight = 4
	PopupProgressBarMinWidth = 120

	# Card layout (px)
	CardCornerRadius      = 8
	CardMinWidth          = 150
	PillCornerRadius      = 999
	BorderRadiusSmall     = 6
	BorderRadiusLarge     = 10

	# Component dimensions (px)
	ComboBoxMinWidth      = 220
	ComboBoxCompareWidth  = 160
	ComboBoxCompareHeight = 28
	TooltipMaxWidth       = 320
	CheckBoxMinHeight     = 24
	ScrollBarWidth        = 6
	PanelHorizontalPad    = 24

	# Timing (ms)
	SearchRefreshDelayMs  = 300

	# Shadow effect
	ShadowDirection       = 270

	# Line heights (px)
	DialogLineHeight      = 20
}
# Legacy alias kept for any external references
$Script:GuiDialogDefaultWidth = $Script:GuiLayout.DialogDefaultWidth

<#
    .SYNOPSIS
#>
function Get-GuiLayout
{
	return [hashtable]$Script:GuiLayout.Clone()
}

<#
    .SYNOPSIS
#>
function Get-GuiCommonSafeFontSize
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[double]$Default = 12,

		[object]$Layout = $Script:GuiLayout
	)

	$resolvedDefault = if (
		$Default -gt 0 -and
		-not [double]::IsNaN($Default) -and
		-not [double]::IsInfinity($Default)
	)
	{
		$Default
	}
	else
	{
		12
	}

	$value = $null
	if ($Layout -is [System.Collections.IDictionary])
	{
		if ($Layout.Contains($Key))
		{
			$value = $Layout[$Key]
		}
	}
	elseif ($Layout -and $Layout.PSObject -and $Layout.PSObject.Properties[$Key])
	{
		$value = $Layout.$Key
	}

	$candidate = 0.0
	if (
		$null -ne $value -and
		[double]::TryParse([string]$value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$candidate) -and
		$candidate -gt 0 -and
		-not [double]::IsNaN($candidate) -and
		-not [double]::IsInfinity($candidate)
	)
	{
		return $candidate
	}

	$displayValue = if ($null -eq $value) { '<null>' } else { [string]$value }
	$warningKey = '{0}={1}' -f $Key, $displayValue
	if (
		$Script:GuiFontSizeWarnings -and
		(Test-GuiCommonUniqueAdd -HashSet $Script:GuiFontSizeWarnings -SyncRoot $Script:GuiFontSizeWarningsSyncRoot -Value $warningKey)
	)
	{
		Write-GuiCommonWarning ("Invalid GUI font size for '{0}' (value '{1}'). Using fallback {2}." -f $Key, $displayValue, $resolvedDefault)
	}

	return $resolvedDefault
}
