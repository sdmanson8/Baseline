try
	{
		$Capabilities = Get-WindowsCapability -Online -ErrorAction Stop |
			Where-Object -FilterScript {
				$CapabilityName = $_.Name
				($_.State -eq $State) -and
				(
					(Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $UncheckedCapabilities) -or
					(Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $CheckedCapabilities)
				) -and
				-not (Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $ExcludedCapabilities)
			} |
			Sort-Object -Property DisplayName, Name
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\System\WindowsFeatures\WindowsCapabilities\CapabilityQuery.ps1:15' -Severity Debug }

		Remove-HandledErrorRecord -ErrorRecord $_
		$Capabilities = $null
	}
