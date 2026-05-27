using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1
<#
    .SYNOPSIS
    Return Baseline metadata for the supported user folders.

    .DESCRIPTION
    Builds the definition table for Desktop, Documents, Downloads, Music, Pictures, and Videos, including registry names, GUIDs, shell namespaces, and default paths.

    .EXAMPLE
    Get-BaselineUserFolderDefinitions
#>
function Get-BaselineUserFolderDefinitions
{
	[CmdletBinding()]
	param ()

	$userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

	return @(
		[pscustomobject]@{
			Folder         = 'Desktop'
			DisplayName    = 'Desktop'
			RegistryName   = 'Desktop'
			GuidName       = '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}'
			ShellNamespace = 'shell:Desktop'
			DefaultPath    = (Join-Path $userProfile 'Desktop')
		}
		[pscustomobject]@{
			Folder         = 'Documents'
			DisplayName    = 'Documents'
			RegistryName   = 'Personal'
			GuidName       = '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'
			ShellNamespace = 'shell:Personal'
			DefaultPath    = (Join-Path $userProfile 'Documents')
		}
		[pscustomobject]@{
			Folder         = 'Downloads'
			DisplayName    = 'Downloads'
			RegistryName   = '{374DE290-123F-4565-9164-39C4925E467B}'
			GuidName       = '{7D83EE9B-2244-4E70-B1F5-5404642AF1E4}'
			ShellNamespace = 'shell:Downloads'
			DefaultPath    = (Join-Path $userProfile 'Downloads')
		}
		[pscustomobject]@{
			Folder         = 'Music'
			DisplayName    = 'Music'
			RegistryName   = 'My Music'
			GuidName       = '{A0C69A99-21C8-4671-8703-7934162FCF1D}'
			ShellNamespace = 'shell:My Music'
			DefaultPath    = (Join-Path $userProfile 'Music')
		}
		[pscustomobject]@{
			Folder         = 'Pictures'
			DisplayName    = 'Pictures'
			RegistryName   = 'My Pictures'
			GuidName       = '{0DDD015D-B06C-45D5-8C4C-F59713854639}'
			ShellNamespace = 'shell:My Pictures'
			DefaultPath    = (Join-Path $userProfile 'Pictures')
		}
		[pscustomobject]@{
			Folder         = 'Videos'
			DisplayName    = 'Videos'
			RegistryName   = 'My Video'
			GuidName       = '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}'
			ShellNamespace = 'shell:My Video'
			DefaultPath    = (Join-Path $userProfile 'Videos')
		}
	)
}
<#
    .SYNOPSIS
    Return the metadata definition for one supported user folder.

    .DESCRIPTION
    Looks up a single folder definition from the Baseline user-folder definition table.

    .PARAMETER Folder
    Supported user folder name to resolve.

    .EXAMPLE
    Get-BaselineUserFolderDefinition -Folder 'Desktop'
#>
function Get-BaselineUserFolderDefinition
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder
	)

	return (Get-BaselineUserFolderDefinitions | Where-Object { [string]$_.Folder -eq $Folder } | Select-Object -First 1)
}
<#
    .SYNOPSIS
    Return the current path for a supported user folder.

    .DESCRIPTION
    Reads the current User Shell Folders path for the selected folder and falls back to the default path when no registry value is present.

    .PARAMETER Folder
    Supported user folder name to inspect.

    .EXAMPLE
    Get-BaselineUserFolderCurrentPath -Folder 'Documents'
#>
function Get-BaselineUserFolderCurrentPath
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder
	)

	$definition = Get-BaselineUserFolderDefinition -Folder $Folder
	$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'

	foreach ($name in @($definition.RegistryName, $definition.GuidName))
	{
		try
		{
			$value = Get-ItemPropertyValue -Path $registryPath -Name $name -ErrorAction Stop
			if (-not [string]::IsNullOrWhiteSpace([string]$value))
			{
				return [string]$value
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserFolders.Get-BaselineUserFolderCurrentPath:catch130' -Severity Debug }

		}
	}

	return [string]$definition.DefaultPath
}
<#
    .SYNOPSIS
    Return the desktop.ini content for a supported user folder.

    .DESCRIPTION
    Builds the desktop.ini lines Baseline writes after redirecting a known user folder.

    .PARAMETER Folder
    Supported user folder name to build desktop.ini content for.

    .EXAMPLE
    Get-BaselineUserFolderDesktopIniContent -Folder 'Pictures'
#>
function Get-BaselineUserFolderDesktopIniContent
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder
	)

	switch ($Folder)
	{
		'Desktop' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21769'
				'IconResource=%SystemRoot%\System32\imageres.dll,-183'
			)
		}
		'Documents' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21770'
				'IconResource=%SystemRoot%\System32\imageres.dll,-112'
				'IconFile=%SystemRoot%\System32\shell32.dll'
				'IconIndex=-235'
			)
		}
		'Downloads' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21798'
				'IconResource=%SystemRoot%\System32\imageres.dll,-184'
			)
		}
		'Music' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21790'
				'InfoTip=@%SystemRoot%\System32\shell32.dll,-12689'
				'IconResource=%SystemRoot%\System32\imageres.dll,-108'
				'IconFile=%SystemRoot%\System32\shell32.dll'
				'IconIndex=-237'
			)
		}
		'Pictures' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21779'
				'InfoTip=@%SystemRoot%\System32\shell32.dll,-12688'
				'IconResource=%SystemRoot%\System32\imageres.dll,-113'
				'IconFile=%SystemRoot%\System32\shell32.dll'
				'IconIndex=-236'
			)
		}
		'Videos' {
			return @(
				'[.ShellClassInfo]'
				'LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21791'
				'InfoTip=@%SystemRoot%\System32\shell32.dll,-12690'
				'IconResource=%SystemRoot%\System32\imageres.dll,-189'
				'IconFile=%SystemRoot%\System32\shell32.dll'
				'IconIndex=-238'
			)
		}
	}
}
<#
    .SYNOPSIS
    Validate whether a path can be used as a user folder destination.

    .DESCRIPTION
    Rejects blank or root-only paths and, when possible, checks the destination drive type before a user folder redirect is applied.

    .PARAMETER Path
    Destination path to validate.

    .EXAMPLE
    Test-BaselineUserFolderDestination -Path 'D:\Documents'
#>
function Test-BaselineUserFolderDestination
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if ([string]::IsNullOrWhiteSpace($Path))
	{
		return $false
	}

	$fullPath = [System.IO.Path]::GetFullPath($Path)
	$pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
	if ([string]::IsNullOrWhiteSpace($pathRoot))
	{
		return $false
	}

	if (($fullPath -ieq $pathRoot) -and $pathRoot -ieq 'C:\')
	{
		return $false
	}

	if ($pathRoot.Length -eq 3 -and $pathRoot.Substring(1, 1) -eq ':')
	{
		if (-not (Get-Command -Name 'Get-Volume' -ErrorAction SilentlyContinue))
		{
			throw 'Get-Volume is required to validate the destination drive type.'
		}

		$driveLetter = $pathRoot.Substring(0, 1)
		$volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
		if ([string]$volume.DriveType -eq 'Removable')
		{
			return $false
		}
	}

	return $true
}
<#
    .SYNOPSIS
    Apply a known-folder redirect through the Windows API helper.

    .DESCRIPTION
    Uses the Windows API Code Pack known-folder object for the selected folder to point Windows at the new path.

    .PARAMETER Folder
    Supported user folder name to redirect.

    .PARAMETER Path
    Destination path to assign.

    .EXAMPLE
    Invoke-BaselineUserFolderKnownFolderRedirect -Folder 'Downloads' -Path 'D:\Downloads'
#>
function Invoke-BaselineUserFolderKnownFolderRedirect
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder,

		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	try
	{
		switch ($Folder)
		{
			'Desktop'   { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Desktop.Path   = $Path }
			'Documents' { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Documents.Path = $Path }
			'Downloads' { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Downloads.Path = $Path }
			'Music'     { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Music.Path     = $Path }
			'Pictures'  { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Pictures.Path  = $Path }
			'Videos'    { [Microsoft.WindowsAPICodePack.Shell.KnownFolders]::Videos.Path    = $Path }
		}

		return $true
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserFolders.Invoke-BaselineUserFolderKnownFolderRedirect:catch313' -Severity Debug }

	}

	try
	{
		$definition = Get-BaselineUserFolderDefinition -Folder $Folder
		$shell = New-Object -ComObject Shell.Application -ErrorAction Stop
		$folderNamespace = $shell.Namespace($definition.ShellNamespace)
		if ($folderNamespace -and $folderNamespace.Self)
		{
			$folderNamespace.Self.Path = $Path
			return $true
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserFolders.Invoke-BaselineUserFolderKnownFolderRedirect:catch328' -Severity Debug }

	}

	return $false
}
<#
    .SYNOPSIS
    Write desktop.ini metadata for a redirected user folder.

    .DESCRIPTION
    Creates the destination folder if needed, writes the desktop.ini file, and applies the hidden and system attributes Baseline expects.

    .PARAMETER Folder
    Supported user folder name to write desktop.ini for.

    .PARAMETER Path
    Folder path that should receive the desktop.ini file.

    .EXAMPLE
    Set-BaselineUserFolderDesktopIni -Folder 'Music' -Path 'D:\Music'
#>
function Set-BaselineUserFolderDesktopIni
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder,

		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	$desktopIniPath = Join-Path $Path 'desktop.ini'
	$desktopIni = Get-BaselineUserFolderDesktopIniContent -Folder $Folder

	if (-not (Test-Path -LiteralPath $Path))
	{
		New-Item -ItemType Directory -Path $Path -Force | Out-Null
	}

	[System.IO.File]::WriteAllLines($desktopIniPath, $desktopIni, [System.Text.UnicodeEncoding]::new($false, $true))
	$item = Get-Item -LiteralPath $desktopIniPath -Force -ErrorAction Stop
	$item.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System -bor [System.IO.FileAttributes]::Archive
	$item.Refresh()
}
<#
    .SYNOPSIS
    Return a localized or fallback user-folder message.

    .DESCRIPTION
    Uses Get-UxLocalizedString when available and falls back to the supplied text and format arguments when localization helpers are unavailable.

    .PARAMETER Key
    Localization key to request.

    .PARAMETER Fallback
    Fallback text to use when no localized value is available.

    .PARAMETER FormatArgs
    Optional format arguments applied to the fallback text.

    .EXAMPLE
    Get-BaselineUserFolderMessage -Key 'FilesWontBeMoved' -Fallback 'Files will not be moved.'
#>
function Get-BaselineUserFolderMessage
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[Parameter(Mandatory = $true)]
		[string]$Fallback,

		[object[]]$FormatArgs
	)

	if (Get-Command -Name 'Get-UxLocalizedString' -CommandType Function -ErrorAction SilentlyContinue)
	{
		return (Get-UxLocalizedString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs)
	}

	if ($null -ne $FormatArgs -and 0 -lt $FormatArgs.Count)
	{
		return ($Fallback -f $FormatArgs)
	}

	return $Fallback
}
<#
    .SYNOPSIS
    Move existing contents into a new user-folder location.

    .DESCRIPTION
    Moves all items except desktop.ini from the current folder path into the destination path and returns the number of moved items.

    .PARAMETER SourcePath
    Current folder location.

    .PARAMETER DestinationPath
    New folder location.

    .PARAMETER Folder
    Supported user folder name being moved.

    .EXAMPLE
    Move-BaselineUserFolderContents -SourcePath 'C:\Users\User\Documents' -DestinationPath 'D:\Documents' -Folder 'Documents'
#>
function Move-BaselineUserFolderContents
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$SourcePath,

		[Parameter(Mandatory = $true)]
		[string]$DestinationPath,

		[Parameter(Mandatory = $true)]
		[string]$Folder
	)

	if (-not (Test-Path -LiteralPath $SourcePath))
	{
		return 0
	}

	if (-not (Test-Path -LiteralPath $DestinationPath))
	{
		New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
	}

	$sourceItems = @(Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop | Where-Object { -not ([string]$_.Name -ieq 'desktop.ini') })
	$movedCount = 0
	foreach ($sourceItem in $sourceItems)
	{
		Move-Item -LiteralPath $sourceItem.FullName -Destination $DestinationPath -Force -ErrorAction Stop | Out-Null
		$movedCount++
	}

	$remainingItems = @(Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop | Where-Object { -not ([string]$_.Name -ieq 'desktop.ini') })
	if ($remainingItems.Count -gt 0)
	{
		LogError (Get-BaselineUserFolderMessage -Key 'UserShellFolderNotEmpty' -Fallback 'Some files left in the "{0}" folder. Move them manually to a new location.' -FormatArgs @($SourcePath))
		throw "User folder '$Folder' still contains items after the move."
	}

	return $movedCount
}
<#
    .SYNOPSIS
    Update User Shell Folders registry values for a supported folder.

    .DESCRIPTION
    Writes both the friendly-name and GUID-based User Shell Folders values that Windows uses for a redirected known folder.

    .PARAMETER Folder
    Supported user folder name to redirect in the registry.

    .PARAMETER Path
    Destination path to write into User Shell Folders.

    .EXAMPLE
    Invoke-BaselineUserFolderRegistryRedirect -Folder 'Videos' -Path 'D:\Videos'
#>
function Invoke-BaselineUserFolderRegistryRedirect
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder,

		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	$definition = Get-BaselineUserFolderDefinition -Folder $Folder
	$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
	Set-RegistryValueSafe -Path $registryPath -Name $definition.RegistryName -Type ExpandString -Value $Path | Out-Null
	Set-RegistryValueSafe -Path $registryPath -Name $definition.GuidName -Type ExpandString -Value $Path | Out-Null
}
<#
    .SYNOPSIS
    Move or restore a supported user-folder location.

    .DESCRIPTION
    Validates the target path, updates registry and known-folder state, moves files when appropriate, and refreshes desktop.ini metadata for the selected folder.

    .PARAMETER Folder
    Supported user folder name to update.

    .PARAMETER Path
    Custom destination path to use.

    .PARAMETER Default
    Restore the selected folder to its default location.

    .EXAMPLE
    Set-BaselineUserFolderLocation -Folder 'Desktop' -Path 'D:\Desktop'
#>
function Set-BaselineUserFolderLocation
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder,

		[Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
		[string]$Path,

		[Parameter(ParameterSetName = 'Default', Mandatory = $true)]
		[switch]$Default
	)

	$definition = Get-BaselineUserFolderDefinition -Folder $Folder
	$currentPath = Get-BaselineUserFolderCurrentPath -Folder $Folder

	if ($Default)
	{
		LogWarning (Get-BaselineUserFolderMessage -Key 'FilesWontBeMoved' -Fallback 'Files will not be moved.')
		$targetPath = [string]$definition.DefaultPath
	}
	else
	{
		$targetPath = [string]$Path
	}

	if (-not (Test-BaselineUserFolderDestination -Path $targetPath))
	{
		if ([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($targetPath)) -ieq 'C:\')
		{
			LogError (Get-BaselineUserFolderMessage -Key 'UserFolderLocationMove' -Fallback 'You should not change a user folder location to the C drive root.')
		}
		else
		{
			LogError "The destination drive for '$Folder' is removable."
		}

		throw "Invalid destination path for '$Folder': $targetPath"
	}

	if ([System.IO.Path]::GetFullPath($currentPath) -ieq [System.IO.Path]::GetFullPath($targetPath))
	{
		$redirected = Invoke-BaselineUserFolderKnownFolderRedirect -Folder $Folder -Path $targetPath
		if (-not $redirected)
		{
			Invoke-BaselineUserFolderRegistryRedirect -Folder $Folder -Path $targetPath
		}

		Set-BaselineUserFolderDesktopIni -Folder $Folder -Path $targetPath
		return [pscustomobject]@{
			Folder     = $Folder
			Mode       = if ($Default) { 'Default' } else { 'Custom' }
			SourcePath = $currentPath
			TargetPath = $targetPath
			MovedCount = 0
			Updated    = $true
		}
	}

	$movedCount = 0
	if (-not $Default)
	{
		$movedCount = [int](Move-BaselineUserFolderContents -SourcePath $currentPath -DestinationPath $targetPath -Folder $Folder)
	}

	$oldDesktopIniPath = Join-Path $currentPath 'desktop.ini'
	Remove-Item -LiteralPath $oldDesktopIniPath -Force -ErrorAction SilentlyContinue | Out-Null

	$redirected = Invoke-BaselineUserFolderKnownFolderRedirect -Folder $Folder -Path $targetPath
	if (-not $redirected)
	{
		Invoke-BaselineUserFolderRegistryRedirect -Folder $Folder -Path $targetPath
	}

	Set-BaselineUserFolderDesktopIni -Folder $Folder -Path $targetPath

	return [pscustomobject]@{
		Folder     = $Folder
		Mode       = if ($Default) { 'Default' } else { 'Custom' }
		SourcePath = $currentPath
		TargetPath = $targetPath
		MovedCount = $movedCount
		Updated    = $true
	}
}
<#
    .SYNOPSIS
    Run the public user-folder redirect command.

    .DESCRIPTION
    Calls Set-BaselineUserFolderLocation with either a custom path or the default-location switch for one supported user folder.

    .PARAMETER Folder
    Supported user folder name to update.

    .PARAMETER Path
    Custom destination path to use.

    .PARAMETER Default
    Restore the selected folder to its default location.

    .EXAMPLE
    UserFolders -Folder 'Downloads' -Path 'D:\Downloads'
#>
function UserFolders
{
	[CmdletBinding(DefaultParameterSetName = 'Custom')]
	param (
		[Parameter(Mandatory = $true, ParameterSetName = 'Custom')]
		[Parameter(Mandatory = $true, ParameterSetName = 'Default')]
		[ValidateSet('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')]
		[string]$Folder,

		[Parameter(Mandatory = $true, ParameterSetName = 'Custom')]
		[string]$Path,

		[Parameter(Mandatory = $true, ParameterSetName = 'Default')]
		[switch]$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		'Custom'  { return (Set-BaselineUserFolderLocation -Folder $Folder -Path $Path) }
		'Default' { return (Set-BaselineUserFolderLocation -Folder $Folder -Default) }
	}
}

Export-ModuleMember -Function Get-BaselineUserFolderDefinitions, Get-BaselineUserFolderDefinition, Get-BaselineUserFolderCurrentPath, Test-BaselineUserFolderDestination, Invoke-BaselineUserFolderKnownFolderRedirect, Set-BaselineUserFolderLocation, UserFolders
