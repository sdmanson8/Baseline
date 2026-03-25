# Shared helper slice for Win10_11Util.

function Set-Policy
{
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
			New-Item -LiteralPath $FullPath -Force -ErrorAction Stop | Out-Null
		}

		if ($MappedType -eq "CLEAR")
		{
			return Remove-RegistryValueSafe -Path $FullPath -Name $Name
		}

		return Set-RegistryValueSafe -Path $FullPath -Name $Name -Value $Value -Type $MappedType
	}
	catch
	{
		throw "Failed to set policy '$Name' at '$FullPath': $($_.Exception.Message)"
	}
}

function ConvertTo-NativeRegistryPath
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Path
	)

	$NativePath = $Path -replace '^Registry::', ''

	switch -Regex ($NativePath)
	{
		'^HKCU:\\'
		{
			$UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
			return "HKU\$UserSid\$($NativePath.Substring(6))"
		}
		'^HKLM:\\'               { return "HKLM\$($NativePath.Substring(6))" }
		'^HKU:\\'                { return "HKU\$($NativePath.Substring(5))" }
		'^HKEY_CURRENT_USER\\'
		{
			$UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
			return "HKU\$UserSid\$($NativePath.Substring(18))"
		}
		'^HKEY_LOCAL_MACHINE\\'  { return "HKLM\$($NativePath.Substring(19))" }
		'^HKEY_USERS\\'          { return "HKU\$($NativePath.Substring(11))" }
		'^HKLM\\'                { return $NativePath }
		'^HKU\\'                 { return $NativePath }
		default                  { throw "Unsupported registry path: $Path" }
	}
}

function ConvertTo-RegExeValueType
{
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('DWord', 'String')]
		[string]
		$Type
	)

	switch ($Type)
	{
		'DWord' { return 'REG_DWORD' }
		'String' { return 'REG_SZ' }
	}
}

function Dismount-RegistryHive
{
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

function Mount-RegistryHive
{
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

function Test-RegistryValueEquivalent
{
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
			catch { return ([string]$CurrentValue -eq [string]$DesiredValue) }
		}
		'QWORD'
		{
			try { return ([int64]$CurrentValue -eq [int64]$DesiredValue) }
			catch { return ([string]$CurrentValue -eq [string]$DesiredValue) }
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
		'BINARY'
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

function Set-RegistryValueSafe
{
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
		[ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
		[string]
		$Type,

		[scriptblock]
		$AccessDeniedFallback,

		[scriptblock]
		$OnAccessDenied,

		[switch]
		$SkipOnAccessDenied
	)

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
			try
			{
				$currentValueKind = $registryKey.GetValueKind($Name).ToString()
			}
			catch
			{
				$currentValueKind = $null
			}
		}
		catch
		{
			$currentValueKind = $null
		}

		$existingProperty = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
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
				$FallbackSucceeded = $false
			}
		}

		if ($FallbackSucceeded)
		{
			Remove-HandledErrorRecord -ErrorRecord $HandledError
			return
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

function Remove-RegistryValueSafe
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $true)]
		[string]
		$Name
	)

	try
	{
		if (-not (Test-Path -Path $Path))
		{
			return $false
		}

		$existingProperty = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
		if (-not ($existingProperty -and $existingProperty.PSObject.Properties[$Name]))
		{
			return $false
		}

		Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop | Out-Null
		return $true
	}
	catch
	{
		throw "Failed to remove registry value '$Name' at '$Path': $($_.Exception.Message)"
	}
}

function Set-SystemTweaksRegistryValue
{
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

function Remove-SystemTweaksRegistryValue
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	return Remove-RegistryValueSafe -Path $Path -Name $Name
}
