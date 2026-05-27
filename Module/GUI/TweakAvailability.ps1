# Shared GUI tweak availability helpers.

	<#
	    .SYNOPSIS
	#>

	function Get-GuiTweakAvailability
	{
		param ([object]$Tweak)

		$availability = $null
		if ($null -eq $Tweak)
		{
			return $null
		}

		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('Availability')) { $availability = $Tweak['Availability'] }
		}
		elseif ($Tweak.PSObject -and $Tweak.PSObject.Properties['Availability'])
		{
			$availability = $Tweak.Availability
		}

		return $availability
	}

	<#
	    .SYNOPSIS
	#>

	function Test-GuiTweakAvailableOnCurrentSystem
	{
		param ([object]$Tweak)

		$availability = Get-GuiTweakAvailability -Tweak $Tweak
		$isAvailable = $true
		if ($null -ne $availability)
		{
			if ($availability -is [System.Collections.IDictionary])
			{
				if ($availability.Contains('Available'))
				{
					$isAvailable = [bool]$availability['Available']
				}
			}
			elseif ($availability.PSObject -and $availability.PSObject.Properties['Available'])
			{
				$isAvailable = [bool]$availability.Available
			}
		}

		if (-not $isAvailable)
		{
			return $false
		}

		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('SupportsExecution'))
			{
				return [bool]$Tweak['SupportsExecution']
			}
			return $true
		}

		if ($Tweak.PSObject -and $Tweak.PSObject.Properties['SupportsExecution'])
		{
			return [bool]$Tweak.SupportsExecution
		}

		return $true
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiTweakUnavailableReason
	{
		param ([object]$Tweak)

		$availability = Get-GuiTweakAvailability -Tweak $Tweak
		if ($null -eq $availability)
		{
			return $null
		}

		foreach ($fieldName in @('Reason', 'UnavailableReason', 'Detail'))
		{
			if ($availability -is [System.Collections.IDictionary])
			{
				if ($availability.Contains($fieldName) -and -not [string]::IsNullOrWhiteSpace([string]$availability[$fieldName]))
				{
					return [string]$availability[$fieldName]
				}
			}
			elseif ($availability.PSObject -and $availability.PSObject.Properties[$fieldName] -and -not [string]::IsNullOrWhiteSpace([string]$availability.$fieldName))
			{
				return [string]$availability.$fieldName
			}
		}

		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('SupportsExecutionReason') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak['SupportsExecutionReason']))
			{
				return [string]$Tweak['SupportsExecutionReason']
			}
		}
		elseif ($Tweak.PSObject -and $Tweak.PSObject.Properties['SupportsExecutionReason'] -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.SupportsExecutionReason))
		{
			return [string]$Tweak.SupportsExecutionReason
		}

		return $null
	}
