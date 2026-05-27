# Shared helpers for Baseline -- registry operations, policy setting, and hive management.

<#
    .SYNOPSIS
#>

function Set-Policy
{
	<#
	.SYNOPSIS
	Sets a registry policy value at Computer or User scope with type normalization.
	#>
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet("Computer", "User")]
		[string]
		$Scope,

		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $true)]
		[string]
		$Name,

		[Parameter(Mandatory = $true)]
		[ValidateSet("CLEAR", "String", "ExpandString", "Binary", "DWord", "MultiString", "QWord", "SZ", "EXPANDSZ", "BINARY", "DWORD", "MULTISZ", "QWORD")]
		[string]
		$Type,

		[Parameter(Mandatory = $false)]
		$Value
	)

	switch ($Scope)
	{
		"Computer" { $Root = "HKLM:\" }
		"User"     { $Root = "HKCU:\" }
	}

	# Normalize common registry type aliases so callers can use either PowerShell or registry-style names.
	switch ($Type.ToUpperInvariant())
	{
		"CLEAR"    { $MappedType = "CLEAR" }
		"STRING"   { $MappedType = "String" }
		"SZ"       { $MappedType = "String" }
		"EXPANDSTRING" { $MappedType = "ExpandString" }
		"EXPANDSZ" { $MappedType = "ExpandString" }
		"BINARY"   { $MappedType = "Binary" }
		"DWORD"    { $MappedType = "DWord" }
		"DWORD32"  { $MappedType = "DWord" }
		"MULTISTRING" { $MappedType = "MultiString" }
		"MULTISZ"  { $MappedType = "MultiString" }
		"QWORD"    { $MappedType = "QWord" }
		default    { $MappedType = $Type }
	}

	$FullPath = Join-Path $Root $Path

	try
	{
		if (-not (Test-Path -LiteralPath $FullPath))
		{
			New-Item -Path $FullPath -Force -ErrorAction Stop | Out-Null
		}

		if ($MappedType -eq "CLEAR")
		{
			$removed = Remove-RegistryValueSafe -Path $FullPath -Name $Name
			if ($removed) { LogInfo "Set-Policy CLEAR: removed '$Name' from '$FullPath'" }
			return $removed
		}

		return Set-RegistryValueSafe -Path $FullPath -Name $Name -Value $Value -Type $MappedType
	}
	catch
	{
		throw "Failed to set policy '$Name' at '$FullPath': $($_.Exception.Message)"
	}
}

<#
    .SYNOPSIS
#>

function Get-CurrentWindowsUserSid
{
	<# .SYNOPSIS Resolves the current Windows user's SID from WindowsIdentity. #>
	try
	{
		return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	}
	catch
	{
		throw 'Current Windows user SID could not be resolved. Supply -CurrentUserSid when calling ConvertTo-NativeRegistryPath outside a Windows user context.'
	}
}

function ConvertTo-NativeRegistryPath
{
	<# .SYNOPSIS Converts PowerShell registry paths (HKCU:\, HKLM:\) to native reg.exe format. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[string]
		$CurrentUserSid
	)

	$NativePath = $Path -replace '^Registry::', ''
	$ResolvedCurrentUserSid = if ([string]::IsNullOrWhiteSpace($CurrentUserSid))
	{
		$null
	}
	else
	{
		$CurrentUserSid.Trim()
	}

	switch -Regex ($NativePath)
	{
		'^HKCU:\\'
		{
			$UserSid = if ([string]::IsNullOrWhiteSpace($ResolvedCurrentUserSid)) { Get-CurrentWindowsUserSid } else { $ResolvedCurrentUserSid }
			return "HKU\$UserSid\$($NativePath -replace '^HKCU:\\', '')"
		}
		'^HKLM:\\'               { return "HKLM\$($NativePath -replace '^HKLM:\\', '')" }
		'^HKU:\\'                { return "HKU\$($NativePath -replace '^HKU:\\', '')" }
		'^HKEY_CURRENT_USER\\'
		{
			$UserSid = if ([string]::IsNullOrWhiteSpace($ResolvedCurrentUserSid)) { Get-CurrentWindowsUserSid } else { $ResolvedCurrentUserSid }
			return "HKU\$UserSid\$($NativePath -replace '^HKEY_CURRENT_USER\\', '')"
		}
		'^HKEY_LOCAL_MACHINE\\'  { return "HKLM\$($NativePath -replace '^HKEY_LOCAL_MACHINE\\', '')" }
		'^HKEY_USERS\\'          { return "HKU\$($NativePath -replace '^HKEY_USERS\\', '')" }
		'^HKLM\\'                { return $NativePath }
		'^HKU\\'                 { return $NativePath }
		default                  { throw "Unsupported registry path: $Path" }
	}
}

<#
    .SYNOPSIS
#>

function ConvertTo-RegExeValueType
{
	<# .SYNOPSIS Converts PowerShell registry type names to reg.exe format (REG_DWORD, REG_SZ, etc.). #>
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('DWord', 'String', 'QWord', 'Binary', 'ExpandString', 'MultiString', 'None')]
		[string]
		$Type
	)

	switch ($Type)
	{
		'DWord'        { return 'REG_DWORD' }
		'String'       { return 'REG_SZ' }
		'QWord'        { return 'REG_QWORD' }
		'Binary'       { return 'REG_BINARY' }
		'ExpandString' { return 'REG_EXPAND_SZ' }
		'MultiString'  { return 'REG_MULTI_SZ' }
		'None'         { return 'REG_NONE' }
	}
}

<#
    .SYNOPSIS
#>

function Dismount-RegistryHive
{
	<# .SYNOPSIS Unmounts a registry hive with retry logic. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$MountPath,

		[Parameter(Mandatory = $true)]
		[string]
		$PsPath,

		[int]
		$MaxAttempts = 8,

		[int]
		$DelayMilliseconds = 250
	)

	if (-not (Test-Path -Path $PsPath))
	{
		return $true
	}

	for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++)
	{
		& reg.exe UNLOAD $MountPath *> $null
		if ($LASTEXITCODE -eq 0 -or -not (Test-Path -Path $PsPath))
		{
			return $true
		}

		Start-Sleep -Milliseconds $DelayMilliseconds
	}

	return (-not (Test-Path -Path $PsPath))
}

<#
    .SYNOPSIS
#>

function Mount-RegistryHive
{
	<# .SYNOPSIS Mounts a registry hive file with retry logic. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$MountPath,

		[Parameter(Mandatory = $true)]
		[string]
		$PsPath,

		[Parameter(Mandatory = $true)]
		[string]
		$HiveFile,

		[int]
		$MaxAttempts = 8,

		[int]
		$DelayMilliseconds = 500
	)

	if (-not (Test-Path -LiteralPath $HiveFile -PathType Leaf))
	{
		LogWarning "Registry hive file not found: $HiveFile"
		return $false
	}

	Dismount-RegistryHive -MountPath $MountPath -PsPath $PsPath | Out-Null

	for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++)
	{
		& reg.exe LOAD $MountPath $HiveFile *> $null
		if ($LASTEXITCODE -eq 0 -and (Test-Path -Path $PsPath))
		{
			return $true
		}

		Start-Sleep -Milliseconds $DelayMilliseconds
	}

	return $false
}

<#
    .SYNOPSIS
#>

function Test-RegistryValueEquivalent
{
	<# .SYNOPSIS Compares current and desired registry values accounting for type differences. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[object]
		$CurrentValue,

		[Parameter(Mandatory = $true)]
		[object]
		$DesiredValue,

		[Parameter(Mandatory = $true)]
		[string]
		$Type,

		[string]
		$CurrentType
	)

	$expectedKind = switch ($Type.ToUpperInvariant())
	{
		'DWORD'        { 'DWord' }
		'QWORD'        { 'QWord' }
		'STRING'       { 'String' }
		'EXPANDSTRING' { 'ExpandString' }
		'MULTISTRING'  { 'MultiString' }
		'BINARY'       { 'Binary' }
		'NONE'         { 'None' }
		default        { $Type }
	}

	if ($CurrentType -and $CurrentType -ne $expectedKind)
	{
		return $false
	}

	switch ($Type.ToUpperInvariant())
	{
		'DWORD'
		{
			try { return ([int64]$CurrentValue -eq [int64]$DesiredValue) }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Registry.Helpers.Test-RegistryValueEquivalent:catch313' -Severity Debug }
			 return ([string]$CurrentValue -eq [string]$DesiredValue) }
		}
		'QWORD'
		{
			try { return ([int64]$CurrentValue -eq [int64]$DesiredValue) }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Registry.Helpers.Test-RegistryValueEquivalent:catch318' -Severity Debug }
			 return ([string]$CurrentValue -eq [string]$DesiredValue) }
		}
		'STRING' { return ([string]$CurrentValue -eq [string]$DesiredValue) }
		'EXPANDSTRING' { return ([string]$CurrentValue -eq [string]$DesiredValue) }
		'MULTISTRING'
		{
			$currentItems = @($CurrentValue)
			$desiredItems = @($DesiredValue)
			if ($currentItems.Count -ne $desiredItems.Count) { return $false }
			for ($i = 0; $i -lt $currentItems.Count; $i++)
			{
				if ($currentItems[$i] -ne $desiredItems[$i]) { return $false }
			}
			return $true
		}
		{ $_ -in @('BINARY', 'NONE') }
		{
			$currentBytes = [byte[]]@($CurrentValue)
			$desiredBytes = [byte[]]@($DesiredValue)
			if ($currentBytes.Length -ne $desiredBytes.Length) { return $false }
			for ($i = 0; $i -lt $currentBytes.Length; $i++)
			{
				if ($currentBytes[$i] -ne $desiredBytes[$i]) { return $false }
			}
			return $true
		}
		default
		{
			return ([string]$CurrentValue -eq [string]$DesiredValue)
		}
	}
}

<#
    .SYNOPSIS
#>

function Set-RegistryValueSafe
{
	<# .SYNOPSIS Sets a registry value with access-denied fallback via reg.exe. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $true)]
		[string]
		$Name,

		[Parameter(Mandatory = $true)]
		[object]
		$Value,

		[Parameter(Mandatory = $true)]
		[ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord', 'None')]
		[string]
		$Type,

		# Scriptblock invoked on UnauthorizedAccessException. Receives positional
		# parameters: $Path, $Name, $Value, $Type. Must return $true on success.
		[scriptblock]
		$AccessDeniedFallback,

		[scriptblock]
		$OnAccessDenied,

		[switch]
		$SkipOnAccessDenied
	)

	if (Get-Command -Name 'Assert-BaselineWriteAllowed' -ErrorAction SilentlyContinue)
	{
		Assert-BaselineWriteAllowed -Operation ("Set-RegistryValueSafe({0}\{1})" -f $Path, $Name)
	}

	try
	{
		if (-not (Test-Path -Path $Path))
		{
			New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
		}

		$currentValueKind = $null
		try
		{
			$registryKey = Get-Item -Path $Path -ErrorAction Stop
			if ($registryKey.GetValueNames() -contains $Name)
			{
				$currentValueKind = $registryKey.GetValueKind($Name).ToString()
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Registry.Helpers.Set-RegistryValueSafe:catch410' -Severity Debug }

			$currentValueKind = $null
		}

		$existingProperty = Get-ItemProperty -Path $Path -ErrorAction Ignore
		if ($existingProperty -and $existingProperty.PSObject.Properties[$Name])
		{
			$currentValue = $existingProperty.PSObject.Properties[$Name].Value
			if (Test-RegistryValueEquivalent -CurrentValue $currentValue -DesiredValue $Value -Type $Type -CurrentType $currentValueKind)
			{
				return $false
			}

			Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
		}
		else
		{
			New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
		}

		return $true
	}
	catch [System.UnauthorizedAccessException]
	{
		$HandledError = $_
		$FallbackSucceeded = $false

		if ($AccessDeniedFallback)
		{
			try
			{
				$FallbackSucceeded = [bool](& $AccessDeniedFallback $Path $Name $Value $Type)
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Registry.Helpers.Set-RegistryValueSafe:catch444' -Severity Debug }

				$FallbackSucceeded = $false
			}
		}

		if ($FallbackSucceeded)
		{
			Remove-HandledErrorRecord -ErrorRecord $HandledError
			return $true
		}

		if ($SkipOnAccessDenied)
		{
			Remove-HandledErrorRecord -ErrorRecord $HandledError
			if ($OnAccessDenied)
			{
				& $OnAccessDenied $Path $Name | Out-Null
			}
			else
			{
				Write-Warning "Skipping registry value '$Name' at '$Path' because access was denied."
			}

			return $false
		}

		throw
	}
	catch
	{
		throw "Failed to set registry value '$Name' at '$Path': $($_.Exception.Message)"
	}
}

<#
    .SYNOPSIS
#>

function Remove-RegistryValueSafe
{
	<# .SYNOPSIS Safely removes a registry value, returning $true if removed or $false if absent. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string[]]
		$Path,

		[Parameter(Mandatory = $true)]
		[string[]]
		$Name
	)

	$removedAny = $false

	foreach ($singlePath in @($Path))
	{
		if ([string]::IsNullOrWhiteSpace([string]$singlePath))
		{
			continue
		}

		foreach ($singleName in @($Name))
		{
			if ([string]::IsNullOrWhiteSpace([string]$singleName))
			{
				continue
			}

			if (Get-Command -Name 'Assert-BaselineWriteAllowed' -ErrorAction SilentlyContinue)
			{
				Assert-BaselineWriteAllowed -Operation ("Remove-RegistryValueSafe({0}\{1})" -f $singlePath, $singleName)
			}

			try
			{
				if (-not (Test-Path -Path $singlePath))
				{
					continue
				}

				$existingProperty = Get-ItemProperty -Path $singlePath -ErrorAction Ignore
				if (-not ($existingProperty -and $existingProperty.PSObject.Properties[$singleName]))
				{
					continue
				}

				Remove-ItemProperty -Path $singlePath -Name $singleName -Force -ErrorAction Stop | Out-Null
				$removedAny = $true
			}
			catch
			{
				throw "Failed to remove registry value '$singleName' at '$singlePath': $($_.Exception.Message)"
			}
		}
	}

	return $removedAny
}

<#
    .SYNOPSIS
#>

function ConvertTo-RegistryCompositeStringValue
{
	<# .SYNOPSIS Updates a semicolon-delimited registry string while preserving unrelated key/value pairs. #>
	param
	(
		[Parameter(Mandatory = $false)]
		[string]
		$CurrentValue,

		[Parameter(Mandatory = $true)]
		[string]
		$CompositeStringKey,

		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]
		$Value
	)

	$normalizedKey = $CompositeStringKey.Trim()
	$parts = [System.Collections.Generic.List[string]]::new()
	$keyMatched = $false

	if (-not [string]::IsNullOrWhiteSpace($CurrentValue))
	{
		foreach ($segment in $CurrentValue.Split(';'))
		{
			$token = $segment.Trim()
			if ([string]::IsNullOrWhiteSpace($token))
			{
				continue
			}

			$equalsIndex = $token.IndexOf('=')
			if ($equalsIndex -lt 0)
			{
				$parts.Add($token)
				continue
			}

			$segmentKey = $token.Substring(0, $equalsIndex).Trim()
			$segmentValue = $token.Substring($equalsIndex + 1).Trim()

			if ($segmentKey.Equals($normalizedKey, [System.StringComparison]::OrdinalIgnoreCase))
			{
				if (-not $keyMatched)
				{
					$parts.Add(('{0}={1}' -f $normalizedKey, $Value))
					$keyMatched = $true
				}

				continue
			}

			$parts.Add(('{0}={1}' -f $segmentKey, $segmentValue))
		}
	}

	if (-not $keyMatched)
	{
		$parts.Add(('{0}={1}' -f $normalizedKey, $Value))
	}

	if ($parts.Count -eq 0)
	{
		return $null
	}

	return (($parts -join ';') + ';')
}

<#
    .SYNOPSIS
#>

function Set-RegistryCompositeStringValue
{
	<# .SYNOPSIS Sets a key=value pair inside a semicolon-delimited registry string without clobbering unrelated pairs. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $true)]
		[string]
		$Name,

		[Parameter(Mandatory = $true)]
		[string]
		$CompositeStringKey,

		[Parameter(Mandatory = $true)]
		[object]
		$Value
	)

	try
	{
		if (-not (Test-Path -Path $Path))
		{
			New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
		}

		$existingProperty = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
		$currentValue = $null
		if ($existingProperty -and $existingProperty.PSObject.Properties[$Name])
		{
			$currentValue = [string]$existingProperty.PSObject.Properties[$Name].Value
		}

		$desiredValue = ConvertTo-RegistryCompositeStringValue -CurrentValue $currentValue -CompositeStringKey $CompositeStringKey -Value ([string]$Value)
		if ($currentValue -eq $desiredValue)
		{
			return $false
		}

		if ($existingProperty -and $existingProperty.PSObject.Properties[$Name])
		{
			Set-ItemProperty -Path $Path -Name $Name -Type String -Value $desiredValue -Force -ErrorAction Stop | Out-Null
		}
		else
		{
			New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $desiredValue -Force -ErrorAction Stop | Out-Null
		}

		return $true
	}
	catch
	{
		throw "Failed to set composite registry value '$Name' at '$Path': $($_.Exception.Message)"
	}
}

<#
    .SYNOPSIS
#>

function Set-SystemTweaksRegistryValue
{
	<# .SYNOPSIS Wrapper that sets a registry value via Set-RegistryValueSafe for system tweaks. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[object]$Value,

		[Parameter(Mandatory = $true)]
		[ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
		[string]$Type
	)

	Set-RegistryValueSafe -Path $Path -Name $Name -Value $Value -Type $Type | Out-Null
}

<#
    .SYNOPSIS
#>

function Remove-SystemTweaksRegistryValue
{
	<# .SYNOPSIS Wrapper that removes a registry value via Remove-RegistryValueSafe for system tweaks. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	return Remove-RegistryValueSafe -Path $Path -Name $Name
}

