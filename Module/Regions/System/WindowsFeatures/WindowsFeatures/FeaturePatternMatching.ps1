function Test-FeaturePatternMatch
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]
			$FeatureName,

			[string[]]
			$Patterns
		)

		foreach ($Pattern in $Patterns)
		{
			if ($FeatureName -like $Pattern)
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

	function Update-FeatureSelectionFromCheckbox
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

		$Feature = $CheckBox.Tag

		if ($CheckBox.IsChecked)
		{
			if ($Feature -and ($Feature -notin $SelectedFeatures))
			{
				[void]$SelectedFeatures.Add($Feature)
			}
		}
		else
		{
			if ($Feature)
			{
				[void]$SelectedFeatures.Remove($Feature)
			}
		}
		if ($SelectedFeatures.Count -gt 0)
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
	    Checks feature seed selected.

		#>

	function Test-FeatureSeedSelected
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			$Feature
		)

		if ($SelectedFeatureNamesProvided)
		{
			return [bool](@($SelectedFeatureNames | Where-Object -FilterScript {$_ -eq $Feature.FeatureName}).Count -gt 0)
		}

		return Test-FeaturePatternMatch -FeatureName $Feature.FeatureName -Patterns $CheckedFeatures
	}
