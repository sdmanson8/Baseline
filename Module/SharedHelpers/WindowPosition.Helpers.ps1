# WindowPosition helpers for Baseline.
# Persists the GUI window placement (Left/Top/Width/Height/Maximized) across
# sessions and validates that the saved rectangle still falls on a connected
# display before reusing it. Window placement contract:
# the saved rectangle is only restored when at least the minimum visible
# width x height overlaps the working area of any display, otherwise the
# caller falls
# back to the default centred placement.

$BaselineWindowMinVisibleWidth  = 120
$BaselineWindowMinVisibleHeight = 40
$BaselineWindowPrefKeys = @{
	Left       = 'WindowLeft'
	Top        = 'WindowTop'
	Width      = 'WindowWidth'
	Height     = 'WindowHeight'
	Maximized  = 'WindowMaximized'
	Remember   = 'RememberWindowPosition'
}

function Get-BaselineWindowPreferencesPath
{
	[CmdletBinding()]
	param ()

	$stateRoot = [System.Environment]::GetEnvironmentVariable('BASELINE_STATE_ROOT')
	if (-not [string]::IsNullOrWhiteSpace([string]$stateRoot))
	{
		return (Join-Path (Join-Path $stateRoot 'Profiles') 'Baseline-user-prefs.json')
	}

	$localAppData = $env:LOCALAPPDATA
	if ([string]::IsNullOrWhiteSpace([string]$localAppData))
	{
		$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
	}
	if ([string]::IsNullOrWhiteSpace([string]$localAppData))
	{
		$localAppData = [System.IO.Path]::GetTempPath()
	}

	return (Join-Path (Join-Path (Join-Path $localAppData 'Baseline') 'UserState\Profiles') 'Baseline-user-prefs.json')
}

function Read-BaselineWindowPreferenceValues
{
	[CmdletBinding()]
	param ()

	$path = Get-BaselineWindowPreferencesPath
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

	try
	{
		$raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
		$parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
		if (-not $parsed -or -not $parsed.Values) { return $null }
		return $parsed.Values
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowPosition.Helpers.Read-BaselineWindowPreferenceValues:catch61' -Severity Debug }

		return $null
	}
}

function Get-BaselineWindowPreference
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Key,

		[object]$Default = $null
	)

	if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
	{
		return (Get-BaselineUserPreference -Key $Key -Default $Default)
	}

	$values = Read-BaselineWindowPreferenceValues
	if ($values -and $values.PSObject.Properties[$Key])
	{
		return $values.PSObject.Properties[$Key].Value
	}

	return $Default
}

function Set-BaselineWindowPreference
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Key,

		[object]$Value
	)

	if (Get-Command -Name 'Set-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-BaselineUserPreference -Key $Key -Value $Value
		return $true
	}

	$path = Get-BaselineWindowPreferencesPath
	$values = [ordered]@{}
	$existingValues = Read-BaselineWindowPreferenceValues
	if ($existingValues)
	{
		foreach ($property in $existingValues.PSObject.Properties)
		{
			$values[[string]$property.Name] = $property.Value
		}
	}
	$values[$Key] = $Value

	$directory = Split-Path -Path $path -Parent
	if (-not (Test-Path -LiteralPath $directory))
	{
		$null = New-Item -Path $directory -ItemType Directory -Force
	}
	$payload = [pscustomobject]@{
		Schema        = 'Baseline.UserPreferences'
		SchemaVersion = 1
		SavedAtUtc    = ([DateTime]::UtcNow.ToString('o'))
		Values        = $values
	}
	$json = $payload | ConvertTo-Json -Depth 6
	[System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)
	return $true
}

function Get-BaselineDisplayWorkAreas
{
	<#
		.SYNOPSIS
		Returns the work-area rectangles for every connected display.

		.DESCRIPTION
		Prefers System.Windows.Forms.Screen so multi-monitor setups are
		enumerated. Falls back to System.Windows.SystemParameters.WorkArea
		(primary display only) when WinForms is unavailable. Each returned
		object exposes Left/Top/Width/Height in device-independent pixels.
	#>
	[CmdletBinding()]
	param ()

	$result = New-Object System.Collections.Generic.List[object]
	try
	{
		Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
		$screens = [System.Windows.Forms.Screen]::AllScreens
		foreach ($screen in $screens)
		{
			$wa = $screen.WorkingArea
			$result.Add([pscustomobject]@{
				Left   = [double]$wa.X
				Top    = [double]$wa.Y
				Width  = [double]$wa.Width
				Height = [double]$wa.Height
			})
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowPosition.Helpers.Get-BaselineDisplayWorkAreas:catch166' -Severity Debug }

		try
		{
			$wa = [System.Windows.SystemParameters]::WorkArea
			$result.Add([pscustomobject]@{
				Left   = [double]$wa.Left
				Top    = [double]$wa.Top
				Width  = [double]$wa.Width
				Height = [double]$wa.Height
			})
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowPosition.Helpers.Get-BaselineDisplayWorkAreas:catch178' -Severity Debug }

			$result.Add([pscustomobject]@{
				Left   = 0.0
				Top    = 0.0
				Width  = 1024.0
				Height = 768.0
			})
		}
	}
	return ,$result.ToArray()
}

function Test-BaselineWindowRectVisible
{
	<#
		.SYNOPSIS
		Returns $true when at least MinVisibleWidth x MinVisibleHeight of the
		given window rectangle overlaps the work area of any display.

		.PARAMETER Rect
		Hashtable / pscustomobject with Left, Top, Width, Height (doubles).

		.PARAMETER WorkAreas
		Array of display work-area rectangles produced by
		Get-BaselineDisplayWorkAreas.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Rect,

		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[AllowNull()]
		[object[]]$WorkAreas,

		[double]$MinVisibleWidth  = $BaselineWindowMinVisibleWidth,
		[double]$MinVisibleHeight = $BaselineWindowMinVisibleHeight
	)

	if (-not $Rect) { return $false }
	if ($null -eq $WorkAreas -or $WorkAreas.Count -eq 0) { return $false }

	$rLeft   = [double]$Rect.Left
	$rTop    = [double]$Rect.Top
	$rWidth  = [double]$Rect.Width
	$rHeight = [double]$Rect.Height
	if ($rWidth -le 0 -or $rHeight -le 0) { return $false }
	$rRight  = $rLeft + $rWidth
	$rBottom = $rTop  + $rHeight

	foreach ($wa in $WorkAreas)
	{
		if (-not $wa) { continue }
		$wLeft   = [double]$wa.Left
		$wTop    = [double]$wa.Top
		$wRight  = $wLeft + [double]$wa.Width
		$wBottom = $wTop  + [double]$wa.Height

		$ovLeft   = [Math]::Max($rLeft,   $wLeft)
		$ovTop    = [Math]::Max($rTop,    $wTop)
		$ovRight  = [Math]::Min($rRight,  $wRight)
		$ovBottom = [Math]::Min($rBottom, $wBottom)

		$ovWidth  = $ovRight  - $ovLeft
		$ovHeight = $ovBottom - $ovTop
		if ($ovWidth -ge $MinVisibleWidth -and $ovHeight -ge $MinVisibleHeight)
		{
			return $true
		}
	}
	return $false
}

function ConvertTo-BaselineWindowPlacementDouble
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Value,

		[ref]$Result
	)

	if ($null -eq $Value) { return $false }
	if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [long] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal])
	{
		$Result.Value = [double]$Value
		return $true
	}

	$text = [string]$Value
	if ([string]::IsNullOrWhiteSpace($text)) { return $false }

	$parsed = 0.0
	if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed))
	{
		$Result.Value = $parsed
		return $true
	}
	if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$parsed))
	{
		$Result.Value = $parsed
		return $true
	}

	return $false
}

function Get-BaselineSavedWindowPlacement
{
	<#
		.SYNOPSIS
		Reads the persisted window placement from the user-prefs store.
		Returns $null when nothing has been saved or the saved values are
		not numerically usable.
	#>
	[CmdletBinding()]
	param ()

	$left      = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Left
	$top       = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Top
	$width     = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Width
	$height    = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Height
	$maximized = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Maximized -Default $false

	if ($null -eq $width -or $null -eq $height) { return $null }
	if ($null -eq $left -or $null -eq $top) { return $null }

	$dLeft   = 0.0; $dTop = 0.0; $dWidth = 0.0; $dHeight = 0.0
	if (-not (ConvertTo-BaselineWindowPlacementDouble -Value $left -Result ([ref]$dLeft))) { return $null }
	if (-not (ConvertTo-BaselineWindowPlacementDouble -Value $top -Result ([ref]$dTop))) { return $null }
	if (-not (ConvertTo-BaselineWindowPlacementDouble -Value $width -Result ([ref]$dWidth))) { return $null }
	if (-not (ConvertTo-BaselineWindowPlacementDouble -Value $height -Result ([ref]$dHeight))) { return $null }

	if ($dWidth -le 0 -or $dHeight -le 0) { return $null }

	return [pscustomobject]@{
		Left      = $dLeft
		Top       = $dTop
		Width     = $dWidth
		Height    = $dHeight
		Maximized = [bool]$maximized
	}
}

function Save-BaselineWindowPlacement
{
	<#
		.SYNOPSIS
		Persists the supplied window placement to the user-prefs store. A
		no-op when the user has opted out via RememberWindowPosition=$false
		or when the user-prefs API is unavailable. Maximized windows save
		their RestoreBounds rather than the screen-filling rect so the
		next launch comes up at a usable size.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[double]$Left,
		[Parameter(Mandatory)]
		[double]$Top,
		[Parameter(Mandatory)]
		[double]$Width,
		[Parameter(Mandatory)]
		[double]$Height,
		[bool]$Maximized = $false
	)

	$remember = Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Remember -Default $true
	if (-not [bool]$remember) { return $false }

	if ($Width -le 0 -or $Height -le 0) { return $false }

	Set-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Left      -Value ([double]$Left) | Out-Null
	Set-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Top       -Value ([double]$Top) | Out-Null
	Set-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Width     -Value ([double]$Width) | Out-Null
	Set-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Height    -Value ([double]$Height) | Out-Null
	Set-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Maximized -Value ([bool]$Maximized) | Out-Null
	return $true
}

function Get-BaselineWindowRectOverlapArea
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Rect,

		[Parameter(Mandatory)]
		[object]$WorkArea
	)

	$rectLeft = [double]$Rect.Left
	$rectTop = [double]$Rect.Top
	$rectRight = $rectLeft + [double]$Rect.Width
	$rectBottom = $rectTop + [double]$Rect.Height
	$workLeft = [double]$WorkArea.Left
	$workTop = [double]$WorkArea.Top
	$workRight = $workLeft + [double]$WorkArea.Width
	$workBottom = $workTop + [double]$WorkArea.Height

	$overlapWidth = [Math]::Max(0.0, [Math]::Min($rectRight, $workRight) - [Math]::Max($rectLeft, $workLeft))
	$overlapHeight = [Math]::Max(0.0, [Math]::Min($rectBottom, $workBottom) - [Math]::Max($rectTop, $workTop))
	return ($overlapWidth * $overlapHeight)
}

function Resolve-BaselineWindowPlacementWorkArea
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Rect,

		[Parameter(Mandatory)]
		[object[]]$WorkAreas
	)

	$bestWorkArea = $null
	$bestOverlapArea = -1.0

	foreach ($area in $WorkAreas)
	{
		if (-not $area -or [double]$area.Width -le 0 -or [double]$area.Height -le 0) { continue }

		$overlapArea = Get-BaselineWindowRectOverlapArea -Rect $Rect -WorkArea $area
		if ($overlapArea -gt $bestOverlapArea)
		{
			$bestOverlapArea = $overlapArea
			$bestWorkArea = $area
		}
	}

	return $bestWorkArea
}

function ConvertTo-BaselineWindowPlacementBoundsWithinWorkArea
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Rect,

		[AllowNull()]
		[object]$WorkArea
	)

	if (-not $WorkArea -or [double]$WorkArea.Width -le 0 -or [double]$WorkArea.Height -le 0) { return $Rect }

	$workLeft = [double]$WorkArea.Left
	$workTop = [double]$WorkArea.Top
	$workWidth = [double]$WorkArea.Width
	$workHeight = [double]$WorkArea.Height
	$boundedWidth = [Math]::Min([Math]::Max([double]$Rect.Width, 1.0), $workWidth)
	$boundedHeight = [Math]::Min([Math]::Max([double]$Rect.Height, 1.0), $workHeight)
	$maxLeft = $workLeft + $workWidth - $boundedWidth
	$maxTop = $workTop + $workHeight - $boundedHeight

	return [pscustomobject]@{
		Left   = [Math]::Min([Math]::Max([double]$Rect.Left, $workLeft), $maxLeft)
		Top    = [Math]::Min([Math]::Max([double]$Rect.Top, $workTop), $maxTop)
		Width  = $boundedWidth
		Height = $boundedHeight
	}
}

function Resolve-BaselineWindowPlacement
{
	<#
		.SYNOPSIS
		Returns the window placement to apply at startup. Prefers the
		persisted placement when it is still visible on a connected
		display; otherwise returns the supplied default rectangle.

		.PARAMETER DefaultRect
		The fallback rectangle (Left/Top/Width/Height) computed from the
		current display's work area. Used when bounds-validation rejects
		the saved rect or when no rect has been saved.

		.PARAMETER WorkAreas
		Display work areas as produced by Get-BaselineDisplayWorkAreas. If
		omitted, queried at call time.

		.OUTPUTS
		[pscustomobject] with Left/Top/Width/Height/Maximized/Source where
		Source is one of 'saved', 'default-no-saved', 'default-off-screen',
		'default-disabled'.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$DefaultRect,

		[object[]]$WorkAreas,

		[double]$MinVisibleWidth  = $BaselineWindowMinVisibleWidth,
		[double]$MinVisibleHeight = $BaselineWindowMinVisibleHeight
	)

	$remember = $true
	$remember = [bool](Get-BaselineWindowPreference -Key $BaselineWindowPrefKeys.Remember -Default $true)

	$default = [pscustomobject]@{
		Left      = [double]$DefaultRect.Left
		Top       = [double]$DefaultRect.Top
		Width     = [double]$DefaultRect.Width
		Height    = [double]$DefaultRect.Height
		Maximized = $false
		Source    = 'default-disabled'
	}

	if (-not $remember) { return $default }

	$saved = Get-BaselineSavedWindowPlacement
	if (-not $saved)
	{
		$default.Source = 'default-no-saved'
		return $default
	}

	if (-not $WorkAreas) { $WorkAreas = Get-BaselineDisplayWorkAreas }

	$visible = Test-BaselineWindowRectVisible -Rect $saved -WorkAreas $WorkAreas `
		-MinVisibleWidth $MinVisibleWidth -MinVisibleHeight $MinVisibleHeight
	if (-not $visible)
	{
		$default.Source = 'default-off-screen'
		return $default
	}

	$savedMaximized = [bool]$saved.Maximized
	$targetWorkArea = Resolve-BaselineWindowPlacementWorkArea -Rect $saved -WorkAreas $WorkAreas
	$saved = ConvertTo-BaselineWindowPlacementBoundsWithinWorkArea -Rect $saved -WorkArea $targetWorkArea

	return [pscustomobject]@{
		Left      = $saved.Left
		Top       = $saved.Top
		Width     = $saved.Width
		Height    = $saved.Height
		Maximized = $savedMaximized
		Source    = 'saved'
	}
}

