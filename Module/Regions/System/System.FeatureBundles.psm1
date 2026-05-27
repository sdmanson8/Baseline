using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
    .SYNOPSIS
    Configures Windows feature bundle state.

    .DESCRIPTION
    Exposes the feature-bundle toggles used by Baseline's system maintenance
    workflows.
#>

function Set-OptionalFeatureBundleState
{
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Enable', 'Disable')]
		[string]
		$State,

		[Parameter(Mandatory = $true)]
		[string]
		$DisplayName,

		[Parameter(Mandatory = $true)]
		[string]
		$EnableAction,

		[Parameter(Mandatory = $true)]
		[string]
		$DisableAction,

		[Parameter(Mandatory = $true)]
		[string[]]
		$FeatureNames,

		[switch]
		$UseAll,

		[scriptblock]
		$PostEnableScript
	)

	$actionText = if ($State -eq 'Enable') { $EnableAction } else { $DisableAction }
	$featureVerb = if ($State -eq 'Enable') { 'Enabling' } else { 'Disabling' }

	Write-ConsoleStatus -Action $actionText
	LogInfo $actionText

	try
	{
		foreach ($featureName in @($FeatureNames))
		{
			if ([string]::IsNullOrWhiteSpace([string]$featureName))
			{
				continue
			}

			LogInfo ("{0} Windows feature: {1}" -f $featureVerb, $featureName)

			Invoke-SilencedProgress {
				if ($State -eq 'Enable')
				{
					if ($UseAll)
					{
						Enable-WindowsOptionalFeature -FeatureName $featureName -Online -All -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					}
					else
					{
						Enable-WindowsOptionalFeature -FeatureName $featureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					}
				}
				else
				{
					Disable-WindowsOptionalFeature -FeatureName $featureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				}
			}
		}

		if ($State -eq 'Enable' -and $PostEnableScript)
		{
			& $PostEnableScript
		}

		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError ("Failed to {0} {1}: {2}" -f $State.ToLowerInvariant(), $DisplayName, $_.Exception.Message)
	}
}

<#
    .SYNOPSIS
    Runs legacy media bundle.

    #>

function LegacyMediaBundle
{
	[CmdletBinding(DefaultParameterSetName = 'Enable')]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	Set-OptionalFeatureBundleState `
		-State $PSCmdlet.ParameterSetName `
		-DisplayName 'Legacy Media' `
		-EnableAction 'Enabling Legacy Media bundle' `
		-DisableAction 'Disabling Legacy Media bundle' `
		-FeatureNames @(
			'Media.WindowsMediaPlayer'
			'MediaPlayback'
			'DirectPlay'
			'LegacyComponents'
		)
}

<#
    .SYNOPSIS
    Runs NFS bundle.

    #>

function NfsBundle
{
	[CmdletBinding(DefaultParameterSetName = 'Enable')]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	Set-OptionalFeatureBundleState `
		-State $PSCmdlet.ParameterSetName `
		-DisplayName 'NFS' `
		-EnableAction 'Enabling NFS bundle' `
		-DisableAction 'Disabling NFS bundle' `
		-FeatureNames @(
			'ServicesForNFS-ClientOnly'
			'ClientForNFS-Infrastructure'
			'NFS-Administration'
		) `
		-PostEnableScript {
			& nfsadmin client stop | Out-Null
			Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default' -Name 'AnonymousUID' -Value 0 -ErrorAction Stop | Out-Null
			Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default' -Name 'AnonymousGID' -Value 0 -ErrorAction Stop | Out-Null
			& nfsadmin client start | Out-Null
			& nfsadmin client localhost config 'fileaccess=755' 'SecFlavors=+sys' '-krb5' '-krb5i' | Out-Null
		}
}

<#
    .SYNOPSIS
    Runs hyper v management tools.

    #>

function HyperVManagementTools
{
	[CmdletBinding(DefaultParameterSetName = 'Enable')]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	Set-OptionalFeatureBundleState `
		-State $PSCmdlet.ParameterSetName `
		-DisplayName 'Hyper-V Management Tools' `
		-EnableAction 'Enabling Hyper-V Management Tools' `
		-DisableAction 'Disabling Hyper-V Management Tools' `
		-FeatureNames @('Microsoft-Hyper-V-Tools-All') `
		-UseAll
}

Export-ModuleMember -Function 'HyperVManagementTools', 'LegacyMediaBundle', 'NfsBundle'
