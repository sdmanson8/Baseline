
# Remote targeting helpers for Baseline.
# Provides multi-machine compliance checking and profile application over
# PowerShell Remoting (WinRM / PSSession). Each function accepts an array of
# computer names and operates in parallel per-session.
#
# Dependencies (loaded earlier in SharedHelpers.psm1):
#   Import-ConfigurationProfile       (ConfigProfile.Helpers.ps1)
#   Test-SystemCompliance              (Compliance.Helpers.ps1)
#   Import-TweakManifestFromData       (Manifest.Helpers.ps1)
#   Get-HeadlessPresetCommandList      (Preset.Helpers.ps1)

if (-not (Test-Path -Path 'Variable:\Script:CachedRemoteSessionCache'))
{
	$Script:CachedRemoteSessionCache = @{}
}
else
{
	$cachedRemoteSessionCacheValue = Get-Variable -Name CachedRemoteSessionCache -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if ($null -eq $cachedRemoteSessionCacheValue)
	{
		$Script:CachedRemoteSessionCache = @{}
	}
}

if (-not (Test-Path -Path 'Variable:\Script:CachedRemoteOrchestrationHistoryPath'))
{
	$Script:CachedRemoteOrchestrationHistoryPath = $null
}

if (-not (Test-Path -Path 'Variable:\Script:CachedRemoteOrchestrationDefaultRetryCount'))
{
	$Script:CachedRemoteOrchestrationDefaultRetryCount = 2
}
else
{
	$cachedRemoteOrchestrationDefaultRetryCountValue = Get-Variable -Name CachedRemoteOrchestrationDefaultRetryCount -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if ($null -eq $cachedRemoteOrchestrationDefaultRetryCountValue)
	{
		$Script:CachedRemoteOrchestrationDefaultRetryCount = 2
	}
}

if (-not (Test-Path -Path 'Variable:\Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds'))
{
	$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds = 250
}
else
{
	$cachedRemoteOrchestrationDefaultRetryDelayMillisecondsValue = Get-Variable -Name CachedRemoteOrchestrationDefaultRetryDelayMilliseconds -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if ($null -eq $cachedRemoteOrchestrationDefaultRetryDelayMillisecondsValue)
	{
		$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds = 250
	}
}

if (-not (Test-Path -Path 'Variable:\Script:CachedRemoteSessionIdleTimeoutMinutes'))
{
	$Script:CachedRemoteSessionIdleTimeoutMinutes = 15
}
else
{
	$cachedRemoteSessionIdleTimeoutMinutesValue = Get-Variable -Name CachedRemoteSessionIdleTimeoutMinutes -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if ($null -eq $cachedRemoteSessionIdleTimeoutMinutesValue)
	{
		$Script:CachedRemoteSessionIdleTimeoutMinutes = 15
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteCredentialScopeKey
{
	[CmdletBinding()]
	param (
		[System.Management.Automation.PSCredential]$Credential
	)

	if (-not $Credential)
	{
		return '<default>'
	}

	$credentialName = [string]$Credential.UserName
	$networkCredential = $null
	try
	{
		$networkCredential = $Credential.GetNetworkCredential()
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteCredentialScopeKey:catch92' -Severity Debug }

		$networkCredential = $null
	}

	$domain = if ($networkCredential -and -not [string]::IsNullOrWhiteSpace([string]$networkCredential.Domain)) { [string]$networkCredential.Domain.Trim() } else { $null }
	$userName = if ($networkCredential -and -not [string]::IsNullOrWhiteSpace([string]$networkCredential.UserName)) { [string]$networkCredential.UserName.Trim() } else { $credentialName.Trim() }
	$scope = if ([string]::IsNullOrWhiteSpace($domain)) { $userName } else { '{0}\{1}' -f $domain, $userName }
	return ([string]$scope).Trim().ToLowerInvariant()
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteSessionKey
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[System.Management.Automation.PSCredential]$Credential,

		[hashtable]$TransportSettings
	)

	$scope = Get-BaselineRemoteCredentialScopeKey -Credential $Credential
	$transportSignature = Get-BaselineRemoteTransportSettingsSignature -TransportSettings $TransportSettings
	return ('{0}|{1}|{2}' -f ([string]$ComputerName).Trim().ToLowerInvariant(), $scope, $transportSignature.Hash)
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineRemoteTransportSettingsValue
{
	[CmdletBinding()]
	param (
		[object]$InputObject
	)

	if ($null -eq $InputObject)
	{
		return $null
	}

	if ($InputObject -is [string] -or $InputObject -is [bool] -or $InputObject -is [byte] -or $InputObject -is [sbyte] -or $InputObject -is [int16] -or $InputObject -is [uint16] -or $InputObject -is [int32] -or $InputObject -is [uint32] -or $InputObject -is [int64] -or $InputObject -is [uint64] -or $InputObject -is [single] -or $InputObject -is [double] -or $InputObject -is [decimal])
	{
		return $InputObject
	}

	if ($InputObject -is [datetime])
	{
		return ([datetime]$InputObject).ToUniversalTime().ToString('o')
	}

	if ($InputObject -is [timespan] -or $InputObject -is [guid] -or $InputObject -is [version] -or $InputObject -is [enum])
	{
		return [string]$InputObject
	}

	if ($InputObject -is [System.Collections.IDictionary])
	{
		$ordered = [ordered]@{}
		foreach ($key in @($InputObject.Keys | Sort-Object { [string]$_ }))
		{
			$ordered[[string]$key] = ConvertTo-BaselineRemoteTransportSettingsValue -InputObject $InputObject[$key]
		}
		return $ordered
	}

	if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string]) -and -not ($InputObject -is [byte[]]))
	{
		return @($InputObject | ForEach-Object { ConvertTo-BaselineRemoteTransportSettingsValue -InputObject $_ })
	}

	if ($InputObject.PSObject -and $InputObject.PSObject.Properties.Count -gt 0)
	{
		$ordered = [ordered]@{}
		foreach ($property in @($InputObject.PSObject.Properties | Sort-Object Name))
		{
			$ordered[$property.Name] = ConvertTo-BaselineRemoteTransportSettingsValue -InputObject $property.Value
		}
		return $ordered
	}

	return [string]$InputObject
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteTransportSettingsSignature
{
	[CmdletBinding()]
	param (
		[hashtable]$TransportSettings
	)

	if (-not $TransportSettings -or $TransportSettings.Count -eq 0)
	{
		return [pscustomobject]@{
			Text = '<default>'
			Hash = '<default>'
		}
	}

	$ordered = [ordered]@{}
	foreach ($key in @($TransportSettings.Keys | Sort-Object { [string]$_ }))
	{
		$ordered[[string]$key] = ConvertTo-BaselineRemoteTransportSettingsValue -InputObject $TransportSettings[$key]
	}

	$text = ConvertTo-Json -InputObject $ordered -Compress -Depth 10
	$sha256 = [System.Security.Cryptography.SHA256]::Create()
	try
	{
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
		$hashBytes = $sha256.ComputeHash($bytes)
		$hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
	}
	finally
	{
		$sha256.Dispose()
	}

	return [pscustomobject]@{
		Text = $text
		Hash = $hash
	}
}

<#
    .SYNOPSIS
#>

function New-BaselineRemoteSessionCacheEntry
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[Parameter(Mandatory)]
		[string]$CredentialScopeKey,

		[Parameter(Mandatory)]
		[pscustomobject]$TransportSignature,

		[Parameter(Mandatory)]
		[object]$Session
	)

	$now = [datetime]::UtcNow
	return [pscustomobject]@{
		ComputerName         = $ComputerName
		CredentialScopeKey    = $CredentialScopeKey
		TransportSettingsText = [string]$TransportSignature.Text
		TransportKey          = [string]$TransportSignature.Hash
		Key                   = ('{0}|{1}|{2}' -f ([string]$ComputerName).Trim().ToLowerInvariant(), [string]$CredentialScopeKey, [string]$TransportSignature.Hash)
		Session               = $Session
		CreatedUtc            = $now
		LastUsedUtc           = $now
	}
}

<#
    .SYNOPSIS
#>

function Test-BaselineRemoteSessionCacheEntry
{
	[CmdletBinding()]
	param (
		[object]$Entry,

		[string]$TransportKey,

		[Parameter()]
		[int]$IdleTimeoutMinutes = $(if ($Script:CachedRemoteSessionIdleTimeoutMinutes) { [int]$Script:CachedRemoteSessionIdleTimeoutMinutes } else { 15 }),

		[Parameter()]
		[datetime]$Now = [datetime]::UtcNow
	)

	if (-not $Entry)
	{
		return $false
	}

	$session = $null
	try { $session = $Entry.Session } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteSessionCacheEntry:catch286' -Severity Debug }
	 $session = $null }
	if (-not $session)
	{
		return $false
	}

	$state = $null
	try { $state = [string]$session.State } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteSessionCacheEntry:catch293' -Severity Debug }
	 $state = $null }
	if ($state -notin @('Opened', 'Open'))
	{
		return $false
	}

	if (-not [string]::IsNullOrWhiteSpace($TransportKey))
	{
		$currentTransportKey = $null
		try { $currentTransportKey = [string]$Entry.TransportKey } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteSessionCacheEntry:catch302' -Severity Debug }
		 $currentTransportKey = $null }
		if ([string]::IsNullOrWhiteSpace($currentTransportKey) -or $currentTransportKey -ne $TransportKey)
		{
			return $false
		}
	}

	if ($IdleTimeoutMinutes -gt 0)
	{
		$lastUsedUtc = $null
		try { $lastUsedUtc = [datetime]$Entry.LastUsedUtc } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteSessionCacheEntry:catch312' -Severity Debug }
		 $lastUsedUtc = $null }
		if (-not $lastUsedUtc)
		{
			try { $lastUsedUtc = [datetime]$Entry.CreatedUtc } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteSessionCacheEntry:catch315' -Severity Debug }
			 $lastUsedUtc = $null }
		}
		if (-not $lastUsedUtc)
		{
			return $false
		}

		if ((($Now.ToUniversalTime()) - $lastUsedUtc.ToUniversalTime()).TotalMinutes -ge $IdleTimeoutMinutes)
		{
			return $false
		}
	}

	return $true
}

<#
    .SYNOPSIS
#>

function Remove-BaselineRemoteSessionCacheEntry
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Key
	)

	if (-not $Script:CachedRemoteSessionCache -or -not $Script:CachedRemoteSessionCache.ContainsKey($Key))
	{
		return $null
	}

	$entry = $Script:CachedRemoteSessionCache[$Key]
	$session = $null
	try { $session = $entry.Session } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Remove-BaselineRemoteSessionCacheEntry:catch350' -Severity Debug }
	 $session = $entry }
	if ($session)
	{
		try { Remove-PSSession -Session $session -ErrorAction SilentlyContinue } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Remove-BaselineRemoteSessionCacheEntry.RemovePSSession' }
	}
	$null = $Script:CachedRemoteSessionCache.Remove($Key)
	return $entry
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteSessionCacheMaintenance
{
	[CmdletBinding()]
	param (
		[string[]]$ComputerName,

		[Parameter()]
		[int]$IdleTimeoutMinutes = $(if ($Script:CachedRemoteSessionIdleTimeoutMinutes) { [int]$Script:CachedRemoteSessionIdleTimeoutMinutes } else { 15 })
	)

	if (-not $Script:CachedRemoteSessionCache -or $Script:CachedRemoteSessionCache.Count -eq 0)
	{
		return @()
	}

	$targets = @()
	if ($ComputerName -and $ComputerName.Count -gt 0)
	{
		$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	}

	$removedKeys = [System.Collections.Generic.List[string]]::new()
	foreach ($key in @($Script:CachedRemoteSessionCache.Keys))
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$key) -and $targets.Count -gt 0)
		{
			$computer = ($key -split '\|', 3)[0]
			if ($targets -notcontains ([string]$computer).Trim().ToLowerInvariant())
			{
				continue
			}
		}

		$entry = $Script:CachedRemoteSessionCache[$key]
		$transportKey = $null
		try { $transportKey = [string]$entry.TransportKey } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Invoke-BaselineRemoteSessionCacheMaintenance:catch398' -Severity Debug }
		 $transportKey = $null }
		if (-not (Test-BaselineRemoteSessionCacheEntry -Entry $entry -TransportKey $transportKey -IdleTimeoutMinutes $IdleTimeoutMinutes))
		{
			[void]$removedKeys.Add([string]$key)
			[void](Remove-BaselineRemoteSessionCacheEntry -Key $key)
		}
	}

	return @($removedKeys)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteTargetTerminalState
{
	[CmdletBinding()]
	param (
		[string]$Status,
		[bool]$Retryable = $false,
		[bool]$Blocked = $false,
		[bool]$Cancelled = $false,
		[bool]$Skipped = $false
	)

	if ($Cancelled)
	{
		return 'Cancelled'
	}

	if ($Blocked -or $Skipped)
	{
		return 'Skipped'
	}

	switch ([string]$Status)
	{
		'Reachable' { return 'Succeeded' }
		'Applied' { return 'Succeeded' }
		'Compliant' { return 'Succeeded' }
		'Success' { return 'Succeeded' }
		'Skipped' { return 'Skipped' }
		'NotApplicable' { return 'Skipped' }
		'Not Applicable' { return 'Skipped' }
		'Cancelled' { return 'Cancelled' }
		'Partial'
		{
			if ($Retryable) { return 'Retrying' }
			return 'Failed'
		}
		'Drifted'
		{
			if ($Retryable) { return 'Retrying' }
			return 'Failed'
		}
		'Failed'
		{
			if ($Retryable) { return 'Retrying' }
			return 'Failed'
		}
		'Unreachable'
		{
			if ($Retryable) { return 'Retrying' }
			return 'Failed'
		}
		default
		{
			if ($Retryable) { return 'Retrying' }
			return 'Failed'
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteTargetState
{
	[CmdletBinding()]
	param (
		[string]$Operation,
		[string]$State,
		[string]$Status,
		[bool]$Retryable = $false,
		[bool]$Blocked = $false,
		[bool]$Cancelled = $false
	)

	if (-not [string]::IsNullOrWhiteSpace($State))
	{
		switch ([string]$State)
		{
			'Pending' { return 'Pending' }
			'Connecting' { return 'Connecting' }
			'Connected' { return 'Connected' }
			'PreflightFailed' { return 'PreflightFailed' }
			'PreviewReady' { return 'PreviewReady' }
			'Running' { return 'Running' }
			'Succeeded' { return 'Succeeded' }
			'Failed' { return 'Failed' }
			'Cancelled' { return 'Cancelled' }
			'RequiresReview' { return 'RequiresReview' }
		}
	}

	if ($Cancelled)
	{
		return 'Cancelled'
	}

	if ($Blocked)
	{
		return 'PreflightFailed'
	}

	switch ([string]$Status)
	{
		'Reachable' { return 'Succeeded' }
		'Applied' { return 'Succeeded' }
		'Compliant' { return 'Succeeded' }
		'Success' { return 'Succeeded' }
		'Partial' { return 'RequiresReview' }
		'Drifted' { return 'RequiresReview' }
		'Skipped'
		{
			if ([string]$Operation -eq 'RemoteApply') { return 'RequiresReview' }
			return 'Succeeded'
		}
		'NotApplicable' { return 'RequiresReview' }
		'Not Applicable' { return 'RequiresReview' }
		'Cancelled' { return 'Cancelled' }
		default
		{
			if ($Retryable)
			{
				return 'Running'
			}
			return 'Failed'
		}
	}
}

<#
    .SYNOPSIS
#>

function New-BaselineRemoteTargetStateTransition
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Operation,

		[Parameter(Mandatory)]
		[string]$State,

		[string]$Phase,

		[string]$Status,

		[string]$Reason,

		[datetime]$Timestamp = [datetime]::UtcNow
	)

	return [pscustomobject]@{
		Operation = [string]$Operation
		State     = [string]$State
		Phase     = [string]$Phase
		Status    = [string]$Status
		Reason    = [string]$Reason
		Timestamp = $Timestamp.ToUniversalTime()
	}
}

<#
    .SYNOPSIS
#>

function Add-BaselineRemoteTargetStateTransition
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[pscustomobject]]$Transitions,

		[Parameter(Mandatory)]
		[string]$Operation,

		[Parameter(Mandatory)]
		[string]$State,

		[string]$Phase,

		[string]$Status,

		[string]$Reason,

		[datetime]$Timestamp = [datetime]::UtcNow
	)

	$transition = New-BaselineRemoteTargetStateTransition -Operation $Operation -State $State -Phase $Phase -Status $Status -Reason $Reason -Timestamp $Timestamp
	[void]$Transitions.Add($transition)
	return $transition
}

<#
    .SYNOPSIS
#>

function Clear-BaselineRemoteSessionCache
{
	<#
		.SYNOPSIS Clears cached remote sessions.
	#>
	[CmdletBinding()]
	param (
		[string[]]$ComputerName
	)

	if (-not $Script:CachedRemoteSessionCache)
	{
		$Script:CachedRemoteSessionCache = @{}
		return
	}

	$keysToRemove = @()
	if ($ComputerName -and $ComputerName.Count -gt 0)
	{
		$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
		foreach ($key in @($Script:CachedRemoteSessionCache.Keys))
		{
			foreach ($target in $targets)
			{
				if ($key.StartsWith(($target + '|'), [System.StringComparison]::OrdinalIgnoreCase))
				{
					$keysToRemove += $key
					break
				}
			}
		}
	}
	else
	{
		$keysToRemove = @($Script:CachedRemoteSessionCache.Keys)
	}

	foreach ($key in @($keysToRemove | Select-Object -Unique))
	{
		[void](Remove-BaselineRemoteSessionCacheEntry -Key $key)
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteSession
{
	<#
		.SYNOPSIS Gets or creates a cached remote session for a target.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[System.Management.Automation.PSCredential]$Credential,

		[Parameter()]
		[hashtable]$TransportSettings,

		[Parameter()]
		[int]$MaxRetryCount = $(if ($Script:CachedRemoteOrchestrationDefaultRetryCount) { [int]$Script:CachedRemoteOrchestrationDefaultRetryCount } else { 2 }),

		[Parameter()]
		[int]$RetryDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 }),

		[Parameter()]
		[int]$IdleTimeoutMinutes = $(if ($Script:CachedRemoteSessionIdleTimeoutMinutes) { [int]$Script:CachedRemoteSessionIdleTimeoutMinutes } else { 15 })
	)

	$transportSignature = Get-BaselineRemoteTransportSettingsSignature -TransportSettings $TransportSettings
	$key = Get-BaselineRemoteSessionKey -ComputerName $ComputerName -Credential $Credential -TransportSettings $TransportSettings
	$session = $null
	[void](Invoke-BaselineRemoteSessionCacheMaintenance -ComputerName @($ComputerName) -IdleTimeoutMinutes $IdleTimeoutMinutes)
	if ($Script:CachedRemoteSessionCache.ContainsKey($key))
	{
		$entry = $Script:CachedRemoteSessionCache[$key]
		if (Test-BaselineRemoteSessionCacheEntry -Entry $entry -TransportKey $transportSignature.Hash -IdleTimeoutMinutes $IdleTimeoutMinutes)
		{
			try { $entry.LastUsedUtc = [datetime]::UtcNow } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Invoke-BaselineRemoteSessionCacheMaintenance.UpdateLastUsedUtc' }
			$session = $entry.Session
		}
		else
		{
			[void](Remove-BaselineRemoteSessionCacheEntry -Key $key)
		}
	}

	if (-not $session)
	{
		$sessionParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
		if ($Credential) { $sessionParams.Credential = $Credential }
		if ($TransportSettings)
		{
			foreach ($setting in @($TransportSettings.GetEnumerator()))
			{
				if (-not $setting.Key)
				{
					continue
				}

				switch ([string]$setting.Key)
				{
					'ComputerName' { continue }
					'Credential' { continue }
					'MaxRetryCount' { continue }
					'RetryDelayMilliseconds' { continue }
					'IdleTimeoutMinutes' { continue }
				}

				if ($null -ne $setting.Value)
				{
					$sessionParams[[string]$setting.Key] = $setting.Value
				}
			}
		}

		$attempt = 0
		while ($true)
		{
			$attempt++
			try
			{
				$session = New-PSSession @sessionParams
				$cacheEntry = New-BaselineRemoteSessionCacheEntry -ComputerName $ComputerName -CredentialScopeKey (Get-BaselineRemoteCredentialScopeKey -Credential $Credential) -TransportSignature $transportSignature -Session $session
				$Script:CachedRemoteSessionCache[$key] = $cacheEntry
				break
			}
			catch
			{
				$failureProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($_.Exception.Message) -Status 'Unreachable'
				if (-not $failureProfile.Retryable -or $attempt -gt ([math]::Max(1, $MaxRetryCount + 1)))
				{
					throw
				}

				Invoke-BaselineRemoteRetryDelay -Attempt $attempt -BaseDelayMilliseconds $RetryDelayMilliseconds
			}
		}
	}

	return $session
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteSessionSummary
{
	<#
		.SYNOPSIS Returns a light-weight summary of the cached remote sessions.
	#>
	[CmdletBinding()]
	param (
		[string[]]$ComputerName
	)

	$entries = [System.Collections.Generic.List[pscustomobject]]::new()
	if (-not $Script:CachedRemoteSessionCache -or $Script:CachedRemoteSessionCache.Count -eq 0)
	{
		return @()
	}

	[void](Invoke-BaselineRemoteSessionCacheMaintenance -ComputerName $ComputerName)

	$targets = @()
	if ($ComputerName -and $ComputerName.Count -gt 0)
	{
		$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	}

	foreach ($key in @($Script:CachedRemoteSessionCache.Keys))
	{
		$entry = $Script:CachedRemoteSessionCache[$key]
		$session = $null
		try { $session = $entry.Session } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteSessionSummary:catch788' -Severity Debug }
		 $session = $entry }
		if (-not $session) { continue }

		$computer = $null
		try { $computer = [string]$session.ComputerName } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteSessionSummary:catch792' -Severity Debug }
		 $computer = $null }
		if ([string]::IsNullOrWhiteSpace($computer))
		{
			$computer = ($key -split '\|', 3)[0]
		}

		if ($targets.Count -gt 0 -and $targets -notcontains ([string]$computer).Trim().ToLowerInvariant())
		{
			continue
		}

		$keyParts = @($key -split '\|', 3)
		$userName = if ($keyParts.Count -gt 1) { $keyParts[1] } else { '<default>' }
		$state = $null
		try { $state = [string]$session.State } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteSessionSummary:catch806' -Severity Debug }
		 $state = 'Unknown' }
		$transportKey = $null
		try { $transportKey = [string]$entry.TransportKey } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteSessionSummary:catch808' -Severity Debug }
		 $transportKey = $null }
		$lastUsedUtc = $null
		try { $lastUsedUtc = [datetime]$entry.LastUsedUtc } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteSessionSummary:catch810' -Severity Debug }
		 $lastUsedUtc = $null }

		$entries.Add([pscustomobject]@{
			ComputerName = $computer
			UserName     = $userName
			State        = if ([string]::IsNullOrWhiteSpace($state)) { 'Unknown' } else { $state }
			TransportKey = $transportKey
			LastUsedUtc  = $lastUsedUtc
		})
	}

	return @($entries)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteOrchestrationHistoryPath
{
	<# .SYNOPSIS Returns the path to the remote orchestration history file. #>
	[CmdletBinding()]
	param ()

	$historyDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline')
	if (-not [System.IO.Directory]::Exists($historyDir))
	{
		[void][System.IO.Directory]::CreateDirectory($historyDir)
	}

	$path = [System.IO.Path]::Combine($historyDir, 'remote-orchestration.jsonl')
	$Script:CachedRemoteOrchestrationHistoryPath = $path
	return $path
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteFailureProfile
{
	<# .SYNOPSIS Classifies remote failures for retry and audit purposes. #>
	[CmdletBinding()]
	param (
		[string[]]$ErrorMessages,
		[string]$Status = 'Unknown'
	)

	$text = @($ErrorMessages | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }) -join ' | '
	if ([string]::IsNullOrWhiteSpace($text) -and @('Reachable', 'Success', 'Compliant', 'Applied') -contains $Status)
	{
		return [pscustomobject]@{
			Category   = 'Success'
			Retryable  = $false
			RetryReason = 'Completed successfully.'
		}
	}

	if ([string]::IsNullOrWhiteSpace($text) -and @('Drifted', 'NonCompliant') -contains $Status)
	{
		return [pscustomobject]@{
			Category   = 'Compliance'
			Retryable  = $false
			RetryReason = 'The target completed, but drift was detected and manual remediation is required.'
		}
	}

	if ([string]::IsNullOrWhiteSpace($text) -and $Status -eq 'Partial')
	{
		return [pscustomobject]@{
			Category   = 'Partial'
			Retryable  = $false
			RetryReason = 'The target completed with partial success; review the failed items before retrying.'
		}
	}

	if ([string]::IsNullOrWhiteSpace($text))
	{
		return [pscustomobject]@{
			Category   = 'Unknown'
			Retryable  = $false
			RetryReason = 'No error details were captured.'
		}
	}

	switch -regex ($text)
	{
		'(?i)\b(timeout|timed out|unreachable|network|rpc|wsman|winrm|transport)\b'
		{
			return [pscustomobject]@{
				Category   = 'Connectivity'
				Retryable  = $true
				RetryReason = 'The failure looks transient or transport-related; retry after connectivity recovers.'
			}
		}
		'(?i)\b(access denied|authentication|logon failure|credential|unauthorized)\b'
		{
			return [pscustomobject]@{
				Category   = 'Authentication'
				Retryable  = $false
				RetryReason = 'The failure points to credentials or authorization; retry only after fixing access.'
			}
		}
		'(?i)\b(policy|gpo|group policy|blocked by policy|not permitted)\b'
		{
			return [pscustomobject]@{
				Category   = 'Policy'
				Retryable  = $false
				RetryReason = 'The failure is policy-driven; retry only after the policy conflict is resolved.'
			}
		}
		default
		{
			return [pscustomobject]@{
				Category   = 'Execution'
				Retryable  = $false
				RetryReason = 'The failure does not appear transient enough to justify an automatic retry.'
			}
		}
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Creates a structured record for a single execution attempt, capturing timing
    and failure classification for later aggregation in orchestration history.
#>

function New-BaselineRemoteAttemptRecord
{
	<# .SYNOPSIS Creates a record capturing one attempt toward a remote operation. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[Parameter(Mandatory)]
		[int]$AttemptIndex,

		[Parameter(Mandatory)]
		[datetime]$StartedUtc,

		[datetime]$CompletedUtc = [datetime]::UtcNow,

		[string]$Status = 'Unknown',

		[string[]]$Errors = @(),

		[object]$FailureProfile = $null
	)

	$resolvedProfile = $FailureProfile
	if (-not $resolvedProfile -and $Errors.Count -gt 0)
	{
		$resolvedProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($Errors) -Status $Status
	}
	elseif (-not $resolvedProfile)
	{
		$resolvedProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @() -Status $Status
	}

	$durationMs = [int][math]::Round(($CompletedUtc - $StartedUtc).TotalMilliseconds, 0)
	return [pscustomobject]@{
		ComputerName    = [string]$ComputerName
		AttemptIndex    = [int]$AttemptIndex
		StartedUtc      = $StartedUtc.ToUniversalTime()
		CompletedUtc    = $CompletedUtc.ToUniversalTime()
		DurationMs      = $durationMs
		Status          = [string]$Status
		Errors          = @($Errors | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
		FailureCategory = [string]$resolvedProfile.Category
		Retryable       = [bool]$resolvedProfile.Retryable
		RetryReason     = [string]$resolvedProfile.RetryReason
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Computes aggregate retry metrics from a collection of attempt records.
#>

function Get-BaselineRemoteRetryAnalytics
{
	<# .SYNOPSIS Computes aggregate retry metrics from attempt records. #>
	[CmdletBinding()]
	param (
		[object[]]$AttemptRecords = @()
	)

	$attempts = @($AttemptRecords | Where-Object { $null -ne $_ })
	if ($attempts.Count -eq 0)
	{
		return [pscustomobject]@{
			TotalAttempts       = 0
			TotalRetries        = 0
			RetryableFailures   = 0
			NonRetryableFailures = 0
			Succeeded           = $false
			FinalAttemptIndex   = 0
			FinalStatus         = 'Unknown'
			TotalDurationMs     = 0
			RetryDurationMs     = 0
			FirstAttemptUtc     = $null
			LastAttemptUtc      = $null
			FailureCategoryCounts = [ordered]@{}
			AttemptRecords      = @()
		}
	}

	$totalAttempts = $attempts.Count
	$totalRetries = [math]::Max(0, $totalAttempts - 1)
	$retryable = @($attempts | Where-Object { [bool]$_.Retryable }).Count
	$nonRetryable = @($attempts | Where-Object { -not [bool]$_.Retryable -and [string]$_.FailureCategory -notin @('Success', 'Unknown') }).Count
	$finalAttempt = $attempts | Sort-Object { [int]$_.AttemptIndex } | Select-Object -Last 1
	$succeeded = [bool]($finalAttempt.FailureCategory -eq 'Success')
	$totalDurationMs = ($attempts | Measure-Object -Property DurationMs -Sum).Sum
	$retryDurationMs = if ($totalRetries -gt 0) { ($attempts | Select-Object -Skip 1 | Measure-Object -Property DurationMs -Sum).Sum } else { 0 }
	$firstUtc = ($attempts | Sort-Object { [datetime]$_.StartedUtc } | Select-Object -First 1).StartedUtc
	$lastUtc = ($attempts | Sort-Object { [datetime]$_.CompletedUtc } | Select-Object -Last 1).CompletedUtc
	$categoryCounts = [ordered]@{}
	foreach ($attempt in $attempts)
	{
		$cat = [string]$attempt.FailureCategory
		if (-not $categoryCounts.Contains($cat))
		{
			$categoryCounts[$cat] = 0
		}
		$categoryCounts[$cat]++
	}

	return [pscustomobject]@{
		TotalAttempts        = $totalAttempts
		TotalRetries         = $totalRetries
		RetryableFailures    = $retryable
		NonRetryableFailures = $nonRetryable
		Succeeded            = $succeeded
		FinalAttemptIndex    = [int]$finalAttempt.AttemptIndex
		FinalStatus          = [string]$finalAttempt.Status
		TotalDurationMs      = [int]$totalDurationMs
		RetryDurationMs      = [int]$retryDurationMs
		FirstAttemptUtc      = $firstUtc
		LastAttemptUtc       = $lastUtc
		FailureCategoryCounts = $categoryCounts
		AttemptRecords       = @($attempts | ForEach-Object {
			[ordered]@{
				AttemptIndex    = [int]$_.AttemptIndex
				StartedUtc      = $_. StartedUtc
				CompletedUtc    = $_.CompletedUtc
				DurationMs      = [int]$_.DurationMs
				Status          = [string]$_.Status
				FailureCategory = [string]$_.FailureCategory
				Retryable       = [bool]$_.Retryable
				Errors          = @($_.Errors)
			}
		})
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Appends individual attempt events to the orchestration history JSONL file
    so each retry is visible in the audit trail.
#>

function Write-BaselineRemoteAttemptHistoryRecord
{
	<# .SYNOPSIS Records a single retry attempt to orchestration history. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$RunId,

		[Parameter(Mandatory)]
		[string]$Operation,

		[Parameter(Mandatory)]
		[object]$AttemptRecord
	)

	$path = Get-BaselineRemoteOrchestrationHistoryPath
	$record = $AttemptRecord
	$payload = [ordered]@{
		RecordKind        = 'RetryAttempt'
		RecordedUtc       = [datetime]::UtcNow.ToUniversalTime().ToString('o')
		RunId             = [string]$RunId
		Operation         = [string]$Operation
		ComputerName      = [string]$record.ComputerName
		AttemptIndex      = [int]$record.AttemptIndex
		StartedUtc        = $record.StartedUtc.ToString('o')
		CompletedUtc      = $record.CompletedUtc.ToString('o')
		DurationMs        = [int]$record.DurationMs
		Status            = [string]$record.Status
		FailureCategory   = [string]$record.FailureCategory
		Retryable         = [bool]$record.Retryable
		RetryReason       = [string]$record.RetryReason
		Errors            = @($record.Errors)
	}

	$json = ConvertTo-Json -InputObject $payload -Compress -Depth 8
	[System.IO.File]::AppendAllText($path, "$json`n", [System.Text.UTF8Encoding]::new($false))
	return [pscustomobject]$payload
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteOrchestrationHistory
{
	<# .SYNOPSIS Reads the remote orchestration JSONL history file. #>
	[CmdletBinding()]
	param (
		[datetime]$Since,
		[int]$MaxRecords = 100,
		[string]$Operation,
		[string]$ComputerName,
		[string]$RecordKind
	)

	$path = Get-BaselineRemoteOrchestrationHistoryPath
	if (-not [System.IO.File]::Exists($path))
	{
		return @()
	}

	$records = [System.Collections.Generic.List[object]]::new()
	$lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
	foreach ($line in $lines)
	{
		if ([string]::IsNullOrWhiteSpace($line)) { continue }

		try
		{
			$obj = $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteOrchestrationHistory.ParseLine'
			continue
		}

		if ($PSBoundParameters.ContainsKey('Since') -and $obj.Timestamp)
		{
			try
			{
				$ts = [datetime]::Parse([string]$obj.Timestamp)
				if ($ts -lt $Since) { continue }
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteOrchestrationHistory.SinceTimestampParse' }
		}

		if (-not [string]::IsNullOrWhiteSpace($Operation) -and $obj.Operation -ne $Operation)
		{
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and $obj.ComputerName -ne $ComputerName)
		{
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($RecordKind))
		{
			$recordKind = if ($obj.PSObject.Properties['RecordKind']) { [string]$obj.RecordKind } else { 'Target' }
			if ($recordKind -ne $RecordKind)
			{
				continue
			}
		}

		$records.Add($obj)
	}

	$ordered = @($records | Sort-Object -Property Timestamp -Descending)
	if ($MaxRecords -gt 0)
	{
		$ordered = @($ordered | Select-Object -First $MaxRecords)
	}

	return @($ordered)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteOrchestrationSummary
{
	<# .SYNOPSIS Returns a human-readable summary of recent remote orchestration runs. #>
	[CmdletBinding()]
	param (
		[int]$MaxRecords = 5,
		[string]$RecordKind = 'Target'
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords $MaxRecords -RecordKind $RecordKind)
	if ($records.Count -eq 0)
	{
		return @()
	}

	$lines = [System.Collections.Generic.List[string]]::new()
	foreach ($record in $records)
	{
		$recordKind = if ($record.PSObject.Properties['RecordKind']) { [string]$record.RecordKind } else { 'Target' }
		if ($recordKind -ne $RecordKind)
		{
			continue
		}

		$stamp = $null
		try { $stamp = ([datetime]::Parse([string]$record.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteOrchestrationSummary:catch1227' -Severity Debug }
		 $stamp = [string]$record.Timestamp }
		$status = if ($record.Status) { [string]$record.Status } else { 'Unknown' }
		$target = if ($record.ComputerName) { [string]$record.ComputerName } else { 'unknown target' }
		$operation = if ($record.Operation) { [string]$record.Operation } else { 'Remote' }
		$state = if ($record.LifecycleState) { [string]$record.LifecycleState } else { 'Unknown' }
		$targetState = if ($record.PSObject.Properties['TargetState'] -and -not [string]::IsNullOrWhiteSpace([string]$record.TargetState)) { [string]$record.TargetState } else { 'Unknown' }
		$terminalState = if ($record.PSObject.Properties['TerminalState'] -and -not [string]::IsNullOrWhiteSpace([string]$record.TerminalState)) { [string]$record.TerminalState } else { 'Unknown' }
		$attempts = if ($record.PSObject.Properties['AttemptCount']) { [int]$record.AttemptCount } else { 1 }
		$retries = if ($record.PSObject.Properties['RetryCount']) { [int]$record.RetryCount } else { 0 }
		$retry = if ($record.Retryable -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$record.RetryReason)) { ' | Retryable: {0}' -f [string]$record.RetryReason } else { '' }
		[void]$lines.Add(('{0} | {1} | {2} | {3} | State: {4} | Target: {5} | Terminal: {6} | Attempts: {7} | Retries: {8}{9}' -f $stamp, $operation, $target, $status, $state, $targetState, $terminalState, $attempts, $retries, $retry))
	}

	return @($lines)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteOrchestrationDetails
{
	<# .SYNOPSIS Returns structured remote orchestration results with optional filters. #>
	[CmdletBinding()]
	param (
		[string[]]$ComputerName,
		[string[]]$Operation,
		[string[]]$Status,
		[string[]]$LifecycleState,
		[string[]]$RecordKind = @('Target'),
		[string]$RunId,
		[int]$MaxRecords = 25
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords $MaxRecords)
	if ($records.Count -eq 0)
	{
		return @()
	}

	$computerFilter = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$operationFilter = @($Operation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$statusFilter = @($Status | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$lifecycleFilter = @($LifecycleState | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$recordKindFilter = @($RecordKind | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })

	$entries = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($record in $records)
	{
		if (-not [string]::IsNullOrWhiteSpace($RunId) -and ([string]$record.RunId) -ne [string]$RunId) { continue }

		$recordComputer = if ($record.ComputerName) { [string]$record.ComputerName } else { 'unknown target' }
		$recordOperation = if ($record.Operation) { [string]$record.Operation } else { 'Remote' }
		$recordStatus = if ($record.Status) { [string]$record.Status } else { 'Unknown' }
		$recordLifecycle = if ($record.LifecycleState) { [string]$record.LifecycleState } else { 'Unknown' }
		$recordTargetState = if ($record.PSObject.Properties['TargetState']) { [string]$record.TargetState } else { 'Unknown' }
		$recordRecordKind = if ($record.PSObject.Properties['RecordKind']) { [string]$record.RecordKind } else { 'Target' }
		$recordTerminal = if ($record.PSObject.Properties['TerminalState']) { [string]$record.TerminalState } else { 'Unknown' }
		if ($computerFilter.Count -gt 0 -and $computerFilter -notcontains $recordComputer.Trim().ToLowerInvariant()) { continue }
		if ($operationFilter.Count -gt 0 -and $operationFilter -notcontains $recordOperation.Trim().ToLowerInvariant()) { continue }
		if ($statusFilter.Count -gt 0 -and $statusFilter -notcontains $recordStatus.Trim().ToLowerInvariant()) { continue }
		if ($lifecycleFilter.Count -gt 0 -and $lifecycleFilter -notcontains $recordLifecycle.Trim().ToLowerInvariant()) { continue }
		if ($recordKindFilter.Count -gt 0 -and $recordKindFilter -notcontains $recordRecordKind.Trim().ToLowerInvariant()) { continue }

		$stamp = $null
		try { $stamp = [datetime]::Parse([string]$record.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteOrchestrationDetails:catch1292' -Severity Debug }
		 $stamp = [datetime]::UtcNow }

		$errors = @()
		if ($record.PSObject.Properties['Errors'] -and $record.Errors)
		{
			$errors = @($record.Errors | ForEach-Object { [string]$_ })
		}
		$attemptCount = if ($record.PSObject.Properties['AttemptCount']) { [int]$record.AttemptCount } else { 1 }
		$retryCount = if ($record.PSObject.Properties['RetryCount']) { [int]$record.RetryCount } else { 0 }

		$entries.Add([pscustomobject]@{
			Timestamp       = $stamp
			ComputerName    = $recordComputer
			RemoteTarget    = if ($record.PSObject.Properties['RemoteTargetLabel']) { [string]$record.RemoteTargetLabel } else { $recordComputer }
			RecordKind      = $recordRecordKind
			Operation       = $recordOperation
			Status          = $recordStatus
			LifecycleState  = $recordLifecycle
			TargetState     = $recordTargetState
			TerminalState   = if ($record.PSObject.Properties['TerminalState']) { [string]$record.TerminalState } else { 'Unknown' }
			RunId           = if ($record.PSObject.Properties['RunId']) { [string]$record.RunId } else { $null }
			AttemptCount    = if ($record.PSObject.Properties['AttemptCount']) { [int]$record.AttemptCount } else { 1 }
			RetryCount      = if ($record.PSObject.Properties['RetryCount']) { [int]$record.RetryCount } else { 0 }
			SessionState    = if ($record.PSObject.Properties['SessionState']) { [string]$record.SessionState } else { 'Unknown' }
			SessionReused   = if ($record.PSObject.Properties['SessionReused']) { [bool]$record.SessionReused } else { $false }
			BlockedByPolicy = if ($record.PSObject.Properties['BlockedByPolicy']) { [bool]$record.BlockedByPolicy } else { $false }
			FailureCategory = if ($record.PSObject.Properties['FailureCategory']) { [string]$record.FailureCategory } else { 'Unknown' }
			Retryable       = if ($record.PSObject.Properties['Retryable']) { [bool]$record.Retryable } else { $false }
			RetryReason     = if ($record.PSObject.Properties['RetryReason']) { [string]$record.RetryReason } else { $null }
			HistoryPath     = if ($record.PSObject.Properties['HistoryPath']) { [string]$record.HistoryPath } else { $null }
			DurationSeconds = if ($record.PSObject.Properties['DurationSeconds']) { [double]$record.DurationSeconds } else { 0 }
			Errors          = @($errors)
			Summary         = ('{0} | {1} | {2} | {3} | State: {4} | Target: {5} | Terminal: {6} | Attempts: {7} | Retries: {8}' -f $stamp.ToString('yyyy-MM-dd HH:mm:ss'), $recordOperation, $recordComputer, $recordStatus, $recordLifecycle, $recordTargetState, $recordTerminal, $attemptCount, $retryCount)
		})
	}

	return @($entries)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteRunSummaries
{
	<# .SYNOPSIS Returns structured per-run remote orchestration summaries. #>
	[CmdletBinding()]
	param (
		[string[]]$Operation,
		[string[]]$TerminalState,
		[string]$RunId,
		[int]$MaxRecords = 25
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords $MaxRecords)
	if ($records.Count -eq 0)
	{
		return @()
	}

	$operationFilter = @($Operation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$terminalFilter = @($TerminalState | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })

	$entries = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($record in $records)
	{
		$recordKind = if ($record.PSObject.Properties['RecordKind']) { [string]$record.RecordKind } else { 'Target' }
		if ($recordKind -ne 'RunSummary')
		{
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($RunId) -and ([string]$record.RunId) -ne [string]$RunId) { continue }

		$recordOperation = if ($record.Operation) { [string]$record.Operation } else { 'Remote' }
		$recordTerminal = if ($record.PSObject.Properties['TerminalState']) { [string]$record.TerminalState } else { 'Unknown' }
		if ($operationFilter.Count -gt 0 -and $operationFilter -notcontains $recordOperation.Trim().ToLowerInvariant()) { continue }
		if ($terminalFilter.Count -gt 0 -and $terminalFilter -notcontains $recordTerminal.Trim().ToLowerInvariant()) { continue }

		$stamp = $null
		try { $stamp = [datetime]::Parse([string]$record.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteRunSummaries:catch1372' -Severity Debug }
		 $stamp = [datetime]::UtcNow }

		$entries.Add([pscustomobject]@{
			Timestamp        = $stamp
			RunId            = if ($record.PSObject.Properties['RunId']) { [string]$record.RunId } else { $null }
			Operation        = $recordOperation
			RecordKind       = if ($record.PSObject.Properties['RecordKind']) { [string]$record.RecordKind } else { 'RunSummary' }
			TerminalState    = $recordTerminal
			TargetState      = if ($record.PSObject.Properties['TargetState']) { [string]$record.TargetState } else { 'Unknown' }
			TargetCount      = if ($record.PSObject.Properties['TargetCount']) { [int]$record.TargetCount } else { 0 }
			SucceededCount   = if ($record.PSObject.Properties['SucceededCount']) { [int]$record.SucceededCount } else { 0 }
			FailedCount      = if ($record.PSObject.Properties['FailedCount']) { [int]$record.FailedCount } else { 0 }
			SkippedCount     = if ($record.PSObject.Properties['SkippedCount']) { [int]$record.SkippedCount } else { 0 }
			RetryingCount    = if ($record.PSObject.Properties['RetryingCount']) { [int]$record.RetryingCount } else { 0 }
			CancelledCount   = if ($record.PSObject.Properties['CancelledCount']) { [int]$record.CancelledCount } else { 0 }
			TotalAttempts    = if ($record.PSObject.Properties['TotalAttempts']) { [int]$record.TotalAttempts } else { 0 }
			TotalRetries     = if ($record.PSObject.Properties['TotalRetries']) { [int]$record.TotalRetries } else { 0 }
			HistoryPath      = if ($record.PSObject.Properties['HistoryPath']) { [string]$record.HistoryPath } else { $null }
			TerminalStateCounts = if ($record.PSObject.Properties['TerminalStateCounts']) { $record.TerminalStateCounts } else { $null }
			TargetStateCounts = if ($record.PSObject.Properties['TargetStateCounts']) { $record.TargetStateCounts } else { $null }
			Details          = if ($record.PSObject.Properties['Details']) { $record.Details } else { $null }
			Summary          = if ($record.PSObject.Properties['Summary']) { [string]$record.Summary } else { ('{0} | {1} | Run {2} | Target: {3} | Terminal: {4} | Targets: {5} | Success={6} | Failed={7} | Skipped={8} | Retrying={9} | Cancelled={10}' -f $stamp.ToString('yyyy-MM-dd HH:mm:ss'), $recordOperation, $record.RunId, $recordTargetState, $recordTerminal, ([int]$record.TargetCount), ([int]$record.SucceededCount), ([int]$record.FailedCount), ([int]$record.SkippedCount), ([int]$record.RetryingCount), ([int]$record.CancelledCount)) }
		})
	}

	return @($entries)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns the path to the per-target health tracking file.
#>

function Get-BaselineRemoteTargetHealthPath
{
	<# .SYNOPSIS Returns the path to target health tracking file. #>
	[CmdletBinding()]
	param ()

	$healthDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline')
	if (-not [System.IO.Directory]::Exists($healthDir))
	{
		[void][System.IO.Directory]::CreateDirectory($healthDir)
	}

	return [System.IO.Path]::Combine($healthDir, 'remote-target-health.json')
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Retrieves the last known health state for one or more remote targets.
#>

function Get-BaselineRemoteTargetHealth
{
	<# .SYNOPSIS Retrieves last known health for remote targets. #>
	[CmdletBinding()]
	param (
		[string[]]$ComputerName
	)

	$path = Get-BaselineRemoteTargetHealthPath
	if (-not [System.IO.File]::Exists($path))
	{
		return @()
	}

	$content = $null
	try
	{
		$content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
		$data = $content | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteTargetHealth:catch1449' -Severity Debug }

		return @()
	}

	$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$entries = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($entry in @($data.Targets))
	{
		if (-not $entry) { continue }
		$name = if ($entry.PSObject.Properties['ComputerName']) { [string]$entry.ComputerName } else { $null }
		if ([string]::IsNullOrWhiteSpace($name)) { continue }
		if ($targets.Count -gt 0 -and $targets -notcontains $name.Trim().ToLowerInvariant()) { continue }

		$entries.Add([pscustomobject]@{
			ComputerName           = [string]$name
			LastSeenUtc            = if ($entry.PSObject.Properties['LastSeenUtc']) { try { [datetime]::Parse([string]$entry.LastSeenUtc) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteTargetHealth:catch1465' -Severity Debug }
			 $null } } else { $null }
			LastStatus             = if ($entry.PSObject.Properties['LastStatus']) { [string]$entry.LastStatus } else { 'Unknown' }
			LastOperation          = if ($entry.PSObject.Properties['LastOperation']) { [string]$entry.LastOperation } else { $null }
			LastTerminalState      = if ($entry.PSObject.Properties['LastTerminalState']) { [string]$entry.LastTerminalState } else { 'Unknown' }
			LastFailureCategory    = if ($entry.PSObject.Properties['LastFailureCategory']) { [string]$entry.LastFailureCategory } else { $null }
			ConsecutiveFailures    = if ($entry.PSObject.Properties['ConsecutiveFailures']) { [int]$entry.ConsecutiveFailures } else { 0 }
			TotalSuccesses         = if ($entry.PSObject.Properties['TotalSuccesses']) { [int]$entry.TotalSuccesses } else { 0 }
			TotalFailures          = if ($entry.PSObject.Properties['TotalFailures']) { [int]$entry.TotalFailures } else { 0 }
			FailureCategoryCounts  = if ($entry.PSObject.Properties['FailureCategoryCounts']) { $entry.FailureCategoryCounts } else { [ordered]@{} }
			RecentFailureCategories = if ($entry.PSObject.Properties['RecentFailureCategories']) { @($entry.RecentFailureCategories) } else { @() }
			HealthScore            = if ($entry.PSObject.Properties['HealthScore']) { [double]$entry.HealthScore } else { 0 }
			HealthGrade            = if ($entry.PSObject.Properties['HealthGrade']) { [string]$entry.HealthGrade } else { 'Unknown' }
		})
	}

	return @($entries)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Updates the health tracking record for a remote target after an operation.
#>

function Update-BaselineRemoteTargetHealth
{
	<# .SYNOPSIS Updates health tracking for a remote target. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[Parameter(Mandatory)]
		[string]$Operation,

		[Parameter(Mandatory)]
		[string]$Status,

		[string]$TerminalState = 'Unknown',

		[string]$FailureCategory = $null
	)

	$path = Get-BaselineRemoteTargetHealthPath
	$data = $null
	if ([System.IO.File]::Exists($path))
	{
		try
		{
			$content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
			$data = $content | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Update-BaselineRemoteTargetHealth:catch1518' -Severity Debug }

			$data = $null
		}
	}

	if (-not $data)
	{
		$data = [pscustomobject]@{
			Version   = 1
			UpdatedUtc = [datetime]::UtcNow.ToString('o')
			Targets   = @()
		}
	}

	$computerKey = [string]$ComputerName.Trim().ToLowerInvariant()
	$existing = $null
	$targetIndex = -1
	for ($i = 0; $i -lt @($data.Targets).Count; $i++)
	{
		$t = $data.Targets[$i]
		if ($t -and $t.PSObject.Properties['ComputerName'])
		{
			if ([string]$t.ComputerName.Trim().ToLowerInvariant() -eq $computerKey)
			{
				$existing = $t
				$targetIndex = $i
				break
			}
		}
	}

	$now = [datetime]::UtcNow
	$isSuccess = $TerminalState -eq 'Succeeded' -or $Status -in @('Reachable', 'Compliant', 'Applied', 'Success')
	$isFailed = $TerminalState -eq 'Failed' -or $Status -in @('Failed', 'Unreachable', 'Drifted', 'Partial')

	if (-not $existing)
	{
		$existing = [pscustomobject]@{
			ComputerName           = $ComputerName
			LastSeenUtc            = $now.ToString('o')
			LastStatus             = $Status
			LastOperation          = $Operation
			LastTerminalState      = $TerminalState
			LastFailureCategory    = $FailureCategory
			ConsecutiveFailures    = 0
			TotalSuccesses         = 0
			TotalFailures          = 0
			FailureCategoryCounts  = [ordered]@{}
			RecentFailureCategories = @()
			HealthScore            = 100.0
			HealthGrade            = 'A'
		}
		$data.Targets = @($data.Targets) + @($existing)
		$targetIndex = @($data.Targets).Count - 1
	}
	else
	{
		$existing.LastSeenUtc = $now.ToString('o')
		$existing.LastStatus = $Status
		$existing.LastOperation = $Operation
		$existing.LastTerminalState = $TerminalState
		$existing.LastFailureCategory = $FailureCategory
	}

	if ($isSuccess)
	{
		$existing.ConsecutiveFailures = 0
		$existing.TotalSuccesses = [int]$existing.TotalSuccesses + 1
	}
	elseif ($isFailed)
	{
		$existing.ConsecutiveFailures = [int]$existing.ConsecutiveFailures + 1
		$existing.TotalFailures = [int]$existing.TotalFailures + 1
		if (-not [string]::IsNullOrWhiteSpace($FailureCategory))
		{
			$cats = $existing.FailureCategoryCounts
			if (-not $cats) { $cats = [ordered]@{} }
			if ($cats -is [pscustomobject])
			{
				$newCats = [ordered]@{}
				foreach ($prop in $cats.PSObject.Properties)
				{
					$newCats[$prop.Name] = [int]$prop.Value
				}
				$cats = $newCats
			}
			if (-not $cats.Contains($FailureCategory))
			{
				$cats[$FailureCategory] = 0
			}
			$cats[$FailureCategory] = [int]$cats[$FailureCategory] + 1
			$existing.FailureCategoryCounts = $cats

			$recent = @($existing.RecentFailureCategories)
			$recent = @($recent + $FailureCategory) | Select-Object -Last 10
			$existing.RecentFailureCategories = @($recent)
		}
	}

	# Calculate health score (0-100) based on success rate and consecutive failures
	$total = [int]$existing.TotalSuccesses + [int]$existing.TotalFailures
	if ($total -gt 0)
	{
		$successRate = [double]$existing.TotalSuccesses / [double]$total
		$consecutivePenalty = [math]::Min(50, [int]$existing.ConsecutiveFailures * 10)
		$score = [math]::Max(0, [math]::Min(100, ($successRate * 100) - $consecutivePenalty))
		$existing.HealthScore = [math]::Round($score, 1)
	}
	else
	{
		$existing.HealthScore = 100.0
	}

	# Assign grade based on score
	$grade = switch ([int]$existing.HealthScore)
	{
		{ $_ -ge 90 } { 'A' }
		{ $_ -ge 80 } { 'B' }
		{ $_ -ge 70 } { 'C' }
		{ $_ -ge 60 } { 'D' }
		default { 'F' }
	}
	$existing.HealthGrade = $grade

	$data.UpdatedUtc = $now.ToString('o')
	$json = ConvertTo-Json -InputObject $data -Depth 10
	[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

	return [pscustomobject]@{
		ComputerName        = $existing.ComputerName
		HealthScore         = $existing.HealthScore
		HealthGrade         = $existing.HealthGrade
		ConsecutiveFailures = $existing.ConsecutiveFailures
		TotalSuccesses      = $existing.TotalSuccesses
		TotalFailures       = $existing.TotalFailures
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Retrieves aggregated failure history for a target across orchestration runs.
#>

function Get-BaselineRemoteTargetFailureHistory
{
	<# .SYNOPSIS Retrieves failure history aggregated by target. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ComputerName,

		[int]$MaxRecords = 50,

		[datetime]$Since
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords ($MaxRecords * 5) -ComputerName $ComputerName)
	if ($records.Count -eq 0)
	{
		return [pscustomobject]@{
			ComputerName          = $ComputerName
			TotalRecords          = 0
			FailedRecords         = 0
			SuccessRate           = 0
			FailureCategoryCounts = [ordered]@{}
			RecentFailures        = @()
			MostCommonCategory    = $null
		}
	}

	$filtered = $records
	if ($PSBoundParameters.ContainsKey('Since'))
	{
		$filtered = @($records | Where-Object {
			$ts = $null
			try { $ts = [datetime]::Parse([string]$_.Timestamp) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteOrchestrationSummary.SinceTimestampParse'; $ts = $null }
			$ts -and $ts -ge $Since
		})
	}

	$failed = @($filtered | Where-Object {
		$term = if ($_.PSObject.Properties['TerminalState']) { [string]$_.TerminalState } else { 'Unknown' }
		$term -eq 'Failed'
	})

	$categories = [ordered]@{}
	$recentFailures = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($record in @($failed | Select-Object -First $MaxRecords))
	{
		$cat = if ($record.PSObject.Properties['FailureCategory']) { [string]$record.FailureCategory } else { 'Unknown' }
		if (-not $categories.Contains($cat))
		{
			$categories[$cat] = 0
		}
		$categories[$cat]++

		$ts = $null
		try { $ts = [datetime]::Parse([string]$record.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteTargetFailureHistory:catch1718' -Severity Debug }
		 $ts = [datetime]::UtcNow }
		$recentFailures.Add([pscustomobject]@{
			Timestamp       = $ts
			Operation       = if ($record.Operation) { [string]$record.Operation } else { 'Unknown' }
			Status          = if ($record.Status) { [string]$record.Status } else { 'Unknown' }
			FailureCategory = $cat
			RunId           = if ($record.RunId) { [string]$record.RunId } else { $null }
			Errors          = if ($record.Errors) { @($record.Errors) } else { @() }
		})
	}

	$mostCommon = $null
	$maxCount = 0
	foreach ($key in $categories.Keys)
	{
		if ($categories[$key] -gt $maxCount)
		{
			$maxCount = $categories[$key]
			$mostCommon = $key
		}
	}

	$successRate = 0
	if ($filtered.Count -gt 0)
	{
		$successRate = [math]::Round((($filtered.Count - $failed.Count) / $filtered.Count) * 100, 1)
	}

	return [pscustomobject]@{
		ComputerName          = $ComputerName
		TotalRecords          = $filtered.Count
		FailedRecords         = $failed.Count
		SuccessRate           = $successRate
		FailureCategoryCounts = $categories
		RecentFailures        = @($recentFailures)
		MostCommonCategory    = $mostCommon
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns the path to the approval decision tracking file.
#>

function Get-BaselineRemoteApprovalDecisionPath
{
	<# .SYNOPSIS Returns the path to approval decision tracking file. #>
	[CmdletBinding()]
	param ()

	$dir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline')
	if (-not [System.IO.Directory]::Exists($dir))
	{
		[void][System.IO.Directory]::CreateDirectory($dir)
	}

	return [System.IO.Path]::Combine($dir, 'remote-approval-decisions.jsonl')
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Records an approval decision for audit and tracking purposes.
#>

function Write-BaselineRemoteApprovalDecision
{
	<# .SYNOPSIS Records an approval decision to the audit trail. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$RunId,

		[Parameter(Mandatory)]
		[ValidateSet('Approved', 'Rejected', 'Deferred', 'AutoApproved')]
		[string]$Decision,

		[string]$Operation = 'RemoteApply',

		[string[]]$ComputerNames = @(),

		[string]$ApprovedBy = $null,

		[string]$Reason = $null,

		[hashtable]$Context = @{}
	)

	$path = Get-BaselineRemoteApprovalDecisionPath
	$payload = [ordered]@{
		RecordedUtc   = [datetime]::UtcNow.ToString('o')
		RunId         = [string]$RunId
		Operation     = [string]$Operation
		Decision      = [string]$Decision
		ComputerNames = @($ComputerNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
		TargetCount   = @($ComputerNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
		ApprovedBy    = if ([string]::IsNullOrWhiteSpace($ApprovedBy)) { [System.Environment]::UserName } else { $ApprovedBy }
		Reason        = $Reason
		Context       = $Context
	}

	$json = ConvertTo-Json -InputObject $payload -Compress -Depth 8
	[System.IO.File]::AppendAllText($path, "$json`n", [System.Text.UTF8Encoding]::new($false))

	return [pscustomobject]$payload
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Retrieves approval decision history with optional filters.
#>

function Get-BaselineRemoteApprovalDecisions
{
	<# .SYNOPSIS Retrieves approval decision history. #>
	[CmdletBinding()]
	param (
		[string]$RunId,

		[string[]]$Decision,

		[string]$Operation,

		[datetime]$Since,

		[int]$MaxRecords = 50
	)

	$path = Get-BaselineRemoteApprovalDecisionPath
	if (-not [System.IO.File]::Exists($path))
	{
		return @()
	}

	$records = [System.Collections.Generic.List[pscustomobject]]::new()
	$lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
	foreach ($line in $lines)
	{
		if ([string]::IsNullOrWhiteSpace($line)) { continue }

		$obj = $null
		try { $obj = $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteRunSummaries.ParseLine'; continue }
		if (-not $obj) { continue }

		if (-not [string]::IsNullOrWhiteSpace($RunId) -and [string]$obj.RunId -ne $RunId) { continue }
		if (-not [string]::IsNullOrWhiteSpace($Operation) -and [string]$obj.Operation -ne $Operation) { continue }
		if ($Decision -and $Decision.Count -gt 0 -and $Decision -notcontains [string]$obj.Decision) { continue }

		if ($PSBoundParameters.ContainsKey('Since') -and $obj.RecordedUtc)
		{
			$ts = $null
			try { $ts = [datetime]::Parse([string]$obj.RecordedUtc) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteRunSummaries.SinceTimestampParse'; $ts = $null }
			if ($ts -and $ts -lt $Since) { continue }
		}

		$records.Add([pscustomobject]@{
			RecordedUtc   = if ($obj.RecordedUtc) { try { [datetime]::Parse([string]$obj.RecordedUtc) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteApprovalDecisions:catch1879' -Severity Debug }
			 [datetime]::UtcNow } } else { [datetime]::UtcNow }
			RunId         = if ($obj.RunId) { [string]$obj.RunId } else { $null }
			Operation     = if ($obj.Operation) { [string]$obj.Operation } else { 'Unknown' }
			Decision      = if ($obj.Decision) { [string]$obj.Decision } else { 'Unknown' }
			ComputerNames = if ($obj.ComputerNames) { @($obj.ComputerNames) } else { @() }
			TargetCount   = if ($obj.TargetCount) { [int]$obj.TargetCount } else { 0 }
			ApprovedBy    = if ($obj.ApprovedBy) { [string]$obj.ApprovedBy } else { $null }
			Reason        = if ($obj.Reason) { [string]$obj.Reason } else { $null }
			Context       = if ($obj.Context) { $obj.Context } else { @{} }
		})
	}

	$ordered = @($records | Sort-Object -Property RecordedUtc -Descending)
	if ($MaxRecords -gt 0)
	{
		$ordered = @($ordered | Select-Object -First $MaxRecords)
	}

	return @($ordered)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Records a rollout outcome for tracking and dashboard surfaces.
#>

function Write-BaselineRemoteRolloutOutcome
{
	<# .SYNOPSIS Records a rollout outcome to the audit trail. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$RunId,

		[Parameter(Mandatory)]
		[string]$Operation,

		[Parameter(Mandatory)]
		[ValidateSet('Succeeded', 'PartialSuccess', 'Failed', 'Cancelled', 'Aborted')]
		[string]$Outcome,

		[int]$TargetCount = 0,

		[int]$SucceededCount = 0,

		[int]$FailedCount = 0,

		[int]$SkippedCount = 0,

		[int]$CancelledCount = 0,

		[datetime]$StartedUtc = [datetime]::UtcNow,

		[datetime]$CompletedUtc = [datetime]::UtcNow,

		[object]$ArtifactVerification = $null,

		[hashtable]$Details = @{}
	)

	$path = Get-BaselineRemoteOrchestrationHistoryPath
	$payload = [ordered]@{
		RecordKind      = 'RolloutOutcome'
		RecordedUtc     = [datetime]::UtcNow.ToString('o')
		RunId           = [string]$RunId
		Operation       = [string]$Operation
		Outcome         = [string]$Outcome
		TargetCount     = $TargetCount
		SucceededCount  = $SucceededCount
		FailedCount     = $FailedCount
		SkippedCount    = $SkippedCount
		CancelledCount  = $CancelledCount
		StartedUtc      = $StartedUtc.ToUniversalTime().ToString('o')
		CompletedUtc    = $CompletedUtc.ToUniversalTime().ToString('o')
		DurationSeconds = [math]::Round(($CompletedUtc - $StartedUtc).TotalSeconds, 2)
		Details         = $Details
	}

	if ($ArtifactVerification)
	{
		$payload['ArtifactVerificationState'] = if ($ArtifactVerification.PSObject.Properties['VerificationState']) { [string]$ArtifactVerification.VerificationState } else { $null }
		$payload['ArtifactVerificationMessage'] = if ($ArtifactVerification.PSObject.Properties['VerificationMessage']) { [string]$ArtifactVerification.VerificationMessage } else { $null }
		$payload['ArtifactHashAlgorithm'] = if ($ArtifactVerification.PSObject.Properties['HashAlgorithm']) { [string]$ArtifactVerification.HashAlgorithm } else { $null }
		$payload['ArtifactFileHash'] = if ($ArtifactVerification.PSObject.Properties['FileHash']) { [string]$ArtifactVerification.FileHash } else { $null }
		$payload['ArtifactSignatureStatus'] = if ($ArtifactVerification.PSObject.Properties['SignatureStatus']) { [string]$ArtifactVerification.SignatureStatus } else { $null }
		$payload['ArtifactSignerSubject'] = if ($ArtifactVerification.PSObject.Properties['SignerSubject']) { [string]$ArtifactVerification.SignerSubject } else { $null }
		$payload['ArtifactTimestampStatus'] = if ($ArtifactVerification.PSObject.Properties['TimestampStatus']) { [string]$ArtifactVerification.TimestampStatus } else { $null }
		$payload['ArtifactTimestampSubject'] = if ($ArtifactVerification.PSObject.Properties['TimestampSubject']) { [string]$ArtifactVerification.TimestampSubject } else { $null }
		$payload['ArtifactVerificationAt'] = if ($ArtifactVerification.PSObject.Properties['VerificationAt']) { [string]$ArtifactVerification.VerificationAt } else { $null }
		if (-not $payload.Contains('Details') -or $null -eq $payload['Details'])
		{
			$payload['Details'] = [ordered]@{}
		}
		$payload['Details']['ArtifactVerification'] = $ArtifactVerification
	}

	$json = ConvertTo-Json -InputObject $payload -Compress -Depth 8
	[System.IO.File]::AppendAllText($path, "$json`n", [System.Text.UTF8Encoding]::new($false))

	return [pscustomobject]$payload
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Retrieves rollout outcomes for dashboard and reporting surfaces.
#>

function Get-BaselineRemoteRolloutOutcomes
{
	<# .SYNOPSIS Retrieves rollout outcome history. #>
	[CmdletBinding()]
	param (
		[string]$RunId,

		[string[]]$Outcome,

		[string]$Operation,

		[datetime]$Since,

		[int]$MaxRecords = 25
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords ($MaxRecords * 3) -RecordKind 'RolloutOutcome')
	$filtered = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($record in $records)
	{
		if (-not [string]::IsNullOrWhiteSpace($RunId) -and [string]$record.RunId -ne $RunId) { continue }
		if (-not [string]::IsNullOrWhiteSpace($Operation) -and [string]$record.Operation -ne $Operation) { continue }
		if ($Outcome -and $Outcome.Count -gt 0 -and $Outcome -notcontains [string]$record.Outcome) { continue }

		if ($PSBoundParameters.ContainsKey('Since') -and $record.RecordedUtc)
		{
			$ts = $null
			try { $ts = [datetime]::Parse([string]$record.RecordedUtc) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteRolloutOutcomes:catch2018' -Severity Debug }
			 $ts = $null }
			if ($ts -and $ts -lt $Since) { continue }
		}

		$filtered.Add([pscustomobject]@{
			RecordedUtc     = if ($record.RecordedUtc) { try { [datetime]::Parse([string]$record.RecordedUtc) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteRolloutOutcomes:catch2023' -Severity Debug }
			 [datetime]::UtcNow } } else { [datetime]::UtcNow }
			RunId           = if ($record.RunId) { [string]$record.RunId } else { $null }
			Operation       = if ($record.Operation) { [string]$record.Operation } else { 'Unknown' }
			Outcome         = if ($record.Outcome) { [string]$record.Outcome } else { 'Unknown' }
			TargetCount     = if ($record.TargetCount) { [int]$record.TargetCount } else { 0 }
			SucceededCount  = if ($record.SucceededCount) { [int]$record.SucceededCount } else { 0 }
			FailedCount     = if ($record.FailedCount) { [int]$record.FailedCount } else { 0 }
			SkippedCount    = if ($record.SkippedCount) { [int]$record.SkippedCount } else { 0 }
			CancelledCount  = if ($record.CancelledCount) { [int]$record.CancelledCount } else { 0 }
			DurationSeconds = if ($record.DurationSeconds) { [double]$record.DurationSeconds } else { 0 }
			Details         = if ($record.Details) { $record.Details } else { @{} }
			ArtifactVerificationState = if ($record.PSObject.Properties['ArtifactVerificationState']) { [string]$record.ArtifactVerificationState } else { $null }
			ArtifactVerificationMessage = if ($record.PSObject.Properties['ArtifactVerificationMessage']) { [string]$record.ArtifactVerificationMessage } else { $null }
			ArtifactHashAlgorithm = if ($record.PSObject.Properties['ArtifactHashAlgorithm']) { [string]$record.ArtifactHashAlgorithm } else { $null }
			ArtifactFileHash    = if ($record.PSObject.Properties['ArtifactFileHash']) { [string]$record.ArtifactFileHash } else { $null }
			ArtifactSignatureStatus = if ($record.PSObject.Properties['ArtifactSignatureStatus']) { [string]$record.ArtifactSignatureStatus } else { $null }
			ArtifactSignerSubject = if ($record.PSObject.Properties['ArtifactSignerSubject']) { [string]$record.ArtifactSignerSubject } else { $null }
			ArtifactTimestampStatus = if ($record.PSObject.Properties['ArtifactTimestampStatus']) { [string]$record.ArtifactTimestampStatus } else { $null }
			ArtifactTimestampSubject = if ($record.PSObject.Properties['ArtifactTimestampSubject']) { [string]$record.ArtifactTimestampSubject } else { $null }
			ArtifactVerificationAt = if ($record.PSObject.Properties['ArtifactVerificationAt']) { [string]$record.ArtifactVerificationAt } else { $null }
		})

		if ($filtered.Count -ge $MaxRecords) { break }
	}

	return @($filtered)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns aggregated dashboard data over orchestration history.
#>

function Get-BaselineRemoteOrchestrationDashboard
{
	<# .SYNOPSIS Returns aggregated dashboard data for remote orchestration. #>
	[CmdletBinding()]
	param (
		[int]$DaysBack = 7,

		[string[]]$Operation
	)

	$since = [datetime]::UtcNow.AddDays(-$DaysBack)
	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords 1000 -Since $since)

	$operationFilter = @($Operation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })

	$targetRecords = @($records | Where-Object {
		$kind = if ($_.PSObject.Properties['RecordKind']) { [string]$_.RecordKind } else { 'Target' }
		$kind -eq 'Target'
	})

	if ($operationFilter.Count -gt 0)
	{
		$targetRecords = @($targetRecords | Where-Object {
			$op = if ($_.Operation) { [string]$_.Operation.Trim().ToLowerInvariant() } else { 'unknown' }
			$operationFilter -contains $op
		})
	}

	$runRecords = @($records | Where-Object {
		$kind = if ($_.PSObject.Properties['RecordKind']) { [string]$_.RecordKind } else { 'Target' }
		$kind -eq 'RunSummary'
	})

	$rolloutRecords = @($records | Where-Object {
		$kind = if ($_.PSObject.Properties['RecordKind']) { [string]$_.RecordKind } else { 'Target' }
		$kind -eq 'RolloutOutcome'
	})

	# Aggregate by operation
	$opStats = [ordered]@{}
	foreach ($rec in $targetRecords)
	{
		$op = if ($rec.Operation) { [string]$rec.Operation } else { 'Unknown' }
		if (-not $opStats.Contains($op))
		{
			$opStats[$op] = [ordered]@{
				Total     = 0
				Succeeded = 0
				Failed    = 0
				Skipped   = 0
				Retrying  = 0
				Cancelled = 0
			}
		}
		$opStats[$op].Total++
		$term = if ($rec.PSObject.Properties['TerminalState']) { [string]$rec.TerminalState } else { 'Unknown' }
		switch ($term)
		{
			'Succeeded' { $opStats[$op].Succeeded++ }
			'Failed' { $opStats[$op].Failed++ }
			'Skipped' { $opStats[$op].Skipped++ }
			'Retrying' { $opStats[$op].Retrying++ }
			'Cancelled' { $opStats[$op].Cancelled++ }
		}
	}

	# Aggregate failure categories
	$failureCats = [ordered]@{}
	foreach ($rec in $targetRecords)
	{
		$term = if ($rec.PSObject.Properties['TerminalState']) { [string]$rec.TerminalState } else { 'Unknown' }
		if ($term -ne 'Failed') { continue }
		$cat = if ($rec.PSObject.Properties['FailureCategory']) { [string]$rec.FailureCategory } else { 'Unknown' }
		if (-not $failureCats.Contains($cat))
		{
			$failureCats[$cat] = 0
		}
		$failureCats[$cat]++
	}

	# Aggregate by target
	$targetStats = [ordered]@{}
	foreach ($rec in $targetRecords)
	{
		$comp = if ($rec.ComputerName) { [string]$rec.ComputerName } else { 'Unknown' }
		if (-not $targetStats.Contains($comp))
		{
			$targetStats[$comp] = [ordered]@{
				Total     = 0
				Succeeded = 0
				Failed    = 0
				LastSeen  = $null
				LastState = 'Unknown'
			}
		}
		$targetStats[$comp].Total++
		$term = if ($rec.PSObject.Properties['TerminalState']) { [string]$rec.TerminalState } else { 'Unknown' }
		if ($term -eq 'Succeeded') { $targetStats[$comp].Succeeded++ }
		elseif ($term -eq 'Failed') { $targetStats[$comp].Failed++ }

		$ts = $null
		try { $ts = [datetime]::Parse([string]$rec.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteOrchestrationDashboard:catch2159' -Severity Debug }
		 $ts = $null }
		if ($ts -and (-not $targetStats[$comp].LastSeen -or $ts -gt $targetStats[$comp].LastSeen))
		{
			$targetStats[$comp].LastSeen = $ts
			$targetStats[$comp].LastState = $term
		}
	}

	# Calculate totals
	$totalTargetOps = $targetRecords.Count
	$totalSucceeded = @($targetRecords | Where-Object { $_.PSObject.Properties['TerminalState'] -and [string]$_.TerminalState -eq 'Succeeded' }).Count
	$totalFailed = @($targetRecords | Where-Object { $_.PSObject.Properties['TerminalState'] -and [string]$_.TerminalState -eq 'Failed' }).Count
	$successRate = if ($totalTargetOps -gt 0) { [math]::Round(($totalSucceeded / $totalTargetOps) * 100, 1) } else { 0 }

	# Calculate trends (compare this half vs previous half of the window)
	$midpoint = $since.AddDays($DaysBack / 2)
	$recentRecords = @($targetRecords | Where-Object {
		$ts = $null
		try { $ts = [datetime]::Parse([string]$_.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteOrchestrationDashboard:catch2177' -Severity Debug }
		 $ts = $null }
		$ts -and $ts -ge $midpoint
	})
	$olderRecords = @($targetRecords | Where-Object {
		$ts = $null
		try { $ts = [datetime]::Parse([string]$_.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteOrchestrationDashboard:catch2182' -Severity Debug }
		 $ts = $null }
		$ts -and $ts -lt $midpoint
	})

	$recentSuccessRate = 0
	$olderSuccessRate = 0
	if ($recentRecords.Count -gt 0)
	{
		$recentSucceeded = @($recentRecords | Where-Object { $_.PSObject.Properties['TerminalState'] -and [string]$_.TerminalState -eq 'Succeeded' }).Count
		$recentSuccessRate = [math]::Round(($recentSucceeded / $recentRecords.Count) * 100, 1)
	}
	if ($olderRecords.Count -gt 0)
	{
		$olderSucceeded = @($olderRecords | Where-Object { $_.PSObject.Properties['TerminalState'] -and [string]$_.TerminalState -eq 'Succeeded' }).Count
		$olderSuccessRate = [math]::Round(($olderSucceeded / $olderRecords.Count) * 100, 1)
	}

	$trend = 'Stable'
	if ($recentSuccessRate -gt ($olderSuccessRate + 5)) { $trend = 'Improving' }
	elseif ($recentSuccessRate -lt ($olderSuccessRate - 5)) { $trend = 'Declining' }

	return [pscustomobject]@{
		PeriodDays           = $DaysBack
		SinceUtc             = $since
		GeneratedUtc         = [datetime]::UtcNow
		TotalTargetOps       = $totalTargetOps
		TotalSucceeded       = $totalSucceeded
		TotalFailed          = $totalFailed
		SuccessRate          = $successRate
		Trend                = $trend
		RecentSuccessRate    = $recentSuccessRate
		OlderSuccessRate     = $olderSuccessRate
		TotalRuns            = $runRecords.Count
		TotalRollouts        = $rolloutRecords.Count
		UniqueTargets        = $targetStats.Keys.Count
		OperationStats       = $opStats
		FailureCategories    = $failureCats
		TargetStats          = $targetStats
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Provides flexible search over orchestration history with multiple filter criteria.
#>

function Search-BaselineRemoteOrchestrationHistory
{
	<# .SYNOPSIS Searches orchestration history with multiple filters. #>
	[CmdletBinding()]
	param (
		[string[]]$ComputerName,

		[string[]]$Operation,

		[string[]]$Status,

		[string[]]$TerminalState,

		[string[]]$FailureCategory,

		[string[]]$RecordKind,

		[string]$RunId,

		[datetime]$Since,

		[datetime]$Until,

		[int]$MaxRecords = 100,

		[ValidateSet('Timestamp', 'ComputerName', 'Operation', 'Status')]
		[string]$SortBy = 'Timestamp',

		[switch]$Descending
	)

	$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords ($MaxRecords * 3))

	$computerFilter = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$operationFilter = @($Operation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$statusFilter = @($Status | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$terminalFilter = @($TerminalState | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$categoryFilter = @($FailureCategory | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$kindFilter = @($RecordKind | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })

	$results = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($rec in $records)
	{
		$ts = $null
		try { $ts = [datetime]::Parse([string]$rec.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Search-BaselineRemoteOrchestrationHistory:catch2274' -Severity Debug }
		 $ts = [datetime]::UtcNow }

		if ($PSBoundParameters.ContainsKey('Since') -and $ts -lt $Since) { continue }
		if ($PSBoundParameters.ContainsKey('Until') -and $ts -gt $Until) { continue }
		if (-not [string]::IsNullOrWhiteSpace($RunId) -and [string]$rec.RunId -ne $RunId) { continue }

		$recComputer = if ($rec.ComputerName) { [string]$rec.ComputerName.Trim().ToLowerInvariant() } else { 'unknown' }
		$recOp = if ($rec.Operation) { [string]$rec.Operation.Trim().ToLowerInvariant() } else { 'unknown' }
		$recStatus = if ($rec.Status) { [string]$rec.Status.Trim().ToLowerInvariant() } else { 'unknown' }
		$recTerminal = if ($rec.PSObject.Properties['TerminalState']) { [string]$rec.TerminalState.Trim().ToLowerInvariant() } else { 'unknown' }
		$recCategory = if ($rec.PSObject.Properties['FailureCategory']) { [string]$rec.FailureCategory.Trim().ToLowerInvariant() } else { 'unknown' }
		$recKind = if ($rec.PSObject.Properties['RecordKind']) { [string]$rec.RecordKind.Trim().ToLowerInvariant() } else { 'target' }

		if ($computerFilter.Count -gt 0 -and $computerFilter -notcontains $recComputer) { continue }
		if ($operationFilter.Count -gt 0 -and $operationFilter -notcontains $recOp) { continue }
		if ($statusFilter.Count -gt 0 -and $statusFilter -notcontains $recStatus) { continue }
		if ($terminalFilter.Count -gt 0 -and $terminalFilter -notcontains $recTerminal) { continue }
		if ($categoryFilter.Count -gt 0 -and $categoryFilter -notcontains $recCategory) { continue }
		if ($kindFilter.Count -gt 0 -and $kindFilter -notcontains $recKind) { continue }

		$results.Add([pscustomobject]@{
			Timestamp       = $ts
			ComputerName    = if ($rec.ComputerName) { [string]$rec.ComputerName } else { $null }
			Operation       = if ($rec.Operation) { [string]$rec.Operation } else { 'Unknown' }
			Status          = if ($rec.Status) { [string]$rec.Status } else { 'Unknown' }
			TerminalState   = if ($rec.PSObject.Properties['TerminalState']) { [string]$rec.TerminalState } else { 'Unknown' }
			FailureCategory = if ($rec.PSObject.Properties['FailureCategory']) { [string]$rec.FailureCategory } else { $null }
			RecordKind      = if ($rec.PSObject.Properties['RecordKind']) { [string]$rec.RecordKind } else { 'Target' }
			RunId           = if ($rec.RunId) { [string]$rec.RunId } else { $null }
			AttemptCount    = if ($rec.PSObject.Properties['AttemptCount']) { [int]$rec.AttemptCount } else { 1 }
			RetryCount      = if ($rec.PSObject.Properties['RetryCount']) { [int]$rec.RetryCount } else { 0 }
			DurationSeconds = if ($rec.PSObject.Properties['DurationSeconds']) { [double]$rec.DurationSeconds } else { 0 }
			Errors          = if ($rec.Errors) { @($rec.Errors) } else { @() }
		})

		if ($results.Count -ge $MaxRecords) { break }
	}

	$sorted = switch ($SortBy)
	{
		'ComputerName' { $results | Sort-Object -Property ComputerName -Descending:$Descending }
		'Operation' { $results | Sort-Object -Property Operation -Descending:$Descending }
		'Status' { $results | Sort-Object -Property Status -Descending:$Descending }
		default { $results | Sort-Object -Property Timestamp -Descending:(-not $Descending) }
	}

	return @($sorted)
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteTargetLifecycleState
{
	<# .SYNOPSIS Maps remote orchestration status into a lifecycle state. #>
	[CmdletBinding()]
	param (
		[string]$Operation,
		[string]$Status,
		[bool]$Retryable = $false,
		[bool]$Blocked = $false
	)

	if ($Blocked) { return 'BlockedByPolicy' }
	if ([string]::IsNullOrWhiteSpace($Status)) { return 'Pending' }

	switch ([string]$Status)
	{
		'Reachable' { return 'Connected' }
		'Applied' { return 'Succeeded' }
		'Compliant' { return 'Succeeded' }
		'Drifted' { return 'PartiallySucceeded' }
		'Partial' { return 'PartiallySucceeded' }
		'Failed'
		{
			if ($Retryable) { return 'RetryableFailure' }
			return 'Failed'
		}
		'Unreachable'
		{
			if ($Retryable) { return 'RetryableFailure' }
			return 'Failed'
		}
		'Blocked' { return 'BlockedByPolicy' }
		'Cancelled' { return 'Cancelled' }
		default
		{
			if (-not [string]::IsNullOrWhiteSpace($Operation))
			{
				switch ([string]$Operation)
				{
					'ConnectivityTest'
					{
						if ($Status -eq 'Reachable') { return 'Connected' }
						return 'RetryableFailure'
					}
					'RemoteCompliance'
					{
						if ($Status -eq 'Compliant') { return 'Succeeded' }
						if ($Status -eq 'Drifted') { return 'PartiallySucceeded' }
						return 'Failed'
					}
					'RemoteApply'
					{
						if ($Status -eq 'Applied') { return 'Succeeded' }
						if ($Status -eq 'Partial') { return 'PartiallySucceeded' }
						return 'Failed'
					}
				}
			}
			if ($Retryable) { return 'RetryableFailure' }
			return 'Failed'
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteOrchestrationReconciliation
{
	<# .SYNOPSIS Summarizes remote orchestration results across runs or targets. #>
	[CmdletBinding()]
	param (
		[object[]]$Records = @()
	)

	$items = @($Records | Where-Object { $null -ne $_ })
	$summary = [ordered]@{
		Total = $items.Count
		Succeeded = 0
		PartiallySucceeded = 0
		Failed = 0
		RetryableFailures = 0
		Blocked = 0
		SucceededCount = 0
		FailedCount = 0
		SkippedCount = 0
		RetryingCount = 0
		CancelledCount = 0
		TotalAttempts = 0
		TotalRetries = 0
		FailureCategoryCounts = [ordered]@{
			Success       = 0
			Connectivity  = 0
			Authentication = 0
			Policy        = 0
			Execution     = 0
			Compliance    = 0
			Partial       = 0
			Unknown       = 0
		}
		TargetStateCounts = [ordered]@{
			Pending = 0
			Connecting = 0
			Connected = 0
			PreflightFailed = 0
			PreviewReady = 0
			Running = 0
			Succeeded = 0
			Failed = 0
			Cancelled = 0
			RequiresReview = 0
		}
		TerminalStateCounts = [ordered]@{
			Succeeded = 0
			Failed = 0
			Skipped = 0
			Retrying = 0
			Cancelled = 0
		}
		Operations = @{}
	}

	foreach ($item in $items)
	{
		$status = if ($item.PSObject.Properties['Status']) { [string]$item.Status } else { 'Unknown' }
		$attempts = if ($item.PSObject.Properties['AttemptCount']) { [int]$item.AttemptCount } else { 1 }
		$retries = if ($item.PSObject.Properties['RetryCount']) { [int]$item.RetryCount } else { 0 }
		$failureCategory = if ($item.PSObject.Properties['FailureCategory']) { [string]$item.FailureCategory } else { 'Unknown' }
		$retryable = if ($item.PSObject.Properties['Retryable']) { [bool]$item.Retryable } else { $false }
		$blockedByPolicy = if ($item.PSObject.Properties['BlockedByPolicy']) { [bool]$item.BlockedByPolicy } else { $false }
		$cancelled = $false
		if ($item.PSObject.Properties['TerminalState'])
		{
			$cancelled = [string]$item.TerminalState -eq 'Cancelled'
		}
		$summary.TotalAttempts += [math]::Max(1, $attempts)
		$summary.TotalRetries += [math]::Max(0, $retries)
		if ($summary.FailureCategoryCounts.Contains($failureCategory))
		{
			$summary.FailureCategoryCounts[$failureCategory]++
		}
		else
		{
			$summary.FailureCategoryCounts['Unknown']++
		}
		$lifecycle = if ($item.PSObject.Properties['LifecycleState']) { [string]$item.LifecycleState } else { Get-BaselineRemoteTargetLifecycleState -Operation ([string]$item.Operation) -Status $status -Retryable $retryable -Blocked $blockedByPolicy }
		$targetState = if ($item.PSObject.Properties['TargetState']) { [string]$item.TargetState } else { Get-BaselineRemoteTargetState -Operation ([string]$item.Operation) -Status $status -Retryable $retryable -Blocked $blockedByPolicy -Cancelled $cancelled }
		$terminalState = if ($item.PSObject.Properties['TerminalState']) { [string]$item.TerminalState } else { Get-BaselineRemoteTargetTerminalState -Status $status -Retryable $retryable -Blocked $blockedByPolicy }
		switch ($lifecycle)
		{
			'Succeeded' { $summary.Succeeded++ }
			'PartiallySucceeded' { $summary.PartiallySucceeded++ }
			'RetryableFailure' { $summary.RetryableFailures++ }
			'BlockedByPolicy' { $summary.Blocked++ }
			default { $summary.Failed++ }
		}

		switch ($targetState)
		{
			'Pending' { $summary.TargetStateCounts['Pending']++ }
			'Connecting' { $summary.TargetStateCounts['Connecting']++ }
			'Connected' { $summary.TargetStateCounts['Connected']++ }
			'PreflightFailed' { $summary.TargetStateCounts['PreflightFailed']++ }
			'PreviewReady' { $summary.TargetStateCounts['PreviewReady']++ }
			'Running' { $summary.TargetStateCounts['Running']++ }
			'Succeeded' { $summary.TargetStateCounts['Succeeded']++ }
			'Failed' { $summary.TargetStateCounts['Failed']++ }
			'Cancelled' { $summary.TargetStateCounts['Cancelled']++ }
			'RequiresReview' { $summary.TargetStateCounts['RequiresReview']++ }
		}

		switch ($terminalState)
		{
			'Succeeded' { $summary.SucceededCount++; $summary.TerminalStateCounts['Succeeded']++ }
			'Skipped' { $summary.SkippedCount++; $summary.TerminalStateCounts['Skipped']++ }
			'Retrying' { $summary.RetryingCount++; $summary.TerminalStateCounts['Retrying']++ }
			'Cancelled' { $summary.CancelledCount++; $summary.TerminalStateCounts['Cancelled']++ }
			default { $summary.FailedCount++; $summary.TerminalStateCounts['Failed']++ }
		}

		$op = if ($item.PSObject.Properties['Operation']) { [string]$item.Operation } else { 'Unknown' }
		if (-not $summary.Operations.Contains($op))
		{
			$summary.Operations[$op] = [ordered]@{ Total = 0; Succeeded = 0; Failed = 0; RetryableFailures = 0; PartiallySucceeded = 0; Blocked = 0; Attempts = 0; Retries = 0; Skipped = 0; Retrying = 0; Cancelled = 0; TerminalSucceeded = 0; TerminalFailed = 0; TerminalSkipped = 0; TerminalRetrying = 0; TerminalCancelled = 0 }
		}
		$summary.Operations[$op].Total++
		$summary.Operations[$op].Attempts += [math]::Max(1, $attempts)
		$summary.Operations[$op].Retries += [math]::Max(0, $retries)
		switch ($lifecycle)
		{
			'Succeeded' { $summary.Operations[$op].Succeeded++ }
			'PartiallySucceeded' { $summary.Operations[$op].PartiallySucceeded++ }
			'RetryableFailure' { $summary.Operations[$op].RetryableFailures++ }
			'BlockedByPolicy' { $summary.Operations[$op].Blocked++ }
			default { $summary.Operations[$op].Failed++ }
		}
		switch ($terminalState)
		{
			'Succeeded' { $summary.Operations[$op].TerminalSucceeded++ }
			'Skipped' { $summary.Operations[$op].TerminalSkipped++ }
			'Retrying' { $summary.Operations[$op].TerminalRetrying++ }
			'Cancelled' { $summary.Operations[$op].TerminalCancelled++ }
			default { $summary.Operations[$op].TerminalFailed++ }
		}
	}

	if ($summary.CancelledCount -gt 0)
	{
		$summary.TerminalState = 'Cancelled'
	}
	elseif ($summary.FailedCount -gt 0)
	{
		$summary.TerminalState = 'Failed'
	}
	elseif ($summary.RetryingCount -gt 0)
	{
		$summary.TerminalState = 'Retrying'
	}
	elseif ($summary.SkippedCount -gt 0 -and $summary.SucceededCount -eq 0)
	{
		$summary.TerminalState = 'Skipped'
	}
	else
	{
		$summary.TerminalState = 'Succeeded'
	}

	if ($summary.TargetStateCounts['Cancelled'] -gt 0)
	{
		$summary.TargetState = 'Cancelled'
	}
	elseif ($summary.TargetStateCounts['Failed'] -gt 0)
	{
		$summary.TargetState = 'Failed'
	}
	elseif ($summary.TargetStateCounts['RequiresReview'] -gt 0)
	{
		$summary.TargetState = 'RequiresReview'
	}
	elseif ($summary.TargetStateCounts['PreflightFailed'] -gt 0)
	{
		$summary.TargetState = 'PreflightFailed'
	}
	elseif ($summary.TargetStateCounts['Running'] -gt 0)
	{
		$summary.TargetState = 'Running'
	}
	elseif ($summary.TargetStateCounts['PreviewReady'] -gt 0)
	{
		$summary.TargetState = 'PreviewReady'
	}
	elseif ($summary.TargetStateCounts['Connected'] -gt 0)
	{
		$summary.TargetState = 'Connected'
	}
	elseif ($summary.TargetStateCounts['Connecting'] -gt 0)
	{
		$summary.TargetState = 'Connecting'
	}
	else
	{
		$summary.TargetState = 'Succeeded'
	}

	return [pscustomobject]$summary
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteEntryWithRetry
{
	<# .SYNOPSIS Executes a remote profile entry with bounded retry. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$EntryName,

		[Parameter(Mandatory)]
		[scriptblock]$Action,

		[int]$MaxRetryCount = $(if ($Script:CachedRemoteOrchestrationDefaultRetryCount) { [int]$Script:CachedRemoteOrchestrationDefaultRetryCount } else { 2 }),

		[int]$RetryDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 })
	)

	$attempt = 0
	$errors = [System.Collections.Generic.List[string]]::new()
	$lastProfile = $null
	$result = $null

	while ($true)
	{
		$attempt++
		try
		{
			$result = & $Action
			return [pscustomobject]@{
				Success         = $true
				Attempts        = $attempt
				RetryCount      = [math]::Max(0, $attempt - 1)
				Result          = $result
				Errors          = @()
				FailureCategory = 'Success'
				Retryable       = $false
				RetryReason     = 'Completed successfully.'
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Invoke-BaselineRemoteEntryWithRetry:catch2637' -Severity Debug }

			$message = [string]$_.Exception.Message
			if (-not [string]::IsNullOrWhiteSpace($message))
			{
				$errors.Add($message)
			}
			$lastProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($message) -Status 'Failed'
			if (-not $lastProfile.Retryable -or $attempt -ge ([math]::Max(1, $MaxRetryCount + 1)))
			{
				break
			}

			Invoke-BaselineRemoteRetryDelay -Attempt $attempt -BaseDelayMilliseconds $RetryDelayMilliseconds
		}
	}

	return [pscustomobject]@{
		Success         = $false
		Attempts        = $attempt
		RetryCount      = [math]::Max(0, $attempt - 1)
		Result          = $result
		Errors          = @($errors)
		FailureCategory = if ($lastProfile) { [string]$lastProfile.Category } else { 'Unknown' }
		Retryable       = if ($lastProfile) { [bool]$lastProfile.Retryable } else { $false }
		RetryReason     = if ($lastProfile) { [string]$lastProfile.RetryReason } else { 'No error details were captured.' }
	}
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteRetryDelay
{
	[CmdletBinding()]
	param(
		[int]$Attempt = 1,
		[int]$BaseDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 })
	)

	$attemptIndex = [Math]::Max(1, [int]$Attempt)
	$delay = [Math]::Min(5000, $BaseDelayMilliseconds * [Math]::Pow(2, ($attemptIndex - 1)))
	$delay += (Get-Random -Minimum 0 -Maximum 100)
	Start-Sleep -Milliseconds ([int]$delay)
}

<#
    .SYNOPSIS
#>

function Test-BaselineRemoteOrchestrationAllowed
{
	[CmdletBinding()]
	param(
		[string]$KillSwitchPath = $(try { (New-BaselineOperatorPolicy).KillSwitchPath } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteOrchestrationAllowed:catch2692' -Severity Debug }
		 [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'BASELINE_KILL_SWITCH') }),
		[ValidateSet('ConnectivityTest', 'RemoteCompliance', 'RemoteApply', 'Unknown')]
		[string]$Operation = 'Unknown'
	)

	$engaged = $false
	if (Get-Command -Name 'Test-BaselineKillSwitch' -ErrorAction SilentlyContinue)
	{
		try { $engaged = Test-BaselineKillSwitch -Path $KillSwitchPath } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteOrchestrationAllowed:catch2700' -Severity Debug }
		 $engaged = $false }
	}
	else
	{
		try { $engaged = [bool](Test-Path -LiteralPath $KillSwitchPath -PathType Leaf -ErrorAction SilentlyContinue) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteOrchestrationAllowed:catch2704' -Severity Debug }
		 $engaged = $false }
	}

	if ($engaged)
	{
		return [pscustomobject]@{
			Allowed = $false
			Reason  = 'Kill switch is engaged.'
			Path    = $KillSwitchPath
			Operation = $Operation
			MaturityGate = $null
		}
	}

	$maturityGate = $null
	if (Get-Command -Name 'Test-BaselineEnterpriseActionMaturityGate' -ErrorAction SilentlyContinue)
	{
		try { $maturityGate = Test-BaselineEnterpriseActionMaturityGate -FeatureName $Operation } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteOrchestrationAllowed:catch2721' -Severity Debug }
		 $maturityGate = $null }
	}

	if ($maturityGate -and -not [bool]$maturityGate.Allowed)
	{
		return [pscustomobject]@{
			Allowed = $false
			Reason  = ('Feature maturity gate failed for {0}: current={1}, required={2}.' -f $Operation, $maturityGate.CurrentMaturity, $maturityGate.RequiredMaturity)
			Path    = $KillSwitchPath
			Operation = $Operation
			MaturityGate = $maturityGate
		}
	}

	return [pscustomobject]@{
		Allowed = $true
		Reason  = $null
		Path    = $KillSwitchPath
		Operation = $Operation
		MaturityGate = $maturityGate
	}
}

<#
    .SYNOPSIS
#>

function Write-BaselineRemoteOrchestrationRecord
{
	<# .SYNOPSIS Appends a single remote orchestration history record. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[hashtable]$Record
	)

	$path = Get-BaselineRemoteOrchestrationHistoryPath
	$payload = [ordered]@{
		Timestamp      = (Get-Date).ToString('o')
		MachineName    = $env:COMPUTERNAME
		RecordKind     = if ($Record.ContainsKey('RecordKind')) { [string]$Record.RecordKind } else { 'Target' }
		RunId          = if ($Record.ContainsKey('RunId')) { [string]$Record.RunId } else { [guid]::NewGuid().ToString('N') }
		Operation      = if ($Record.ContainsKey('Operation')) { [string]$Record.Operation } else { 'Unknown' }
		ComputerName   = if ($Record.ContainsKey('ComputerName')) { [string]$Record.ComputerName } else { $null }
		Status         = if ($Record.ContainsKey('Status')) { [string]$Record.Status } else { 'Unknown' }
		TargetState    = if ($Record.ContainsKey('TargetState')) { [string]$Record.TargetState } else { $null }
		TerminalState  = if ($Record.ContainsKey('TerminalState')) { [string]$Record.TerminalState } else { $null }
		SessionReused  = if ($Record.ContainsKey('SessionReused')) { [bool]$Record.SessionReused } else { $false }
		SessionState   = if ($Record.ContainsKey('SessionState')) { [string]$Record.SessionState } else { 'Unknown' }
		LifecycleState = if ($Record.ContainsKey('LifecycleState')) { [string]$Record.LifecycleState } else { $null }
		AttemptCount   = if ($Record.ContainsKey('AttemptCount')) { [int]$Record.AttemptCount } else { 1 }
		RetryCount     = if ($Record.ContainsKey('RetryCount')) { [int]$Record.RetryCount } else { 0 }
		BlockedByPolicy = if ($Record.ContainsKey('BlockedByPolicy')) { [bool]$Record.BlockedByPolicy } else { $false }
		AppliedCount   = if ($Record.ContainsKey('AppliedCount')) { [int]$Record.AppliedCount } else { 0 }
		FailedCount    = if ($Record.ContainsKey('FailedCount')) { [int]$Record.FailedCount } else { 0 }
		DriftedCount   = if ($Record.ContainsKey('DriftedCount')) { [int]$Record.DriftedCount } else { 0 }
		TotalChecked   = if ($Record.ContainsKey('TotalChecked')) { [int]$Record.TotalChecked } else { 0 }
		FailureCategory = if ($Record.ContainsKey('FailureCategory')) { [string]$Record.FailureCategory } else { $null }
		Retryable      = if ($Record.ContainsKey('Retryable')) { [bool]$Record.Retryable } else { $false }
		RetryReason    = if ($Record.ContainsKey('RetryReason')) { [string]$Record.RetryReason } else { $null }
		Errors         = if ($Record.ContainsKey('Errors') -and $null -ne $Record.Errors) { @($Record.Errors) } else { @() }
		HistoryPath    = $path
	}

	if ($Record.ContainsKey('StartedAt') -and $Record.StartedAt)
	{
		$payload['StartedAt'] = ([datetime]$Record.StartedAt).ToString('o')
	}
	if ($Record.ContainsKey('CompletedAt') -and $Record.CompletedAt)
	{
		$payload['CompletedAt'] = ([datetime]$Record.CompletedAt).ToString('o')
	}
	if ($Record.ContainsKey('DurationSeconds') -and $null -ne $Record.DurationSeconds)
	{
		$payload['DurationSeconds'] = [math]::Round([double]$Record.DurationSeconds, 2)
	}
	if ($Record.ContainsKey('Details') -and $null -ne $Record.Details)
	{
		$payload['Details'] = $Record.Details
	}
	if ($Record.ContainsKey('TargetStateHistory') -and $null -ne $Record.TargetStateHistory)
	{
		$payload['TargetStateHistory'] = $Record.TargetStateHistory
	}
	if ($Record.ContainsKey('RemoteTargetLabel') -and $Record.RemoteTargetLabel)
	{
		$payload['RemoteTargetLabel'] = [string]$Record.RemoteTargetLabel
	}

	$json = ConvertTo-Json -InputObject $payload -Compress -Depth 6
	[System.IO.File]::AppendAllText($path, "$json`n", [System.Text.UTF8Encoding]::new($false))
	return [pscustomobject]$payload
}

<#
    .SYNOPSIS
#>

function Write-BaselineRemoteOrchestrationSummaryRecord
{
	<# .SYNOPSIS Appends a single remote orchestration run summary record. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[hashtable]$Record
	)

	$path = Get-BaselineRemoteOrchestrationHistoryPath
	$payload = [ordered]@{
		Timestamp      = (Get-Date).ToString('o')
		MachineName    = $env:COMPUTERNAME
		RecordKind     = 'RunSummary'
		RunId          = if ($Record.ContainsKey('RunId')) { [string]$Record.RunId } else { [guid]::NewGuid().ToString('N') }
		Operation      = if ($Record.ContainsKey('Operation')) { [string]$Record.Operation } else { 'Unknown' }
		ComputerName   = if ($Record.ContainsKey('ComputerName')) { [string]$Record.ComputerName } else { $null }
		Status         = if ($Record.ContainsKey('Status')) { [string]$Record.Status } else { 'Unknown' }
		TargetState    = if ($Record.ContainsKey('TargetState')) { [string]$Record.TargetState } else { $null }
		TerminalState  = if ($Record.ContainsKey('TerminalState')) { [string]$Record.TerminalState } else { $null }
		TargetCount    = if ($Record.ContainsKey('TargetCount')) { [int]$Record.TargetCount } else { 0 }
		SucceededCount = if ($Record.ContainsKey('SucceededCount')) { [int]$Record.SucceededCount } else { 0 }
		FailedCount    = if ($Record.ContainsKey('FailedCount')) { [int]$Record.FailedCount } else { 0 }
		SkippedCount   = if ($Record.ContainsKey('SkippedCount')) { [int]$Record.SkippedCount } else { 0 }
		RetryingCount  = if ($Record.ContainsKey('RetryingCount')) { [int]$Record.RetryingCount } else { 0 }
		CancelledCount = if ($Record.ContainsKey('CancelledCount')) { [int]$Record.CancelledCount } else { 0 }
		TotalAttempts  = if ($Record.ContainsKey('TotalAttempts')) { [int]$Record.TotalAttempts } else { 0 }
		TotalRetries   = if ($Record.ContainsKey('TotalRetries')) { [int]$Record.TotalRetries } else { 0 }
		SessionReused  = if ($Record.ContainsKey('SessionReused')) { [bool]$Record.SessionReused } else { $false }
		SessionState   = if ($Record.ContainsKey('SessionState')) { [string]$Record.SessionState } else { 'Unknown' }
		LifecycleState = if ($Record.ContainsKey('LifecycleState')) { [string]$Record.LifecycleState } else { $null }
		FailureCategory = if ($Record.ContainsKey('FailureCategory')) { [string]$Record.FailureCategory } else { $null }
		Retryable      = if ($Record.ContainsKey('Retryable')) { [bool]$Record.Retryable } else { $false }
		RetryReason    = if ($Record.ContainsKey('RetryReason')) { [string]$Record.RetryReason } else { $null }
		Errors         = if ($Record.ContainsKey('Errors') -and $null -ne $Record.Errors) { @($Record.Errors) } else { @() }
		HistoryPath    = $path
	}

	if ($Record.ContainsKey('StartedAt') -and $Record.StartedAt)
	{
		$payload['StartedAt'] = ([datetime]$Record.StartedAt).ToString('o')
	}
	if ($Record.ContainsKey('CompletedAt') -and $Record.CompletedAt)
	{
		$payload['CompletedAt'] = ([datetime]$Record.CompletedAt).ToString('o')
	}
	if ($Record.ContainsKey('DurationSeconds') -and $null -ne $Record.DurationSeconds)
	{
		$payload['DurationSeconds'] = [math]::Round([double]$Record.DurationSeconds, 2)
	}
	if ($Record.ContainsKey('TerminalStateCounts') -and $null -ne $Record.TerminalStateCounts)
	{
		$payload['TerminalStateCounts'] = $Record.TerminalStateCounts
	}
	if ($Record.ContainsKey('TargetStateCounts') -and $null -ne $Record.TargetStateCounts)
	{
		$payload['TargetStateCounts'] = $Record.TargetStateCounts
	}
	if ($Record.ContainsKey('StatusCounts') -and $null -ne $Record.StatusCounts)
	{
		$payload['StatusCounts'] = $Record.StatusCounts
	}
	if ($Record.ContainsKey('Details') -and $null -ne $Record.Details)
	{
		$payload['Details'] = $Record.Details
	}
	if ($Record.ContainsKey('Summary') -and $null -ne $Record.Summary)
	{
		$payload['Summary'] = [string]$Record.Summary
	}

	$json = ConvertTo-Json -InputObject $payload -Compress -Depth 8
	[System.IO.File]::AppendAllText($path, "$json`n", [System.Text.UTF8Encoding]::new($false))
	return [pscustomobject]$payload
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns the directory that holds per-run resume checkpoint files. Checkpoints
    are persisted so that an interrupted multi-target run (kill switch, crash,
    operator abort) can be resumed by replaying only the not-yet-completed
    targets. Override the location with the BASELINE_REMOTE_RESUME_DIR
    environment variable; tests use this to isolate checkpoint state.
#>

function Get-BaselineRemoteResumeDirectory
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = [System.Environment]::GetEnvironmentVariable('BASELINE_REMOTE_RESUME_DIR')
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		$root = $override
	}
	else
	{
		$root = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline', 'remote-resume')
	}

	if (-not [System.IO.Directory]::Exists($root))
	{
		[void][System.IO.Directory]::CreateDirectory($root)
	}
	return $root
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns the checkpoint file path for a given run identifier.
#>

function Get-BaselineRemoteResumeCheckpointPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$RunId
	)

	$runId = ($RunId -replace '[^A-Za-z0-9_.-]', '_')
	return [System.IO.Path]::Combine((Get-BaselineRemoteResumeDirectory), ('{0}.json' -f $runId))
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Writes or updates a resume checkpoint describing the run's targets and
    per-target lifecycle state. Writes are atomic (temp file + move) so a
    crash mid-write cannot leave a truncated checkpoint behind. The
    checkpoint is the authoritative "not-run set" until the run reaches a
    terminal state.
#>

function Save-BaselineRemoteResumeCheckpoint
{
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[string]$RunId,

		[Parameter(Mandatory)]
		[ValidateSet('RemoteCompliance', 'RemoteApply')]
		[string]$Operation,

		[Parameter()]
		[string]$ProfilePath,

		[Parameter()]
		[string[]]$Targets = @(),

		[Parameter()]
		[hashtable]$TargetStates,

		[Parameter()]
		[ValidateSet('Running', 'Interrupted', 'Completed')]
		[string]$Status = 'Running',

		[Parameter()]
		[string]$InterruptReason,

		[Parameter()]
		[int]$MaxRetryCount = 2,

		[Parameter()]
		[int]$RetryDelayMilliseconds = 250
	)

	$path = Get-BaselineRemoteResumeCheckpointPath -RunId $RunId
	$existing = $null
	if ([System.IO.File]::Exists($path))
	{
		try
		{
			$raw = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
			$existing = $raw | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Save-BaselineRemoteResumeCheckpoint:catch3005' -Severity Debug }

			$existing = $null
		}
	}

	$nowIso = [DateTimeOffset]::UtcNow.ToString('o')
	$existingTargetStates = @{}
	if ($existing -and $existing.PSObject.Properties['TargetStates'] -and $existing.TargetStates)
	{
		foreach ($prop in @($existing.TargetStates.PSObject.Properties))
		{
			$existingTargetStates[[string]$prop.Name] = [string]$prop.Value
		}
	}

	if ($TargetStates)
	{
		foreach ($key in @($TargetStates.Keys))
		{
			$existingTargetStates[[string]$key] = [string]$TargetStates[$key]
		}
	}

	$resolvedTargets = @()
	if ($Targets -and $Targets.Count -gt 0)
	{
		$resolvedTargets = @($Targets)
	}
	elseif ($existing -and $existing.PSObject.Properties['Targets'] -and $existing.Targets)
	{
		$resolvedTargets = @($existing.Targets)
	}

	foreach ($t in $resolvedTargets)
	{
		if (-not $existingTargetStates.ContainsKey([string]$t))
		{
			$existingTargetStates[[string]$t] = 'Pending'
		}
	}

	$resolvedProfile = $ProfilePath
	if ([string]::IsNullOrWhiteSpace($resolvedProfile) -and $existing -and $existing.PSObject.Properties['ProfilePath'])
	{
		$resolvedProfile = [string]$existing.ProfilePath
	}

	$resolvedStarted = if ($existing -and $existing.PSObject.Properties['StartedAt']) { [string]$existing.StartedAt } else { $nowIso }
	$resolvedMaxRetry = if ($PSBoundParameters.ContainsKey('MaxRetryCount')) { [int]$MaxRetryCount } elseif ($existing -and $existing.PSObject.Properties['MaxRetryCount']) { [int]$existing.MaxRetryCount } else { 2 }
	$resolvedRetryDelay = if ($PSBoundParameters.ContainsKey('RetryDelayMilliseconds')) { [int]$RetryDelayMilliseconds } elseif ($existing -and $existing.PSObject.Properties['RetryDelayMilliseconds']) { [int]$existing.RetryDelayMilliseconds } else { 250 }
	$resolvedInterruptReason = if ($PSBoundParameters.ContainsKey('InterruptReason')) { $InterruptReason } elseif ($existing -and $existing.PSObject.Properties['InterruptReason']) { [string]$existing.InterruptReason } else { $null }

	$targetStatesOrdered = [ordered]@{}
	foreach ($t in $resolvedTargets)
	{
		$targetStatesOrdered[[string]$t] = [string]$existingTargetStates[[string]$t]
	}

	$payload = [ordered]@{
		RunId                  = $RunId
		Operation              = $Operation
		ProfilePath            = $resolvedProfile
		Targets                = $resolvedTargets
		TargetStates           = $targetStatesOrdered
		Status                 = $Status
		InterruptReason        = $resolvedInterruptReason
		MaxRetryCount          = $resolvedMaxRetry
		RetryDelayMilliseconds = $resolvedRetryDelay
		StartedAt              = $resolvedStarted
		UpdatedAt              = $nowIso
		MachineName            = $env:COMPUTERNAME
		SchemaVersion          = 1
	}

	$json = ConvertTo-Json -InputObject $payload -Depth 6
	$tmp = $path + '.tmp'
	[System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
	if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }
	[System.IO.File]::Move($tmp, $path)

	return [pscustomobject]$payload
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Reads a single checkpoint file, or enumerates every checkpoint in the
    resume directory when no run id is supplied. Corrupt files are silently
    skipped when enumerating, so a partially-written checkpoint cannot block
    listing healthy ones.
#>

function Get-BaselineRemoteResumeCheckpoint
{
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[Parameter()]
		[string]$RunId
	)

	if ($RunId)
	{
		$path = Get-BaselineRemoteResumeCheckpointPath -RunId $RunId
		if (-not [System.IO.File]::Exists($path)) { return @() }
		try
		{
			$raw = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
			$obj = $raw | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
			$obj | Add-Member -NotePropertyName 'CheckpointPath' -NotePropertyValue $path -Force
			return @($obj)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Get-BaselineRemoteResumeCheckpoint:catch3119' -Severity Debug }

			return @()
		}
	}

	$dir = Get-BaselineRemoteResumeDirectory
	$results = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, '*.json'))
	{
		try
		{
			$raw = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))
			$obj = $raw | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
			$obj | Add-Member -NotePropertyName 'CheckpointPath' -NotePropertyValue $file -Force
			[void]$results.Add($obj)
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Get-BaselineRemoteResumeCheckpoint.ParseLine'
			continue
		}
	}
	return @($results)
}
<#
    .SYNOPSIS

    .DESCRIPTION
    Returns interrupted checkpoints (Status = Interrupted, or Running with a
    stale UpdatedAt) that still have Pending/Running/Cancelled targets
    remaining. This is the surface the operator console calls to populate
    the "resume interrupted run" list.
#>

function Get-BaselineRemoteResumableRuns
{
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[Parameter()]
		[int]$StaleAfterMinutes = 60
	)

	$checkpoints = @(Get-BaselineRemoteResumeCheckpoint)
	$now = [DateTimeOffset]::UtcNow
	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($cp in $checkpoints)
	{
		$status = if ($cp.PSObject.Properties['Status']) { [string]$cp.Status } else { 'Running' }
		$isInterrupted = ($status -eq 'Interrupted')
		if ($status -eq 'Running' -and $cp.PSObject.Properties['UpdatedAt'] -and $cp.UpdatedAt)
		{
			$updated = $null
			$rawUpdated = $cp.UpdatedAt
			if ($rawUpdated -is [datetime])
			{
				$updated = [DateTimeOffset]::new([datetime]::SpecifyKind([datetime]$rawUpdated, [System.DateTimeKind]::Utc))
			}
			elseif ($rawUpdated -is [DateTimeOffset])
			{
				$updated = [DateTimeOffset]$rawUpdated
			}
			else
			{
				$parsed = [DateTimeOffset]::MinValue
				if ([DateTimeOffset]::TryParse([string]$rawUpdated, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed))
				{
					$updated = $parsed
				}
			}
			if ($updated -and ($now - $updated).TotalMinutes -ge [double]$StaleAfterMinutes)
			{
				$isInterrupted = $true
			}
		}

		if (-not $isInterrupted) { continue }

		$pending = @()
		if ($cp.PSObject.Properties['TargetStates'] -and $cp.TargetStates)
		{
			foreach ($prop in @($cp.TargetStates.PSObject.Properties))
			{
				$state = [string]$prop.Value
				if ($state -in @('Pending', 'Running', 'Cancelled', 'Connecting', 'Connected', 'PreviewReady')) { $pending += [string]$prop.Name }
			}
		}

		if ($pending.Count -eq 0) { continue }

		$cp | Add-Member -NotePropertyName 'PendingTargets' -NotePropertyValue $pending -Force
		[void]$results.Add($cp)
	}
	return @($results)
}
<#
    .SYNOPSIS

    .DESCRIPTION
    Deletes a checkpoint file after its run reaches a terminal state or the
    operator dismisses it.
#>

function Clear-BaselineRemoteResumeCheckpoint
{
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$RunId
	)

	$path = Get-BaselineRemoteResumeCheckpointPath -RunId $RunId
	if ([System.IO.File]::Exists($path))
	{
		[System.IO.File]::Delete($path)
	}
}

<#
    .SYNOPSIS
#>

function Write-BaselineRemoteCheckpointWarning
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Message
	)

	$logWarningCommand = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
	if ($logWarningCommand)
	{
		LogWarning $Message
		return
	}

	Write-Warning $Message
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteCheckpointAction
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[scriptblock]$Action,

		[Parameter(Mandatory)]
		[string]$Description
	)

	try
	{
		return (& $Action)
	}
	catch
	{
		Write-BaselineRemoteCheckpointWarning -Message ("Failed to {0}: {1}" -f $Description, $_.Exception.Message)

		$removeHandledErrorCommand = Get-Command -Name 'Remove-HandledErrorRecord' -CommandType Function -ErrorAction SilentlyContinue
		if ($removeHandledErrorCommand)
		{
			Remove-HandledErrorRecord -ErrorRecord $_
		}

		return $null
	}
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Given a checkpoint, returns the ordered set of targets whose state is
    still in a non-terminal bucket - this is the list of computers that the
    resume operation should replay.
#>

function Resolve-BaselineRemoteResumeTargets
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter(Mandatory)]
		[pscustomobject]$Checkpoint
	)

	$pending = [System.Collections.Generic.List[string]]::new()
	if ($Checkpoint.PSObject.Properties['Targets'] -and $Checkpoint.Targets)
	{
		foreach ($t in @($Checkpoint.Targets))
		{
			$state = $null
			if ($Checkpoint.PSObject.Properties['TargetStates'] -and $Checkpoint.TargetStates)
			{
				$prop = $Checkpoint.TargetStates.PSObject.Properties[[string]$t]
				if ($prop) { $state = [string]$prop.Value }
			}
			if ([string]::IsNullOrWhiteSpace($state) -or $state -in @('Pending', 'Running', 'Cancelled', 'Connecting', 'Connected', 'PreviewReady'))
			{
				[void]$pending.Add([string]$t)
			}
		}
	}
	return @($pending)
}

<#
    .SYNOPSIS
    Resumes an interrupted remote orchestration run.

    .DESCRIPTION
    Loads the checkpoint for the given RunId and re-dispatches the operation
    against only the targets that did not reach a terminal state on the
    previous attempt. Succeeded/Failed targets are preserved in the
    checkpoint; the resumed run receives its own history records but shares
    the original RunId for cross-attempt correlation.
#>

function Resume-BaselineRemoteOrchestration
{
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[string]$RunId,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential,

		[Parameter()]
		[string]$ProfilePath
	)

	$checkpoints = @(Get-BaselineRemoteResumeCheckpoint -RunId $RunId)
	if ($checkpoints.Count -eq 0)
	{
		throw ("No resume checkpoint found for RunId '{0}'." -f $RunId)
	}

	$checkpoint = $checkpoints[0]
	$operation = [string]$checkpoint.Operation
	$resolvedProfile = if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath } else { [string]$checkpoint.ProfilePath }
	if ([string]::IsNullOrWhiteSpace($resolvedProfile) -or -not (Test-Path -LiteralPath $resolvedProfile))
	{
		throw ("Checkpoint references a profile that cannot be found: '{0}'." -f $resolvedProfile)
	}

	$pendingTargets = @(Resolve-BaselineRemoteResumeTargets -Checkpoint $checkpoint)
	if ($pendingTargets.Count -eq 0)
	{
		Clear-BaselineRemoteResumeCheckpoint -RunId $RunId
		return [pscustomobject]@{
			RunId    = $RunId
			Resumed  = $false
			Reason   = 'No targets remained pending on the checkpoint.'
			Results  = @()
		}
	}

	$maxRetry = if ($checkpoint.PSObject.Properties['MaxRetryCount']) { [int]$checkpoint.MaxRetryCount } else { 2 }
	$retryDelay = if ($checkpoint.PSObject.Properties['RetryDelayMilliseconds']) { [int]$checkpoint.RetryDelayMilliseconds } else { 250 }

	$invokeParams = @{
		ComputerName           = $pendingTargets
		ProfilePath            = $resolvedProfile
		MaxRetryCount          = $maxRetry
		RetryDelayMilliseconds = $retryDelay
		ResumeRunId            = $RunId
	}
	if ($Credential) { $invokeParams['Credential'] = $Credential }

	switch ($operation)
	{
		'RemoteCompliance' { $results = @(Invoke-BaselineRemoteCompliance @invokeParams) }
		'RemoteApply'      { $results = @(Invoke-BaselineRemoteApply @invokeParams) }
		default { throw ("Unsupported checkpoint operation: '{0}'." -f $operation) }
	}

	return [pscustomobject]@{
		RunId   = $RunId
		Resumed = $true
		Reason  = ('Resumed {0} target(s) from checkpoint.' -f $pendingTargets.Count)
		Results = @($results)
	}
}

<#
    .SYNOPSIS
#>

function ConvertFrom-BaselineRemoteTargetInput
{
	<#
		.SYNOPSIS
		Parses free-form computer-name input from the Connect dialog into
		separate Targets and Invalid lists. Splits on commas, semicolons,
		pipes, and whitespace. Deduplicates case-insensitively, preserving
		the first spelling seen. Hostnames (RFC1123) and IPv4 addresses are
		accepted; everything else is surfaced via the Invalid list so the
		dialog can warn the user instead of silently dropping tokens.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[AllowNull()]
		[AllowEmptyString()]
		[string]$InputText
	)

	$targets = [System.Collections.Generic.List[string]]::new()
	$invalid = [System.Collections.Generic.List[string]]::new()
	$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	if ([string]::IsNullOrWhiteSpace($InputText))
	{
		return [pscustomobject]@{
			Targets = @($targets)
			Invalid = @($invalid)
		}
	}

	$hostPattern = '^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
	$ipv4Pattern = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

	foreach ($raw in ($InputText -split '[,;|\s]+'))
	{
		if ([string]::IsNullOrWhiteSpace($raw)) { continue }
		$token = $raw.Trim()
		if (-not $seen.Add($token)) { continue }

		if (($token -match $hostPattern) -or ($token -match $ipv4Pattern))
		{
			$targets.Add($token)
		}
		else
		{
			$invalid.Add($token)
		}
	}

	return [pscustomobject]@{
		Targets = @($targets)
		Invalid = @($invalid)
	}
}

<#
    .SYNOPSIS
#>

function New-BaselineRemoteTargetCredential
{
	<#
		.SYNOPSIS
		Builds a PSCredential from Connect-dialog username + SecureString
		input, validating the username shape up front (DOMAIN\User or
		user@domain - never both, never empty halves) so that bad input
		surfaces as a UI-friendly ArgumentException rather than as an opaque
		WinRM authentication failure later.
	#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCredential])]
	param (
		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]$Username,

		[Parameter()]
		[AllowNull()]
		[System.Security.SecureString]$SecurePassword
	)

	if ([string]::IsNullOrWhiteSpace($Username))
	{
		throw [System.ArgumentException]::new('Username is required.', 'Username')
	}

	$u = $Username.Trim()
	$hasBackslash = $u.Contains('\')
	$hasAt = $u.Contains('@')

	if ($hasBackslash -and $hasAt)
	{
		throw [System.ArgumentException]::new('Use either DOMAIN\Username or user@domain - not both.', 'Username')
	}

	if ($hasBackslash)
	{
		$parts = $u -split '\\'
		if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1]))
		{
			throw [System.ArgumentException]::new('DOMAIN\Username must contain exactly one backslash with a non-empty domain and user.', 'Username')
		}
	}
	elseif ($hasAt)
	{
		$parts = $u -split '@'
		if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1]))
		{
			throw [System.ArgumentException]::new('user@domain must contain exactly one @ with non-empty parts.', 'Username')
		}
	}

	$secure = if ($null -ne $SecurePassword) { $SecurePassword } else { New-Object System.Security.SecureString }
	return [System.Management.Automation.PSCredential]::new($u, $secure)
}

<#
    .SYNOPSIS
#>

function Format-BaselineRemoteConnectivityStatus
{
	<#
		.SYNOPSIS
		Renders the per-target rows shown in the Connect dialog after a
		Test Connection run. Each row carries ComputerName, State
		('Reachable' / 'Unreachable' / 'Blocked'), Icon, and a Display
		string the dialog prints verbatim. Entries without a ComputerName
		are dropped silently - they belong to other parts of the
		connectivity record, not the per-host status panel.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[AllowNull()]
		[object[]]$Result
	)

	if ($null -eq $Result)
	{
		return @()
	}

	$checkIcon = ([char]0x2714).ToString()
	$crossIcon = ([char]0x274C).ToString()
	$blockedIcon = ([char]0x26D4).ToString()
	$arrow = ([char]0x2192).ToString()

	$output = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($entry in @($Result))
	{
		if ($null -eq $entry) { continue }
		$name = if ($entry.PSObject.Properties['ComputerName']) { [string]$entry.ComputerName } else { '' }
		if ([string]::IsNullOrWhiteSpace($name)) { continue }

		$blocked = $false
		if ($entry.PSObject.Properties['BlockedByPolicy']) { $blocked = [bool]$entry.BlockedByPolicy }
		$reachable = $false
		if ($entry.PSObject.Properties['Reachable']) { $reachable = [bool]$entry.Reachable }
		$errMsg = ''
		if ($entry.PSObject.Properties['Error'] -and $entry.Error) { $errMsg = [string]$entry.Error }
		$statusText = ''
		if ($entry.PSObject.Properties['Status'] -and $entry.Status) { $statusText = [string]$entry.Status }

		if ($blocked)
		{
			$state = 'Blocked'
			$icon = $blockedIcon
			$tail = if ($errMsg) { $errMsg } elseif ($statusText) { $statusText } else { 'Blocked by policy' }
		}
		elseif ($reachable)
		{
			$state = 'Reachable'
			$icon = $checkIcon
			$tail = if ($statusText) { $statusText } else { 'Reachable' }
		}
		else
		{
			$state = 'Unreachable'
			$icon = $crossIcon
			$tail = if ($errMsg) { $errMsg } elseif ($statusText) { $statusText } else { 'Unreachable' }
		}

		$display = ('{0} {1} {2} {3}' -f $name, $arrow, $icon, $tail).Trim()

		$output.Add([pscustomobject]@{
			ComputerName = $name
			State        = $state
			Icon         = $icon
			Display      = $display
		})
	}

	return @($output)
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineRemoteConnectionMethod
{
	<#
		.SYNOPSIS
		Folds the friendly Connect-dialog ComboBox labels and common
		synonyms ('WinRM (HTTP)', 'wsman', 'PSRemoting', 'WinRM over
		HTTPS', 'HTTPS', 'OpenSSH', etc.) down to the canonical tokens
		'WinRM', 'WinRMHttps', and 'SSH'. Unknown values fall back to
		'WinRM' so the dialog never produces a value the rest of the
		pipeline can't consume.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Method
	)

	if ([string]::IsNullOrWhiteSpace($Method))
	{
		return 'WinRM'
	}

	$key = $Method.Trim().ToLowerInvariant()
	switch ($key)
	{
		'winrm'                            { return 'WinRM' }
		'winrm (http)'                     { return 'WinRM' }
		'wsman'                            { return 'WinRM' }
		'psremoting'                       { return 'WinRM' }
		'winrmhttps'                       { return 'WinRMHttps' }
		'winrm over https'                 { return 'WinRMHttps' }
		'winrm-ssl'                        { return 'WinRMHttps' }
		'https'                            { return 'WinRMHttps' }
		'ssh'                              { return 'SSH' }
		'ssh (powershell over openssh)'    { return 'SSH' }
		'openssh'                          { return 'SSH' }
		default                            { return 'WinRM' }
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineRemoteConnectionMethodLabel
{
	<#
		.SYNOPSIS
		Returns the short banner-friendly label for a connection method.
		Normalizes the input via ConvertTo-BaselineRemoteConnectionMethod
		first so callers can pass either a canonical token or a
		dialog-friendly string.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Method
	)

	$canonical = ConvertTo-BaselineRemoteConnectionMethod -Method $Method
	switch ($canonical)
	{
		'WinRM'      { return 'WinRM' }
		'WinRMHttps' { return 'WinRM/HTTPS' }
		'SSH'        { return 'SSH' }
		default      { return 'WinRM' }
	}
}

<#
    .SYNOPSIS
#>

function Test-BaselineRemoteConnectivity
{
	<#
		.SYNOPSIS
		Tests WinRM connectivity for one or more remote computers.

		.DESCRIPTION
		Iterates over each computer name, calls Test-WSMan, and returns a
		per-machine result indicating whether the machine is reachable.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential,

		[Parameter()]
		[int]$MaxRetryCount = $(if ($Script:CachedRemoteOrchestrationDefaultRetryCount) { [int]$Script:CachedRemoteOrchestrationDefaultRetryCount } else { 2 }),

		[Parameter()]
		[int]$RetryDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 }),

		[Parameter()]
		[string]$ConnectionMethod = 'WinRM'
	)

	$canonicalMethod = ConvertTo-BaselineRemoteConnectionMethod -Method $ConnectionMethod
	$policyGate = Test-BaselineRemoteOrchestrationAllowed -Operation 'ConnectivityTest'
	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($computer in @($ComputerName))
	{
		$attempt = 0
		$entry = $null
		$attemptHistory = [System.Collections.Generic.List[pscustomobject]]::new()
		$targetStateHistory = [System.Collections.Generic.List[pscustomobject]]::new()
		$runId = [guid]::NewGuid().ToString('N')
		[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'ConnectivityTest' -State 'Pending' -Phase 'Queued' -Timestamp ([datetime]::UtcNow) -Reason 'Target queued for connectivity test.')
		do
		{
			$attempt++
			$attemptStartedAt = [datetime]::UtcNow
			$attemptStatus = if ($policyGate.Allowed) { 'Unreachable' } else { 'Blocked' }
			[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'ConnectivityTest' -State 'Connecting' -Phase 'Connecting' -Timestamp $attemptStartedAt -Reason ("Attempt {0} started." -f $attempt))
			$entry = [pscustomobject]@{
				ComputerName     = $computer
				RunId            = $runId
				AttemptCount     = $attempt
				RetryCount       = 0
				Reachable        = $false
				Status           = $attemptStatus
				TerminalState    = 'Unknown'
				LifecycleState   = Get-BaselineRemoteTargetLifecycleState -Operation 'ConnectivityTest' -Status $attemptStatus -Blocked (-not $policyGate.Allowed)
				FailureCategory  = $null
				Retryable        = $false
				RetryReason      = $null
				BlockedByPolicy  = (-not $policyGate.Allowed)
				HistoryPath      = $null
				DurationSeconds  = 0
				AttemptHistory   = $null
				RetryAnalytics   = $null
				ConnectionMethod = $canonicalMethod
				Error            = if ($policyGate.Allowed) { $null } else { $policyGate.Reason }
			}

			$shouldRetry = $false
			$attemptStatus = if ($policyGate.Allowed) { 'Unreachable' } else { 'Blocked' }
			if ($policyGate.Allowed)
			{
				try
				{
					switch ($canonicalMethod)
					{
						'SSH'
						{
							$tcp = New-Object System.Net.Sockets.TcpClient
							try
							{
								$async = $tcp.BeginConnect($computer, 22, $null, $null)
								$wait = $async.AsyncWaitHandle.WaitOne(5000)
								if (-not $wait)
								{
									throw 'SSH (TCP/22) connection timed out after 5 seconds.'
								}
								$tcp.EndConnect($async)
								if (-not $tcp.Connected)
								{
									throw 'SSH (TCP/22) port did not accept the connection.'
								}
								$entry.Reachable = $true
								$attemptStatus = 'Reachable'
								[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'ConnectivityTest' -State 'Connected' -Phase 'Connected' -Timestamp ([datetime]::UtcNow) -Reason 'SSH port responded.')
							}
							finally
							{
								try { $tcp.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Test-BaselineRemoteTargetConnectivity.TcpClose' }
							}
						}
						default
						{
							$wsmanParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }
							if ($Credential) { $wsmanParams.Credential = $Credential }
							if ($canonicalMethod -eq 'WinRMHttps') { $wsmanParams.UseSSL = $true }

							$null = Test-WSMan @wsmanParams
							$entry.Reachable = $true
							$attemptStatus = 'Reachable'
							$reason = if ($canonicalMethod -eq 'WinRMHttps') { 'WinRM/HTTPS responded successfully.' } else { 'WinRM responded successfully.' }
							[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'ConnectivityTest' -State 'Connected' -Phase 'Connected' -Timestamp ([datetime]::UtcNow) -Reason $reason)
						}
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Helpers.Test-BaselineRemoteConnectivity:catch3814' -Severity Debug }

					$entry.Error = $_.Exception.Message
				}
			}

			$attemptCompletedAt = [datetime]::UtcNow
			$failureProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($entry.Error) -Status $attemptStatus
			$attemptRecord = New-BaselineRemoteAttemptRecord -ComputerName $computer -AttemptIndex $attempt -StartedUtc $attemptStartedAt -CompletedUtc $attemptCompletedAt -Status $attemptStatus -Errors @($entry.Error) -FailureProfile $failureProfile
			[void]$attemptHistory.Add($attemptRecord)
			$null = Write-BaselineRemoteAttemptHistoryRecord -RunId $runId -Operation 'ConnectivityTest' -AttemptRecord $attemptRecord
			$entry.Status = $attemptStatus
			$entry.FailureCategory = $failureProfile.Category
			$entry.Retryable = $failureProfile.Retryable
			$entry.RetryReason = $failureProfile.RetryReason
			$entry.LifecycleState = Get-BaselineRemoteTargetLifecycleState -Operation 'ConnectivityTest' -Status $attemptStatus -Retryable $entry.Retryable -Blocked $entry.BlockedByPolicy
			$entry.TerminalState = if ($entry.BlockedByPolicy) { 'Skipped' } elseif ($entry.Reachable -and $attemptStatus -eq 'Reachable') { 'Succeeded' } elseif ($entry.Retryable) { 'Retrying' } else { 'Failed' }

			if ($policyGate.Allowed -and $entry.Retryable -and $attempt -lt ([math]::Max(1, $MaxRetryCount + 1)))
			{
				$shouldRetry = $true
				Invoke-BaselineRemoteRetryDelay -Attempt $attempt -BaseDelayMilliseconds $RetryDelayMilliseconds
			}
		}
		while ($shouldRetry)

		$retryAnalytics = Get-BaselineRemoteRetryAnalytics -AttemptRecords @($attemptHistory)
		$firstStartedAt = if ($attemptHistory.Count -gt 0) { ($attemptHistory | Sort-Object { [datetime]$_.StartedUtc } | Select-Object -First 1).StartedUtc } else { [datetime]::UtcNow }
		$lastCompletedAt = if ($attemptHistory.Count -gt 0) { ($attemptHistory | Sort-Object { [datetime]$_.CompletedUtc } | Select-Object -Last 1).CompletedUtc } else { [datetime]::UtcNow }
		$entry.AttemptCount = $attempt
		$entry.RetryCount = [math]::Max(0, $attempt - 1)
		$entry.DurationSeconds = [math]::Round(($lastCompletedAt - $firstStartedAt).TotalSeconds, 2)
		$entry.AttemptHistory = @($attemptHistory)
		$entry.RetryAnalytics = $retryAnalytics
		$entry.TargetState = Get-BaselineRemoteTargetState -Operation 'ConnectivityTest' -Status $attemptStatus -Retryable $entry.Retryable -Blocked $entry.BlockedByPolicy
		[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'ConnectivityTest' -State $entry.TargetState -Phase 'Completed' -Status $attemptStatus -Timestamp $lastCompletedAt -Reason $entry.RetryReason)
		$record = Write-BaselineRemoteOrchestrationRecord -Record @{
			RecordKind       = 'Target'
			RunId             = $runId
			Operation         = 'ConnectivityTest'
			ComputerName      = $computer
			RemoteTargetLabel = $computer
			Status            = $entry.Status
			TargetState       = $entry.TargetState
			TerminalState     = $entry.TerminalState
			LifecycleState    = $entry.LifecycleState
			SessionReused     = $false
			SessionState      = 'NotConnected'
			TotalChecked      = 0
			AttemptCount      = $entry.AttemptCount
			RetryCount        = $entry.RetryCount
			Errors            = @($entry.Error)
			FailureCategory   = $entry.FailureCategory
			Retryable         = $entry.Retryable
			RetryReason       = $entry.RetryReason
			StartedAt         = $firstStartedAt
			CompletedAt       = $lastCompletedAt
			DurationSeconds   = $entry.DurationSeconds
			TargetStateHistory = @($targetStateHistory)
			RetryAnalytics    = [ordered]@{
				TotalAttempts         = $retryAnalytics.TotalAttempts
				TotalRetries          = $retryAnalytics.TotalRetries
				RetryableFailures     = $retryAnalytics.RetryableFailures
				NonRetryableFailures  = $retryAnalytics.NonRetryableFailures
				RetryDurationMs       = $retryAnalytics.RetryDurationMs
				FailureCategoryCounts = $retryAnalytics.FailureCategoryCounts
			}
			Details           = [ordered]@{
				Reachable        = [bool]$entry.Reachable
				AttemptCount     = $entry.AttemptCount
				AttemptSummaries = @($attemptHistory | ForEach-Object {
					[ordered]@{
						AttemptIndex    = [int]$_.AttemptIndex
						DurationMs      = [int]$_.DurationMs
						Status          = [string]$_.Status
						FailureCategory = [string]$_.FailureCategory
						Retryable       = [bool]$_.Retryable
					}
				})
			}
		}
		$entry.HistoryPath = $record.HistoryPath

		$results.Add($entry)
	}

	if ($results.Count -gt 0)
	{
		$reconciliation = Get-BaselineRemoteOrchestrationReconciliation -Records @($results)
		$summaryTerminalState = if ($reconciliation.TerminalState) { [string]$reconciliation.TerminalState } else { 'Succeeded' }
		$summaryStatus = if ($summaryTerminalState -eq 'Succeeded') { 'Completed' } else { $summaryTerminalState }
		$null = Write-BaselineRemoteOrchestrationSummaryRecord -Record @{
			RunId              = [guid]::NewGuid().ToString('N')
			Operation          = 'ConnectivityTest'
			Status             = $summaryStatus
			TerminalState      = $summaryTerminalState
			TargetState        = $reconciliation.TargetState
			TargetCount        = $reconciliation.Total
			SucceededCount     = $reconciliation.SucceededCount
			FailedCount        = $reconciliation.FailedCount
			SkippedCount       = $reconciliation.SkippedCount
			RetryingCount      = $reconciliation.RetryingCount
			CancelledCount     = $reconciliation.CancelledCount
			TotalAttempts      = $reconciliation.TotalAttempts
			TotalRetries       = $reconciliation.TotalRetries
			TargetStateCounts   = $reconciliation.TargetStateCounts
			TerminalStateCounts = $reconciliation.TerminalStateCounts
			Details            = [ordered]@{
				Targets = @($results | ForEach-Object {
					[ordered]@{
						ComputerName  = $_.ComputerName
						Status        = $_.Status
						TargetState   = $_.TargetState
						TerminalState = $_.TerminalState
						Retryable     = [bool]$_.Retryable
						RetryReason   = $_.RetryReason
					}
				})
			}
			Summary            = ('Connectivity summary: Targets={0}, Succeeded={1}, Failed={2}, Skipped={3}, Retrying={4}, Cancelled={5}, Attempts={6}, Retries={7}' -f $reconciliation.Total, $reconciliation.SucceededCount, $reconciliation.FailedCount, $reconciliation.SkippedCount, $reconciliation.RetryingCount, $reconciliation.CancelledCount, $reconciliation.TotalAttempts, $reconciliation.TotalRetries)
		}
	}

	return @($results)
}
<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteCompliance
{
	<#
		.SYNOPSIS
		Runs a Baseline compliance check against one or more remote machines.

		.DESCRIPTION
		For each computer, opens a PSSession, copies the profile and Baseline
		module files to a temporary directory, invokes the compliance check
		headlessly inside the session, collects results, and cleans up.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter(Mandatory)]
		[string]$ProfilePath,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential,

		[Parameter()]
		[int]$MaxRetryCount = $(if ($Script:CachedRemoteOrchestrationDefaultRetryCount) { [int]$Script:CachedRemoteOrchestrationDefaultRetryCount } else { 2 }),

		[Parameter()]
		[int]$RetryDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 }),

		[Parameter()]
		[string]$ResumeRunId
	)

	if (-not (Test-Path -LiteralPath $ProfilePath))
	{
		throw "Profile file not found: $ProfilePath"
	}

	$moduleRoot = $Script:SharedHelpersModuleRoot
	$repoRoot   = $Script:SharedHelpersRepoRoot
	$policyGate = Test-BaselineRemoteOrchestrationAllowed -Operation 'RemoteCompliance'

	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	$orchestrationRunId = if (-not [string]::IsNullOrWhiteSpace($ResumeRunId)) { $ResumeRunId } else { [guid]::NewGuid().ToString('N') }
	$checkpointTargetStates = @{}
	foreach ($queued in @($ComputerName)) { $checkpointTargetStates[[string]$queued] = 'Pending' }
	[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteCompliance checkpoint state for run '{0}'" -f $orchestrationRunId) -Action {
		$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteCompliance' -ProfilePath $ProfilePath -Targets @($ComputerName) -TargetStates $checkpointTargetStates -Status 'Running' -MaxRetryCount $MaxRetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
	})

	$cancelEngaged = $false
		. (Join-Path $PSScriptRoot 'RemoteTarget\Invoke-BaselineRemoteCompliance\Invoke-BaselineRemoteCompliance.ps1')

	if ($cancelEngaged)
	{
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist interrupted RemoteCompliance checkpoint for run '{0}'" -f $orchestrationRunId) -Action {
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteCompliance' -Status 'Interrupted' -InterruptReason 'Kill switch engaged during run.'
		})
	}
	else
	{
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("mark RemoteCompliance checkpoint completed for run '{0}'" -f $orchestrationRunId) -Action {
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteCompliance' -Status 'Completed'
		})
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("clear RemoteCompliance checkpoint for run '{0}'" -f $orchestrationRunId) -Action {
			Clear-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId
		})
	}

	if ($results.Count -gt 0)
	{
		$reconciliation = Get-BaselineRemoteOrchestrationReconciliation -Records @($results)
		$summaryTerminalState = if ($reconciliation.TerminalState) { [string]$reconciliation.TerminalState } else { 'Succeeded' }
		$summaryStatus = if ($summaryTerminalState -eq 'Succeeded') { 'Completed' } else { $summaryTerminalState }
		$null = Write-BaselineRemoteOrchestrationSummaryRecord -Record @{
			RunId               = $orchestrationRunId
			Operation           = 'RemoteCompliance'
			Status              = $summaryStatus
			TerminalState       = $summaryTerminalState
			TargetState         = $reconciliation.TargetState
			TargetCount         = $reconciliation.Total
			SucceededCount      = $reconciliation.SucceededCount
			FailedCount         = $reconciliation.FailedCount
			SkippedCount        = $reconciliation.SkippedCount
			RetryingCount       = $reconciliation.RetryingCount
			CancelledCount      = $reconciliation.CancelledCount
			TotalAttempts       = $reconciliation.TotalAttempts
			TotalRetries        = $reconciliation.TotalRetries
			TargetStateCounts   = $reconciliation.TargetStateCounts
			TerminalStateCounts = $reconciliation.TerminalStateCounts
			Details             = [ordered]@{
				Targets = @($results | ForEach-Object {
					[ordered]@{
						ComputerName  = $_.ComputerName
						Status        = $_.Status
						TargetState   = $_.TargetState
						TerminalState = $_.TerminalState
						Retryable     = [bool]$_.Retryable
						RetryReason   = $_.RetryReason
					}
				})
			}
			Summary             = ('Remote compliance summary: Targets={0}, Succeeded={1}, Failed={2}, Skipped={3}, Retrying={4}, Cancelled={5}, Attempts={6}, Retries={7}' -f $reconciliation.Total, $reconciliation.SucceededCount, $reconciliation.FailedCount, $reconciliation.SkippedCount, $reconciliation.RetryingCount, $reconciliation.CancelledCount, $reconciliation.TotalAttempts, $reconciliation.TotalRetries)
		}
	}

	return @($results)
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineRemoteApply
{
	<#
		.SYNOPSIS
		Applies a Baseline configuration profile to one or more remote machines.

		.DESCRIPTION
		For each computer, opens a PSSession, copies the profile and Baseline
		module files to a temporary directory, resolves the profile entries to
		headless commands, executes them inside the remote session, and collects
		per-machine results.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter(Mandatory)]
		[string]$ProfilePath,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential,

		[Parameter()]
		[int]$MaxRetryCount = $(if ($Script:CachedRemoteOrchestrationDefaultRetryCount) { [int]$Script:CachedRemoteOrchestrationDefaultRetryCount } else { 2 }),

		[Parameter()]
		[int]$RetryDelayMilliseconds = $(if ($Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds) { [int]$Script:CachedRemoteOrchestrationDefaultRetryDelayMilliseconds } else { 250 }),

		[Parameter()]
		[string]$ResumeRunId
	)

	if (-not (Test-Path -LiteralPath $ProfilePath))
	{
		throw "Profile file not found: $ProfilePath"
	}

	$moduleRoot = $Script:SharedHelpersModuleRoot
	$repoRoot   = $Script:SharedHelpersRepoRoot
	$policyGate = Test-BaselineRemoteOrchestrationAllowed -Operation 'RemoteApply'

	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	$orchestrationRunId = if (-not [string]::IsNullOrWhiteSpace($ResumeRunId)) { $ResumeRunId } else { [guid]::NewGuid().ToString('N') }
	$checkpointTargetStates = @{}
	foreach ($queued in @($ComputerName)) { $checkpointTargetStates[[string]$queued] = 'Pending' }
	[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteApply checkpoint state for run '{0}'" -f $orchestrationRunId) -Action {
		$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteApply' -ProfilePath $ProfilePath -Targets @($ComputerName) -TargetStates $checkpointTargetStates -Status 'Running' -MaxRetryCount $MaxRetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
	})

	$cancelEngaged = $false
		. (Join-Path $PSScriptRoot 'RemoteTarget\Invoke-BaselineRemoteApply\Invoke-BaselineRemoteApply.ps1')

	if ($cancelEngaged)
	{
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist interrupted RemoteApply checkpoint for run '{0}'" -f $orchestrationRunId) -Action {
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteApply' -Status 'Interrupted' -InterruptReason 'Kill switch engaged during run.'
		})
	}
	else
	{
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("mark RemoteApply checkpoint completed for run '{0}'" -f $orchestrationRunId) -Action {
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteApply' -Status 'Completed'
		})
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("clear RemoteApply checkpoint for run '{0}'" -f $orchestrationRunId) -Action {
			Clear-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId
		})
	}

	if ($results.Count -gt 0)
	{
		$reconciliation = Get-BaselineRemoteOrchestrationReconciliation -Records @($results)
		$summaryTerminalState = if ($reconciliation.TerminalState) { [string]$reconciliation.TerminalState } else { 'Succeeded' }
		$summaryStatus = if ($summaryTerminalState -eq 'Succeeded') { 'Completed' } else { $summaryTerminalState }
		$null = Write-BaselineRemoteOrchestrationSummaryRecord -Record @{
			RunId               = $orchestrationRunId
			Operation           = 'RemoteApply'
			Status              = $summaryStatus
			TerminalState       = $summaryTerminalState
			TargetState         = $reconciliation.TargetState
			TargetCount         = $reconciliation.Total
			SucceededCount      = $reconciliation.SucceededCount
			FailedCount         = $reconciliation.FailedCount
			SkippedCount        = $reconciliation.SkippedCount
			RetryingCount       = $reconciliation.RetryingCount
			CancelledCount      = $reconciliation.CancelledCount
			TotalAttempts       = $reconciliation.TotalAttempts
			TotalRetries        = $reconciliation.TotalRetries
			TargetStateCounts   = $reconciliation.TargetStateCounts
			TerminalStateCounts = $reconciliation.TerminalStateCounts
			Details             = [ordered]@{
				Targets = @($results | ForEach-Object {
					[ordered]@{
						ComputerName  = $_.ComputerName
						Status        = $_.Status
						TargetState   = $_.TargetState
						TerminalState = $_.TerminalState
						Retryable     = [bool]$_.Retryable
						RetryReason   = $_.RetryReason
					}
				})
			}
			Summary             = ('Remote apply summary: Targets={0}, Succeeded={1}, Failed={2}, Skipped={3}, Retrying={4}, Cancelled={5}, Attempts={6}, Retries={7}' -f $reconciliation.Total, $reconciliation.SucceededCount, $reconciliation.FailedCount, $reconciliation.SkippedCount, $reconciliation.RetryingCount, $reconciliation.CancelledCount, $reconciliation.TotalAttempts, $reconciliation.TotalRetries)
		}
	}

	return @($results)
}
