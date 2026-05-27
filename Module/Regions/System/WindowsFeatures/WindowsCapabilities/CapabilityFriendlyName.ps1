function Get-CapabilityFriendlyName
	{
		param ([string]$Name, [string]$DisplayName)

		if (-not [string]::IsNullOrWhiteSpace($DisplayName))
		{
			return $DisplayName
		}

		# Strip version suffix (e.g. ~~~~0.0.1.0) and match against friendly names
		$baseName = ($Name -replace '~.*$', '').TrimEnd('~')
		foreach ($pattern in $CapabilityFriendlyNames.Keys)
		{
			if ($baseName -like "$pattern*")
			{
				return $CapabilityFriendlyNames[$pattern]
			}
		}

		# Last resort: strip the version suffix and return as-is
		return $baseName
	}
