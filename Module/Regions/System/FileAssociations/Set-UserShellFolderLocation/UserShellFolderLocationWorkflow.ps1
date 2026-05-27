switch ($PSCmdlet.ParameterSetName)
	{
		"Root"
		{
			# Write-Host: intentional -- user-visible progress indicator
			Write-Host "Changing user folders location to the root of a drive"
			LogInfo "Changing user folders location to the root of a drive"
			# Store all fixed disks' letters except C (system drive) to use them within Show-Menu function
			# https://learn.microsoft.com/en-us/dotnet/api/system.io.drivetype
			$DriveLetters = @((Get-CimInstance -ClassName CIM_LogicalDisk | Where-Object -FilterScript {($_.DriveType -eq 3) -and ($_.Name -ne $env:SystemDrive)}).DeviceID | Sort-Object)

			if (-not $DriveLetters)
			{
				LogError $Localization.UserFolderLocationMove

				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}

			# Desktop
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Desktop -FolderPath "$($Choice)\Desktop" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Documents -FolderPath "$($Choice)\Documents" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Downloads -FolderPath "$($Choice)\Downloads" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Music -FolderPath "$($Choice)\Music" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Pictures -FolderPath "$($Choice)\Pictures" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Videos -FolderPath "$($Choice)\Videos" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
		"Custom"
		{
			# Write-Host: intentional -- user-visible progress indicator
			Write-Host "Changing user folders location to the custom one selected"
			LogInfo "Changing user folders location to the custom one selected"
			# Desktop
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Desktop -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Documents -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Downloads -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Music -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Pictures -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						$FolderBrowserDialog.ShowDialog()

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Videos -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
		"Default"
		{
			# Write-Host: intentional -- user-visible progress indicator
			Write-Host "Changing user folders location to the default one"
			LogInfo "Changing user folders location to the default one"
			# Desktop
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Desktop -FolderPath "$env:USERPROFILE\Desktop" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Documents -FolderPath "$env:USERPROFILE\Documents" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Downloads -FolderPath "$env:USERPROFILE\Downloads" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Music -FolderPath "$env:USERPROFILE\Music" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Pictures -FolderPath "$env:USERPROFILE\Pictures" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Videos -FolderPath "$env:USERPROFILE\Videos" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
	}
