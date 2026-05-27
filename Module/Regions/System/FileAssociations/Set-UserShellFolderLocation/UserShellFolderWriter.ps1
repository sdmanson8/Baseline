function Set-UserShellFolder
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			[ValidateSet("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos")]
			[string]
			$UserFolder,

			[Parameter(Mandatory = $true)]
			[string]
			$FolderPath
		)

		<#
			.SYNOPSIS
			Redirect user folders to a new location



.DESCRIPTION

Applies the Baseline behavior for redirect user folders to a new location.
			.EXAMPLE
			Set-KnownFolderPath -KnownFolder Desktop -Path "$env:SystemDrive:\Desktop"
		#>
		function Set-KnownFolderPath
		{
			[CmdletBinding()]
			param
			(
				[Parameter(Mandatory = $true)]
				[ValidateSet("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos")]
				[string]
				$KnownFolder,

				[Parameter(Mandatory = $true)]
				[string]
				$Path
			)

			$KnownFolders = @{
				"Desktop"   = @("B4BFCC3A-DB2C-424C-B029-7FE99A87C641")
				"Documents" = @("FDD39AD0-238F-46AF-ADB4-6C85480369C7", "f42ee2d3-909f-4907-8871-4c22fc0bf756")
				"Downloads" = @("374DE290-123F-4565-9164-39C4925E467B", "7d83ee9b-2244-4e70-b1f5-5404642af1e4")
				"Music"     = @("4BD8D571-6D19-48D3-BE97-422220080E43", "a0c69a99-21c8-4671-8703-7934162fcf1d")
				"Pictures"  = @("33E28130-4E1E-4676-835A-98395C3BC3BB", "0ddd015d-b06c-45d5-8c4c-f59713854639")
				"Videos"    = @("18989B1D-99B5-455B-841C-AB7C74E4DDFC", "35286a68-3c57-41a1-bbb1-0eae73d76c95")
			}

			$Signature = @{
				Namespace          = "WinAPI"
				Name               = "KnownFolders"
				Language           = "CSharp"
				CompilerParameters = $CompilerParameters
				MemberDefinition   = @"
[DllImport("shell32.dll")]
public extern static int SHSetKnownFolderPath(ref Guid folderId, uint flags, IntPtr token, [MarshalAs(UnmanagedType.LPWStr)] string path);
"@
			}
			if (-not ("WinAPI.KnownFolders" -as [type]))
			{
				Add-Type @Signature
			}

			foreach ($GUID in $KnownFolders[$KnownFolder])
			{
				[WinAPI.KnownFolders]::SHSetKnownFolderPath([ref]$GUID, 0, 0, $Path)
			}
			(Get-Item -Path $Path -Force).Attributes = "ReadOnly"
		}

		$UserShellFoldersRegistryNames = @{
			"Desktop"   = "Desktop"
			"Documents" = "Personal"
			"Downloads" = "{374DE290-123F-4565-9164-39C4925E467B}"
			"Music"     = "My Music"
			"Pictures"  = "My Pictures"
			"Videos"    = "My Video"
		}

		$UserShellFoldersGUIDs = @{
			"Desktop"   = "{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}"
			"Documents" = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"
			"Downloads" = "{7D83EE9B-2244-4E70-B1F5-5404642AF1E4}"
			"Music"     = "{A0C69A99-21C8-4671-8703-7934162FCF1D}"
			"Pictures"  = "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
			"Videos"    = "{35286A68-3C57-41A1-BBB1-0EAE73D76C95}"
		}

		# Contents of the hidden desktop.ini file for each type of user folders
		$DesktopINI = @{
			"Desktop"   = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21769",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-183"
			"Documents" = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21770",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-112",
                          "IconFile=%SystemRoot%\System32\shell32.dll",
                          "IconIndex=-235"
			"Downloads" = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21798",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-184"
			"Music"     = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21790",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12689",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-108",
                          "IconFile=%SystemRoot%\System32\shell32.dll","IconIndex=-237"
			"Pictures"  = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21779",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12688",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-113",
                          "IconFile=%SystemRoot%\System32\shell32.dll",
                          "IconIndex=-236"
			"Videos"    = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21791",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12690",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-189",
                          "IconFile=%SystemRoot%\System32\shell32.dll","IconIndex=-238"
		}

		# Determining the current user folder path
		$CurrentUserFolderPath = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $UserShellFoldersRegistryNames[$UserFolder]
		if ($CurrentUserFolder -ne $FolderPath)
		{
			# Creating a new folder if there is no one
			if (-not (Test-Path -Path $FolderPath))
			{
				New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
			}

			# Removing old desktop.ini
			Remove-Item -Path "$CurrentUserFolderPath\desktop.ini" -Force -ErrorAction SilentlyContinue | Out-Null

			Set-KnownFolderPath -KnownFolder $UserFolder -Path $FolderPath | Out-Null
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $UserShellFoldersGUIDs[$UserFolder] -Type ExpandString -Value $FolderPath | Out-Null

			# Save desktop.ini in the UTF-16 LE encoding
			Set-Content -Path "$FolderPath\desktop.ini" -Value $DesktopINI[$UserFolder] -Encoding Unicode -Force | Out-Null
			(Get-Item -Path "$FolderPath\desktop.ini" -Force).Attributes = "Hidden", "System", "Archive"
			(Get-Item -Path "$FolderPath\desktop.ini" -Force).Refresh()

			if ((Get-ChildItem -Path $CurrentUserFolderPath -ErrorAction SilentlyContinue | Measure-Object).Count -ne 0)
			{
				LogError ($Localization.UserShellFolderNotEmpty -f $CurrentUserFolderPath)
			}
		}
	}
