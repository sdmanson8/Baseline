<#
    .SYNOPSIS
    Internal shared helper loader module for Baseline.

    .DESCRIPTION
    Imports the helper slices from Module/SharedHelperModules in declared
    dependency order and exports the shared helper functions consumed across
    the project. This is internal plumbing for the Baseline runtime.
#>

# These script-scope variables are available to helper wrappers and any
# functions defined directly in this loader module.
$Script:SharedHelpersModuleRoot = $PSScriptRoot
$Script:SharedHelpersRepoRoot = Split-Path $PSScriptRoot -Parent

# Load order still matters: Manifest depends on GameMode metadata helpers, so
# GameMode must load first. SingleInstance relies on the ErrorHandling debug
# helper, so it loads after ErrorHandling. The wrappers keep each helper in
# its own named module while preserving a declared import order here in the
# loader.
$helperModulesRoot = Join-Path $PSScriptRoot 'SharedHelperModules'
$HelperModuleNames = @(
    'Baseline.SharedHelpers.Json'
    'Baseline.SharedHelpers.Localization'
    'Baseline.SharedHelpers.FeatureMaturity'
    'Baseline.SharedHelpers.ErrorHandling'
    'Baseline.SharedHelpers.Process'
    'Baseline.SharedHelpers.CliMode'
    'Baseline.SharedHelpers.SingleInstance'
    'Baseline.SharedHelpers.Integrity'
    'Baseline.SharedHelpers.Registry'
    'Baseline.SharedHelpers.Environment'
    'Baseline.SharedHelpers.GameMode'
    'Baseline.SharedHelpers.Manifest'
    'Baseline.SharedHelpers.PlatformSupport'
    'Baseline.SharedHelpers.ScenarioMode'
    'Baseline.SharedHelpers.Preset'
    'Baseline.SharedHelpers.Recovery'
    'Baseline.SharedHelpers.Lifecycle'
    'Baseline.SharedHelpers.PackageManagement'
    'Baseline.SharedHelpers.AdvancedStartup'
    'Baseline.SharedHelpers.Taskbar'
    'Baseline.SharedHelpers.SystemMaintenance'
    'Baseline.SharedHelpers.Persistence'
    'Baseline.SharedHelpers.ConfigProfile'
    'Baseline.SharedHelpers.StateCapture'
    'Baseline.SharedHelpers.Compliance'
    'Baseline.SharedHelpers.AuditTrail'
    'Baseline.SharedHelpers.SupportBundle'
    'Baseline.SharedHelpers.Scheduler'
    'Baseline.SharedHelpers.RemovalPersistence'
    'Baseline.SharedHelpers.UserApps'
    'Baseline.SharedHelpers.RansomwareFtype'
    'Baseline.SharedHelpers.NetworkHardening'
    'Baseline.SharedHelpers.BrowserPolicies'
    'Baseline.SharedHelpers.AuthHardening'
    'Baseline.SharedHelpers.RemoteTarget'
    'Baseline.SharedHelpers.GroupPolicy'
    'Baseline.SharedHelpers.CliOutput'
    'Baseline.SharedHelpers.OperatorPolicy'
    'Baseline.SharedHelpers.InitialActions'
    'Baseline.SharedHelpers.WindowsFeatures'
    'Baseline.SharedHelpers.WindowsUpdate'
    'Baseline.SharedHelpers.WindowPosition'
    'Baseline.SharedHelpers.Wsl'
)

foreach ($helperModuleName in $HelperModuleNames)
{
    $helperModulePath = Join-Path $helperModulesRoot "$helperModuleName.psm1"
    if (-not (Test-Path -LiteralPath $helperModulePath))
    {
        throw "Required shared helper module is missing: $helperModulePath"
    }

    foreach ($existingHelperModule in @(Get-Module -Name $helperModuleName -All))
    {
        Remove-Module -ModuleInfo $existingHelperModule -Force -ErrorAction SilentlyContinue
    }

    try
    {
        Import-Module -Name $helperModulePath -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    }
    catch
    {
        $message = "Failed to import shared helper module '$helperModuleName' from '$helperModulePath': $($_.Exception.Message)"
        $exception = New-Object System.InvalidOperationException -ArgumentList $message, $_.Exception
        throw $exception
    }
}

$helperModuleNamesForCleanup = @($HelperModuleNames)
$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($helperModuleName in $helperModuleNamesForCleanup)
    {
        foreach ($loadedHelperModule in @(Get-Module -Name $helperModuleName -All))
        {
            Remove-Module -ModuleInfo $loadedHelperModule -Force -ErrorAction SilentlyContinue
        }
    }
}.GetNewClosure()

function Test-GuiObjectField
{
    [CmdletBinding()]
    param (
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
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

function Get-GuiObjectField
{
    [CmdletBinding()]
    param (
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    if (-not (Test-GuiObjectField -Object $Object -FieldName $FieldName))
    {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary])
    {
        return $Object[$FieldName]
    }

    return $Object.PSObject.Properties[$FieldName].Value
}

function Resolve-BaselinePolicyToolPath
{
    [CmdletBinding()]
    param()

    $candidate = Join-Path $Script:SharedHelpersRepoRoot 'Assets\BaselinePolicyTool.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf))
    {
        throw "Baseline policy tool was expected at '$candidate' but was not found."
    }

    return [IO.Path]::GetFullPath($candidate)
}

<#
    .SYNOPSIS
    Converts values to power scheme display value.

    #>

function ConvertTo-PowerSchemeDisplayValue
{
	param (
		[object]$Value,
		[string]$Units
	)

	if ($null -eq $Value)
	{
		return $null
	}

	$numericValue = Get-GuiNumericRangeValue -Value $Value
	if ($null -eq $numericValue)
	{
		return $null
	}

	switch -Regex ([string]$Units)
	{
		'^\s*minutes\s*$'
		{
			$numericValue = [double]$numericValue / 60
			break
		}
		'^\s*hours\s*$'
		{
			$numericValue = [double]$numericValue / 3600
			break
		}
		'^\s*milliseconds\s*$'
		{
			$numericValue = [double]$numericValue * 1000
			break
		}
	}

	if ($numericValue -is [double] -and [math]::Abs($numericValue - [math]::Round($numericValue)) -lt 0.0000001)
	{
		return [int][math]::Round($numericValue)
	}

	return $numericValue
}

<#
    .SYNOPSIS
    Converts values to power scheme system value.

    #>

function ConvertTo-PowerSchemeSystemValue
{
	param (
		[object]$Value,
		[string]$Units
	)

	if ($null -eq $Value)
	{
		return $null
	}

	$numericValue = Get-GuiNumericRangeValue -Value $Value
	if ($null -eq $numericValue)
	{
		return $null
	}

	switch -Regex ([string]$Units)
	{
		'^\s*minutes\s*$'
		{
			$numericValue = [double]$numericValue * 60
			break
		}
		'^\s*hours\s*$'
		{
			$numericValue = [double]$numericValue * 3600
			break
		}
		'^\s*milliseconds\s*$'
		{
			$numericValue = [double]$numericValue / 1000
			break
		}
	}

	if ($numericValue -is [double] -and [math]::Abs($numericValue - [math]::Round($numericValue)) -lt 0.0000001)
	{
		return [int][math]::Round($numericValue)
	}

	return $numericValue
}

<#
    .SYNOPSIS
    Gets GUI numeric range value.

    #>

function Get-GuiNumericRangeValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Value,

		[object]$NumericRange = $null
	)

	if ($null -eq $Value)
	{
		return $null
	}

	if ($Value -is [System.Collections.IDictionary])
	{
		foreach ($fieldName in @('Value', 'SelectedValue', 'CurrentValue', 'NumericValue', 'ACValue', 'DCValue', 'RawACValue', 'RawDCValue'))
		{
			if ($Value.Contains($fieldName))
			{
				$Value = $Value[$fieldName]
				break
			}
		}
	}
	elseif ($Value.PSObject)
	{
		foreach ($fieldName in @('Value', 'SelectedValue', 'CurrentValue', 'NumericValue'))
		{
			if ($Value.PSObject.Properties[$fieldName])
			{
				$Value = $Value.$fieldName
				break
			}
		}
	}

	if ($null -eq $Value)
	{
		return $null
	}

	$text = ([string]$Value).Trim()
	if ([string]::IsNullOrWhiteSpace($text))
	{
		return $null
	}

	$units = $null
	if ($NumericRange)
	{
		if ($NumericRange -is [System.Collections.IDictionary] -and $NumericRange.Contains('Units'))
		{
			$units = [string]$NumericRange['Units']
		}
		elseif ($NumericRange.PSObject -and $NumericRange.PSObject.Properties['Units'])
		{
			$units = [string]$NumericRange.Units
		}
	}

	if (-not [string]::IsNullOrWhiteSpace($units))
	{
		if ($units -eq '%')
		{
			$text = $text.TrimEnd('%').Trim()
		}
		elseif ($text.EndsWith($units, [System.StringComparison]::OrdinalIgnoreCase))
		{
			$text = $text.Substring(0, $text.Length - $units.Length).Trim()
		}
	}

	$parsedValue = 0.0
	$numberStyles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
	if (-not [double]::TryParse($text, $numberStyles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue))
	{
		return $null
	}

	if ([math]::Abs($parsedValue - [math]::Round($parsedValue)) -lt 0.0000001)
	{
		return [int][math]::Round($parsedValue)
	}

	return $parsedValue
}

<#
    .SYNOPSIS
    Formats GUI numeric range value text.

    #>

function Format-GuiNumericRangeValueText
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Value,

		[object]$NumericRange = $null,

		[string]$Units = $null
	)

	$displayValue = Get-GuiNumericRangeValue -Value $Value -NumericRange $NumericRange
	if ($null -eq $displayValue)
	{
		return $null
	}

	if ([string]::IsNullOrWhiteSpace($Units) -and $NumericRange)
	{
		if ($NumericRange -is [System.Collections.IDictionary] -and $NumericRange.Contains('Units'))
		{
			$Units = [string]$NumericRange['Units']
		}
		elseif ($NumericRange.PSObject -and $NumericRange.PSObject.Properties['Units'])
		{
			$Units = [string]$NumericRange.Units
		}
	}

	$displayText = [System.Convert]::ToString($displayValue, [System.Globalization.CultureInfo]::InvariantCulture)
	if ([string]::IsNullOrWhiteSpace($Units))
	{
		return $displayText
	}
	if ($Units -eq '%')
	{
		return ('{0}%' -f $displayText)
	}

	return ('{0} {1}' -f $displayText, $Units)
}

<#
    .SYNOPSIS
    Formats GUI power scheme value text.

    #>

function Format-GuiPowerSchemeValueText
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Value,

		[object]$NumericRange = $null,

		[string]$Units = $null
	)

	if ($null -eq $Value)
	{
		return $null
	}

	$acValue = $null
	$dcValue = $null
	if ($Value -is [System.Collections.IDictionary])
	{
		if ($Value.Contains('ACValue'))
		{
			$acValue = $Value['ACValue']
		}
		elseif ($Value.Contains('Value'))
		{
			$acValue = $Value['Value']
		}

		if ($Value.Contains('DCValue'))
		{
			$dcValue = $Value['DCValue']
		}
		elseif ($null -ne $acValue)
		{
			$dcValue = $acValue
		}
	}
	elseif ($Value.PSObject)
	{
		if ($Value.PSObject.Properties['ACValue'])
		{
			$acValue = $Value.ACValue
		}
		elseif ($Value.PSObject.Properties['Value'])
		{
			$acValue = $Value.Value
		}

		if ($Value.PSObject.Properties['DCValue'])
		{
			$dcValue = $Value.DCValue
		}
		elseif ($null -ne $acValue)
		{
			$dcValue = $acValue
		}
	}

	if ($null -ne $acValue -or $null -ne $dcValue)
	{
		$acText = if ($null -ne $acValue) { Format-GuiNumericRangeValueText -Value $acValue -NumericRange $NumericRange -Units $Units } else { $null }
		$dcText = if ($null -ne $dcValue) { Format-GuiNumericRangeValueText -Value $dcValue -NumericRange $NumericRange -Units $Units } else { $null }

		if (-not [string]::IsNullOrWhiteSpace([string]$acText) -and -not [string]::IsNullOrWhiteSpace([string]$dcText))
		{
			if ([string]$acText -eq [string]$dcText)
			{
				return [string]$acText
			}

			return ('AC: {0}; DC: {1}' -f [string]$acText, [string]$dcText)
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$acText))
		{
			return ('AC: {0}' -f [string]$acText)
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$dcText))
		{
			return ('DC: {0}' -f [string]$dcText)
		}
	}

	return Format-GuiNumericRangeValueText -Value $Value -NumericRange $NumericRange -Units $Units
}

<#
    .SYNOPSIS
    Gets GUI numeric range channel value.

    #>

function Get-GuiNumericRangeChannelValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Value,

		[ValidateSet('AC', 'DC')]
		[string]$Channel = 'AC',

		[object]$NumericRange = $null
	)

	if ($null -eq $Value)
	{
		return $null
	}

	$channelFields = if ($Channel -eq 'DC')
	{
		@('DCValue', 'ACValue', 'Value', 'NumericValue', 'SelectedValue', 'CurrentValue')
	}
	else
	{
		@('ACValue', 'DCValue', 'Value', 'NumericValue', 'SelectedValue', 'CurrentValue')
	}

	if ($Value -is [System.Collections.IDictionary])
	{
		foreach ($fieldName in $channelFields)
		{
			if ($Value.Contains($fieldName))
			{
				$candidateValue = $Value[$fieldName]
				if ($null -ne $candidateValue)
				{
					return (Get-GuiNumericRangeChannelValue -Value $candidateValue -Channel $Channel -NumericRange $NumericRange)
				}
			}
		}
	}
	elseif ($Value.PSObject)
	{
		foreach ($fieldName in $channelFields)
		{
			if ($Value.PSObject.Properties[$fieldName])
			{
				$candidateValue = $Value.$fieldName
				if ($null -ne $candidateValue)
				{
					return (Get-GuiNumericRangeChannelValue -Value $candidateValue -Channel $Channel -NumericRange $NumericRange)
				}
			}
		}
	}

	return (Get-GuiNumericRangeValue -Value $Value -NumericRange $NumericRange)
}

<#
    .SYNOPSIS
    Gets current power scheme guid.

    #>

function Get-CurrentPowerSchemeGuid
{
	[CmdletBinding()]
	param ()

	try
	{
		$schemeText = (& powercfg /GETACTIVESCHEME 2>$null | Out-String).Trim()
		if ([string]::IsNullOrWhiteSpace($schemeText))
		{
			return $null
		}

		if ($schemeText -match '([0-9a-fA-F-]{36})')
		{
			return [string]$matches[1]
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SharedHelpers.Get-CurrentPowerSchemeGuid:catch597' -Severity Debug }

		return $null
	}

	return $null
}

<#
    .SYNOPSIS
    Gets power scheme setting value.

    #>

function Get-PowerSchemeSettingValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$SubgroupGuid,

		[Parameter(Mandatory = $true)]
		[string]$SettingGuid,

		[string]$SchemeGuid = $null,

		[string]$Units = $null
	)

	$resolvedSchemeGuid = if (-not [string]::IsNullOrWhiteSpace($SchemeGuid)) { [string]$SchemeGuid } else { Get-CurrentPowerSchemeGuid }
	if ([string]::IsNullOrWhiteSpace($resolvedSchemeGuid))
	{
		return $null
	}

	$settingPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$resolvedSchemeGuid\$SubgroupGuid\$SettingGuid"
	if (-not (Test-Path -LiteralPath $settingPath))
	{
		return $null
	}

	$settingItem = Get-ItemProperty -LiteralPath $settingPath -ErrorAction SilentlyContinue
	if (-not $settingItem)
	{
		return $null
	}

	$acRaw = if ($settingItem.PSObject.Properties['ACSettingIndex']) { $settingItem.ACSettingIndex } else { $null }
	$dcRaw = if ($settingItem.PSObject.Properties['DCSettingIndex']) { $settingItem.DCSettingIndex } else { $null }
	$acValue = if ($null -ne $acRaw) { ConvertTo-PowerSchemeDisplayValue -Value $acRaw -Units $Units } else { $null }
	$dcValue = if ($null -ne $dcRaw) { ConvertTo-PowerSchemeDisplayValue -Value $dcRaw -Units $Units } else { $null }

	return [pscustomobject]@{
		SchemeGuid   = $resolvedSchemeGuid
		SubgroupGuid = $SubgroupGuid
		SettingGuid  = $SettingGuid
		Path         = $settingPath
		Units        = $Units
		ACValue      = $acValue
		DCValue      = $dcValue
		Value        = $acValue
		CurrentValue = $acValue
		RawACValue   = $acRaw
		RawDCValue   = $dcRaw
	}
}

<#
    .SYNOPSIS
    Sets power scheme setting value.

    #>

function Set-PowerSchemeSettingValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$SubgroupGuid,

		[Parameter(Mandatory = $true)]
		[string]$SettingGuid,

		[Parameter(Mandatory = $true)]
		[object]$Value,

		[string]$SchemeGuid = $null,

		[string]$Units = $null
	)

	$resolvedSchemeGuid = if (-not [string]::IsNullOrWhiteSpace($SchemeGuid)) { [string]$SchemeGuid } else { Get-CurrentPowerSchemeGuid }
	if ([string]::IsNullOrWhiteSpace($resolvedSchemeGuid))
	{
		throw 'Unable to determine the active power scheme.'
	}

	$desiredACValue = $null
	$desiredDCValue = $null
	if ($Value -is [System.Collections.IDictionary])
	{
		if ($Value.Contains('ACValue'))
		{
			$desiredACValue = ConvertTo-PowerSchemeSystemValue -Value $Value['ACValue'] -Units $Units
		}
		if ($Value.Contains('DCValue'))
		{
			$desiredDCValue = ConvertTo-PowerSchemeSystemValue -Value $Value['DCValue'] -Units $Units
		}
	}
	elseif ($Value.PSObject -and ($Value.PSObject.Properties['ACValue'] -or $Value.PSObject.Properties['DCValue']))
	{
		if ($Value.PSObject.Properties['ACValue'])
		{
			$desiredACValue = ConvertTo-PowerSchemeSystemValue -Value $Value.ACValue -Units $Units
		}
		if ($Value.PSObject.Properties['DCValue'])
		{
			$desiredDCValue = ConvertTo-PowerSchemeSystemValue -Value $Value.DCValue -Units $Units
		}
	}
	else
	{
		$singleValue = ConvertTo-PowerSchemeSystemValue -Value $Value -Units $Units
		$desiredACValue = $singleValue
		$desiredDCValue = $singleValue
	}

	if ($null -eq $desiredACValue -and $null -ne $desiredDCValue)
	{
		$desiredACValue = $desiredDCValue
	}
	if ($null -eq $desiredDCValue -and $null -ne $desiredACValue)
	{
		$desiredDCValue = $desiredACValue
	}

	& powercfg /QUERY $resolvedSchemeGuid $SubgroupGuid $SettingGuid 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0)
	{
		throw "Power scheme setting '$SettingGuid' in subgroup '$SubgroupGuid' is not available for active power scheme '$resolvedSchemeGuid'."
	}

	$currentValues = Get-PowerSchemeSettingValue -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -SchemeGuid $resolvedSchemeGuid -Units $Units
	$rawCurrentAC = if ($currentValues -and $null -ne $currentValues.RawACValue) { [string]$currentValues.RawACValue } else { $null }
	$rawCurrentDC = if ($currentValues -and $null -ne $currentValues.RawDCValue) { [string]$currentValues.RawDCValue } else { $null }
	$rawDesiredAC = if ($null -ne $desiredACValue) { [string]$desiredACValue } else { $null }
	$rawDesiredDC = if ($null -ne $desiredDCValue) { [string]$desiredDCValue } else { $null }

	if ($rawCurrentAC -eq $rawDesiredAC -and $rawCurrentDC -eq $rawDesiredDC)
	{
		return [pscustomobject]@{
			SchemeGuid   = $resolvedSchemeGuid
			SubgroupGuid = $SubgroupGuid
			SettingGuid  = $SettingGuid
			Units        = $Units
			ACValue      = $desiredACValue
			DCValue      = $desiredDCValue
			RawACValue   = $desiredACValue
			RawDCValue   = $desiredDCValue
			Changed      = $false
		}
	}

	& powercfg /SETACVALUEINDEX $resolvedSchemeGuid $SubgroupGuid $SettingGuid $desiredACValue 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0)
	{
		throw "powercfg /SETACVALUEINDEX returned exit code $LASTEXITCODE"
	}

	& powercfg /SETDCVALUEINDEX $resolvedSchemeGuid $SubgroupGuid $SettingGuid $desiredDCValue 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0)
	{
		throw "powercfg /SETDCVALUEINDEX returned exit code $LASTEXITCODE"
	}

	& powercfg /SETACTIVE $resolvedSchemeGuid 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0)
	{
		throw "powercfg /SETACTIVE returned exit code $LASTEXITCODE"
	}

	return [pscustomobject]@{
		SchemeGuid   = $resolvedSchemeGuid
		SubgroupGuid = $SubgroupGuid
		SettingGuid  = $SettingGuid
		Units        = $Units
		ACValue      = $desiredACValue
		DCValue      = $desiredDCValue
		RawACValue   = $desiredACValue
		RawDCValue   = $desiredDCValue
		Changed      = $true
	}
}

$ExportedFunctions = @(
    'Resolve-BaselineLocalizationDirectory'
    'Import-BaselineLocalization'
	'Resolve-BaselineCultureName'
	'Set-BaselineThreadCulture'
    'Get-BaselineLocalizedString'
    'Get-BaselineBilingualString'
    'Remove-HandledErrorRecord'
    'Test-IgnorableErrorMessage'
    'Test-IgnorableErrorRecord'
    'Get-NewUnhandledErrorRecords'
    'Get-BaselineErrorCatalog'
    'Resolve-BaselineErrorCode'
    'Get-BaselineErrorInfo'
    'Format-BaselineErrorDialogMessage'
    'Invoke-SilencedProgress'
    'Stop-BaselineProcessTree'
    'ConvertTo-BaselineWindowsProcessArgument'
    'ConvertTo-BaselineProcessArgumentString'
    'Invoke-BaselineProcess'
    'Invoke-UserLaunch'
    'Set-Policy'
    'ConvertTo-NativeRegistryPath'
    'ConvertTo-RegExeValueType'
    'Dismount-RegistryHive'
    'Mount-RegistryHive'
    'Test-RegistryValueEquivalent'
    'Set-RegistryValueSafe'
    'Set-RegistryCompositeStringValue'
    'Remove-RegistryValueSafe'
    'Set-SystemTweaksRegistryValue'
    'Remove-SystemTweaksRegistryValue'
    'Initialize-ForegroundWindowInterop'
    'Initialize-ConsoleWindowInterop'
    'Get-ConsoleHandle'
    'Hide-ConsoleWindow'
    'Show-ConsoleWindow'
    'Test-InteractiveHost'
    'Initialize-WpfWindowForeground'
    'Get-WindowsVersionData'
    'Get-OSInfo'
    'Get-BaselineStartupThemePreference'
    'Get-BaselineStartupThemeName'
    'Get-LocalizedShellString'
    'ConvertTo-WindowsDisplayVersionComparable'
    'Test-Windows11FeatureBranchSupport'
    'Show-BootstrapLoadingSplash'
    'Set-BootstrapLoadingSplashState'
    'Set-BootstrapLoadingSplashStep'
    'Close-LoadingSplashWindow'
    'Show-Menu'
    'Restart-Script'
    'Get-BaselineDisplayVersion'
    'Get-TweakSkipLabel'
    'Stop-Foreground'
    'Invoke-UCPDBypassed'
    'Get-UCPDTemporaryPowerShellPath'
    'Convert-JsonManifestValue'
    'ConvertTo-TweakRiskLevel'
    'ConvertTo-TweakPresetTier'
    'ConvertTo-TweakWorkflowSensitivity'
    'Convert-ToWhyThisMattersText'
    'Import-TweakManifestFromData'
    'Get-ValidScenarioTagCatalog'
    'Get-ValidGamingPreviewGroups'
    'Get-ValidGameModeProfileNames'
    'Test-TweakManifestIntegrity'
    'Test-BaselineEditionInFamily'
    'Get-BaselineServerReleaseFromBuild'
    'Get-BaselineSystemPlatformInfo'
    'ConvertTo-BaselinePlatformLabel'
    'Set-BaselineDefenderExecutionAvailability'
    'Set-BaselineDefenderComponentAvailability'
    'Reset-BaselineDefenderExecutionAvailability'
    'Resolve-BaselineDefenderExecutionAvailability'
    'Resolve-BaselineDefenderComponentAvailability'
    'Test-BaselineDefenderExecutionAvailable'
    'Get-BaselineDefenderExecutionUnavailableReason'
    'Test-BaselineDefenderComponentAvailable'
    'Get-BaselineDefenderComponentUnavailableReason'
    'Test-BaselineEntryAvailable'
    'Test-BaselineEntrySupportsExecution'
    'Get-BaselineEntryAvailabilitySummary'
    'Update-BaselineManifestAvailability'
    'Update-BaselineManifestExecutionSupport'
    'Get-ManifestEntryByFunction'
    'Get-TweakManifestDefaultCommand'
    'Get-ScenarioProfileDefinitions'
    'Get-ScenarioProfileValidationIssues'
    'Get-ScenarioProfilePlan'
    'Get-ScenarioProfileCommandList'
    'ConvertTo-HeadlessPresetName'
    'Resolve-HeadlessEnvironmentPreset'
    'Set-HeadlessPresetIncludedFunctionSet'
    'Get-HeadlessPresetIncludedTweakLibraryPathSet'
    'Set-HeadlessPresetIncludedTweakLibraryPathSet'
    'Get-HeadlessPresetCommandList'
    'Get-GameModeAllowlist'
    'Get-GameModeReviewedCrossCategoryAllowlist'
    'Import-GameModeAllowlistData'
    'Import-GameModeAdvancedData'
    'Import-GameModeProfileData'
    'Get-GameModeAdvancedFunctions'
    'Test-GameModeAdvancedProfileDefaultSelection'
    'Resolve-GameModeAllowlistToggleParam'
    'Get-GameModeProfileDefinitions'
    'Get-GameModeDecisionPromptKeyCatalog'
    'Get-GameModeDecisionPromptDefinitions'
    'Get-GameModeDecisionOverridesText'
    'Resolve-ValidatedGameModeDecisionOverrides'
    'Test-GameModeAllowlistEntryReviewed'
    'Test-GameModeProfileDefaultEligible'
    'Merge-GameModeSelectionState'
    'Get-GameModeSelectionSet'
    'Get-GameModeProfilePlan'
    'Get-GameModeProfileCommandList'
    'Get-DirectUndoCommandForEntry'
    'Get-DirectUndoCommandLineForEntry'
    'Get-GuiNumericRangeValue'
    'Format-GuiNumericRangeValueText'
    'Format-GuiPowerSchemeValueText'
    'Get-GuiNumericRangeChannelValue'
    'Get-CurrentPowerSchemeGuid'
    'Get-PowerSchemeSettingValue'
    'Set-PowerSchemeSettingValue'
    'Test-ShouldRecommendRestorePoint'
	'Update-ProcessPathFromRegistry'
	'Resolve-WinGetExecutable'
	'Get-WinGetVersion'
	'Test-WinGetAvailable'
	'Reset-WinGetAvailabilityState'
	'Resolve-ChocolateyExecutable'
	'Get-ChocolateyVersion'
	'Test-ChocolateyAvailable'
	'Reset-ChocolateyAvailabilityState'
	'Test-ChocolateyBootstrapApproved'
	'Get-WinGetBootstrapInstallerMetadata'
	'Get-WinGetBootstrapInstallerArguments'
	'Invoke-WinGetBootstrap'
	'Invoke-ChocolateyBootstrap'
	'Invoke-DownloadFile'
	'Set-DownloadSecurityProtocol'
    'Assert-FileHash'
    'Assert-AuthenticodeSignature'
    'Get-PowerShellInstallerArchitecture'
    'Resolve-PowerShellInstallerUri'
    'Get-OneDriveSetupPath'
    'ConvertTo-NormalizedVersion'
    'Get-InstalledVCRedistVersion'
    'Get-InstalledDotNetRuntimeVersion'
    'Get-LatestDotNetRuntimeRelease'
    'Install-VCRedist'
    'Install-DotNetRuntimes'
    'Get-AdvancedStartupDesktopDirectory'
    'Get-AdvancedStartupDownloadsDirectory'
    'Get-AdvancedStartupAssetPath'
    'Get-AdvancedStartupIconLocation'
    'Enable-AdvancedStartupWindowsRecoveryEnvironment'
    'Get-AdvancedStartupCommandPath'
    'Set-AdvancedStartupCommandFile'
    'Get-AdvancedStartupShortcutArguments'
    'Get-TaskbarPinnedItems'
    'Get-TaskbarPinnedMatches'
    'Get-TaskbarUnpinVerbCandidates'
    'Set-NewsInterestsTaskbarViewMode'
    'Invoke-TaskbarUnpin'
    'Remove-TaskbarPinnedLink'
    'Invoke-TaskbarUnpinWithFallback'
    'Remove-TaskbarPinnedLinksByPattern'
    'Invoke-ARM64ShellUnpin'
    'Test-Windows11SmbDuplicateSidIssue'
    'Invoke-AdditionalServiceOptimizations'
    'Get-BaselineDataDirectory'
    'Write-BaselineDocument'
    'Read-BaselineDocument'
    'Add-BaselineAuditRecord'
    'Read-BaselineAuditLog'
    'Test-BaselineDocumentSchema'
    'New-ConfigurationProfile'
    'Export-ConfigurationProfile'
    'Export-BaselineFirstLogonCommandSnippet'
    'Import-ConfigurationProfile'
    'Import-ConfigurationProfileIncludeLibraries'
    'Test-ConfigurationProfileCompatibility'
    'Compare-ConfigurationProfiles'
    'ConvertFrom-PresetToProfile'
    'Get-TweakCurrentStateValue'
    'New-SystemStateSnapshot'
    'Compare-SystemStateSnapshots'
    'Export-SystemStateSnapshot'
    'Import-SystemStateSnapshot'
    'Get-TweakPlannedStateValue'
    'Limit-SnapshotDirectory'
    'Test-SystemCompliance'
    'Get-DriftedEntries'
    'Get-ComplianceFixList'
    'Export-ComplianceReport'
    'Get-ApplicationPackageIdCandidates'
    'Resolve-ApplicationPackageId'
    'Test-ApplicationPackageIdInCache'
    'Get-BaselineLifecycleComparableVersion'
    'Get-BaselineReleaseArtifactVerification'
    'Get-BaselineValidationMatrixSummary'
    'Get-BaselineValidationEvidenceReport'
    'Import-BaselineRollbackProfile'
    'New-BaselineLifecyclePlaybook'
    'Invoke-BaselineLifecyclePlaybook'
    'Assert-BaselineReleaseArtifactVerification'
    'New-BaselineIncidentReproductionPack'
    'Get-AuditLogPath'
    'Get-BaselineAuditRetentionDays'
    'Get-BaselineAuditRetentionCutoff'
    'Invoke-BaselineAuditRetentionPolicy'
    'Write-AuditRecord'
    'Get-AuditLog'
    'Export-AuditReport'
    'Clear-AuditLog'
    'Get-BaselineAuditRetentionPolicyThreshold'
    'Test-BaselineAuditRetentionBelowPolicy'
    'Get-BaselineAuditRetentionPolicyWarning'
    'Test-BaselineAuditRetentionTaskExecution'
    'Get-BaselineAuditRetentionReport'
    'Get-BaselineSupportBundleDeepLinks'
    'Export-BaselineSupportBundle'
    'Test-BaselineSupportBundleIntegrity'
    'Register-BaselineScheduledTask'
    'Unregister-BaselineScheduledTask'
    'Get-BaselineScheduledTasks'
    'Test-BaselineScheduledTaskExists'
    'Get-BaselineRemovalScriptDirectory'
    'Test-BaselineRemovalPersistenceEntryName'
    'Save-BaselineRemovalScript'
    'Register-BaselineRemovalPersistenceTask'
    'Unregister-BaselineRemovalPersistenceTask'
    'Get-BaselineRemovalPersistenceTasks'
    'Test-BaselineRemovalPersistenceTaskExists'
    'Get-BaselineUserAppsDirectory'
    'Test-BaselineUserAppEntry'
    'Get-BaselineUserAppEntries'
    'Merge-BaselineUserAppEntries'
    'Save-BaselineUserAppEntriesFromProfile'
    'Get-BaselineRansomwareFtypeExtensions'
    'Get-BaselineRansomwareFtypeClassesRoot'
    'Get-BaselineRansomwareFtypeBackupRoot'
    'Get-BaselineRansomwareFtypeNotepadCommand'
    'Get-BaselineFtypeAssociation'
    'Set-BaselineRansomwareFtypeMitigation'
    'Restore-BaselineRansomwareFtypeMitigation'
    'Get-BaselineRansomwareFtypeStatus'
    'Get-BaselineNetworkHardeningRegistrySettings'
    'Get-BaselineNetworkHardeningBackupRoot'
    'Set-BaselineNetworkHardeningRegistrySettings'
    'Restore-BaselineNetworkHardeningRegistrySettings'
    'Get-BaselineNetworkHardeningRegistryStatus'
    'Get-BaselineNetBiosInterfacesRoot'
    'Disable-BaselineNetBiosOverTcpip'
    'Restore-BaselineNetBiosOverTcpip'
    'Get-BaselineWinRMServiceBackupKey'
    'Disable-BaselineWinRMService'
    'Restore-BaselineWinRMService'
    'Get-BaselineBrowserPolicySettings'
    'Get-BaselineBrowserPolicyBackupRoot'
    'ConvertTo-BaselineBrowserPolicyBackupKey'
    'Set-BaselineBrowserPolicySettings'
    'Restore-BaselineBrowserPolicySettings'
    'Get-BaselineBrowserPolicyStatus'
    'Get-BaselineAuthHardeningSettings'
    'Get-BaselineAuthHardeningBackupRoot'
    'ConvertTo-BaselineAuthHardeningBackupKey'
    'Set-BaselineAuthHardeningSettings'
    'Restore-BaselineAuthHardeningSettings'
    'Get-BaselineAuthHardeningStatus'
    'Test-BaselineRemoteConnectivity'
    'Get-BaselineRemoteSession'
    'Clear-BaselineRemoteSessionCache'
    'Get-BaselineRemoteSessionSummary'
    'Get-BaselineRemoteOrchestrationHistoryPath'
    'Get-BaselineRemoteFailureProfile'
    'New-BaselineRemoteAttemptRecord'
    'Get-BaselineRemoteRetryAnalytics'
    'Write-BaselineRemoteAttemptHistoryRecord'
    'Get-BaselineRemoteOrchestrationHistory'
    'Get-BaselineRemoteOrchestrationDetails'
    'Get-BaselineRemoteOrchestrationSummary'
    'Get-BaselineRemoteRunSummaries'
    'Get-BaselineRemoteOrchestrationReconciliation'
    'Write-BaselineRemoteOrchestrationRecord'
    'Write-BaselineRemoteOrchestrationSummaryRecord'
    'Invoke-BaselineRemoteCompliance'
    'Invoke-BaselineRemoteApply'
    'Get-BaselineRemoteResumeDirectory'
    'Get-BaselineRemoteResumeCheckpointPath'
    'Save-BaselineRemoteResumeCheckpoint'
    'Get-BaselineRemoteResumeCheckpoint'
    'Get-BaselineRemoteResumableRuns'
    'Clear-BaselineRemoteResumeCheckpoint'
    'Resolve-BaselineRemoteResumeTargets'
    'Resume-BaselineRemoteOrchestration'
    'Get-BaselineRemoteTargetHealthPath'
    'Get-BaselineRemoteTargetHealth'
    'Update-BaselineRemoteTargetHealth'
    'Get-BaselineRemoteTargetFailureHistory'
    'Get-BaselineRemoteApprovalDecisionPath'
    'Write-BaselineRemoteApprovalDecision'
    'Get-BaselineRemoteApprovalDecisions'
    'Write-BaselineRemoteRolloutOutcome'
    'Get-BaselineRemoteRolloutOutcomes'
    'Get-BaselineRemoteOrchestrationDashboard'
    'Search-BaselineRemoteOrchestrationHistory'
    'Invoke-BaselineAutoUpdate'
    'Invoke-BaselineUpdateCheck'
    'Get-BaselineUpdateAsset'
    'Get-BaselineUpdateAssetPattern'
    'Get-BaselineUpdateSettings'
    'Get-BaselineStartupSplashSettings'
    'Get-BaselineStartupPackageManagerCheckStatePath'
    'Get-BaselineStartupPackageManagerCheckState'
    'Set-BaselineStartupPackageManagerCheckState'
    'Get-BaselineStartupPackageManagerCheckDecision'
    'Get-BaselineUpdateCheckState'
    'Set-BaselineUpdateCheckState'
    'Format-BaselineUpdateLastChecked'
    'ConvertTo-BaselineUpdateCheckFrequency'
    'ConvertTo-BaselineUpdateBranch'
    'Get-BaselineDefaultUpdateBranch'
    'Get-BaselineUpdateRepositoryName'
    'Get-BaselineUpdateRepositoryUrl'
    'Get-BaselineUpdateReleaseApiUri'
    'Get-BaselineUpdateReleasePageUrl'
    'Test-BaselineUpdatePrereleaseAllowed'
    'Test-BaselineAutoUpdateStartupEnabled'
    'Initialize-BaselineWinRtRuntimeDependencies'
    'Initialize-BaselineMarkdownRuntime'
    'Test-BaselineMarkdownRuntimeReady'
    'ConvertFrom-BaselineMarkdownToFlowDocument'
    'ConvertFrom-BaselineMarkdownToAnchoredFlowDocument'
    'Get-BaselineMarkdownPipeline'
    'ConvertFrom-BaselineMarkdownToHtml'
    'Initialize-BaselineWebView2Runtime'
    'Test-BaselineWebView2RuntimeReady'
    'Set-BaselineOperationMode'
    'Get-BaselineOperationMode'
    'Test-BaselineReadOnlyMode'
    'Assert-BaselineWriteAllowed'
    'Test-BaselineGpoPolicyPath'
    'Get-BaselineGpoPolicyValueState'
    'Get-BaselineGpoEnvironmentSummary'
    'Get-BaselineGpoConflictForEntry'
    'Get-BaselineGpoConflictReport'
    'Format-BaselineGpoConflictReport'
    'Set-BaselineCliOutputFormat'
    'Get-BaselineCliOutputFormat'
    'Format-BaselineCliResult'
    'Write-BaselineCliEvent'
    'Resolve-BaselinePolicyToolPath'
    'Test-GuiObjectField'
    'Get-GuiObjectField'
	'Get-BaselineFeatureMaturityLevels'
	'ConvertTo-BaselineFeatureMaturityLevel'
	'Get-BaselineFeatureMaturityRank'
	'Test-BaselineFeatureMaturityAtLeast'
	'Get-BaselineEnterpriseActionMaturityCatalog'
	'Test-BaselineEnterpriseActionMaturityGate'
	'Get-BaselineFeatureMaturityReport'
    'New-BaselineOperatorPolicy'
    'Test-BaselineOperatorChangeWindow'
    'Test-BaselineKillSwitch'
    'Invoke-BaselineKillSwitch'
    'Clear-BaselineKillSwitch'
    'Test-BaselineOperatorRunPolicy'
    'Format-BaselineOperatorPolicyDecision'
    'ConvertFrom-BaselineJson'
    'Get-BaselineStartupLabel'
    'Test-BaselineUnsupportedHost'
    'Test-BaselineHostsEntry'
    'Get-BaselineHostsCandidateEntries'
    'Test-BaselineHostsDownloadSuspect'
    'Get-BaselineDefenderProductStateCode'
    'Test-BaselineDefenderActiveByProductState'
    'Test-BaselineDefenderFullyEnabled'
    'Test-BaselineDefenderServicesHealthy'
    'Resolve-BaselineSettingsAppsFeaturesHealthAssessment'
    'Resolve-BaselineScreenSnippingHealthAssessment'
    'Resolve-BaselineHostsCleanupPolicy'
    'Resolve-BaselineHostTaintAssessment'
    'Get-WindowsCapabilityCheckedDefaults'
    'Get-WindowsCapabilityUncheckedDefaults'
    'Get-WindowsCapabilityExcludedDefaults'
    'Get-WindowsCapabilityFriendlyNameMap'
    'Get-WindowsFeatureCheckedDefaults'
    'Get-WindowsFeatureUncheckedDefaults'
    'Test-WindowsCapabilityPatternMatch'
    'Get-WindowsCapabilityFriendlyName'
    'Test-WindowsCapabilitySeedSelected'
    'Select-WindowsCapabilityVisible'
    'Get-BaselineDisplayWorkAreas'
    'Test-BaselineWindowRectVisible'
    'Get-BaselineSavedWindowPlacement'
    'Save-BaselineWindowPlacement'
    'Resolve-BaselineWindowPlacement'
)

Export-ModuleMember -Function $ExportedFunctions
