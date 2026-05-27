<#
    .SYNOPSIS
#>
function Test-GuiCommonUniqueAdd
{
	param(
		[Parameter(Mandatory = $true)]
		[object]$HashSet,

		[Parameter(Mandatory = $true)]
		[object]$SyncRoot,

		[Parameter(Mandatory = $true)]
		[string]$Value
	)

	if ([string]::IsNullOrWhiteSpace($Value))
	{
		return $false
	}

	if ($null -eq $HashSet)
	{
		return $false
	}

	$lockTaken = $false
	try
	{
		[System.Threading.Monitor]::Enter($SyncRoot, [ref]$lockTaken)
		return $HashSet.Add($Value)
	}
	finally
	{
		if ($lockTaken)
		{
			[System.Threading.Monitor]::Exit($SyncRoot)
		}
	}
}

<#
    .SYNOPSIS
#>
function Get-GuiBooleanValue
{
	param(
		[Parameter(Mandatory = $false)]
		[object]$Value,

		[bool]$Default = $false,

		[string]$Context = 'GUI'
	)

	if ($null -eq $Value)
	{
		return $Default
	}

	if ($Value -is [bool])
	{
		return [bool]$Value
	}

	if ($Value -is [System.Management.Automation.SwitchParameter])
	{
		return [bool]$Value
	}

	$text = [string]$Value
	if ([string]::IsNullOrWhiteSpace($text))
	{
		return $Default
	}

	$trimmed = $text.Trim()
	$parsedBool = $false
	if ([bool]::TryParse($trimmed, [ref]$parsedBool))
	{
		return $parsedBool
	}

	$parsedNumber = 0.0
	if ([double]::TryParse($trimmed, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedNumber))
	{
		return ($parsedNumber -ne 0)
	}

	switch ($trimmed.ToLowerInvariant())
	{
		'yes' { return $true }
		'on' { return $true }
		'enabled' { return $true }
		'no' { return $false }
		'off' { return $false }
		'disabled' { return $false }
	}

	Write-GuiCommonWarning ("Invalid boolean value '{0}'{1}. Using fallback {2}." -f $trimmed, $(if ([string]::IsNullOrWhiteSpace($Context)) { '' } else { " for $Context" }), $Default)
	return $Default
}

<#
    .SYNOPSIS
#>
function Get-GuiDialogDismissResult
{
	param(
		[string[]]$Buttons = @()
	)

	if ($Buttons -contains 'Cancel')
	{
		return 'Cancel'
	}

	if ($Buttons -contains 'Close')
	{
		return 'Close'
	}

	if ($Buttons.Count -eq 1)
	{
		return $Buttons[0]
	}

	return $null
}

<#
    .SYNOPSIS
#>
function Write-GuiCommonWarning
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	$shouldLog = $true
	if ($Script:GuiCommonWarnings)
	{
		try
		{
			$shouldLog = Test-GuiCommonUniqueAdd -HashSet $Script:GuiCommonWarnings -SyncRoot $Script:GuiCommonWarningsSyncRoot -Value $Message
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Utilities.Write-GuiCommonWarning:catch153' -Severity Debug }

			$shouldLog = $true
		}
	}

	if ($shouldLog)
	{
		LogWarning $Message
	}
}
