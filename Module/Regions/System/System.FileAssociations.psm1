using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1


<#
    .SYNOPSIS
    Configures file association maintenance.

    .DESCRIPTION
    Creates or updates the file association data for the requested extension and
    optionally sets a custom icon for the associated program. This is an
    internal maintenance helper, not user-facing setup documentation.

	.PARAMETER ProgramPath
	The executable path or ProgID to associate with the file extension.

	.PARAMETER Extension
	The file extension to associate, including the leading dot.

	.PARAMETER Icon
	Optional icon resource to use for the file association.

	.EXAMPLE
	Set-Association -ProgramPath '%ProgramFiles%\\Notepad++\\notepad++.exe' -Extension .txt

	.NOTES
	Current user
#>

function Set-Association
{
	[CmdletBinding()]
	Param
	(
		[Parameter(
			Mandatory = $true,
			Position = 0
		)]
		[string]
		$ProgramPath,

		[Parameter(
			Mandatory = $true,
			Position = 1
		)]
		[string]
		$Extension,

		[Parameter(
			Mandatory = $false,
			Position = 2
		)]
		[string]
		$Icon
	)

	$TempPowerShellPath = Get-UCPDTemporaryPowerShellPath
	$AssociationFailed = $false

	# Suppress all output from the entire function
		. (Join-Path $PSScriptRoot 'FileAssociations\Set-Association\Set-Association.ps1')

	if ($AssociationFailed)
	{
		Write-ConsoleStatus -Status failed
	}
	else
	{
		Write-ConsoleStatus -Status success
	}
}

<#
	.SYNOPSIS
	Export all Windows associations



.DESCRIPTION

Applies the Baseline behavior for export all Windows associations.
	.EXAMPLE
	Export-Associations

	.NOTES
	Associations will be exported as Application_Associations.json file in script root folder

	.NOTES
	You need to install all apps according to an exported JSON file to restore all associations

	.NOTES
	Machine-wide
#>
function Export-Associations
{
	Write-ConsoleStatus -Action "Exporting associations"
	LogInfo "Exporting associations"
	try
	{
		Dism.exe /Online /Export-DefaultAppAssociations:"$env:TEMP\Application_Associations.xml" 2>$null | Out-Null
		if ($LASTEXITCODE -ne 0) { throw "Dism.exe returned exit code $LASTEXITCODE" }
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to export application associations: $($_.Exception.Message)"
		return
	}

	Clear-Variable -Name AllJSON, ProgramPath, Icon -ErrorAction SilentlyContinue | Out-Null

	$AllJSON = @()
	$AppxProgIds = @((Get-ChildItem -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\ProgIDs").PSChildName)

	[xml]$XML = Get-Content -Path "$env:TEMP\Application_Associations.xml" -Encoding UTF8 -Force
	$XML.DefaultAssociations.Association | ForEach-Object -Process {
		if ($AppxProgIds -contains $_.ProgId)
		{
			# if ProgId is a UWP app
			# ProgrammPath
			if (Test-Path -Path "HKCU:\Software\Classes\$($_.ProgId)\Shell\Open\Command")
			{

				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "DelegateExecute", $null))
				{
					$ProgramPath, $Icon = ""
				}
			}
		}
		else
		{
			if (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\$($_.ProgId)")
			{
				# ProgrammPath
				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "", $null))
				{
					$PartProgramPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$Program = $PartProgramPath.Substring(0, ($PartProgramPath.IndexOf(".exe") + 4)).Trim('"')

					if ($Program)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($Program)))
						{
							$ProgramPath = $PartProgramPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command", "", $null))
				{
					$PartProgramPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$Program = $PartProgramPath.Substring(0, ($PartProgramPath.IndexOf(".exe") + 4)).Trim('"')

					if ($Program)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($Program)))
						{
							$ProgramPath = $PartProgramPath
						}
					}
				}

				# Icon
				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\DefaultIcon", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\DefaultIcon" -Name "(default)")
					if ($IconPartPath.EndsWith(".ico"))
					{
						$IconPath = $IconPartPath
					}
					else
					{
						if ($IconPartPath.Contains(","))
						{
							$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(",")).Trim('"')
						}
						else
						{
							$IconPath = $IconPartPath.Trim('"')
						}
					}

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = $IconPartPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\DefaultIcon", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\DefaultIcon" -Name "(default)").Trim()
					if ($IconPartPath.EndsWith(".ico"))
					{
						$IconPath = $IconPartPath
					}
					else
					{
						if ($IconPartPath.Contains(","))
						{
							$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(",")).Trim('"')
						}
						else
						{
							$IconPath = $IconPartPath.Trim('"')
						}
					}

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = $IconPartPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\shell\open\command" -Name "(default)").Trim()
					$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(".exe") + 4).Trim('"')

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = "$IconPath,0"
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(".exe") + 4)

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = "$IconPath,0"
						}
					}
				}
			}
		}

		$_.ProgId = $_.ProgId.Replace("\", "\\")
		$ProgramPath = $ProgramPath.Replace("\", "\\").Replace('"', '\"')
		if ($Icon)
		{
			$Icon = $Icon.Replace("\", "\\").Replace('"', '\"')
		}

		# Create a hash table
		$JSON = @"
[
  {
     "ProgId":  "$($_.ProgId)",
     "ProgrammPath": "$ProgramPath",
     "Extension": "$($_.Identifier)",
     "Icon": "$Icon"
  }
]
"@ | ConvertFrom-JSON
		$AllJSON += $JSON
	}

	Clear-Variable -Name ProgramPath, Icon -ErrorAction SilentlyContinue | Out-Null

	# Save in UTF-8 without BOM; use explicit depth and UTF-8 encoding for cross-edition consistency
	[System.IO.File]::WriteAllText(
		(Join-Path $PSScriptRoot '..\Application_Associations.json'),
		($AllJSON | ConvertTo-Json -Depth 16),
		[System.Text.Encoding]::UTF8
	)

	Remove-Item -Path "$env:TEMP\Application_Associations.xml" -Force -ErrorAction SilentlyContinue | Out-Null
	Write-ConsoleStatus -Status success
}

<#
	.SYNOPSIS
	Import all Windows associations



.DESCRIPTION

Applies the Baseline behavior for import all Windows associations.
	.EXAMPLE
	Import-Associations

	.NOTES
	You have to install all apps according to an exported JSON file to restore all associations

	.NOTES
	Current user
#>
function Import-Associations
{
	Write-ConsoleStatus -Action "Importing associations"
	LogInfo "Importing associations"

	Add-Type -AssemblyName System.Windows.Forms
	$OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.Filter = "*.json|*.json|{0} (*.*)|*.*" -f $Localization.AllFilesFilter
	$OpenFileDialog.InitialDirectory = $PSScriptRoot
	$OpenFileDialog.Multiselect = $false

	$OpenFileDialog.ShowDialog()

	if ($OpenFileDialog.FileName)
	{
		$AppxProgIds = @((Get-ChildItem -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\ProgIDs").PSChildName)

		try
		{
			$JSON = Get-Content -Path $OpenFileDialog.FileName -Encoding UTF8 -Force | ConvertFrom-JSON
		}
		catch [System.Exception]
		{
			LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))

			return
		}

		$JSON | ForEach-Object -Process {
			if ($AppxProgIds -contains $_.ProgId)
			{
				Set-Association -ProgramPath $_.ProgId -Extension $_.Extension
			}
			else
			{
				Set-Association -ProgramPath $_.ProgrammPath -Extension $_.Extension -Icon $_.Icon
			}
		}
	}
	Write-ConsoleStatus -Status success
}

<#
	.SYNOPSIS
	Change User folders location



.DESCRIPTION

Applies the Baseline behavior for change User folders location.
	.PARAMETER Root
	Change user folders location to the root of any drive using the interactive menu

	.PARAMETER Custom
	Select folders for user folders location manually using a folder browser dialog

	.PARAMETER Default
	Change user folders location to the default values

	.EXAMPLE
	Set-UserShellFolderLocation -Root

	.EXAMPLE
	Set-UserShellFolderLocation -Custom

	.EXAMPLE
	Set-UserShellFolderLocation -Default

	.NOTES
	User files or folders won't be moved to a new location

	.NOTES
	Current user
#>

function Set-UserShellFolderLocation
{

	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Root"
		)]
		[switch]
		$Root,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Custom"
		)]
		[switch]
		$Custom,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	<#
		.SYNOPSIS
		Change the location of the each user folder using SHSetKnownFolderPath function



.DESCRIPTION

Applies the Baseline behavior for change the location of the each user folder using SHSetKnownFolderPath function.
		.EXAMPLE
		Set-UserShellFolder -UserFolder Desktop -FolderPath "$env:SystemDrive:\Desktop"

		.LINK
		https://docs.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath

		.NOTES
		User files or folders won't be moved to a new location
	#>
		. (Join-Path $PSScriptRoot 'FileAssociations\Set-UserShellFolderLocation\UserShellFolderWriter.ps1')

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'FileAssociations\Set-UserShellFolderLocation\UserShellFolderLocationWorkflow.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
}

<#
	.SYNOPSIS
	The location to save screenshots by pressing Win+PrtScr



.DESCRIPTION

Applies the Baseline behavior for the location to save screenshots by pressing Win+PrtScr.
	.PARAMETER Desktop
	Save screenshots by pressing Win+PrtScr on the Desktop

	.PARAMETER Default
	Save screenshots by pressing Win+PrtScr in the Pictures folder (default value)

	.EXAMPLE
	WinPrtScrFolder -Desktop

	.EXAMPLE
	WinPrtScrFolder -Default

	.NOTES
	The function will be applied only if the preset is configured to remove the OneDrive application, or the app was already uninstalled
	otherwise the backup functionality for the "Desktop" and "Pictures" folders in OneDrive breaks

	.NOTES
	Current user
#>

function WinPrtScrFolder
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Desktop"
		)]
		[switch]
		$Desktop,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Desktop"
		{
			Write-ConsoleStatus -Action "Setting the location to save screenshots by pressing Win+PrtScr to the Desktop"
			LogInfo "Setting the location to save screenshots by pressing Win+PrtScr to the Desktop"
			# Skip if OneDrive is currently linked to a Microsoft account.
			$UserEmail = Get-ItemProperty -Path HKCU:\Software\Microsoft\OneDrive\Accounts\Personal -Name UserEmail -ErrorAction SilentlyContinue
			if ($UserEmail)
			{
				LogError $Localization.OneDriveWarning
				LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

				return
			}

			# Determine invocation path (preset, Functions.ps1, or bootstrap).
			# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-variable
			# This tweak only runs when OneDrive is already removed or the
			# run request includes "OneDrive -Uninstall".
			$PresetName = (Get-Variable -Name MyInvocation -Scope Script).Value.PSCommandPath
			$PSCallStack = (Get-PSCallStack).Position.Text
			$OneDriveInstalled = Get-Package -Name "Microsoft OneDrive" -ProviderName Programs -Force -ErrorAction Ignore -WarningAction SilentlyContinue
			$HeadlessCommands = Get-Variable -Name BaselineHeadlessCommands -Scope Global -ErrorAction SilentlyContinue

			# Headless runs pass the requested command list through a global variable.
			if ($HeadlessCommands -and $HeadlessCommands.Value)
			{
				$RequestedCommands = [string[]]@($HeadlessCommands.Value)
				if (($RequestedCommands -contains 'OneDrive -Uninstall') -or (-not $OneDriveInstalled))
				{
					$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
					Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -Type ExpandString -Value $DesktopFolder | Out-Null
				}
				else
				{
					LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
					LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
				}
			}
			# Called from Functions.ps1.
			elseif ($PresetName -match "Functions.ps1")
			{
				# Apply only when the command includes WinPrtScrFolder -Desktop.
				if ($PSCallStack -match "WinPrtScrFolder -Desktop")
				{
					# Also allow this path if any queued command includes OneDrive -Uninstall,
					# or OneDrive is no longer installed.
					if (($PSCallStack -match "OneDrive -Uninstall") -or (-not $OneDriveInstalled))
					{
						$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
						Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -Type ExpandString -Value $DesktopFolder | Out-Null
					}
					else
					{
						LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
				}
			}
			else
			{
				# Called from Bootstrap/Baseline.ps1; require the "OneDrive -Uninstall"
				# line in the preset to be uncommented.
				if (Select-String -Path $PresetName -Pattern "OneDrive -Uninstall" -SimpleMatch)
				{
					# Read the preset line and ensure it is not commented out.
					$IsOneDriveToUninstall = (Select-String -Path $PresetName -Pattern "OneDrive -Uninstall" -SimpleMatch).Line.StartsWith("#") -eq $false
					# Also apply if OneDrive is already uninstalled or the bootstrap command
					# includes OneDrive -Uninstall alongside WinPrtScrFolder -Desktop.
					if ($IsOneDriveToUninstall -or (-not $OneDriveInstalled) -or ($PSCallStack -match "OneDrive -Uninstall"))
					{
						$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
						Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -Type ExpandString -Value $DesktopFolder | Out-Null
					}
					else
					{
						LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
				}
			}
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting the location to save screenshots by pressing Win+PrtScr to the default one"
			LogInfo "Setting the location to save screenshots by pressing Win+PrtScr to the default one"
			Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}
$ExportedFunctions = @(
    'Export-Associations',
    'Import-Associations',
    'Set-Association',
    'Set-UserShellFolderLocation',
    'WinPrtScrFolder'
)
Export-ModuleMember -Function $ExportedFunctions
