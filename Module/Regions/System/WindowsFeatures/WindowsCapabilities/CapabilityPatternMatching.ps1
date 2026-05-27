function Test-CapabilityPatternMatch
	{
			<#
			    .SYNOPSIS
			    Test whether a Windows capability name matches any supplied pattern.

			    .DESCRIPTION
			    Returns $true when the capability name matches one of the wildcard patterns used by the Windows capability selection workflow.

			    .PARAMETER CapabilityName
			    Capability name to test.

			    .PARAMETER Patterns
			    Wildcard patterns to compare against the capability name.

			    .EXAMPLE
			    Test-CapabilityPatternMatch -CapabilityName 'OpenSSH.Client~~~~0.0.1.0' -Patterns 'OpenSSH*'
			#>
		param
		(
			[Parameter(Mandatory = $true)]
			[string]
			$CapabilityName,

			[string[]]
			$Patterns
		)

		foreach ($Pattern in $Patterns)
		{
			if ($CapabilityName -like $Pattern)
			{
				return $true
			}
		}

		return $false
	}

	<#
	    .SYNOPSIS
	    Gets checkbox clicked.

		#>

	function Update-CapabilitySelectionFromCheckbox
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$CheckBox
		)

		$Capability = $CheckBox.Tag

		if ($CheckBox.IsChecked)
		{
			if ($Capability -and ($Capability -notin $SelectedCapabilities))
			{
				[void]$SelectedCapabilities.Add($Capability)
			}
		}
		else
		{
			if ($Capability)
			{
				[void]$SelectedCapabilities.Remove($Capability)
			}
		}

		if ($SelectedCapabilities.Count -gt 0)
		{
			$Button.IsEnabled = $true
		}
		else
		{
			$Button.IsEnabled = $false
		}
	}

	<#
	    .SYNOPSIS
	    Checks capability seed selected.

		#>

	function Test-CapabilitySeedSelected
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			$Capability
		)

		if ($SelectedCapabilityNamesProvided)
		{
			return [bool](@($SelectedCapabilityNames | Where-Object -FilterScript {$_ -eq $Capability.Name}).Count -gt 0)
		}

		return Test-CapabilityPatternMatch -CapabilityName $Capability.Name -Patterns $CheckedCapabilities
	}
