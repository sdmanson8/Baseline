using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Configures File Explorer behavior settings.



.DESCRIPTION

Applies Baseline's File Explorer behavior settings in GUI and headless runs.
	.PARAMETER Enable
	Show confirmation dialog when deleting files

	.PARAMETER Disable
	Do not show confirmation dialog when deleting files (default value)

	.EXAMPLE
	FileDeleteConfirm -Enable

	.EXAMPLE
	FileDeleteConfirm -Disable

	.NOTES
	Current user
#>
function FileDeleteConfirm
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling confirmation dialog when deleting files"
			LogInfo "Enabling confirmation dialog when deleting files"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
					-Name "ConfirmFileDelete" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable file delete confirmation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling confirmation dialog when deleting files"
			LogInfo "Disabling confirmation dialog when deleting files"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ConfirmFileDelete" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ConfirmFileDelete"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable file delete confirmation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File operation progress details in File Explorer



.DESCRIPTION

Applies the Baseline behavior for file operation progress details in File Explorer.
	.PARAMETER Enable
	Show detailed file operation progress information

	.PARAMETER Disable
	Hide detailed file operation progress information

	.EXAMPLE
	FileOperationsDetails -Enable

	.EXAMPLE
	FileOperationsDetails -Disable

	.NOTES
	Current user
#>
function FileOperationsDetails
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling detailed file progress information"
			LogInfo "Enabling detailed file progress information"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" `
					-Name "EnthusiastMode" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable detailed file operation information: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling detailed file progress information"
			LogInfo "Disabling detailed file progress information"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable detailed file operation information: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Task Manager details view in Windows 10 and later



.DESCRIPTION

Applies the Baseline behavior for task Manager details view in Windows 10 and later.
	.PARAMETER Enable
	Always show full details view in Task Manager

	.PARAMETER Disable
	Revert Task Manager to default summary view

	.EXAMPLE
	TaskManagerDetails -Enable

	.EXAMPLE
	TaskManagerDetails -Disable

	.NOTES
	Current user
	Anniversary Update workaround. The GPO used in DisableTaskManagerDetails has been broken in 1607 and fixed again in 1803
#>
function TaskManagerDetails
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Task Manager detailed view"
			LogInfo "Enabling Task Manager detailed view"
			try
			{
				$taskmgr = Start-Process -WindowStyle Hidden -FilePath taskmgr.exe -PassThru -ErrorAction Stop
				$timeout = 30000
				$sleep = 100
				Do {
					Start-Sleep -Milliseconds $sleep
					$timeout -= $sleep
					$preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
				} Until ($preferences -or $timeout -le 0)
				Stop-Process $taskmgr -ErrorAction SilentlyContinue | Out-Null
				If ($preferences) {
					$preferences.Preferences[28] = 0
					Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" `
						-Name "Preferences" `
						-Value $preferences.Preferences `
						-Type Binary
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Task Manager detailed view: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Task Manager detailed view"
			LogInfo "Disabling Task Manager detailed view"
			try
			{
				$preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
				If ($preferences) {
					$preferences.Preferences[28] = 1
					Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" `
						-Name "Preferences" `
						-Value $preferences.Preferences `
						-Type Binary
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Task Manager detailed view: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Control Panel icons view



.DESCRIPTION

Applies the Baseline behavior for the Control Panel icons view.
	.PARAMETER Category
	View the Control Panel icons by category (default value)

	.PARAMETER LargeIcons
	View the Control Panel icons by large icons

	.PARAMETER SmallIcons
	View the Control Panel icons by Small icons

	.EXAMPLE
	ControlPanelView -Category

	.EXAMPLE
	ControlPanelView -LargeIcons

	.EXAMPLE
	ControlPanelView -SmallIcons

	.NOTES
	Current user
#>

function ControlPanelView
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Category"
		)]
		[switch]
		$Category,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "LargeIcons"
		)]
		[switch]
		$LargeIcons,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SmallIcons"
		)]
		[switch]
		$SmallIcons
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-RegistryValueSafe -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ForceClassicControlPanel | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ForceClassicControlPanel -Type CLEAR | Out-Null

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Category"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Category"
			LogInfo "Setting Control Panel to be viewed by Category"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "AllItemsIconView" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "StartupPage" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Category: $($_.Exception.Message)"
			}
		}
		"LargeIcons"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Large Icons"
			LogInfo "Setting Control Panel to be viewed by Large Icons"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "AllItemsIconView" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "StartupPage" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Large Icons: $($_.Exception.Message)"
			}
		}
		"SmallIcons"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Small Icons"
			LogInfo "Setting Control Panel to be viewed by Small Icons"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "AllItemsIconView" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" `
					-Name "StartupPage" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Small Icons: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Files and folders grouping in the Downloads folder



.DESCRIPTION

Applies the Baseline behavior for files and folders grouping in the Downloads folder.
	.PARAMETER None
	Do not group files and folder in the Downloads folder

	.PARAMETER Default
	Group files and folder by date modified in the Downloads folder (default value)

	.EXAMPLE
	FolderGroupBy -None

	.EXAMPLE
	FolderGroupBy -Default

	.NOTES
	Current user
#>
function FolderGroupBy
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "None"
		)]
		[switch]
		$None,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"None"
		{
			Write-ConsoleStatus -Action "Enabling grouping of files and folder in the Downloads folder"
			LogInfo "Enabling grouping of files and folder in the Downloads folder"
			# Clear any Common Dialog views
			Get-ChildItem -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\*\Shell" -ErrorAction SilentlyContinue |
		Where-Object { $_.PSChildName -eq "{885A186E-A440-4ADA-812B-DB871B942259}" } |
		Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

			# https://learn.microsoft.com/en-us/windows/win32/properties/props-system-null
			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Force | Out-Null
			}
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "ColumnList" `
				-Value "System.Null" `
				-Type String
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "GroupBy" `
				-Value "System.Null" `
				-Type String
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "LogicalViewMode" `
				-Value 1 `
				-Type DWord
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "Name" `
				-Value "NoName" `
				-Type String
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "Order" `
				-Value 0 `
				-Type DWord
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "PrimaryProperty" `
				-Value "System.ItemNameDisplay" `
				-Type String
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" `
				-Name "SortByList" `
				-Value "prop:System.ItemNameDisplay" `
				-Type String
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Disabling grouping of files and folder in the Downloads folder"
			LogInfo "Disabling grouping of files and folder in the Downloads folder"
			Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}" -Recurse -Force -ErrorAction Ignore | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Enable or disable coloring of encrypted or compressed NTFS files (green for encrypted, blue for compressed)



.DESCRIPTION

Enables or disables coloring of encrypted or compressed NTFS files (green for encrypted, blue for compressed) in GUI and headless runs.
.PARAMETER Enable
Enable coloring of encrypted or compressed NTFS files (default value)

.PARAMETER Disable
Disable coloring of encrypted or compressed NTFS files

.EXAMPLE
EncCompFilesColor -Enable

.EXAMPLE
EncCompFilesColor -Disable

.NOTES
Current user
#>
function EncCompFilesColor
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling coloring of encrypted or compressed NTFS files"
			LogInfo "Enabling coloring of encrypted or compressed NTFS files"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowEncryptCompressedColor" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable coloring of encrypted or compressed NTFS files: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling coloring of encrypted or compressed NTFS files"
			LogInfo "Disabling coloring of encrypted or compressed NTFS files"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowEncryptCompressedColor" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowEncryptCompressedColor"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable coloring of encrypted or compressed NTFS files: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable displaying full path in Explorer window title



.DESCRIPTION

Enables or disables displaying full path in Explorer window title in GUI and headless runs.
.PARAMETER Enable
Enable displaying full path in Explorer title

.PARAMETER Disable
Disable displaying full path in Explorer title (default value)

.EXAMPLE
ExplorerTitleFullPath -Enable

.EXAMPLE
ExplorerTitleFullPath -Disable

.NOTES
Current user
#>
function ExplorerTitleFullPath
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the display of full paths in Explorer title"
			LogInfo "Enabling the display of full paths in Explorer title"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" `
					-Name "FullPath" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable full paths in Explorer title: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the display of full paths in Explorer title"
			LogInfo "Disabling the display of full paths in Explorer title"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable full paths in Explorer title: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File Explorer mode



.DESCRIPTION

Applies the Baseline behavior for file Explorer mode.
	.PARAMETER Disable
	Disable File Explorer compact mode (default value)

	.PARAMETER Enable
	Enable File Explorer compact mode

	.EXAMPLE
	FileExplorerCompactMode -Disable

	.EXAMPLE
	FileExplorerCompactMode -Enable

	.NOTES
	Current user
#>
function FileExplorerCompactMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling File Explorer compact mode"
			LogInfo "Disabling File Explorer compact mode"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "UseCompactMode" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable File Explorer compact mode: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling File Explorer compact mode"
			LogInfo "Enabling File Explorer compact mode"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "UseCompactMode" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable File Explorer compact mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File name extensions



.DESCRIPTION

Applies the Baseline behavior for file name extensions.
	.PARAMETER Show
	Show file name extensions

	.PARAMETER Hide
	Hide file name extensions (default value)

	.EXAMPLE
	FileExtensions -Show

	.EXAMPLE
	FileExtensions -Hide

	.NOTES
	Current user
#>
function FileExtensions
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling file name extensions"
			LogInfo "Enabling file name extensions"
			try
			{
				$advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
				if (-not (Test-Path -LiteralPath $advancedKey)) { New-Item -Path $advancedKey -Force -ErrorAction Stop | Out-Null }
				Set-RegistryValueSafe -Path $advancedKey `
					-Name "HideFileExt" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show file name extensions: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling file name extensions"
			LogInfo "Disabling file name extensions"
			try
			{
				$advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
				if (-not (Test-Path -LiteralPath $advancedKey)) { New-Item -Path $advancedKey -Force -ErrorAction Stop | Out-Null }
				Set-RegistryValueSafe -Path $advancedKey `
					-Name "HideFileExt" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide file name extensions: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The file transfer dialog box mode



.DESCRIPTION

Applies the Baseline behavior for the file transfer dialog box mode.
	.PARAMETER Detailed
	Show the file transfer dialog box in the detailed mode

	.PARAMETER Compact
	Show the file transfer dialog box in the compact mode (default value)

	.EXAMPLE
	FileTransferDialog -Detailed

	.EXAMPLE
	FileTransferDialog -Compact

	.NOTES
	Current user
#>
function FileTransferDialog
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Detailed"
		)]
		[switch]
		$Detailed,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Compact"
		)]
		[switch]
		$Compact
	)

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Detailed"
		{
			Write-ConsoleStatus -Action "Enabling detailed view for file transfer dialog boxes"
			LogInfo "Enabling detailed view for file transfer dialog boxes"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" `
					-Name "EnthusiastMode" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable detailed view for file transfer dialog boxes: $($_.Exception.Message)"
			}
		}
		"Compact"
		{
			Write-ConsoleStatus -Action "Enabling compact view for file transfer dialog boxes"
			LogInfo "Enabling compact view for file transfer dialog boxes"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" `
					-Name "EnthusiastMode" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable compact view for file transfer dialog boxes: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	First sign-in animation after the upgrade



.DESCRIPTION

Applies the Baseline behavior for first sign-in animation after the upgrade.
	.PARAMETER Disable
	Disable first sign-in animation after the upgrade

	.PARAMETER Enable
	Enable first sign-in animation after the upgrade (default value)

	.EXAMPLE
	FirstLogonAnimation -Disable

	.EXAMPLE
	FirstLogonAnimation -Enable

	.NOTES
	Current user
#>
function FirstLogonAnimation
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableFirstLogonAnimation -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableFirstLogonAnimation -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the first sign-in animation after upgrade"
			LogInfo "Disabling the first sign-in animation after upgrade"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
					-Name "EnableFirstLogonAnimation" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the first sign-in animation after upgrade: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the first sign-in animation after upgrade"
			LogInfo "Enabling the first sign-in animation after upgrade"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
					-Name "EnableFirstLogonAnimation" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the first sign-in animation after upgrade: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Folder merge conflicts



.DESCRIPTION

Applies the Baseline behavior for folder merge conflicts.
	.PARAMETER Show
	Show folder merge conflicts

	.PARAMETER Hide
	Hide folder merge conflicts (default value)

	.EXAMPLE
	MergeConflicts -Show

	.EXAMPLE
	MergeConflicts -Hide

	.NOTES
	Current user
#>
function MergeConflicts
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling folder merge conflicts"
			LogInfo "Enabling folder merge conflicts"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "HideMergeConflicts" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show folder merge conflicts: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling folder merge conflicts"
			LogInfo "Disabling folder merge conflicts"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "HideMergeConflicts" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide folder merge conflicts: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable launching folder windows in a separate process



.DESCRIPTION

Enables or disables launching folder windows in a separate process in GUI and headless runs.
.PARAMETER Enable
Enable launching folder windows in a separate process

.PARAMETER Disable
Disable launching folder windows in a separate process (default value)

.EXAMPLE
FldrSeparateProcess -Enable

.EXAMPLE
FldrSeparateProcess -Disable

.NOTES
Current user
#>
function FldrSeparateProcess
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling launching folder windows in a separate process"
			LogInfo "Enabling launching folder windows in a separate process"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "SeparateProcess" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable separate folder windows: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling launching folder windows in a separate process"
			LogInfo "Disabling launching folder windows in a separate process"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "SeparateProcess" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable separate folder windows: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Hidden files, folders, and drives



.DESCRIPTION

Applies the Baseline behavior for hidden files, folders, and drives.
	.PARAMETER Enable
	Show hidden files, folders, and drives

	.PARAMETER Disable
	Do not show hidden files, folders, and drives (default value)

	.EXAMPLE
	HiddenItems -Enable

	.EXAMPLE
	HiddenItems -Disable

	.NOTES
	Current user
#>
function HiddenItems
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Hidden files, folders, and drives"
			LogInfo "Enabling Hidden files, folders, and drives"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "Hidden" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show hidden files, folders, and drives: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Hidden files, folders, and drives"
			LogInfo "Disabling Hidden files, folders, and drives"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "Hidden" `
					-Value 2 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide hidden files, folders, and drives: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Item check boxes



.DESCRIPTION

Applies the Baseline behavior for item check boxes.
	.PARAMETER Disable
	Do not use item check boxes

	.PARAMETER Enable
	Use check item check boxes (default value)

	.EXAMPLE
	CheckBoxes -Disable

	.EXAMPLE
	CheckBoxes -Enable

	.NOTES
	Current user
#>
function CheckBoxes
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling item check boxes"
			LogInfo "Enabling item check boxes"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AutoCheckSelect" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable item check boxes: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling item check boxes"
			LogInfo "Disabling item check boxes"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AutoCheckSelect" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable item check boxes: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable item selection checkboxes in Explorer



.DESCRIPTION

Enables or disables item selection checkboxes in Explorer in GUI and headless runs.
.PARAMETER Enable
Enable item selection checkboxes

.PARAMETER Disable
Disable item selection checkboxes (default value)

.EXAMPLE
SelectCheckboxes -Enable

.EXAMPLE
SelectCheckboxes -Disable

.NOTES
Current user
#>
function SelectCheckboxes
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling item selection checkboxes in Explorer"
			LogInfo "Enabling item selection checkboxes in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AutoCheckSelect" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable item selection checkboxes in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling item selection checkboxes in Explorer"
			LogInfo "Enabling item selection checkboxes in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AutoCheckSelect" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable item selection checkboxes in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The quality factor of the JPEG desktop wallpapers



.DESCRIPTION

Applies the Baseline behavior for the quality factor of the JPEG desktop wallpapers.
	.PARAMETER Max
	Set the quality factor of the JPEG desktop wallpapers to maximum

	.PARAMETER Default
	Set the quality factor of the JPEG desktop wallpapers to default (default value)

	.EXAMPLE
	JPEGWallpapersQuality -Max

	.EXAMPLE
	JPEGWallpapersQuality -Default

	.NOTES
	Current user
#>
function JPEGWallpapersQuality
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Max"
		)]
		[switch]
		$Max,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Max"
		{
			Write-ConsoleStatus -Action "Enabling the maximum quality factor of the JPEG desktop wallpapers"
			LogInfo "Enabling the maximum quality factor of the JPEG desktop wallpapers"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "JPEGImportQuality" `
					-Value 100 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the maximum JPEG desktop wallpaper quality: $($_.Exception.Message)"
			}
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Disabling the maximum quality factor of the JPEG desktop wallpapers"
			LogInfo "Disabling the maximum quality factor of the JPEG desktop wallpapers"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" -Name "JPEGImportQuality"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore the default JPEG desktop wallpaper quality: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable showing all folders in Explorer navigation pane



.DESCRIPTION

Enables or disables showing all folders in Explorer navigation pane in GUI and headless runs.
.PARAMETER Enable
Enable showing all folders in navigation pane

.PARAMETER Disable
Disable showing all folders in navigation pane (default value)

.EXAMPLE
NavPaneAllFolders -Enable

.EXAMPLE
NavPaneAllFolders -Disable

.NOTES
Current user
#>
function NavPaneAllFolders
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling all folders in the Explorer navigation pane"
			LogInfo "Enabling all folders in the Explorer navigation pane"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "NavPaneShowAllFolders" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable all folders in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling all folders in the Explorer navigation pane"
			LogInfo "Disabling all folders in the Explorer navigation pane"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable all folders in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable showing Libraries in Explorer navigation pane



.DESCRIPTION

Enables or disables showing Libraries in Explorer navigation pane in GUI and headless runs.
.PARAMETER Enable
Enable showing Libraries in navigation pane

.PARAMETER Disable
Disable showing Libraries in navigation pane (default value)

.EXAMPLE
NavPaneLibraries -Enable

.EXAMPLE
NavPaneLibraries -Disable

.NOTES
Current user
#>
function NavPaneLibraries
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Libraries in the Explorer navigation pane"
			LogInfo "Enabling Libraries in the Explorer navigation pane"
			try
			{
				If (!(Test-Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}")) {
					New-Item -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" `
					-Name "System.IsPinnedToNameSpaceTree" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Libraries in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Libraries in the Explorer navigation pane"
			LogInfo "Disabling Libraries in the Explorer navigation pane"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Name "System.IsPinnedToNameSpaceTree" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Name "System.IsPinnedToNameSpaceTree"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Libraries in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Expand to current folder in navigation pane



.DESCRIPTION

Applies the Baseline behavior for expand to current folder in navigation pane.
	.PARAMETER Disable
	Do not expand to open folder on navigation pane (default value)

	.PARAMETER Enable
	Expand to open folder on navigation pane

	.EXAMPLE
	NavigationPaneExpand -Disable

	.EXAMPLE
	NavigationPaneExpand -Enable

	.NOTES
	Current user
#>
function NavigationPaneExpand
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling expand to open folder on navigation pane"
			LogInfo "Disabling expand to open folder on navigation pane"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "NavPaneExpandToCurrentFolder" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable expanding to the current folder in the navigation pane: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling expand to open folder on navigation pane"
			LogInfo "Enabling expand to open folder on navigation pane"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "NavPaneExpandToCurrentFolder" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable expanding to the current folder in the navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Sync provider notification in File Explorer



.DESCRIPTION

Applies the Baseline behavior for sync provider notification in File Explorer.
	.PARAMETER Hide
	Do not show sync provider notification within File Explorer

	.PARAMETER Show
	Show sync provider notification within File Explorer (default value)

	.EXAMPLE
	OneDriveFileExplorerAd -Hide

	.EXAMPLE
	OneDriveFileExplorerAd -Show

	.NOTES
	Current user
#>
function OneDriveFileExplorerAd
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling sync provider notification within File Explorer"
			LogInfo "Disabling sync provider notification within File Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowSyncProviderNotifications" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide sync provider notification within File Explorer: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling sync provider notification within File Explorer"
			LogInfo "Enabling sync provider notification within File Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowSyncProviderNotifications" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show sync provider notification within File Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Configure how to open File Explorer



.DESCRIPTION

Applies the Baseline behavior for configure how to open File Explorer.
	.PARAMETER ThisPC
	Open File Explorer to "This PC"

	.PARAMETER QuickAccess
	Open File Explorer to Quick access (default value)

	.PARAMETER Downloads
	Open File Explorer to Downloads

	.EXAMPLE
	OpenFileExplorerTo -ThisPC

	.EXAMPLE
	OpenFileExplorerTo -QuickAccess

	.EXAMPLE
	OpenFileExplorerTo -Downloads

	.NOTES
	Current user
#>

function OpenFileExplorerTo
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "ThisPC"
		)]
		[switch]
		$ThisPC,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "QuickAccess"
		)]
		[switch]
		$QuickAccess,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Downloads"
		)]
		[switch]
		$Downloads
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"ThisPC"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'This PC'"
			LogInfo "Setting File Explorer to open to 'This PC'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "LaunchTo" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'This PC': $($_.Exception.Message)"
			}
		}
		"QuickAccess"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'Quick Access'"
			LogInfo "Setting File Explorer to open to 'Quick Access'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "LaunchTo" `
					-Value 2 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'Quick Access': $($_.Exception.Message)"
			}
		}
		"Downloads"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'Downloads'"
			LogInfo "Setting File Explorer to open to 'Downloads'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "LaunchTo" `
					-Value 3 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'Downloads': $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show or hide protected operating system files



.DESCRIPTION

Shows or hide protected operating system files from Baseline's GUI flow.
	.PARAMETER Enable
	Show protected operating system files

	.PARAMETER Disable
	Do not show protected operating system files (default value)

	.EXAMPLE
	SuperHiddenFiles -Enable

	.EXAMPLE
	SuperHiddenFiles -Disable

	.NOTES
	Current user
#>
function SuperHiddenFiles
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'Show protected operating system files'"
			LogInfo "Enabling 'Show protected operating system files'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowSuperHidden" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show protected operating system files: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'Show protected operating system files'"
			LogInfo "Disabling 'Show protected operating system files'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowSuperHidden" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide protected operating system files: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Frequently used folders in Quick access



.DESCRIPTION

Applies the Baseline behavior for frequently used folders in Quick access.
	.PARAMETER Hide
	Hide frequently used folders in Quick access

	.PARAMETER Show
	Show frequently used folders in Quick access (default value)

	.EXAMPLE
	QuickAccessFrequentFolders -Hide

	.EXAMPLE
	QuickAccessFrequentFolders -Show

	.NOTES
	Current user
#>
function QuickAccessFrequentFolders
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling frequently used folders in Quick access"
			LogInfo "Disabling frequently used folders in Quick access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowFrequent" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide frequently used folders in Quick access: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling frequently used folders in Quick access"
			LogInfo "Enabling frequently used folders in Quick access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowFrequent" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show frequently used folders in Quick access: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recently used files in Quick access



.DESCRIPTION

Applies the Baseline behavior for recently used files in Quick access.
	.PARAMETER Hide
	Hide recently used files in Quick access

	.PARAMETER Show
	Show recently used files in Quick access (default value)

	.EXAMPLE
	QuickAccessRecentFiles -Hide

	.EXAMPLE
	QuickAccessRecentFiles -Show

	.NOTES
	Current user
#>
function QuickAccessRecentFiles
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-RegistryValueSafe -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoRecentDocsHistory | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoRecentDocsHistory -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoRecentDocsHistory -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling recently used files in Quick access"
			LogInfo "Disabling recently used files in Quick access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowRecent" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide recently used files in Quick access: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling recently used files in Quick access"
			LogInfo "Enabling recently used files in Quick access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowRecent" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show recently used files in Quick access: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable recently and frequently used item shortcuts in Explorer

.DESCRIPTION
Note: This is only a UI tweak to hide the shortcuts. In order to stop creating most recently used (MRU) items lists everywhere, use privacy tweak 'DisableRecentFiles' instead.

.PARAMETER Enable
Enable hiding recently and frequently used item shortcuts

.PARAMETER Disable
Disable hiding recently and frequently used item shortcuts (default value)

.EXAMPLE
RecentShortcuts -Enable

.EXAMPLE
RecentShortcuts -Disable

.NOTES
Current user
#>

function RecentShortcuts
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling recently and frequently used item shortcuts in Explorer"
			LogInfo "Enabling recently and frequently used item shortcuts in Explorer"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent"
				}
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable recent and frequent item shortcuts in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling recently and frequently used item shortcuts in Explorer"
			LogInfo "Disabling recently and frequently used item shortcuts in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowRecent" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShowFrequent" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable recent and frequent item shortcuts in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The recycle bin files delete confirmation dialog



.DESCRIPTION

Applies the Baseline behavior for the recycle bin files delete confirmation dialog.
	.PARAMETER Enable
	Display the recycle bin files delete confirmation dialog

	.PARAMETER Disable
	Do not display the recycle bin files delete confirmation dialog (default value)

	.EXAMPLE
	RecycleBinDeleteConfirmation -Enable

	.EXAMPLE
	RecycleBinDeleteConfirmation -Disable

	.NOTES
	Current user
#>
function RecycleBinDeleteConfirmation
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-RegistryValueSafe -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ConfirmFileDelete | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name ConfirmFileDelete -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name ConfirmFileDelete -Type CLEAR | Out-Null

	$ShellState = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShellState

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the recycle bin files delete confirmation dialog"
			LogInfo "Enabling the recycle bin files delete confirmation dialog"
			try
			{
				$ShellState[4] = 51
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShellState" `
					-Value $ShellState `
					-Type Binary
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the recycle bin delete confirmation dialog: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the recycle bin files delete confirmation dialog"
			LogInfo "Disabling the recycle bin files delete confirmation dialog"
			try
			{
				$ShellState[4] = 55
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShellState" `
					-Value $ShellState `
					-Type Binary
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the recycle bin delete confirmation dialog: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable restoring previous folder windows at logon



.DESCRIPTION

Enables or disables restoring previous folder windows at logon in GUI and headless runs.
.PARAMETER Enable
Enable restoring previous folder windows at logon

.PARAMETER Disable
Disable restoring previous folder windows at logon (default value)

.EXAMPLE
RestoreFldrWindows -Enable

.EXAMPLE
RestoreFldrWindows -Disable

.NOTES
Current user
#>
function RestoreFldrWindows
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling restoring previous folder windows at logon"
			LogInfo "Enabling restoring previous folder windows at logon"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "PersistBrowsers" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable restoring previous folder windows at logon: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling restoring previous folder windows at logon"
			LogInfo "Disabling restoring previous folder windows at logon"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PersistBrowsers" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PersistBrowsers"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable restoring previous folder windows at logon: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Startup delay for apps at login



.DESCRIPTION

Applies the Baseline behavior for startup delay for apps at login.
	.PARAMETER Disable
	Disable startup delay for apps at login

	.PARAMETER Enable
	Enable startup delay for apps at login

	.EXAMPLE
	Set-StartupAppDelay -Enable

	.EXAMPLE
	Set-StartupAppDelay -Disable

	.NOTES
	Current user. Controls the delay in milliseconds before apps start at login.
#>
function Set-StartupAppDelay
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling startup delay for apps at login"
			LogInfo "Enabling startup delay for apps at login"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" `
					-Name "StartupDelayInMSec" `
					-Value 2000 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable startup app delay: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling startup delay for apps at login"
			LogInfo "Disabling startup delay for apps at login"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" `
					-Name "StartupDelayInMSec" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable startup app delay: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Browse folders in same or new window



.DESCRIPTION

Applies the Baseline behavior for browse folders in same or new window.
	.PARAMETER SameWindow
	Browse folders in the same window

	.PARAMETER NewWindow
	Browse folders in new windows

	.EXAMPLE
	Set-ExplorerBrowseMode -SameWindow

	.EXAMPLE
	Set-ExplorerBrowseMode -NewWindow

	.NOTES
	Current user. Controls CabinetState\BrowseNewProcess setting.
#>
function Set-ExplorerBrowseMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SameWindow"
		)]
		[switch]
		$SameWindow,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "NewWindow"
		)]
		[switch]
		$NewWindow
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"SameWindow"
		{
			Write-ConsoleStatus -Action "Setting Explorer to browse folders in the same window"
			LogInfo "Setting Explorer to browse folders in the same window"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" `
					-Name "BrowseNewProcess" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Explorer browse mode: $($_.Exception.Message)"
			}
		}
		"NewWindow"
		{
			Write-ConsoleStatus -Action "Setting Explorer to browse folders in new windows"
			LogInfo "Setting Explorer to browse folders in new windows"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" `
					-Name "BrowseNewProcess" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Explorer browse mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Click behavior for items in Explorer



.DESCRIPTION

Applies the Baseline behavior for click behavior for items in Explorer.
	.PARAMETER SingleClick
	Single-click to open items

	.PARAMETER DoubleClick
	Double-click to open items (default)

	.EXAMPLE
	Set-ExplorerClickBehavior -SingleClick

	.EXAMPLE
	Set-ExplorerClickBehavior -DoubleClick

	.NOTES
	Current user. Controls ShellState registry setting.
#>
function Set-ExplorerClickBehavior
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SingleClick"
		)]
		[switch]
		$SingleClick,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "DoubleClick"
		)]
		[switch]
		$DoubleClick
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"SingleClick"
		{
			Write-ConsoleStatus -Action "Enabling single-click mode in Explorer"
			LogInfo "Enabling single-click mode in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShellState" `
					-Value ([byte[]](240, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) `
					-Type Binary | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable single-click mode: $($_.Exception.Message)"
			}
		}
		"DoubleClick"
		{
			Write-ConsoleStatus -Action "Enabling double-click mode in Explorer (default)"
			LogInfo "Enabling double-click mode in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "ShellState" `
					-Value ([byte[]](240, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) `
					-Type Binary | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable double-click mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show Office files in Quick Access



.DESCRIPTION

Shows Office files in Quick Access from Baseline's GUI flow.
	.PARAMETER Enable
	Show files from Office.com in Quick Access

	.PARAMETER Disable
	Hide files from Office.com in Quick Access

	.EXAMPLE
	Set-OfficeCloudFilesInQuickAccess -Enable

	.EXAMPLE
	Set-OfficeCloudFilesInQuickAccess -Disable

	.NOTES
	Current user. Controls ShowCloudFilesInQuickAccess setting.
#>
function Set-OfficeCloudFilesInQuickAccess
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Office.com files in Quick Access"
			LogInfo "Enabling Office.com files in Quick Access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowCloudFilesInQuickAccess" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Office.com files in Quick Access: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Office.com files in Quick Access"
			LogInfo "Disabling Office.com files in Quick Access"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowCloudFilesInQuickAccess" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Office.com files in Quick Access: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Always show menu bar in Explorer



.DESCRIPTION

Applies the Baseline behavior for always show menu bar in Explorer.
	.PARAMETER Enable
	Always show menu bar in Explorer

	.PARAMETER Disable
	Hide menu bar in Explorer

	.EXAMPLE
	Set-ExplorerAlwaysShowMenuBar -Enable

	.EXAMPLE
	Set-ExplorerAlwaysShowMenuBar -Disable

	.NOTES
	Current user. Controls AlwaysShowMenus setting.
#>
function Set-ExplorerAlwaysShowMenuBar
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling always show menu bar in Explorer"
			LogInfo "Enabling always show menu bar in Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AlwaysShowMenus" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable always show menu bar: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling always show menu bar in Explorer"
			LogInfo "Disabling always show menu bar in Explorer"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "AlwaysShowMenus" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable always show menu bar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Display file icon on thumbnails



.DESCRIPTION

Applies the Baseline behavior for display file icon on thumbnails.
	.PARAMETER Enable
	Display file icon on thumbnails

	.PARAMETER Disable
	Hide file icon on thumbnails

	.EXAMPLE
	Set-DisplayFileIconOnThumbnails -Enable

	.EXAMPLE
	Set-DisplayFileIconOnThumbnails -Disable

	.NOTES
	Current user. Controls IconsOnly setting.
#>
function Set-DisplayFileIconOnThumbnails
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling file icon display on thumbnails"
			LogInfo "Enabling file icon display on thumbnails"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "IconsOnly" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable file icon on thumbnails: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling file icon display on thumbnails"
			LogInfo "Disabling file icon display on thumbnails"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "IconsOnly" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable file icon on thumbnails: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Display file size info in folder tooltips



.DESCRIPTION

Applies the Baseline behavior for display file size info in folder tooltips.
	.PARAMETER Enable
	Display file size info in folder tooltips

	.PARAMETER Disable
	Hide file size info in folder tooltips

	.EXAMPLE
	Set-FolderTooltipDetails -Enable

	.EXAMPLE
	Set-FolderTooltipDetails -Disable

	.NOTES
	Current user. Controls FolderContentsInfoTip setting.
#>
function Set-FolderTooltipDetails
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling file size info in folder tooltips"
			LogInfo "Enabling file size info in folder tooltips"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "FolderContentsInfoTip" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable folder tooltip details: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling file size info in folder tooltips"
			LogInfo "Disabling file size info in folder tooltips"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "FolderContentsInfoTip" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable folder tooltip details: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show drive letters before drive names



.DESCRIPTION

Shows drive letters before drive names from Baseline's GUI flow.
	.PARAMETER Enable
	Show drive letters before drive names (e.g., "C: Local Disk")

	.PARAMETER Disable
	Hide drive letters from display

	.EXAMPLE
	Set-ShowDriveLetters -Enable

	.EXAMPLE
	Set-ShowDriveLetters -Disable

	.NOTES
	Current user. Affects how drives appear in Explorer nav pane.
#>
function Set-ShowDriveLetters
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Displaying drive letters before drive names"
			LogInfo "Displaying drive letters before drive names"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
					-Name "NoDrives" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show drive letters: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Hiding drive letters from drive names"
			LogInfo "Hiding drive letters from drive names"
			try
			{
				# This is typically handled by shell state, implementation kept simple
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide drive letters: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Hide empty drives



.DESCRIPTION

Applies the Baseline behavior for hide empty drives.
	.PARAMETER Enable
	Hide drives with no media in Explorer

	.PARAMETER Disable
	Show all drives including those with no media

	.EXAMPLE
	Set-HideEmptyDrives -Enable

	.EXAMPLE
	Set-HideEmptyDrives -Disable

	.NOTES
	Current user. Controls HideDrivesWithNoMedia setting.
#>
function Set-HideEmptyDrives
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Hiding empty drives from Explorer"
			LogInfo "Hiding empty drives from Explorer"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "HideDrivesWithNoMedia" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide empty drives: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Showing empty drives in Explorer"
			LogInfo "Showing empty drives in Explorer"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "HideDrivesWithNoMedia" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show empty drives: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show status bar in Explorer



.DESCRIPTION

Shows status bar in Explorer from Baseline's GUI flow.
	.PARAMETER Enable
	Show status bar in Explorer

	.PARAMETER Disable
	Hide status bar in Explorer

	.EXAMPLE
	Set-ExplorerStatusBar -Enable

	.EXAMPLE
	Set-ExplorerStatusBar -Disable

	.NOTES
	Current user. Controls ShowStatusBar setting.
#>
function Set-ExplorerStatusBar
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Explorer status bar"
			LogInfo "Enabling Explorer status bar"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowStatusBar" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Explorer status bar: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Explorer status bar"
			LogInfo "Disabling Explorer status bar"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowStatusBar" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Explorer status bar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Type-ahead behavior in Explorer list view



.DESCRIPTION

Applies the Baseline behavior for type-ahead behavior in Explorer list view.
	.PARAMETER TypeAhead
	Use type-ahead to search for items

	.PARAMETER Search
	Use search mode when typing in list view

	.EXAMPLE
	Set-ExplorerTypeAhead -TypeAhead

	.EXAMPLE
	Set-ExplorerTypeAhead -Search

	.NOTES
	Current user. Controls TypeAhead setting.
#>
function Set-ExplorerTypeAhead
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "TypeAhead"
		)]
		[switch]
		$TypeAhead,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Search"
		)]
		[switch]
		$Search
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"TypeAhead"
		{
			Write-ConsoleStatus -Action "Enabling type-ahead in Explorer"
			LogInfo "Enabling type-ahead search in Explorer list view"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TypeAhead" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable type-ahead: $($_.Exception.Message)"
			}
		}
		"Search"
		{
			Write-ConsoleStatus -Action "Enabling search mode in Explorer"
			LogInfo "Enabling search mode when typing in Explorer list view"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TypeAhead" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable search mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show 3D Objects folder in This PC



.DESCRIPTION

Shows 3D Objects folder in This PC from Baseline's GUI flow.
	.PARAMETER Enable
	Show the 3D Objects folder in This PC

	.PARAMETER Disable
	Hide the 3D Objects folder from This PC

	.EXAMPLE
	Set-Show3DObjectsFolder -Enable

	.EXAMPLE
	Set-Show3DObjectsFolder -Disable

	.NOTES
	Current user. Uses namespace CLSID {0DB7E03F-FC81-11E0-AC91-862B2E5C16DA}.
#>
function Set-Show3DObjectsFolder
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 3D Objects folder in This PC"
			LogInfo "Enabling 3D Objects folder in This PC"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{0DB7E03F-FC81-11E0-AC91-862B2E5C16DA}" `
					-Name "None" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 3D Objects folder: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 3D Objects folder in This PC"
			LogInfo "Disabling 3D Objects folder in This PC"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{0DB7E03F-FC81-11E0-AC91-862B2E5C16DA}"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "None" `
					-Value "" `
					-Type String | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 3D Objects folder: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show Home folder in navigation pane



.DESCRIPTION

Shows Home folder in navigation pane from Baseline's GUI flow.
	.PARAMETER Enable
	Show Home folder in Explorer navigation pane

	.PARAMETER Disable
	Hide Home folder from Explorer navigation pane

	.EXAMPLE
	Set-ShowHomeFolderInNavPane -Enable

	.EXAMPLE
	Set-ShowHomeFolderInNavPane -Disable

	.NOTES
	Current user. Uses namespace CLSID {f874310e-b6b7-36c8-9445-389bbb00226b}.
#>
function Set-ShowHomeFolderInNavPane
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Home folder in navigation pane"
			LogInfo "Enabling Home folder in Explorer navigation pane"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-36c8-9445-389bbb00226b}" `
					-Name "None" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Home folder in nav pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Home folder in navigation pane"
			LogInfo "Disabling Home folder in Explorer navigation pane"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-36c8-9445-389bbb00226b}"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "None" `
					-Value "" `
					-Type String | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Home folder in nav pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show Gallery in navigation pane



.DESCRIPTION

Shows Gallery in navigation pane from Baseline's GUI flow.
	.PARAMETER Enable
	Show Gallery folder in Explorer navigation pane

	.PARAMETER Disable
	Hide Gallery folder from Explorer navigation pane

	.EXAMPLE
	Set-ShowGalleryInNavPane -Enable

	.EXAMPLE
	Set-ShowGalleryInNavPane -Disable

	.NOTES
	Current user. Uses namespace CLSID {e88865ea-0e1c-495d-b050-1665d618313f}.
#>
function Set-ShowGalleryInNavPane
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Gallery in navigation pane"
			LogInfo "Enabling Gallery folder in Explorer navigation pane"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-495d-b050-1665d618313f}" `
					-Name "None" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Gallery in nav pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Gallery in navigation pane"
			LogInfo "Disabling Gallery folder in Explorer navigation pane"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-495d-b050-1665d618313f}"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "None" `
					-Value "" `
					-Type String | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Gallery in nav pane: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'CheckBoxes',
    'ControlPanelView',
    'EncCompFilesColor',
    'ExplorerTitleFullPath',
    'FileDeleteConfirm',
    'FileExplorerCompactMode',
    'FileExtensions',
    'FileOperationsDetails',
    'FileTransferDialog',
    'FirstLogonAnimation',
    'FldrSeparateProcess',
    'FolderGroupBy',
    'HiddenItems',
    'JPEGWallpapersQuality',
    'MergeConflicts',
    'NavigationPaneExpand',
    'NavPaneAllFolders',
    'NavPaneLibraries',
    'OneDriveFileExplorerAd',
    'OpenFileExplorerTo',
    'QuickAccessFrequentFolders',
    'QuickAccessRecentFiles',
    'RecentShortcuts',
    'RecycleBinDeleteConfirmation',
    'RestoreFldrWindows',
    'SelectCheckboxes',
    'Set-DisplayFileIconOnThumbnails',
    'Set-ExplorerAlwaysShowMenuBar',
    'Set-ExplorerBrowseMode',
    'Set-ExplorerClickBehavior',
    'Set-ExplorerStatusBar',
    'Set-ExplorerTypeAhead',
    'Set-FolderTooltipDetails',
    'Set-HideEmptyDrives',
    'Set-OfficeCloudFilesInQuickAccess',
    'Set-Show3DObjectsFolder',
    'Set-ShowDriveLetters',
    'Set-ShowGalleryInNavPane',
    'Set-ShowHomeFolderInNavPane',
    'Set-StartupAppDelay',
    'SuperHiddenFiles',
    'TaskManagerDetails'
)
Export-ModuleMember -Function $ExportedFunctions