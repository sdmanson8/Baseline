using module ..\Logging.psm1
using module ..\GUICommon.psm1
using module ..\SharedHelpers.psm1

#region Applications

<#
    .SYNOPSIS
    Checks application catalog field.

    #>

function Test-ApplicationCatalogField
{
	param (
		[object]$Object,
		[string]$FieldName
	)

	if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $false
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return $Object.Contains($FieldName)
	}

	return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
}

<#
    .SYNOPSIS
    Gets application catalog field value.

    #>

function Get-ApplicationCatalogFieldValue
{
	param (
		[object]$Object,
		[string]$FieldName
	)

	if (-not (Test-ApplicationCatalogField -Object $Object -FieldName $FieldName))
	{
		return $null
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return $Object[$FieldName]
	}

	return $Object.$FieldName
}

<#
    .SYNOPSIS
    Gets package manager availability state value.

    #>

function Get-PackageManagerAvailabilityStateValue
{
	param (
		[object]$AvailabilityState,
		[string]$PropertyName
	)

	if (-not $AvailabilityState -or [string]::IsNullOrWhiteSpace($PropertyName))
	{
		return $null
	}

	if ($AvailabilityState -is [System.Collections.IDictionary])
	{
		if ($AvailabilityState.Contains($PropertyName))
		{
			return $AvailabilityState[$PropertyName]
		}

		return $null
	}

	if ($AvailabilityState.PSObject.Properties[$PropertyName])
	{
		return $AvailabilityState.$PropertyName
	}

	return $null
}

<#
    .SYNOPSIS
    Resolves application execution route.

    #>

function Resolve-ApplicationExecutionRoute
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Application,

		[string]$PreferredSource = $null,

		[object]$PackageManagerAvailabilityState = $null,

		[ValidateSet('Install', 'Uninstall', 'Update')]
		[string]$Action = 'Install'
	)

	$validRouteTypes = @('winget', 'choco', 'store', 'direct', 'command', 'uwp', 'feature', 'system', 'placeholder')
	$normalizedPreferredSource = if ([string]::IsNullOrWhiteSpace([string]$PreferredSource))
	{
		'winget'
	}
	else
	{
		switch ([string]$PreferredSource.Trim().ToLowerInvariant())
		{
			'winget' { 'winget' }
			'choco' { 'choco' }
			'chocolatey' { 'choco' }
			default { 'winget' }
		}
	}
	$normalizedAction = if ([string]::IsNullOrWhiteSpace([string]$Action)) { 'Install' } else { [string]$Action }

	$entityType = [string](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'EntityType')
	if ([string]::IsNullOrWhiteSpace($entityType))
	{
		$entityType = [string](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'Type')
	}
	$entityType = if ([string]::IsNullOrWhiteSpace($entityType)) { $null } else { [string]$entityType.Trim().ToLowerInvariant() }
	if ($entityType -and ($validRouteTypes -notcontains $entityType))
	{
		$entityType = $null
	}

	$displayName = [string](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'Name')
	if ([string]::IsNullOrWhiteSpace($displayName))
	{
		$displayName = 'Unknown application'
	}

	$extraArgs = Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'ExtraArgs'
	$winGetId = [string](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'WinGetId')
	if ([string]::IsNullOrWhiteSpace($winGetId))
	{
		$winGetId = [string](Get-ApplicationCatalogFieldValue -Object $extraArgs -FieldName 'WinGetId')
	}

	$chocoId = [string](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'ChocoId')
	if ([string]::IsNullOrWhiteSpace($chocoId))
	{
		$chocoId = [string](Get-ApplicationCatalogFieldValue -Object $extraArgs -FieldName 'ChocoId')
	}

	$storeUri = [string](Get-ApplicationCatalogFieldValue -Object $extraArgs -FieldName 'StoreUri')
	$directUrl = [string](Get-ApplicationCatalogFieldValue -Object $extraArgs -FieldName 'DirectUrl')
	$command = [string](Get-ApplicationCatalogFieldValue -Object $extraArgs -FieldName 'Command')

	$selectionKey = $null
	if (Get-Command -Name 'Get-ApplicationCatalogIdentityKey' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try
		{
			$selectionKey = [string](Get-ApplicationCatalogIdentityKey -Entry $Application)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Resolve-ApplicationExecutionRoute:catch174' -Severity Debug }

			$selectionKey = $null
		}
	}
	if ([string]::IsNullOrWhiteSpace($selectionKey))
	{
		if (-not [string]::IsNullOrWhiteSpace($winGetId))
		{
			$selectionKey = "winget:{0}" -f [string]$winGetId.Trim().ToLowerInvariant()
		}
		elseif (-not [string]::IsNullOrWhiteSpace($chocoId))
		{
			$selectionKey = "choco:{0}" -f [string]$chocoId.Trim().ToLowerInvariant()
		}
		elseif (-not [string]::IsNullOrWhiteSpace([string]$displayName))
		{
			$selectionKey = [string]$displayName.Trim().ToLowerInvariant()
		}
		else
			{
				$selectionKey = 'application'
			}
	}

	$supportsExecution = if (Test-ApplicationCatalogField -Object $Application -FieldName 'SupportsExecution')
	{
		[bool](Get-ApplicationCatalogFieldValue -Object $Application -FieldName 'SupportsExecution')
	}
	else
	{
		$true
	}

	$availableSources = [System.Collections.Generic.List[string]]::new()
	if (-not [string]::IsNullOrWhiteSpace($winGetId)) { [void]$availableSources.Add('winget') }
	if (-not [string]::IsNullOrWhiteSpace($chocoId)) { [void]$availableSources.Add('choco') }
	if (-not [string]::IsNullOrWhiteSpace($storeUri)) { [void]$availableSources.Add('store') }
	if (-not [string]::IsNullOrWhiteSpace($directUrl)) { [void]$availableSources.Add('direct') }
	if (-not [string]::IsNullOrWhiteSpace($command)) { [void]$availableSources.Add('command') }

	$wingetAvailable = $true
	$hasWingetAvailabilityState = $false
	if ($PackageManagerAvailabilityState -is [System.Collections.IDictionary])
	{
		$hasWingetAvailabilityState = $PackageManagerAvailabilityState.Contains('WinGetAvailable')
	}
	elseif ($PackageManagerAvailabilityState -and $PackageManagerAvailabilityState.PSObject.Properties['WinGetAvailable'])
	{
		$hasWingetAvailabilityState = $true
	}
	if ($hasWingetAvailabilityState)
	{
		$wingetAvailable = [bool]$PackageManagerAvailabilityState.WinGetAvailable
	}
	elseif (-not [string]::IsNullOrWhiteSpace($winGetId) -and (Get-Command -Name 'Test-WinGetAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try
		{
			$wingetAvailable = [bool](Test-WinGetAvailable)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Resolve-ApplicationExecutionRoute:catch235' -Severity Debug }

			$wingetAvailable = $false
		}
	}

	$chocolateyAvailable = $true
	$hasChocolateyAvailabilityState = $false
	if ($PackageManagerAvailabilityState -is [System.Collections.IDictionary])
	{
		$hasChocolateyAvailabilityState = $PackageManagerAvailabilityState.Contains('ChocolateyAvailable')
	}
	elseif ($PackageManagerAvailabilityState -and $PackageManagerAvailabilityState.PSObject.Properties['ChocolateyAvailable'])
	{
		$hasChocolateyAvailabilityState = $true
	}
	if ($hasChocolateyAvailabilityState)
	{
		$chocolateyAvailable = [bool]$PackageManagerAvailabilityState.ChocolateyAvailable
	}
	elseif (-not [string]::IsNullOrWhiteSpace($chocoId) -and (Get-Command -Name 'Test-ChocolateyAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try
		{
			$chocolateyAvailable = [bool](Test-ChocolateyAvailable)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Resolve-ApplicationExecutionRoute:catch261' -Severity Debug }

			$chocolateyAvailable = $false
		}
	}

	$route = 'unsupported'
	$selectedSource = $null
	$packageId = $null
	$reason = $null

	switch ($entityType)
	{
		'uwp'
		{
			$reason = "Application '$displayName' is tagged as UWP, but no UWP execution adapter is registered yet."
		}
		'feature'
		{
			$reason = "Application '$displayName' is tagged as a Windows feature, but no feature execution adapter is registered yet."
		}
		'system'
		{
			$reason = "Application '$displayName' is tagged as a system component, but no system execution adapter is registered yet."
		}
		'placeholder'
		{
			$reason = "No install method available for $displayName."
		}
		default
		{
			$reason = $null
		}
	}

	if (-not $reason)
	{
		if ($normalizedPreferredSource -eq 'winget' -and -not [string]::IsNullOrWhiteSpace($winGetId))
		{
			$route = 'winget'
			$selectedSource = 'winget'
			$packageId = [string]$winGetId
		}
		elseif ($normalizedPreferredSource -eq 'choco' -and -not [string]::IsNullOrWhiteSpace($chocoId))
		{
			$route = 'choco'
			$selectedSource = 'choco'
			$packageId = [string]$chocoId
		}
		elseif ($entityType -eq 'winget' -and -not [string]::IsNullOrWhiteSpace($winGetId))
		{
			$route = 'winget'
			$selectedSource = 'winget'
			$packageId = [string]$winGetId
		}
		elseif ($entityType -eq 'choco' -and -not [string]::IsNullOrWhiteSpace($chocoId))
		{
			$route = 'choco'
			$selectedSource = 'choco'
			$packageId = [string]$chocoId
		}
		elseif (-not [string]::IsNullOrWhiteSpace($winGetId))
		{
			$route = 'winget'
			$selectedSource = 'winget'
			$packageId = [string]$winGetId
		}
		elseif (-not [string]::IsNullOrWhiteSpace($chocoId))
		{
			$route = 'choco'
			$selectedSource = 'choco'
			$packageId = [string]$chocoId
		}
		elseif ($normalizedAction -eq 'Install')
		{
			if (-not [string]::IsNullOrWhiteSpace($storeUri))
			{
				$route = 'store'
				$selectedSource = 'store'
				$packageId = [string]$storeUri
			}
			elseif (-not [string]::IsNullOrWhiteSpace($directUrl))
			{
				$route = 'direct'
				$selectedSource = 'direct'
				$packageId = [string]$directUrl
			}
			elseif (-not [string]::IsNullOrWhiteSpace($command))
			{
				$route = 'command'
				$selectedSource = 'command'
				$packageId = [string]$command
			}
			else
			{
				if ($entityType -eq 'winget' -and [string]::IsNullOrWhiteSpace($winGetId))
				{
					$reason = "Application '$displayName' is tagged as WinGet, but does not define a WinGetId."
				}
				elseif ($entityType -eq 'choco' -and [string]::IsNullOrWhiteSpace($chocoId))
				{
					$reason = "Application '$displayName' is tagged as Chocolatey, but does not define a ChocoId."
				}
				else
				{
					$reason = "Application '$displayName' does not define an execution route."
				}
			}
		}
		else
		{
			if ($entityType -eq 'winget' -and [string]::IsNullOrWhiteSpace($winGetId))
			{
				$reason = "Application '$displayName' is tagged as WinGet, but does not define a WinGetId."
			}
			elseif ($entityType -eq 'choco' -and [string]::IsNullOrWhiteSpace($chocoId))
			{
				$reason = "Application '$displayName' is tagged as Chocolatey, but does not define a ChocoId."
			}
			else
			{
				$reason = "Application '$displayName' does not define an execution route."
			}
		}
	}

	if ($route -eq 'winget')
	{
		if (-not $wingetAvailable)
		{
			if (-not [string]::IsNullOrWhiteSpace($chocoId) -and $chocolateyAvailable)
			{
				$route = 'choco'
				$selectedSource = 'choco'
				$packageId = [string]$chocoId
				$reason = $null
			}
			else
			{
				$route = 'unsupported'
				$selectedSource = $null
				$packageId = $null
				if (-not [string]::IsNullOrWhiteSpace($chocoId) -and -not $chocolateyAvailable)
				{
					$reason = Get-BaselineLocalizedString -Key 'Progress_PackageManagerUnavailable' -Fallback 'Neither WinGet nor Chocolatey is available on this system.'
				}
				else
				{
					$reason = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
				}
				$supportsExecution = $false
			}
		}
	}
	elseif ($route -eq 'choco' -and -not $chocolateyAvailable)
	{
		if (-not [string]::IsNullOrWhiteSpace($winGetId) -and $wingetAvailable)
		{
			$route = 'winget'
			$selectedSource = 'winget'
			$packageId = [string]$winGetId
			$reason = $null
		}
		else
		{
			$route = 'unsupported'
			$selectedSource = $null
			$packageId = $null
			if (-not [string]::IsNullOrWhiteSpace($winGetId) -and -not $wingetAvailable)
			{
				$reason = Get-BaselineLocalizedString -Key 'Progress_PackageManagerUnavailable' -Fallback 'Neither Chocolatey nor WinGet is available on this system.'
			}
			else
			{
				$reason = Get-BaselineLocalizedString -Key 'Progress_Choco_NotAvailable' -Fallback 'Chocolatey is not available on this system.'
			}
			$supportsExecution = $false
		}
	}

	if (-not $supportsExecution -and $route -ne 'unsupported')
	{
		$route = 'unsupported'
		$selectedSource = $null
		$packageId = $null
		$reason = "Application '$displayName' is marked as not supporting execution."
	}

	if ($route -eq 'unsupported' -and [string]::IsNullOrWhiteSpace($reason))
	{
		if ($entityType -eq 'winget' -and [string]::IsNullOrWhiteSpace($winGetId))
		{
			$reason = "Application '$displayName' is tagged as WinGet, but does not define a WinGetId."
		}
		elseif ($entityType -eq 'choco' -and [string]::IsNullOrWhiteSpace($chocoId))
		{
			$reason = "Application '$displayName' is tagged as Chocolatey, but does not define a ChocoId."
		}
		else
		{
			$reason = "Application '$displayName' is not executable."
		}
	}

	$identityKey = if (-not [string]::IsNullOrWhiteSpace($selectionKey))
	{
		[string]$selectionKey.Trim().ToLowerInvariant()
	}
	elseif ($route -eq 'winget' -and -not [string]::IsNullOrWhiteSpace($packageId))
	{
		"winget:{0}" -f [string]$packageId.Trim().ToLowerInvariant()
	}
	elseif ($route -eq 'choco' -and -not [string]::IsNullOrWhiteSpace($packageId))
	{
		"choco:{0}" -f [string]$packageId.Trim().ToLowerInvariant()
	}
	else
	{
		"name:{0}" -f [string]$displayName.Trim().ToLowerInvariant()
	}

	return [pscustomobject]@{
		EntityType = $entityType
		Route = $route
		SelectedSource = $selectedSource
		PreferredSource = $normalizedPreferredSource
		AvailableSources = @($availableSources)
		PackageId = $packageId
		DisplayName = $displayName
		SupportsExecution = [bool]$supportsExecution
		IdentityKey = $identityKey
		SelectionKey = $selectionKey
		Reason = $reason
		WinGetId = $winGetId
		ChocoId = $chocoId
		StoreUri = $storeUri
		DirectUrl = $directUrl
		Command = $command
	}
}

<#
    .SYNOPSIS
    Saves chocolatey bootstrap script.

    #>

function Save-ChocolateyBootstrapScript
{
	[CmdletBinding()]
	param()

	$bootstrapScriptUrl = 'https://community.chocolatey.org/install.ps1'
	$bootstrapScriptPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("baseline-choco-bootstrap-{0}.ps1" -f [System.Guid]::NewGuid().ToString('N'))
	$expectedChocolateyInstallerHash = [string][Environment]::GetEnvironmentVariable('BASELINE_CHOCOLATEY_INSTALLER_SHA256')
	if (-not (Get-Command -Name 'Invoke-DownloadFile' -CommandType Function -ErrorAction SilentlyContinue))
	{
		throw 'Invoke-DownloadFile is required for Chocolatey bootstrap download.'
	}
	if (-not [string]::IsNullOrWhiteSpace($expectedChocolateyInstallerHash) -and -not (Get-Command -Name 'Assert-FileHash' -CommandType Function -ErrorAction SilentlyContinue))
	{
		throw 'Assert-FileHash is required for Chocolatey bootstrap verification.'
	}

	Invoke-DownloadFile -Uri $bootstrapScriptUrl -OutFile $bootstrapScriptPath
	if (-not [string]::IsNullOrWhiteSpace($expectedChocolateyInstallerHash))
	{
		$null = Assert-FileHash -Path $bootstrapScriptPath -ExpectedSha256 $expectedChocolateyInstallerHash -Label 'Chocolatey install.ps1'
	}
	return $bootstrapScriptPath
}

<#
    .SYNOPSIS
    Converts values to application command literal.

    #>

function ConvertTo-ApplicationCommandLiteral
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Ast,

		[Parameter(Mandatory = $true)]
		[string]$Command,

		[Parameter(Mandatory = $false)]
		[switch]$CommandName
	)

	if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst])
	{
		$literalValue = [string]$Ast.Value
		if ($CommandName -and [string]::IsNullOrWhiteSpace($literalValue))
		{
			throw "Command '$Command' must start with a literal command name."
		}

		return $literalValue
	}

	if (-not $CommandName -and $Ast -is [System.Management.Automation.Language.ConstantExpressionAst])
	{
		return [string]$Ast.Value
	}

	if ($CommandName)
	{
		throw "Command '$Command' must start with a literal command name."
	}

	throw "Command '$Command' contains unsupported syntax."
}

<#
    .SYNOPSIS
    Assert application command AST is safe.

    #>

function Assert-ApplicationCommandAstIsSafe
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Ast,

		[Parameter(Mandatory = $true)]
		[string]$Command
	)

	$cleanBlock = $null
	$cleanBlockProperty = $Ast.PSObject.Properties['CleanBlock']
	if ($cleanBlockProperty)
	{
		$cleanBlock = $cleanBlockProperty.Value
	}

	if ($Ast.ParamBlock -or $Ast.BeginBlock -or $Ast.ProcessBlock -or $Ast.DynamicParamBlock -or $cleanBlock)
	{
		throw "Command '$Command' contains unsupported syntax."
	}

	if (-not $Ast.EndBlock)
	{
		throw "Command '$Command' must resolve to one or more command invocations."
	}

	$statements = @($Ast.EndBlock.Statements)
	if ($statements.Count -eq 0)
	{
		throw "Command '$Command' must resolve to one or more command invocations."
	}

	foreach ($statement in $statements)
	{
		$pipelineAst = $statement -as [System.Management.Automation.Language.PipelineAst]
		if (-not $pipelineAst)
		{
			throw "Command '$Command' must contain only command invocations."
		}

		$pipelineBackground = $false
		$pipelineBackgroundProperty = $pipelineAst.PSObject.Properties['Background']
		if ($pipelineBackgroundProperty)
		{
			$pipelineBackground = [bool]$pipelineBackgroundProperty.Value
		}

		if ($pipelineBackground)
		{
			throw "Command '$Command' contains unsupported syntax."
		}

		foreach ($pipelineElement in @($pipelineAst.PipelineElements))
		{
			$commandAst = $pipelineElement -as [System.Management.Automation.Language.CommandAst]
			if (-not $commandAst -or $commandAst.CommandElements.Count -lt 1)
			{
				throw "Command '$Command' must resolve to a command name plus arguments."
			}

			if (@($commandAst.Redirections).Count -gt 0)
			{
				throw "Command '$Command' contains unsupported syntax."
			}

			if ($commandAst.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown)
			{
				throw "Command '$Command' contains unsupported syntax."
			}

			$null = ConvertTo-ApplicationCommandLiteral -Ast $commandAst.CommandElements[0] -Command $Command -CommandName
			foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1))
			{
				if ($element -is [System.Management.Automation.Language.CommandParameterAst])
				{
					if ($null -ne $element.Argument)
					{
						$null = ConvertTo-ApplicationCommandLiteral -Ast $element.Argument -Command $Command
					}

					continue
				}

				$null = ConvertTo-ApplicationCommandLiteral -Ast $element -Command $Command
			}
		}
	}
}

<#
    .SYNOPSIS
    Converts values to application command invocation.

    #>

function ConvertTo-ApplicationCommandInvocation
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Command
	)

	$tokens = $null
	$parseErrors = $null
	$ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$parseErrors)
	if ($parseErrors -and $parseErrors.Count -gt 0)
	{
		throw "Command '$Command' could not be parsed safely."
	}

	Assert-ApplicationCommandAstIsSafe -Ast $ast -Command $Command

	$statements = @($ast.EndBlock.Statements)
	$commandNames = [System.Collections.Generic.List[string]]::new()
	$isSingleCommandInvocation = ($statements.Count -eq 1)
	$commandAst = $null
	if ($isSingleCommandInvocation)
	{
		$pipelineAst = $statements[0] -as [System.Management.Automation.Language.PipelineAst]
		$isSingleCommandInvocation = ($pipelineAst -and $pipelineAst.PipelineElements.Count -eq 1)
		if ($isSingleCommandInvocation)
		{
			$commandAst = $pipelineAst.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst]
		}
	}

	$commandArguments = [System.Collections.Generic.List[string]]::new()
	foreach ($statement in $statements)
	{
		$pipelineAst = $statement -as [System.Management.Automation.Language.PipelineAst]
		foreach ($pipelineElement in @($pipelineAst.PipelineElements))
		{
			$pipelineCommandAst = $pipelineElement -as [System.Management.Automation.Language.CommandAst]
			[void]$commandNames.Add((ConvertTo-ApplicationCommandLiteral -Ast $pipelineCommandAst.CommandElements[0] -Command $Command -CommandName))
		}
	}

	if ($commandAst)
	{
		foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1))
		{
			if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $element -is [System.Management.Automation.Language.ConstantExpressionAst])
			{
				[void]$commandArguments.Add([string]$element.Value)
				continue
			}

			if ($element -is [System.Management.Automation.Language.CommandParameterAst])
			{
				[void]$commandArguments.Add("-$($element.ParameterName)")
				if ($null -ne $element.Argument)
				{
					[void]$commandArguments.Add((ConvertTo-ApplicationCommandLiteral -Ast $element.Argument -Command $Command))
				}

				continue
			}
		}
	}

	return [pscustomobject]@{
		CommandName = if ($commandAst) { [string]$commandNames[0] } else { $null }
		CommandArguments = @($commandArguments)
		CommandNames = @($commandNames)
		HasSingleCommandInvocation = [bool]$commandAst
	}
}

<#
	.SYNOPSIS
	Runs streaming process.
	.DESCRIPTION
	Runs an external process with no visible window and captures stdout/stderr so
	package-manager failures include enough diagnostics for support.
	Returns the exit code.
#>

function Get-ApplicationProcessOutputTail
{
	[CmdletBinding()]
	param(
		[AllowNull()]
		[string]$Text,

		[int]$MaxLines = 8
	)

	if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

	$lines = @(
		[regex]::Split([string]$Text, '\r?\n') |
			Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
			ForEach-Object { [string]$_.Trim() }
	)
	if ($lines.Count -eq 0) { return '' }

	return (($lines | Select-Object -Last $MaxLines) -join ' | ')
}

function ConvertTo-ApplicationProcessArgumentString
{
	[CmdletBinding()]
	param(
		[AllowNull()]
		[object[]]$ArgumentList
	)

	if (Get-Command -Name 'ConvertTo-BaselineProcessArgumentString' -CommandType Function -ErrorAction SilentlyContinue)
	{
		return (ConvertTo-BaselineProcessArgumentString -ArgumentList $ArgumentList)
	}

	$quotedArgs = foreach ($arg in @($ArgumentList))
	{
		$value = [string]$arg
		if ([string]::IsNullOrEmpty($value)) { '""' }
		elseif ($value -match '[\s"]') { '"' + ($value -replace '"', '\"') + '"' }
		else { $value }
	}

	return ($quotedArgs -join ' ')
}

function Write-ApplicationProcessFailureDiagnostics
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Result
	)

	if (-not $Result -or -not $Result.PSObject.Properties['ExitCode'] -or [int]$Result.ExitCode -eq 0)
	{
		return
	}

	$detailParts = [System.Collections.Generic.List[string]]::new()
	[void]$detailParts.Add(("exitCode={0}" -f [int]$Result.ExitCode))
	if ($Result.PSObject.Properties['FilePath']) { [void]$detailParts.Add(("file={0}" -f [string]$Result.FilePath)) }
	if ($Result.PSObject.Properties['Arguments'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.Arguments)) { [void]$detailParts.Add(("args={0}" -f [string]$Result.Arguments)) }

	$stderrTail = if ($Result.PSObject.Properties['StandardError']) { Get-ApplicationProcessOutputTail -Text ([string]$Result.StandardError) } else { '' }
	$stdoutTail = if ($Result.PSObject.Properties['StandardOutput']) { Get-ApplicationProcessOutputTail -Text ([string]$Result.StandardOutput) } else { '' }
	if (-not [string]::IsNullOrWhiteSpace($stderrTail)) { [void]$detailParts.Add(("stderr={0}" -f $stderrTail)) }
	if (-not [string]::IsNullOrWhiteSpace($stdoutTail)) { [void]$detailParts.Add(("stdout={0}" -f $stdoutTail)) }

	$message = "Application process failed: {0}" -f ($detailParts -join '; ')
	if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
	{
		LogWarning $message
	}
	else
	{
		Write-Warning $message
	}
}

function Invoke-StreamingProcess
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)][string]$FilePath,
		[Parameter(Mandatory = $true)][string[]]$ArgumentList,
		[int]$TimeoutSeconds = 900
	)

	if (Get-Command -Name 'Invoke-BaselineProcess' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$result = Invoke-BaselineProcess `
			-FilePath $FilePath `
			-ArgumentList $ArgumentList `
			-TimeoutSeconds $TimeoutSeconds `
			-CaptureOutput `
			-AllowAnyExitCode
		Write-ApplicationProcessFailureDiagnostics -Result $result
		return [int]$result.ExitCode
	}

	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $FilePath
	$psi.Arguments = ConvertTo-ApplicationProcessArgumentString -ArgumentList $ArgumentList
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	[void]$process.Start()

	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$timedOut = $false
	if ($TimeoutSeconds -gt 0)
	{
		$timedOut = -not $process.WaitForExit([int]([TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds))
	}
	else
	{
		$process.WaitForExit()
	}

	if ($timedOut)
	{
		Stop-BaselineProcessTree -Process $process -Source 'Applications.Invoke-StreamingProcess.KillTimedOutProcess'
		try { $null = $stdoutTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-StreamingProcess.TimeoutStdoutAwait' }
		try { $null = $stderrTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-StreamingProcess.TimeoutStderrAwait' }
		try { $process.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-StreamingProcess.TimeoutDisposeProcess' }
		throw ([System.TimeoutException]::new(("Process '{0}' timed out after {1} second(s)." -f $FilePath, $TimeoutSeconds)))
	}

	$stdout = ''
	$stderr = ''
	try { $stdout = [string]$stdoutTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessCapture.StdoutAwait' }
	try { $stderr = [string]$stderrTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessCapture.StderrAwait' }

	$exitCode = [int]$process.ExitCode
	Write-ApplicationProcessFailureDiagnostics -Result ([pscustomobject]@{
		ExitCode       = $exitCode
		StandardOutput = $stdout
		StandardError  = $stderr
		FilePath        = $FilePath
		Arguments       = ConvertTo-ApplicationProcessArgumentString -ArgumentList $ArgumentList
	})
	try { $process.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessCapture.DisposeProcess' }
	return $exitCode
}

<#
    .SYNOPSIS
    Captures process text output with timeout control.
#>
function Invoke-ProcessTextCapture
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)][string]$FilePath,
		[Parameter(Mandatory = $true)][string[]]$ArgumentList,
		[int]$TimeoutSeconds = 300
	)

	$quotedArgs = foreach ($arg in $ArgumentList)
	{
		if ([string]::IsNullOrEmpty($arg)) { '""' }
		elseif ($arg -match '[\s"]') { '"' + ($arg -replace '"', '\"') + '"' }
		else { $arg }
	}

	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $FilePath
	$psi.Arguments = ($quotedArgs -join ' ')
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	[void]$process.Start()

	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$timedOut = $false
	if ($TimeoutSeconds -gt 0)
	{
		$timedOut = -not $process.WaitForExit([int]([TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds))
	}
	else
	{
		$process.WaitForExit()
	}

	if ($timedOut)
	{
		Stop-BaselineProcessTree -Process $process -Source 'Applications.Invoke-ProcessTextCapture.KillTimedOutProcess'
		try { $null = $stdoutTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.TimeoutStdoutAwait' }
		try { $null = $stderrTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.TimeoutStderrAwait' }
		try { $process.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.TimeoutDisposeProcess' }
		throw ([System.TimeoutException]::new(("Process '{0}' timed out after {1} second(s)." -f $FilePath, $TimeoutSeconds)))
	}

	$stdout = ''
	$stderr = ''
	try { $stdout = [string]$stdoutTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.StdoutAwait' }
	try { $stderr = [string]$stderrTask.GetAwaiter().GetResult() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.StderrAwait' }
	$exitCode = [int]$process.ExitCode
	try { $process.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ProcessTextCapture.DisposeProcess' }

	return [pscustomobject]@{
		ExitCode = $exitCode
		StandardOutput = $stdout
		StandardError = $stderr
	}
}

<#
    .SYNOPSIS
    Waits for a started process with timeout control.
#>
function Wait-ApplicationProcess
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Process,

		[int]$TimeoutSeconds = 900
	)

	if ($TimeoutSeconds -gt 0)
	{
		$completed = $Process.WaitForExit([int]([TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds))
		if (-not $completed)
		{
			Stop-BaselineProcessTree -Process $Process -Source 'Applications.WaitApplicationProcess.KillTimedOutProcess'
			throw ([System.TimeoutException]::new(("Process '{0}' timed out after {1} second(s)." -f [string]$Process.StartInfo.FileName, $TimeoutSeconds)))
		}

		return [int]$Process.ExitCode
	}

	$Process.WaitForExit()
	return [int]$Process.ExitCode
}

<#
    .SYNOPSIS
    Gets the timeout exception from an application action error.
#>
function Get-ApplicationActionTimeoutException
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$ErrorRecord
	)

	$exception = if ($ErrorRecord -and $ErrorRecord.Exception) { $ErrorRecord.Exception } else { $null }
	while ($exception)
	{
		if ($exception -is [System.TimeoutException])
		{
			return $exception
		}

		$exception = $exception.InnerException
	}

	return $null
}

<#
    .SYNOPSIS
    Throws a normalized application action failure.
#>
function Throw-ApplicationActionFailure
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$TargetName,

		[Parameter(Mandatory = $true)]
		[string]$ActionLabel,

		[int]$TimeoutSeconds = 0,

		$ErrorRecord = $null
	)

	$timeoutException = if ($ErrorRecord) { Get-ApplicationActionTimeoutException -ErrorRecord $ErrorRecord } else { $null }
	if ($timeoutException)
	{
		$failureMessage = if ($TimeoutSeconds -gt 0)
		{
			"{0} {1} - Timed out after {2} second(s)." -f $TargetName, $ActionLabel, $TimeoutSeconds
		}
		else
		{
			"{0} {1} - Timed out." -f $TargetName, $ActionLabel
		}

		LogWarning $failureMessage
		throw ([System.TimeoutException]::new($failureMessage, $timeoutException))
	}

	$genericFailureMessage = "{0} {1} - Failed" -f $TargetName, $ActionLabel
	LogError $genericFailureMessage
	throw $genericFailureMessage
}

<#
    .SYNOPSIS
    Runs winget install.

    #>

function Invoke-WingetInstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$WinGetId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$wingetAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'WinGetAvailable'
	if ($null -eq $wingetAvailableState)
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogError $failureMessage
			throw $failureMessage
		}
	}
	elseif (-not [bool]$wingetAvailableState)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	$wingetPath = Resolve-WinGetExecutable
	if (-not $wingetPath)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_WinGet_StartingInstallation' -Fallback 'Starting installation of {0}...' -FormatArgs @($DisplayName))

	try
	{
		$exitCode = Invoke-StreamingProcess -FilePath $wingetPath -ArgumentList @(
			'install', '--id', $WinGetId, '--exact', '--silent',
			'--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Install - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Install - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-WingetInstall:catch1146' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Install' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs winget uninstall.

    #>

function Invoke-WingetUninstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$WinGetId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 600
	)

	$wingetAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'WinGetAvailable'
	if ($null -eq $wingetAvailableState)
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogError $failureMessage
			throw $failureMessage
		}
	}
	elseif (-not [bool]$wingetAvailableState)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	$wingetPath = Resolve-WinGetExecutable
	if (-not $wingetPath)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_WinGet_StartingUninstallation' -Fallback 'Starting uninstallation of {0}...' -FormatArgs @($DisplayName))

	try
	{
		$exitCode = Invoke-StreamingProcess -FilePath $wingetPath -ArgumentList @(
			'uninstall', '--id', $WinGetId, '--exact', '--silent', '--disable-interactivity'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Uninstall - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Uninstall - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-WingetUninstall:catch1217' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Uninstall' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs winget update.

    #>

function Invoke-WingetUpdate
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$WinGetId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$wingetAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'WinGetAvailable'
	if ($null -eq $wingetAvailableState)
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogError $failureMessage
			throw $failureMessage
		}
	}
	elseif (-not [bool]$wingetAvailableState)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	$wingetPath = Resolve-WinGetExecutable
	if (-not $wingetPath)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Processing' -Fallback 'Processing {0}...' -FormatArgs @($DisplayName))

	try
	{
		$exitCode = Invoke-StreamingProcess -FilePath $wingetPath -ArgumentList @(
			'upgrade', '--id', $WinGetId, '--exact', '--include-unknown', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Update - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Update - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-WingetUpdate:catch1288' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Update' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs chocolatey bootstrap install.

    #>

function Invoke-ChocolateyBootstrapInstall
{
	[CmdletBinding()]
	param(
		[int]$TimeoutSeconds = 900
	)

	if (-not (Get-Command -Name 'Invoke-ChocolateyBootstrap' -CommandType Function -ErrorAction SilentlyContinue))
	{
		throw 'Invoke-ChocolateyBootstrap is required for Chocolatey bootstrap installation.'
	}

	$result = Invoke-ChocolateyBootstrap -TimeoutSeconds $TimeoutSeconds
	if (-not $result -or -not [bool]$result.Success)
	{
		$errorMessage = if ($result -and $result.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Error))
		{
			[string]$result.Error
		}
		else
		{
			'Chocolatey bootstrap did not complete successfully.'
		}
		throw $errorMessage
	}

	Reset-ChocolateyAvailabilityState
}

<#
    .SYNOPSIS
    Runs choco install.

    #>

function Invoke-ChocoInstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ChocoId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$resolvedChocoId = Resolve-ApplicationPackageId -PackageId $ChocoId
	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Choco_InstallingPackage' -Fallback "Installing '{0}' via Chocolatey..." -FormatArgs @($DisplayName))

	try
	{
		$chocoPath = Resolve-ChocolateyExecutable
		if (-not $chocoPath)
		{
			Invoke-ChocolateyBootstrapInstall -TimeoutSeconds $TimeoutSeconds
			$chocoPath = Resolve-ChocolateyExecutable
		}

		if (-not $chocoPath)
		{
			$failureMessage = "{0} Install - Failed" -f $DisplayName
			LogError $failureMessage
			throw $failureMessage
		}

		$exitCode = Invoke-StreamingProcess -FilePath $chocoPath -ArgumentList @(
			'install', $resolvedChocoId, '-y', '--no-progress', '--accept-license'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Install - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Install - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ChocoInstall:catch1384' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Install' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs choco uninstall.

    #>

function Invoke-ChocoUninstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ChocoId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 600
	)

	$resolvedChocoId = Resolve-ApplicationPackageId -PackageId $ChocoId
	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Choco_UninstallingPackage' -Fallback "Uninstalling '{0}' via Chocolatey..." -FormatArgs @($DisplayName))

	try
	{
		$chocoPath = Resolve-ChocolateyExecutable
		if (-not $chocoPath)
		{
			Invoke-ChocolateyBootstrapInstall -TimeoutSeconds $TimeoutSeconds
			$chocoPath = Resolve-ChocolateyExecutable
		}

		if (-not $chocoPath)
		{
			$failureMessage = "{0} Uninstall - Failed" -f $DisplayName
			LogError $failureMessage
			throw $failureMessage
		}

		$exitCode = Invoke-StreamingProcess -FilePath $chocoPath -ArgumentList @(
			'uninstall', $resolvedChocoId, '-y', '--no-progress'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Uninstall - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Uninstall - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ChocoUninstall:catch1445' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Uninstall' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs choco update.

    #>

function Invoke-ChocoUpdate
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ChocoId,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$resolvedChocoId = Resolve-ApplicationPackageId -PackageId $ChocoId
	Write-ConsoleStatus -Action ("Updating '{0}' via Chocolatey..." -f $DisplayName)

	try
	{
		$chocoPath = Resolve-ChocolateyExecutable
		if (-not $chocoPath)
		{
			Invoke-ChocolateyBootstrapInstall -TimeoutSeconds $TimeoutSeconds
			$chocoPath = Resolve-ChocolateyExecutable
		}

		if (-not $chocoPath)
		{
			$failureMessage = "{0} Update - Failed" -f $DisplayName
			LogError $failureMessage
			throw $failureMessage
		}

		$exitCode = Invoke-StreamingProcess -FilePath $chocoPath -ArgumentList @(
			'upgrade', $resolvedChocoId, '-y', '--no-progress'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo ("{0} Update - Success" -f $DisplayName)
			return
		}

		$failureMessage = "{0} Update - Failed" -f $DisplayName
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ChocoUpdate:catch1506' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Update' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs winget update all.

    #>

function Invoke-WingetUpdateAll
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$wingetAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'WinGetAvailable'
	if ($null -eq $wingetAvailableState)
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogError $failureMessage
			throw $failureMessage
		}
	}
	elseif (-not [bool]$wingetAvailableState)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	$wingetPath = Resolve-WinGetExecutable
	if (-not $wingetPath)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_WinGet_CheckingUpdates' -Fallback 'Checking for WinGet updates...')

	try
	{
		$exitCode = Invoke-StreamingProcess -FilePath $wingetPath -ArgumentList @(
			'upgrade', '--all', '--include-unknown', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo 'WinGet Update All - Success'
			return
		}

		$failureMessage = 'WinGet Update All - Failed'
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-WingetUpdateAll:catch1571' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName 'WinGet Update All' -ActionLabel 'Update' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs choco update all.

    #>

function Invoke-ChocoUpdateAll
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$chocoAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'ChocolateyAvailable'
	if ($null -eq $chocoAvailableState)
	{
		if (-not (Test-ChocolateyAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Choco_NotAvailable' -Fallback 'Chocolatey is not available on this system.'
			LogError $failureMessage
			throw $failureMessage
		}
	}
	elseif (-not [bool]$chocoAvailableState)
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Choco_NotAvailable' -Fallback 'Chocolatey is not available on this system.'
		LogError $failureMessage
		throw $failureMessage
	}

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Choco_CheckingUpdates' -Fallback 'Checking Chocolatey updates...')

	try
	{
		$chocoPath = Resolve-ChocolateyExecutable
		if (-not $chocoPath)
		{
			$failureMessage = 'Chocolatey Update All - Failed'
			LogError $failureMessage
			throw $failureMessage
		}

		$exitCode = Invoke-StreamingProcess -FilePath $chocoPath -ArgumentList @(
			'upgrade', 'all', '-y', '--no-progress'
		) -TimeoutSeconds $TimeoutSeconds

		if ($exitCode -eq 0)
		{
			LogInfo 'Chocolatey Update All - Success'
			return
		}

		$failureMessage = 'Chocolatey Update All - Failed'
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-ChocoUpdateAll:catch1636' -Severity Debug }

		Throw-ApplicationActionFailure -TargetName 'Chocolatey Update All' -ActionLabel 'Update' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
	}
}

<#
    .SYNOPSIS
    Runs store install.

    #>

function Invoke-StoreInstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$StoreUri,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,

		[Parameter(Mandatory = $false)]
		[scriptblock]$ApplyButtonChrome = $null,

		[Parameter(Mandatory = $false)]
		[object]$OwnerWindow = $null,

		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Store_StartingInstallation' -Fallback 'Opening Microsoft Store for {0}...' -FormatArgs @($DisplayName))
	LogInfo (Get-BaselineLocalizedString -Key 'Progress_Store_Opening' -Fallback 'Opening Microsoft Store for {0}...' -FormatArgs @($DisplayName))

	try
	{
		$UseDarkMode = Resolve-ApplicationDialogUseDarkMode -UseDarkMode $UseDarkMode
		$Theme = Get-ApplicationDialogTheme -Theme $Theme
		$ApplyButtonChrome = Get-ApplicationDialogButtonChrome -ApplyButtonChrome $ApplyButtonChrome

		# Open Store
		Start-Process -FilePath $StoreUri

		# Show themed dialog that blocks until user clicks OK
		$messageText = Get-BaselineLocalizedString -Key 'Progress_Store_InstallPrompt' -Fallback "Microsoft Store has been opened for {0}.`n`nPlease install the app manually, then click OK to continue with the next app." -FormatArgs @($DisplayName)

		$dialogResult = GUICommon\Show-GuiCommonThemedDialog `
			-Theme $Theme `
			-ApplyButtonChrome $ApplyButtonChrome `
			-OwnerWindow $OwnerWindow `
			-Title (Get-BaselineLocalizedString -Key 'Progress_Store_DialogTitle' -Fallback 'Manual Installation Required') `
			-Message $messageText `
			-Buttons @('OK') `
			-UseDarkMode $UseDarkMode

		Start-Sleep -Seconds 2

		# Verify installation (for future enhancement - currently just logs)
		LogInfo (Get-BaselineLocalizedString -Key 'Progress_Store_OpenedSuccess' -Fallback 'Microsoft Store interaction completed for {0}. Proceeding to next app.' -FormatArgs @($DisplayName))
		return
	}
	catch
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}
}

function Get-ApplicationDialogTheme
{
	param (
		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null
	)

	if ($Theme -and $Theme.Count -gt 0)
	{
		return $Theme
	}

	if (Test-Path -Path Variable:\Script:CurrentTheme)
	{
		return $Script:CurrentTheme
	}

	if (Test-Path -Path Variable:\Global:BaselineCurrentTheme)
	{
		return $Global:BaselineCurrentTheme
	}

	return @{}
}

function Resolve-ApplicationDialogUseDarkMode
{
	param (
		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	if (Test-Path -Path Variable:\Script:CurrentThemeName)
	{
		return ([string]$Script:CurrentThemeName -ne 'Light')
	}

	if (Test-Path -Path Variable:\Global:BaselineCurrentThemeName)
	{
		return ([string]$Global:BaselineCurrentThemeName -ne 'Light')
	}

	if (Test-Path -Path Variable:\Global:BaselineUseDarkMode)
	{
		return [bool]$Global:BaselineUseDarkMode
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$env:BASELINE_USE_DARK_MODE))
	{
		return ([string]$env:BASELINE_USE_DARK_MODE -eq '1')
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$env:BASELINE_THEME_NAME))
	{
		return ([string]$env:BASELINE_THEME_NAME -ne 'Light')
	}

	return [bool]$UseDarkMode
}

function Get-ApplicationDialogButtonChrome
{
	param (
		[Parameter(Mandatory = $false)]
		[scriptblock]$ApplyButtonChrome = $null
	)

	if ($ApplyButtonChrome)
	{
		return $ApplyButtonChrome
	}

	if (Test-Path -Path Function:\Set-ButtonChrome)
	{
		return ${function:Set-ButtonChrome}
	}

	return { param($Button, $Variant) }
}

<#
    .SYNOPSIS
    Runs direct URL install.

    #>

function Invoke-DirectUrlInstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$DirectUrl,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,

		[Parameter(Mandatory = $false)]
		[scriptblock]$ApplyButtonChrome = $null,

		[Parameter(Mandatory = $false)]
		[object]$OwnerWindow = $null,

		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true,

		[int]$TimeoutSeconds = 1800
	)

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_DirectUrl_StartingDownload' -Fallback 'Downloading {0}...' -FormatArgs @($DisplayName))
	LogInfo (Get-BaselineLocalizedString -Key 'Progress_DirectUrl_Downloading' -Fallback 'Downloading {0} from {1}...' -FormatArgs @($DisplayName, $DirectUrl))

	try
	{
		# Resolve theme if not provided
		if ($null -eq $Theme)
		{
			$Theme = if (Test-Path -Path Variable:\Script:CurrentTheme) { $Script:CurrentTheme } else { @{} }
		}

		if ($null -eq $ApplyButtonChrome)
		{
			$ApplyButtonChrome = if (Test-Path -Path Function:\Set-ButtonChrome) { ${function:Set-ButtonChrome} } else { { } }
		}

		if (Test-Path -Path Variable:\Script:CurrentThemeName)
		{
			$UseDarkMode = ($Script:CurrentThemeName -eq 'Dark')
		}

		$tempDir = [System.IO.Path]::GetTempPath()
		$fileName = Split-Path -Leaf $DirectUrl
		$filePath = Join-Path -Path $tempDir -ChildPath $fileName

		$webClient = New-Object System.Net.WebClient
		$webClient.DownloadFile($DirectUrl, $filePath)

		LogInfo (Get-BaselineLocalizedString -Key 'Progress_DirectUrl_Downloaded' -Fallback 'Downloaded {0} to {1}. Attempting to execute...' -FormatArgs @($DisplayName, $filePath))

		if ($filePath.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase))
		{
			$result = Start-Process -FilePath $filePath -PassThru -ErrorAction Stop
			$exitCode = Wait-ApplicationProcess -Process $result -TimeoutSeconds $TimeoutSeconds
			if ($exitCode -eq 0 -or $exitCode -eq 3010)
			{
				LogInfo (Get-BaselineLocalizedString -Key 'Progress_DirectUrl_InstalledSuccess' -Fallback 'Successfully installed {0}' -FormatArgs @($DisplayName))
				return
			}
		}
		else
		{
			$result = Start-Process -FilePath $filePath -PassThru -ErrorAction Stop
			LogInfo (Get-BaselineLocalizedString -Key 'Progress_DirectUrl_OpenedSuccess' -Fallback 'Opened {0}' -FormatArgs @($DisplayName))
			return
		}

		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_FailedInstall' -Fallback 'Failed to install {0}' -FormatArgs @($DisplayName)
		LogError $failureMessage
		throw $failureMessage
	}
	catch
	{
		$timeoutException = Get-ApplicationActionTimeoutException -ErrorRecord $_
		if ($timeoutException)
		{
			Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Install' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
		}

		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}
}

<#
    .SYNOPSIS
    Runs command install.

    #>

function Invoke-CommandInstall
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Command,

		[Parameter(Mandatory = $true)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,

		[Parameter(Mandatory = $false)]
		[scriptblock]$ApplyButtonChrome = $null,

		[Parameter(Mandatory = $false)]
		[object]$OwnerWindow = $null,

		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true,

		[int]$TimeoutSeconds = 1800
	)

	Write-ConsoleStatus -Action (Get-BaselineLocalizedString -Key 'Progress_Command_Executing' -Fallback 'Executing installation command for {0}...' -FormatArgs @($DisplayName))
	LogInfo (Get-BaselineLocalizedString -Key 'Progress_Command_Executing' -Fallback 'Executing installation command for {0}...' -FormatArgs @($DisplayName))

	try
	{
		# Resolve theme if not provided
		if ($null -eq $Theme)
		{
			$Theme = if (Test-Path -Path Variable:\Script:CurrentTheme) { $Script:CurrentTheme } else { @{} }
		}

		if ($null -eq $ApplyButtonChrome)
		{
			$ApplyButtonChrome = if (Test-Path -Path Function:\Set-ButtonChrome) { ${function:Set-ButtonChrome} } else { { } }
		}

		if (Test-Path -Path Variable:\Script:CurrentThemeName)
		{
			$UseDarkMode = ($Script:CurrentThemeName -eq 'Dark')
		}

		$commandInvocation = ConvertTo-ApplicationCommandInvocation -Command $Command
		if (-not $commandInvocation.HasSingleCommandInvocation)
		{
			throw "Command '$Command' must resolve to a single executable invocation."
		}

		$exitCode = Invoke-StreamingProcess `
			-FilePath $commandInvocation.CommandName `
			-ArgumentList $commandInvocation.CommandArguments `
			-TimeoutSeconds $TimeoutSeconds
		if ($exitCode -ne 0)
		{
			throw "Command '$Command' exited with code $exitCode."
		}

		LogInfo (Get-BaselineLocalizedString -Key 'Progress_Command_Success' -Fallback 'Successfully executed installation command for {0}' -FormatArgs @($DisplayName))
		return
	}
	catch
	{
		$timeoutException = Get-ApplicationActionTimeoutException -ErrorRecord $_
		if ($timeoutException)
		{
			Throw-ApplicationActionFailure -TargetName $DisplayName -ActionLabel 'Install' -TimeoutSeconds $TimeoutSeconds -ErrorRecord $_
		}

		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}
}

<#
    .SYNOPSIS
    Runs application action.

    #>

function Invoke-ApplicationAction
{
	[CmdletBinding(DefaultParameterSetName = 'Legacy')]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall', 'Update')]
		[string]$Action,

		[Parameter(Mandatory = $true, ParameterSetName = 'Application')]
		[object]$Application,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$WinGetId,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$ChocoId,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$DisplayName,

		[Parameter(Mandatory = $false, ParameterSetName = 'Application')]
		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$PreferredSource,

		[Parameter(Mandatory = $false, ParameterSetName = 'Application')]
		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[object]$PackageManagerAvailabilityState = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'Application')]
		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[int]$TimeoutSeconds = 900
	)

	if ($PSCmdlet.ParameterSetName -eq 'Application')
	{
		$route = Resolve-ApplicationExecutionRoute -Application $Application -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -Action $Action
		if ($route.Route -eq 'unsupported')
		{
			LogError $route.Reason
			throw $route.Reason
		}

		switch ($route.Route)
		{
			'winget'
			{
				switch ($Action)
				{
					'Install' { Invoke-WingetInstall -WinGetId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
					'Uninstall' { Invoke-WingetUninstall -WinGetId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
					'Update' { Invoke-WingetUpdate -WinGetId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
				}
			}
			'choco'
			{
				switch ($Action)
				{
					'Install' { Invoke-ChocoInstall -ChocoId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
					'Uninstall' { Invoke-ChocoUninstall -ChocoId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
					'Update' { Invoke-ChocoUpdate -ChocoId $route.PackageId -DisplayName $route.DisplayName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds; return }
				}
			}
			'store'
			{
				$storeParams = @{
					StoreUri = $route.PackageId
					DisplayName = $route.DisplayName
				}

				if (Test-Path -Path Variable:\Script:CurrentTheme)
				{
					$storeParams['Theme'] = $Script:CurrentTheme
				}
				if (Test-Path -Path Function:\Set-ButtonChrome)
				{
					$storeParams['ApplyButtonChrome'] = ${function:Set-ButtonChrome}
				}
				if (Test-Path -Path Variable:\Script:CurrentThemeName)
				{
					$storeParams['UseDarkMode'] = ($Script:CurrentThemeName -eq 'Dark')
				}

				Invoke-StoreInstall @storeParams
				return
			}
			'direct'
			{
				$directParams = @{
					DirectUrl = $route.PackageId
					DisplayName = $route.DisplayName
				}

				if (Test-Path -Path Variable:\Script:CurrentTheme)
				{
					$directParams['Theme'] = $Script:CurrentTheme
				}
				if (Test-Path -Path Function:\Set-ButtonChrome)
				{
					$directParams['ApplyButtonChrome'] = ${function:Set-ButtonChrome}
				}
				if (Test-Path -Path Variable:\Script:CurrentThemeName)
				{
					$directParams['UseDarkMode'] = ($Script:CurrentThemeName -eq 'Dark')
				}

				$directParams['TimeoutSeconds'] = $TimeoutSeconds
				Invoke-DirectUrlInstall @directParams
				return
			}
			'command'
			{
				$commandParams = @{
					Command = $route.PackageId
					DisplayName = $route.DisplayName
				}

				if (Test-Path -Path Variable:\Script:CurrentTheme)
				{
					$commandParams['Theme'] = $Script:CurrentTheme
				}
				if (Test-Path -Path Function:\Set-ButtonChrome)
				{
					$commandParams['ApplyButtonChrome'] = ${function:Set-ButtonChrome}
				}
				if (Test-Path -Path Variable:\Script:CurrentThemeName)
				{
					$commandParams['UseDarkMode'] = ($Script:CurrentThemeName -eq 'Dark')
				}

				$commandParams['TimeoutSeconds'] = $TimeoutSeconds
				Invoke-CommandInstall @commandParams
				return
			}
		}

		throw $route.Reason
	}

	$hasWinGetId = -not [string]::IsNullOrWhiteSpace([string]$WinGetId)
	$hasChocoId = -not [string]::IsNullOrWhiteSpace([string]$ChocoId)
	$targetName = if (-not [string]::IsNullOrWhiteSpace([string]$DisplayName)) { [string]$DisplayName } elseif ($hasWinGetId) { [string]$WinGetId } elseif ($hasChocoId) { [string]$ChocoId } else { 'application' }
	$legacyRoute = Resolve-ApplicationExecutionRoute -Application @{
		Name = $targetName
		WinGetId = $WinGetId
		ChocoId = $ChocoId
		SupportsExecution = $true
	} -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -Action $Action

	if ($legacyRoute.Route -eq 'unsupported')
	{
		LogError $legacyRoute.Reason
		throw $legacyRoute.Reason
	}

	switch ($Action)
	{
		'Install'
		{
			if ($legacyRoute.Route -eq 'winget')
			{
				Invoke-WingetInstall -WinGetId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			if ($legacyRoute.Route -eq 'choco')
			{
				Invoke-ChocoInstall -ChocoId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			throw $legacyRoute.Reason
		}
		'Uninstall'
		{
			if ($legacyRoute.Route -eq 'winget')
			{
				Invoke-WingetUninstall -WinGetId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			if ($legacyRoute.Route -eq 'choco')
			{
				Invoke-ChocoUninstall -ChocoId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			throw $legacyRoute.Reason
		}
		'Update'
		{
			if ($legacyRoute.Route -eq 'winget')
			{
				Invoke-WingetUpdate -WinGetId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			if ($legacyRoute.Route -eq 'choco')
			{
				Invoke-ChocoUpdate -ChocoId $legacyRoute.PackageId -DisplayName $targetName -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
				return
			}

			throw $legacyRoute.Reason
		}
	}
}

<#
	.SYNOPSIS
	Compatibility wrapper for install and uninstall actions.



.DESCRIPTION

Applies the Baseline behavior for compatibility wrapper for install and uninstall actions..
	.PARAMETER Install
	Install the specified application.

	.PARAMETER Uninstall
	Uninstall the specified application.

	.PARAMETER WinGetId
	Optional WinGet package identifier (e.g. Mozilla.Firefox).

	.PARAMETER ChocoId
	Optional Chocolatey package identifier used as fallback.

	.PARAMETER DisplayName
	Friendly application name used for progress and log messages.

	.EXAMPLE
	AppInstall -Install -WinGetId "Mozilla.Firefox" -ChocoId "firefox"

	.EXAMPLE
	AppInstall -Uninstall -WinGetId "Mozilla.Firefox"

	.NOTES
	Machine-wide
#>

function AppInstall
{
	param
	(
		[Parameter(Mandatory = $false)]
		[switch]$Install,

		[Parameter(Mandatory = $false)]
		[switch]$Uninstall,

		[Parameter(Mandatory = $false)]
		[string]$WinGetId,

		[Parameter(Mandatory = $false)]
		[string]$ChocoId,

		[Parameter(Mandatory = $false)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[string]$PreferredSource,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[Parameter(Mandatory = $false)]
		[int]$TimeoutSeconds = 900
	)

	if ($Install)
	{
		Invoke-ApplicationAction -Action 'Install' -WinGetId $WinGetId -ChocoId $ChocoId -DisplayName $DisplayName -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
		return
	}

	if ($Uninstall)
	{
		Invoke-ApplicationAction -Action 'Uninstall' -WinGetId $WinGetId -ChocoId $ChocoId -DisplayName $DisplayName -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
		return
	}
}

<#
	.SYNOPSIS
	Retrieves a cached list of installed applications via WinGet to prevent UI freezing.


.DESCRIPTION

Applies the Baseline behavior for retrieves a cached list of installed applications via WinGet to prevent UI freezing..
#>
function Get-InstalledAppCache
{
	param (
		[int]$TimeoutSeconds = 300
	)

	LogInfo (Get-BaselineLocalizedString -Key 'Progress_CheckingInstallStatus' -Fallback 'Checking installation status...')
	$installedCache = @{}
	$wingetPath = Resolve-WinGetExecutable

	try
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogWarning $failureMessage
			return $installedCache
		}

		if (-not $wingetPath)
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.'
			LogWarning $failureMessage
			return $installedCache
		}

		$processResult = Invoke-ProcessTextCapture -FilePath $wingetPath -ArgumentList @(
			"list", "--accept-source-agreements", "--disable-interactivity"
		) -TimeoutSeconds $TimeoutSeconds
		if ($processResult.ExitCode -ne 0)
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @("winget list exited with code $($processResult.ExitCode)")
			LogError $failureMessage
			throw $failureMessage
		}

		$output = @(([string]$processResult.StandardOutput) -split "(`r`n|`n|`r)")
		$inTable = $false
		foreach ($line in $output)
		{
			$trimmedLine = [string]$line
			if ([string]::IsNullOrWhiteSpace($trimmedLine))
			{
				continue
			}

			$trimmedLine = $trimmedLine.Trim()
			if (-not $inTable)
			{
				if ($trimmedLine -match '^-+$')
				{
					$inTable = $true
				}
				continue
			}

			$columns = @($trimmedLine -split '\s{2,}')
			if ($columns.Count -lt 2)
			{
				continue
			}

			$packageId = [string]$columns[1].Trim()
			if ([string]::IsNullOrWhiteSpace($packageId))
			{
				continue
			}

			if ($packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
			{
				continue
			}

			$installedCache[$packageId] = $true
		}

		LogInfo (Get-BaselineLocalizedString -Key 'Progress_AppsCacheGenerated' -Fallback 'App cache generated with {0} detected packages.' -FormatArgs @($installedCache.Count))
	}
	catch
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}
	return $installedCache
}

<#
    .SYNOPSIS
    Gets installed chocolatey app cache.

    #>

function Get-InstalledChocolateyAppCache
{
	param (
		[int]$TimeoutSeconds = 300
	)

	LogInfo 'Checking Chocolatey installation status...'
	$installedCache = @{}
	if (-not (Test-ChocolateyAvailable -Refresh))
	{
		LogInfo 'Chocolatey is not available on this system.'
		return $installedCache
	}

	$chocoPath = Resolve-ChocolateyExecutable
	if (-not $chocoPath)
	{
		LogInfo 'Chocolatey is not available on this system.'
		return $installedCache
	}

	try
	{
		$processResult = Invoke-ProcessTextCapture -FilePath $chocoPath -ArgumentList @(
			'list', '--local-only', '--limit-output', '--no-progress'
		) -TimeoutSeconds $TimeoutSeconds
		if ($processResult.ExitCode -ne 0)
		{
			throw "choco list exited with code $($processResult.ExitCode)"
		}

		$output = @(([string]$processResult.StandardOutput) -split "(`r`n|`n|`r)")
		foreach ($line in @($output))
		{
			$trimmedLine = [string]$line
			if ([string]::IsNullOrWhiteSpace($trimmedLine))
			{
				continue
			}

			$packageId = ([string]$trimmedLine -split '\|', 2)[0].Trim()
			if ([string]::IsNullOrWhiteSpace($packageId))
			{
				continue
			}

			$installedCache[$packageId] = $true
		}

		LogInfo ("Chocolatey cache generated with {0} detected packages." -f $installedCache.Count)
	}
	catch
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}

	return $installedCache
}

<#
    .SYNOPSIS
    Gets available app update cache.

    #>

function Get-AvailableAppUpdateCache
{
	param (
		[int]$TimeoutSeconds = 300
	)

	LogInfo 'Checking WinGet update availability...'
	$updateCache = @{}
	$wingetPath = Resolve-WinGetExecutable

	try
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			LogInfo (Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.')
			return $updateCache
		}

		if (-not $wingetPath)
		{
			LogInfo (Get-BaselineLocalizedString -Key 'Progress_WinGet_NotAvailable' -Fallback 'WinGet is not available on this system.')
			return $updateCache
		}

		$processResult = Invoke-ProcessTextCapture -FilePath $wingetPath -ArgumentList @(
			"list", "--upgrade-available", "--include-unknown", "--accept-source-agreements", "--disable-interactivity"
		) -TimeoutSeconds $TimeoutSeconds
		if ($processResult.ExitCode -ne 0)
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @("winget list --upgrade-available --include-unknown exited with code $($processResult.ExitCode)")
			LogError $failureMessage
			throw $failureMessage
		}

		$output = @(([string]$processResult.StandardOutput) -split "(`r`n|`n|`r)")
		$inTable = $false
		foreach ($line in $output)
		{
			$trimmedLine = [string]$line
			if ([string]::IsNullOrWhiteSpace($trimmedLine))
			{
				continue
			}

			$trimmedLine = $trimmedLine.Trim()
			if (-not $inTable)
			{
				if ($trimmedLine -match '^-+$')
				{
					$inTable = $true
				}
				continue
			}

			$columns = @($trimmedLine -split '\s{2,}')
			if ($columns.Count -lt 2)
			{
				continue
			}

			$packageId = [string]$columns[1].Trim()
			if ([string]::IsNullOrWhiteSpace($packageId))
			{
				continue
			}

			if ($packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
			{
				continue
			}

			$updateCache[$packageId] = $true
		}

		LogInfo ("WinGet update cache generated with {0} detected packages." -f $updateCache.Count)
	}
	catch
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}

	return $updateCache
}

<#
    .SYNOPSIS
    Gets available chocolatey update cache.

    #>

function Get-AvailableChocolateyUpdateCache
{
	param (
		[int]$TimeoutSeconds = 300
	)

	LogInfo 'Checking Chocolatey update availability...'
	$updateCache = @{}
	if (-not (Test-ChocolateyAvailable -Refresh))
	{
		LogInfo 'Chocolatey is not available on this system.'
		return $updateCache
	}

	$chocoPath = Resolve-ChocolateyExecutable
	if (-not $chocoPath)
	{
		LogInfo 'Chocolatey is not available on this system.'
		return $updateCache
	}

	try
	{
		$processResult = Invoke-ProcessTextCapture -FilePath $chocoPath -ArgumentList @(
			'outdated', '--limit-output', '--no-progress'
		) -TimeoutSeconds $TimeoutSeconds
		if ($processResult.ExitCode -ne 0)
		{
			throw "choco outdated exited with code $($processResult.ExitCode)"
		}

		$output = @(([string]$processResult.StandardOutput) -split "(`r`n|`n|`r)")
		foreach ($line in @($output))
		{
			$trimmedLine = [string]$line
			if ([string]::IsNullOrWhiteSpace($trimmedLine))
			{
				continue
			}

			$packageId = ([string]$trimmedLine -split '\|', 2)[0].Trim()
			if ([string]::IsNullOrWhiteSpace($packageId))
			{
				continue
			}

			$updateCache[$packageId] = $true
		}

		LogInfo ("Chocolatey update cache generated with {0} detected packages." -f $updateCache.Count)
	}
	catch
	{
		$failureMessage = Get-BaselineLocalizedString -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @($_.Exception.Message)
		LogError $failureMessage
		throw $failureMessage
	}

	return $updateCache
}

<#
	.SYNOPSIS
	Updates a specific application or all available applications.



.DESCRIPTION

Applies the Baseline behavior for updates a specific application or all available applications..
	.PARAMETER WinGetId
	Optional WinGet package identifier for the application to update.

	.PARAMETER ChocoId
	Optional Chocolatey package identifier used as fallback.

	.PARAMETER DisplayName
	Friendly application name used for progress and log messages.

	.PARAMETER All
	Update all available applications.
#>
function AppUpdate
{
	param
	(
		[Parameter(Mandatory = $false)]
		[string]$WinGetId,

		[Parameter(Mandatory = $false)]
		[string]$ChocoId,

		[Parameter(Mandatory = $false)]
		[string]$DisplayName,

		[Parameter(Mandatory = $false)]
		[string]$PreferredSource,

		[Parameter(Mandatory = $false)]
		[object]$PackageManagerAvailabilityState = $null,

		[Parameter(Mandatory = $false)]
		[switch]$All,

		[Parameter(Mandatory = $false)]
		[int]$TimeoutSeconds = 900
	)

	$wingetPath = Resolve-WinGetExecutable
	$hasWinGetId = -not [string]::IsNullOrWhiteSpace([string]$WinGetId)
	$hasChocoId = -not [string]::IsNullOrWhiteSpace([string]$ChocoId)
	$resolvedChocoId = if ($hasChocoId) { Resolve-ApplicationPackageId -PackageId $ChocoId } else { $null }
	$targetName = if (-not [string]::IsNullOrWhiteSpace([string]$DisplayName)) { [string]$DisplayName } elseif ($hasWinGetId) { [string]$WinGetId } elseif ($hasChocoId) { [string]$resolvedChocoId } else { [string]$WinGetId }

	if ($All)
	{
		$wingetAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'WinGetAvailable'
		$chocolateyAvailableState = Get-PackageManagerAvailabilityStateValue -AvailabilityState $PackageManagerAvailabilityState -PropertyName 'ChocolateyAvailable'
		$attemptedAny = $false
		$failureMessages = [System.Collections.Generic.List[string]]::new()

		$shouldAttemptWinget = if ($null -eq $wingetAvailableState)
		{
			Test-WinGetAvailable -Refresh
		}
		else
		{
			[bool]$wingetAvailableState
		}

		if ($shouldAttemptWinget -and $wingetPath)
		{
			$attemptedAny = $true
			try
			{
				Invoke-WingetUpdateAll -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.AppUpdate:catch2656' -Severity Debug }

				[void]$failureMessages.Add([string]$_.Exception.Message)
			}
		}

		$shouldAttemptChocolatey = if ($null -eq $chocolateyAvailableState)
		{
			Test-ChocolateyAvailable -Refresh
		}
		else
		{
			[bool]$chocolateyAvailableState
		}

		if ($shouldAttemptChocolatey)
		{
			$attemptedAny = $true
			try
			{
				Invoke-ChocoUpdateAll -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.AppUpdate:catch2678' -Severity Debug }

				[void]$failureMessages.Add([string]$_.Exception.Message)
			}
		}
		elseif (-not $wingetPath)
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_App_NoInstallMethod' -Fallback 'No install method available for {0}.' -FormatArgs @('application updates')
			LogError $failureMessage
			throw $failureMessage
		}

		if (-not $attemptedAny)
		{
			$failureMessage = Get-BaselineLocalizedString -Key 'Progress_App_NoInstallMethod' -Fallback 'No install method available for {0}.' -FormatArgs @('application updates')
			LogError $failureMessage
			throw $failureMessage
		}

		if ($failureMessages.Count -gt 0)
		{
			$failureMessage = ($failureMessages -join ' ')
			throw $failureMessage
		}

		LogInfo (Get-BaselineLocalizedString -Key 'Progress_App_UpdatesReady' -Fallback 'Application updates completed.')
	}
	elseif ($hasWinGetId -or $hasChocoId)
	{
		Invoke-ApplicationAction -Action 'Update' -WinGetId $WinGetId -ChocoId $ChocoId -DisplayName $targetName -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
		return
	}
}

<#
	.SYNOPSIS
	Applies a single app action across multiple selected applications.


.DESCRIPTION

Applies the Baseline behavior for applies a single app action across multiple selected applications..
#>
function Invoke-AppBatchAction
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall', 'Update')]
		[string]$Action,

		[Parameter(Mandatory = $true)]
		[object[]]$Applications,

		[string]$PreferredSource = $null,

		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 900
	)

	$uniqueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$successfulApps = [System.Collections.Generic.List[object]]::new()
	$failedApps = [System.Collections.Generic.List[object]]::new()

	foreach ($application in @($Applications))
	{
		if (-not $application)
		{
			continue
		}

		$route = Resolve-ApplicationExecutionRoute -Application $application -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -Action $Action
		if (-not $uniqueIds.Add($route.IdentityKey))
		{
			continue
		}

		if ($route.Route -eq 'unsupported')
		{
			$failedApps.Add([pscustomobject]@{
				SelectionKey = $route.SelectionKey
				WinGetId   = $route.WinGetId
				ChocoId    = $route.ChocoId
				Name       = $route.DisplayName
				EntityType = if ([string]::IsNullOrWhiteSpace($route.EntityType)) { 'placeholder' } else { $route.EntityType }
				Route      = $route.Route
				SelectedSource = $route.SelectedSource
				PackageId  = $route.PackageId
				Error      = $route.Reason
			}) | Out-Null
			continue
		}

		try
		{
			Invoke-ApplicationAction -Action $Action -Application $application -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -TimeoutSeconds $TimeoutSeconds
			$successfulApps.Add([pscustomobject]@{
				SelectionKey = $route.SelectionKey
				WinGetId   = $route.WinGetId
				ChocoId    = $route.ChocoId
				Name       = $route.DisplayName
				EntityType = $route.EntityType
				Route      = $route.Route
				SelectedSource = $route.SelectedSource
				PackageId  = $route.PackageId
			}) | Out-Null
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Applications.Invoke-AppBatchAction:catch2787' -Severity Debug }

			$failedApps.Add([pscustomobject]@{
				SelectionKey = $route.SelectionKey
				WinGetId   = $route.WinGetId
				ChocoId    = $route.ChocoId
				Name       = $route.DisplayName
				EntityType = $route.EntityType
				Route      = $route.Route
				SelectedSource = $route.SelectedSource
				PackageId  = $route.PackageId
				Error      = [string]$_.Exception.Message
			}) | Out-Null
		}
	}

	$processedCount = $successfulApps.Count + $failedApps.Count
	if ($processedCount -eq 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_NoSelection' -Fallback 'No applications were selected.'
		LogWarning $message
		return [pscustomobject]@{
			Action         = $Action
			TotalCount      = 0
			SuccessCount    = 0
			FailureCount    = 0
			Outcome         = 'Failed'
			Message         = $message
			SuccessfulApps  = @()
			FailedApps      = @()
		}
	}

	$pastTense = switch ($Action)
	{
		'Install'   { 'installed' }
		'Uninstall' { 'uninstalled' }
		'Update'    { 'updated' }
	}

	if ($failedApps.Count -gt 0 -and $successfulApps.Count -gt 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchPartial' -Fallback 'Partially {0} {1} selected app(s): {2} succeeded, {3} failed.' -FormatArgs @($pastTense, $processedCount, $successfulApps.Count, $failedApps.Count)
		LogWarning $message
		$outcome = 'Partial'
	}
	elseif ($failedApps.Count -gt 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchFailed' -Fallback 'Failed to {0} {1} selected app(s).' -FormatArgs @($pastTense, $processedCount)
		LogError $message
		$outcome = 'Failed'
	}
	else
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchSuccess' -Fallback 'Successfully {0} {1} selected app(s).' -FormatArgs @($pastTense, $successfulApps.Count)
		LogInfo $message
		$outcome = 'Success'
	}

	return [pscustomobject]@{
		Action         = $Action
		TotalCount      = $processedCount
		SuccessCount    = $successfulApps.Count
		FailureCount    = $failedApps.Count
		Outcome         = $outcome
		Message         = $message
		SuccessfulApps  = @($successfulApps)
		FailedApps      = @($failedApps)
	}
}

#endregion
