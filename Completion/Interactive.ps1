<#
	.SYNOPSIS
	Bootstraps an interactive Baseline session and provides tab completion for functions and arguments.

    .VERSION
	2.0.0

	.DATE
	17.03.2026 - initial version
	21.03.2026 - Added GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

	.DESCRIPTION
	Dot source the script first: . .\Completion\Interactive.ps1 (with a dot at the beginning)
	Start typing any characters contained in the function's name or its arguments, and press the TAB button

	.EXAMPLE
	Baseline -Functions <tab>
	Baseline -Functions temp<tab>
	Baseline -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", UninstallUWPApps

	.NOTES
	Use commas to separate functions and their arguments. If a function doesn't have arguments, just type its name. You can also use the TAB button to complete only the function name or only the argument name.

	.LINK
	https://github.com/sdmanson8/Baseline
#>

#Requires -RunAsAdministrator

<#
	.SYNOPSIS
	Run one or more Baseline functions after the module has been loaded.

	.PARAMETER Functions
	One or more function calls to execute.

	.EXAMPLE
	Baseline -Functions "DiagTrackService -Disable", "BingSearch -Disable"
#>
function Baseline
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[string[]]
		$Functions
	)

	foreach ($Function in $Functions)
	{
		Invoke-Expression -Command $Function
	}

	# The "PostActions" and "Errors" functions will be executed at the end
	Invoke-Command -ScriptBlock {PostActions; Errors}
}

Clear-Host

$Host.UI.RawUI.WindowTitle = "Baseline | Windows Utility"

# Import the Baseline module and load the localization strings used by its functions.
$Script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:ModuleRoot = Join-Path $Script:RepoRoot 'Module'

if (-not (Test-Path -LiteralPath $Script:ModuleRoot -PathType Container))
{
	throw "Module directory not found under: $Script:RepoRoot"
}

Remove-Module -Name Baseline -Force -ErrorAction Ignore
Import-Module -Name (Join-Path $Script:ModuleRoot 'Baseline.psd1') -PassThru -Force

try
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture $PSUICulture -BaseDirectory $Script:RepoRoot\Localizations -FileName Baseline -ErrorAction Stop
}
catch
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture en-US -BaseDirectory $Script:RepoRoot\Localizations -FileName Baseline
}

$displayVersion = Get-BaselineDisplayVersion
if (-not [string]::IsNullOrWhiteSpace([string]$displayVersion))
{
	$osName = (Get-OSInfo).OSName
	$Host.UI.RawUI.WindowTitle = "Baseline | Windows Utility for $osName $displayVersion"
}

# Run the mandatory startup checks before enabling tab completion.
# DO NOT comment out or remove this line
InitialActions

# Register tab completion for the -Functions parameter so users can complete function names and arguments.
$Parameters = @{
	CommandName   = "Baseline"
	ParameterName = "Functions"
	ScriptBlock   = {
		param
		(
			$commandName,
			$parameterName,
			$wordToComplete,
			$commandAst,
			$fakeBoundParameters
		)

		# Get functions list with arguments to complete
		$Commands = (Get-Module -Name Baseline).ExportedCommands.Keys
		foreach ($Command in $Commands)
		{
			$ParameterSets = (Get-Command -Name $Command).Parametersets.Parameters | Where-Object -FilterScript {$null -eq $_.Attributes.AliasNames}

			# If a module command is OneDrive
			if ($Command -eq "OneDrive")
			{
				(Get-Command -Name $Command).Name | Where-Object -FilterScript {$_ -like "*$wordToComplete*"}

				# Get all command arguments, excluding defaults
				foreach ($ParameterSet in $ParameterSets.Name)
				{
					# If an argument is AllUsers
					if ($ParameterSet -eq "AllUsers")
					{
						# The "OneDrive -Install -AllUsers" construction
						"OneDrive" + " " + "-Install" + " " + "-" + $ParameterSet | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}

					continue
				}
			}

			# If a module command is UnpinTaskbarShortcuts
			if ($Command -eq "UnpinTaskbarShortcuts")
			{
				# Get all command arguments, excluding defaults
				foreach ($ParameterSet in $ParameterSets.Name)
				{
					# If an argument is Shortcuts
					if ($ParameterSet -eq "Shortcuts")
					{
						$ValidValues = ((Get-Command -Name UnpinTaskbarShortcuts).Parametersets.Parameters | Where-Object -FilterScript {$null -eq $_.Attributes.AliasNames}).Attributes.ValidValues
						foreach ($ValidValue in $ValidValues)
						{
							# The "UnpinTaskbarShortcuts -Shortcuts <function>" construction
							"UnpinTaskbarShortcuts" + " " + "-" + $ParameterSet + " " + $ValidValue | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
						}

						# The "UnpinTaskbarShortcuts -Shortcuts <functions>" construction
						"UnpinTaskbarShortcuts" + " " + "-" + $ParameterSet + " " + ($ValidValues -join ", ") | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}

					continue
				}
			}

			# If a module command is UninstallUWPApps
			if ($Command -eq "UninstallUWPApps")
			{
				(Get-Command -Name $Command).Name | Where-Object -FilterScript {$_ -like "*$wordToComplete*"}

				# Get all command arguments, excluding defaults
				foreach ($ParameterSet in $ParameterSets.Name)
				{
					# If an argument is ForAllUsers
					if ($ParameterSet -eq "ForAllUsers")
					{
						# The "UninstallUWPApps -ForAllUsers" construction
						"UninstallUWPApps" + " " + "-" + $ParameterSet | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}

					continue
				}
			}

			# If a module command is Install-VCRedist
			if ($Command -eq "Install-VCRedist")
			{
				# Get all command arguments, excluding defaults
				foreach ($ParameterSet in $ParameterSets.Name)
				{
					# If an argument is Redistributables
					if ($ParameterSet -eq "Redistributables")
					{
						$ValidValues = ((Get-Command -Name Install-VCRedist).Parametersets.Parameters | Where-Object -FilterScript {$null -eq $_.Attributes.AliasNames}).Attributes.ValidValues
						foreach ($ValidValue in $ValidValues)
						{
							# The "Install-VCRedist -Redistributables <function>" construction
							"Install-VCRedist" + " " + "-" + $ParameterSet + " " + $ValidValue | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
						}

						# The "Install-VCRedist -Redistributables <functions>" construction
						"Install-VCRedist" + " " + "-" + $ParameterSet + " " + ($ValidValues -join ", ") | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}

					continue
				}
			}

			# If a module command is Install-DotNetRuntimes
			if ($Command -eq "Install-DotNetRuntimes")
			{
				# Get all command arguments, excluding defaults
				foreach ($ParameterSet in $ParameterSets.Name)
				{
					# If an argument is Runtimes
					if ($ParameterSet -eq "Runtimes")
					{
						$ValidValues = ((Get-Command -Name Install-DotNetRuntimes).Parametersets.Parameters | Where-Object -FilterScript {$null -eq $_.Attributes.AliasNames}).Attributes.ValidValues
						foreach ($ValidValue in $ValidValues)
						{
							# The "Install-DotNetRuntimes -Runtimes <function>" construction
							"Install-DotNetRuntimes" + " " + "-" + $ParameterSet + " " + $ValidValue | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
						}

						# The "Install-DotNetRuntimes -Runtimes <functions>" construction
						"Install-DotNetRuntimes" + " " + "-" + $ParameterSet + " " + ($ValidValues -join ", ") | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}

					continue
				}
			}

			# If a module command is DNSoverHTTPS
			if ($Command -eq "DNSoverHTTPS")
			{
				(Get-Command -Name $Command).Name | Where-Object -FilterScript {$_ -like "*$wordToComplete*"}

				# Get the valid IPv4 addresses array
				# ((Get-Command -Name DNSoverHTTPS).Parametersets.Parameters | Where-Object -FilterScript {$null -eq $_.Attributes.AliasNames}).Attributes.ValidValues | Select-Object -Unique
				$ValidValues = @((Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers).PSChildName) | Where-Object {$_ -notmatch ":"}
				foreach ($ValidValue in $ValidValues)
				{
					$ValidValuesDescending = @((Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers).PSChildName) | Where-Object {$_ -notmatch ":"}
					foreach ($ValidValueDescending in $ValidValuesDescending)
					{
						# The "DNSoverHTTPS -Enable -PrimaryDNS x.x.x.x -SecondaryDNS x.x.x.x" construction
						"DNSoverHTTPS -Enable -PrimaryDNS $ValidValue -SecondaryDNS $ValidValueDescending" | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
					}
				}

				"DNSoverHTTPS -Disable" | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}
				"DNSoverHTTPS -ComssOneDNS" | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}

				continue
			}

			# If a module command is Set-Policy
			if ($Command -eq "Set-Policy")
			{
				continue
			}

			foreach ($ParameterSet in $ParameterSets.Name)
			{
				# The "Function -Argument" construction
				$Command + " " + "-" + $ParameterSet | Where-Object -FilterScript {$_ -like "*$wordToComplete*"} | ForEach-Object -Process {"`"$_`""}

				continue
			}

			# Get functions list without arguments to complete
			Get-Command -Name $Command | Where-Object -FilterScript {$null -eq $_.Parametersets.Parameters} | Where-Object -FilterScript {$_.Name -like "*$wordToComplete*"}

			continue
		}
	}
}
Register-ArgumentCompleter @Parameters

Write-Information -MessageData "" -InformationAction Continue
Write-Verbose -Message "Baseline -Functions <tab>" -Verbose
Write-Verbose -Message "Baseline -Functions temp<tab>" -Verbose
Write-Verbose -Message "Baseline -Functions `"DiagTrackService -Disable`", `"DiagnosticDataLevel -Minimal`", UninstallUWPApps" -Verbose
Write-Information -MessageData "" -InformationAction Continue
Write-Verbose -Message "Baseline -Functions `"UninstallUWPApps, `"PinToStart -UnpinAll`" -Verbose"
Write-Verbose -Message "Baseline -Functions `"Set-Association -ProgramPath ```"%ProgramFiles%\Notepad++\notepad++.exe```" -Extension .txt -Icon ```"%ProgramFiles%\Notepad++\notepad++.exe,0```"`"" -Verbose
