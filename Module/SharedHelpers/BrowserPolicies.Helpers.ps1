# Browser enterprise-policy hardening helpers.
#
# Spec: todo.md "Browser enterprise policies" --
#   Edge:    SmartScreenEnabled, SitePerProcess, SSLVersionMin = tls1.2,
#            PasswordManagerEnabled = 0, AutofillCreditCardEnabled = 0
#   Chrome:  BlockThirdPartyCookies, DnsOverHttpsMode = automatic,
#            SafeBrowsingProtectionLevel = 2, PasswordManagerEnabled = 0,
#            AutofillCreditCardEnabled = 0, AutofillAddressEnabled = 0
#   Firefox: DisableTelemetry, DisableFirefoxStudies,
#            DisableDefaultBrowserAgent, SSLVersionMin = tls1.2,
#            PasswordManagerEnabled = 0, OfferToSaveLogins = 0,
#            OfferToSaveLoginsDefault = 0, AutofillCreditCardEnabled = 0,
#            AutofillAddressEnabled = 0
#   Brave:   Chrome-compatible privacy/password/autofill policies plus
#            Brave-specific rewards/wallet/analytics/search-discovery/AI
#            disables.
#
# Each policy targets the documented HKLM ADMX policy key:
#   * Edge    --> HKLM:\Software\Policies\Microsoft\Edge
#   * Chrome  --> HKLM:\Software\Policies\Google\Chrome
#   * Firefox --> HKLM:\Software\Policies\Mozilla\Firefox
#   * Brave   --> HKLM:\Software\Policies\BraveSoftware\Brave
#
# Back-end helpers only; the Tweaks JSON entry that exposes these browser
# policy toggles in OS Hardening is implemented in a separate slice.

function Get-BaselineBrowserPolicySettings
{
	<#
		.SYNOPSIS
		Returns the canonical per-browser policy catalog Baseline applies.

		.DESCRIPTION
		Each record carries Id, Browser, Path, Name, Type, Value, and
		Description. The Id is browser-qualified (e.g. `Edge:SmartScreenEnabled`)
		so backup keys for Edge and Chrome cannot collide.

		Order is stable across invocations. Firefox uses Mozilla's documented
		Windows GPO registry policy keys instead of a policies.json file so
		the same reversible registry-backup contract applies to every entry.

		.PARAMETER Browser
		One or more browsers to include. Defaults to the complete Baseline
		policy set: Edge, Chrome, Firefox, and Brave.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[ValidateSet('Edge','Chrome','Firefox','Brave')]
		[string[]]$Browser = @('Edge','Chrome','Firefox','Brave')
	)

	$edgeRoot    = 'HKLM:\Software\Policies\Microsoft\Edge'
	$chromeRoot  = 'HKLM:\Software\Policies\Google\Chrome'
	$firefoxRoot = 'HKLM:\Software\Policies\Mozilla\Firefox'
	$braveRoot   = 'HKLM:\Software\Policies\BraveSoftware\Brave'

	$catalog = @{
		Edge = @(
			[pscustomobject]@{ Id='Edge:SmartScreenEnabled';            Browser='Edge'; Path=$edgeRoot; Name='SmartScreenEnabled';           Type='DWord';  Value=1;        Description='Force-enable Microsoft Defender SmartScreen.' }
			[pscustomobject]@{ Id='Edge:SitePerProcess';                Browser='Edge'; Path=$edgeRoot; Name='SitePerProcess';               Type='DWord';  Value=1;        Description='Enforce per-site process isolation (anti-Spectre).' }
			[pscustomobject]@{ Id='Edge:SSLVersionMin';                 Browser='Edge'; Path=$edgeRoot; Name='SSLVersionMin';                Type='String'; Value='tls1.2'; Description='Reject TLS connections older than TLS 1.2.' }
			[pscustomobject]@{ Id='Edge:PasswordManagerEnabled';        Browser='Edge'; Path=$edgeRoot; Name='PasswordManagerEnabled';       Type='DWord';  Value=0;        Description='Disable in-browser password storage (use a dedicated password manager instead).' }
			[pscustomobject]@{ Id='Edge:AutofillCreditCardEnabled';     Browser='Edge'; Path=$edgeRoot; Name='AutofillCreditCardEnabled';    Type='DWord';  Value=0;        Description='Disable credit-card autofill (anti-skimming).' }
		)
		Chrome = @(
			[pscustomobject]@{ Id='Chrome:BlockThirdPartyCookies';      Browser='Chrome'; Path=$chromeRoot; Name='BlockThirdPartyCookies';      Type='DWord';  Value=1;          Description='Block third-party cookies (anti-tracking).' }
			[pscustomobject]@{ Id='Chrome:DnsOverHttpsMode';            Browser='Chrome'; Path=$chromeRoot; Name='DnsOverHttpsMode';            Type='String'; Value='automatic'; Description='Use DoH when the resolver supports it (anti-snooping).' }
			[pscustomobject]@{ Id='Chrome:SafeBrowsingProtectionLevel'; Browser='Chrome'; Path=$chromeRoot; Name='SafeBrowsingProtectionLevel'; Type='DWord';  Value=2;          Description='Enable enhanced Safe Browsing protection.' }
			[pscustomobject]@{ Id='Chrome:PasswordManagerEnabled';      Browser='Chrome'; Path=$chromeRoot; Name='PasswordManagerEnabled';      Type='DWord';  Value=0;          Description='Disable in-browser password storage.' }
			[pscustomobject]@{ Id='Chrome:AutofillCreditCardEnabled';   Browser='Chrome'; Path=$chromeRoot; Name='AutofillCreditCardEnabled';   Type='DWord';  Value=0;          Description='Disable credit-card autofill.' }
			[pscustomobject]@{ Id='Chrome:AutofillAddressEnabled';      Browser='Chrome'; Path=$chromeRoot; Name='AutofillAddressEnabled';      Type='DWord';  Value=0;          Description='Disable address autofill (companion to credit-card autofill).' }
		)
		Firefox = @(
			[pscustomobject]@{ Id='Firefox:DisableTelemetry';            Browser='Firefox'; Path=$firefoxRoot; Name='DisableTelemetry';            Type='DWord';  Value=1;        Description='Disable Firefox telemetry upload.' }
			[pscustomobject]@{ Id='Firefox:DisableFirefoxStudies';       Browser='Firefox'; Path=$firefoxRoot; Name='DisableFirefoxStudies';       Type='DWord';  Value=1;        Description='Disable Firefox Shield studies.' }
			[pscustomobject]@{ Id='Firefox:DisableDefaultBrowserAgent';  Browser='Firefox'; Path=$firefoxRoot; Name='DisableDefaultBrowserAgent';  Type='DWord';  Value=1;        Description='Disable the Firefox default-browser background agent.' }
			[pscustomobject]@{ Id='Firefox:SSLVersionMin';               Browser='Firefox'; Path=$firefoxRoot; Name='SSLVersionMin';               Type='String'; Value='tls1.2'; Description='Reject TLS connections older than TLS 1.2.' }
			[pscustomobject]@{ Id='Firefox:PasswordManagerEnabled';      Browser='Firefox'; Path=$firefoxRoot; Name='PasswordManagerEnabled';      Type='DWord';  Value=0;        Description='Disable access to the built-in password manager.' }
			[pscustomobject]@{ Id='Firefox:OfferToSaveLogins';           Browser='Firefox'; Path=$firefoxRoot; Name='OfferToSaveLogins';           Type='DWord';  Value=0;        Description='Disable password-save prompts.' }
			[pscustomobject]@{ Id='Firefox:OfferToSaveLoginsDefault';    Browser='Firefox'; Path=$firefoxRoot; Name='OfferToSaveLoginsDefault';    Type='DWord';  Value=0;        Description='Set the default password-save preference to disabled.' }
			[pscustomobject]@{ Id='Firefox:AutofillCreditCardEnabled';   Browser='Firefox'; Path=$firefoxRoot; Name='AutofillCreditCardEnabled';   Type='DWord';  Value=0;        Description='Disable credit-card autofill.' }
			[pscustomobject]@{ Id='Firefox:AutofillAddressEnabled';      Browser='Firefox'; Path=$firefoxRoot; Name='AutofillAddressEnabled';      Type='DWord';  Value=0;        Description='Disable address autofill.' }
		)
		Brave = @(
			[pscustomobject]@{ Id='Brave:BlockThirdPartyCookies';        Browser='Brave'; Path=$braveRoot; Name='BlockThirdPartyCookies';        Type='DWord';  Value=1;          Description='Block third-party cookies (anti-tracking).' }
			[pscustomobject]@{ Id='Brave:DnsOverHttpsMode';              Browser='Brave'; Path=$braveRoot; Name='DnsOverHttpsMode';              Type='String'; Value='automatic'; Description='Use DoH when the resolver supports it (anti-snooping).' }
			[pscustomobject]@{ Id='Brave:SafeBrowsingProtectionLevel';   Browser='Brave'; Path=$braveRoot; Name='SafeBrowsingProtectionLevel';   Type='DWord';  Value=2;          Description='Enable enhanced Safe Browsing protection.' }
			[pscustomobject]@{ Id='Brave:PasswordManagerEnabled';        Browser='Brave'; Path=$braveRoot; Name='PasswordManagerEnabled';        Type='DWord';  Value=0;          Description='Disable in-browser password storage.' }
			[pscustomobject]@{ Id='Brave:AutofillCreditCardEnabled';     Browser='Brave'; Path=$braveRoot; Name='AutofillCreditCardEnabled';     Type='DWord';  Value=0;          Description='Disable credit-card autofill.' }
			[pscustomobject]@{ Id='Brave:AutofillAddressEnabled';        Browser='Brave'; Path=$braveRoot; Name='AutofillAddressEnabled';        Type='DWord';  Value=0;          Description='Disable address autofill.' }
			[pscustomobject]@{ Id='Brave:BraveRewardsDisabled';          Browser='Brave'; Path=$braveRoot; Name='BraveRewardsDisabled';          Type='DWord';  Value=1;          Description='Disable Brave Rewards.' }
			[pscustomobject]@{ Id='Brave:BraveWalletDisabled';           Browser='Brave'; Path=$braveRoot; Name='BraveWalletDisabled';           Type='DWord';  Value=1;          Description='Disable Brave Wallet and related web3 functionality.' }
			[pscustomobject]@{ Id='Brave:BraveP3AEnabled';               Browser='Brave'; Path=$braveRoot; Name='BraveP3AEnabled';               Type='DWord';  Value=0;          Description='Disable Brave privacy-preserving product analytics.' }
			[pscustomobject]@{ Id='Brave:BraveStatsPingEnabled';         Browser='Brave'; Path=$braveRoot; Name='BraveStatsPingEnabled';         Type='DWord';  Value=0;          Description='Disable Brave active-user stats pings.' }
			[pscustomobject]@{ Id='Brave:BraveWebDiscoveryEnabled';      Browser='Brave'; Path=$braveRoot; Name='BraveWebDiscoveryEnabled';      Type='DWord';  Value=0;          Description='Disable Brave Web Discovery contributions.' }
			[pscustomobject]@{ Id='Brave:BraveAIChatEnabled';            Browser='Brave'; Path=$braveRoot; Name='BraveAIChatEnabled';            Type='DWord';  Value=0;          Description='Disable Brave AI chat surfaces.' }
		)
	}

	$results = New-Object System.Collections.Generic.List[object]
	foreach ($b in $Browser)
	{
		foreach ($entry in $catalog[$b])
		{
			$results.Add($entry) | Out-Null
		}
	}
	return $results.ToArray()
}

function Get-BaselineBrowserPolicyBackupRoot
{
	<#
		.SYNOPSIS
		Returns the registry root where Baseline stores prior browser-policy
		values so the apply can be reversed.

		.DESCRIPTION
		Defaults to `HKLM:\Software\Baseline\BrowserPolicies`. Honours an
		override via `BASELINE_BROWSER_POLICY_BACKUP_ROOT` so tests redirect
		to an HKCU sandbox.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_BROWSER_POLICY_BACKUP_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}
	return 'HKLM:\Software\Baseline\BrowserPolicies'
}

function ConvertTo-BaselineBrowserPolicyBackupKey
{
	<#
		.SYNOPSIS
		Translates a browser-qualified policy Id into the file-system-safe
		registry key name used inside the backup root.

		.DESCRIPTION
		Replaces ':' with '__' so `Edge:SmartScreenEnabled` becomes
		`Edge__SmartScreenEnabled`. The colon would otherwise be rejected
		by the registry path syntax on Windows (drive-letter parsing).
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Id
	)
	return $Id.Replace(':','__')
}

function Set-BaselineBrowserPolicySettings
{
	<#
		.SYNOPSIS
		Applies the browser-policy catalog with backup.

		.DESCRIPTION
		Mirrors the apply/backup pattern used by NetworkHardening:
		  1. Read current value (if any) from the policy key.
		  2. If a Baseline backup for this Id does not yet exist, snapshot
		     the prior value into the backup so the genuine original
		     survives drift between re-applies.
		  3. Write the desired value via Set-RegistryValueSafe.

		Returns one record per setting describing the outcome.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[ValidateSet('Edge','Chrome','Firefox','Brave')]
		[string[]]$Browser,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$browserArgs = @{}
		if ($PSBoundParameters.ContainsKey('Browser') -and $Browser.Count -gt 0) { $browserArgs['Browser'] = $Browser }
		$Settings = Get-BaselineBrowserPolicySettings @browserArgs
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineBrowserPolicyBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		$currentValue = $null
		$currentExists = $false
		if (Test-Path -LiteralPath $setting.Path)
		{
			$item = Get-ItemProperty -LiteralPath $setting.Path -ErrorAction SilentlyContinue
			if ($item -and $item.PSObject.Properties[$setting.Name])
			{
				$currentValue = $item.PSObject.Properties[$setting.Name].Value
				$currentExists = $true
			}
		}

		$backupKeyName = ConvertTo-BaselineBrowserPolicyBackupKey -Id $setting.Id
		$backupKey = Join-Path -Path $BackupRoot -ChildPath $backupKeyName
		$backupCreated = $false
		if (-not (Test-Path -LiteralPath $backupKey))
		{
			if ($PSCmdlet.ShouldProcess($backupKey, "Snapshot prior value for $($setting.Id)"))
			{
				if ($currentExists)
				{
					Set-RegistryValueSafe -Path $backupKey -Name 'Value' -Value $currentValue -Type $setting.Type | Out-Null
					Set-RegistryValueSafe -Path $backupKey -Name 'Existed' -Value 1 -Type 'DWord' | Out-Null
				}
				else
				{
					if (-not (Test-Path -LiteralPath $backupKey))
					{
						New-Item -Path $backupKey -Force | Out-Null
					}
					Set-RegistryValueSafe -Path $backupKey -Name 'Existed' -Value 0 -Type 'DWord' | Out-Null
				}
				Set-RegistryValueSafe -Path $backupKey -Name 'Browser' -Value $setting.Browser -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'Path' -Value $setting.Path -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'ValueName' -Value $setting.Name -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'OriginalType' -Value $setting.Type -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'AppliedAt' -Value ([DateTime]::UtcNow.ToString('o')) -Type 'String' | Out-Null
				$backupCreated = $true
			}
		}

		$applied = $false
		if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", "Set $($setting.Id) = $($setting.Value)"))
		{
			$applied = [bool](Set-RegistryValueSafe -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type)
		}

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Browser       = $setting.Browser
			Path          = $setting.Path
			Name          = $setting.Name
			DesiredValue  = $setting.Value
			PreviousValue = $currentValue
			PreviousExists= $currentExists
			BackupCreated = $backupCreated
			Applied       = $applied
		}) | Out-Null
	}

	return $results.ToArray()
}

function Restore-BaselineBrowserPolicySettings
{
	<#
		.SYNOPSIS
		Restores prior browser-policy values from Baseline backups.

		.DESCRIPTION
		If the snapshot says the value did not exist before (Existed=0),
		removes the live value rather than inventing a default. Returns
		Skipped=$true / SkipReason='NoBackup' when no snapshot is on disk.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[ValidateSet('Edge','Chrome','Firefox','Brave')]
		[string[]]$Browser,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$browserArgs = @{}
		if ($PSBoundParameters.ContainsKey('Browser') -and $Browser.Count -gt 0) { $browserArgs['Browser'] = $Browser }
		$Settings = Get-BaselineBrowserPolicySettings @browserArgs
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineBrowserPolicyBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		$backupKeyName = ConvertTo-BaselineBrowserPolicyBackupKey -Id $setting.Id
		$backupKey = Join-Path -Path $BackupRoot -ChildPath $backupKeyName
		if (-not (Test-Path -LiteralPath $backupKey))
		{
			$results.Add([pscustomobject]@{
				Id         = $setting.Id
				Restored   = $false
				Skipped    = $true
				SkipReason = 'NoBackup'
			}) | Out-Null
			continue
		}

		$backupItem = Get-ItemProperty -LiteralPath $backupKey -ErrorAction SilentlyContinue
		$existed = 0
		if ($backupItem -and $backupItem.PSObject.Properties['Existed'])
		{
			$existed = [int]$backupItem.Existed
		}
		$originalValue = $null
		if ($existed -eq 1 -and $backupItem.PSObject.Properties['Value'])
		{
			$originalValue = $backupItem.Value
		}

		$restored = $false
		if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", "Restore $($setting.Id)"))
		{
			if ($existed -eq 1)
			{
				Set-RegistryValueSafe -Path $setting.Path -Name $setting.Name -Value $originalValue -Type $setting.Type | Out-Null
			}
			else
			{
				if (Test-Path -LiteralPath $setting.Path)
				{
					Remove-RegistryValueSafe -Path $setting.Path -Name $setting.Name | Out-Null
				}
			}
			Remove-Item -LiteralPath $backupKey -Recurse -Force -ErrorAction SilentlyContinue
			$restored = $true
		}

		$results.Add([pscustomobject]@{
			Id              = $setting.Id
			Restored        = $restored
			Skipped         = $false
			SkipReason      = $null
			OriginalExisted = ($existed -eq 1)
		}) | Out-Null
	}

	return $results.ToArray()
}

function Get-BaselineBrowserPolicyStatus
{
	<#
		.SYNOPSIS
		Reports per-policy status across the catalog.

		.DESCRIPTION
		Classifies each policy as Hardened (live matches desired), Drift
		(live differs), or NotSet (live missing). Notes BackupPresent so
		callers can decide whether a restore is safe.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[ValidateSet('Edge','Chrome','Firefox','Brave')]
		[string[]]$Browser,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$browserArgs = @{}
		if ($PSBoundParameters.ContainsKey('Browser') -and $Browser.Count -gt 0) { $browserArgs['Browser'] = $Browser }
		$Settings = Get-BaselineBrowserPolicySettings @browserArgs
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineBrowserPolicyBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]
	foreach ($setting in $Settings)
	{
		$currentValue = $null
		$currentExists = $false
		if (Test-Path -LiteralPath $setting.Path)
		{
			$item = Get-ItemProperty -LiteralPath $setting.Path -ErrorAction SilentlyContinue
			if ($item -and $item.PSObject.Properties[$setting.Name])
			{
				$currentValue = $item.PSObject.Properties[$setting.Name].Value
				$currentExists = $true
			}
		}

		$state = if (-not $currentExists) { 'NotSet' }
				 elseif ($currentValue -eq $setting.Value) { 'Hardened' }
				 else { 'Drift' }

		$backupKeyName = ConvertTo-BaselineBrowserPolicyBackupKey -Id $setting.Id
		$backupPresent = Test-Path -LiteralPath (Join-Path -Path $BackupRoot -ChildPath $backupKeyName)

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Browser       = $setting.Browser
			Path          = $setting.Path
			Name          = $setting.Name
			DesiredValue  = $setting.Value
			CurrentValue  = $currentValue
			State         = $state
			BackupPresent = $backupPresent
		}) | Out-Null
	}

	return $results.ToArray()
}
