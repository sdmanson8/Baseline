switch ($PSCmdlet.ParameterSetName)
		{
		"Install"
		{
            if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedPackagesProvided)
            {
                $selectionResult = Request-GuiUWPAppsSelection -Mode 'Install' -ForAllUsersSelection ([bool]$ForAllUsers) -SeedPackages @($SelectedPackages)
                $confirmedPackages = @(Get-UWPAppsConfirmedSelectionPackages -SelectionResult $selectionResult)
                if ($confirmedPackages.Count -le 0)
                {
                    Write-ConsoleStatus -Action "Installing UWP apps"
                    LogWarning "Skipping UWP app install because the package picker was closed without a confirmed selection."
                    Write-ConsoleStatus -Status warning
                    $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
                }

                $ForAllUsers = [bool]$selectionResult.ForAllUsers
                $SelectedPackages = @($confirmedPackages)
                $script:UWPAppsSelectionSeed = @($SelectedPackages)
                $SelectedPackagesProvided = $true
            }

            if ($NonInteractive -and -not $SelectedPackagesProvided)
            {
                Write-ConsoleStatus -Action "Installing UWP apps"
                LogWarning "Skipping UWP app install because no preselected packages were provided for noninteractive execution."
                Write-ConsoleStatus -Status warning
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }

            # Show the app picker and install the packages the user selects.
            Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop
            if (-not $CollectSelectionOnly)
            {
                Write-ConsoleStatus -Action "Installing UWP apps"
                LogInfo "Installing UWP apps:"
            }

            # Check for admin rights when "All Users" is selected
            if ($ForAllUsers)
            {
                $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                if (-not $IsAdmin)
                {
                    LogWarning "Skipping UWP app install for all users because administrator privileges are required."
                    if (-not $CollectSelectionOnly)
                    {
                        Write-ConsoleStatus -Status warning
                    }
                    if (-not $NonInteractive)
                    {
                        $wshell = New-Object -ComObject Wscript.Shell
                        $wshell.Popup("Installing for all users requires administrator privileges.`nPlease run PowerShell as Administrator.", 0, "Admin Required", 0)
                    }
                    $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
                }
            }

            # The following UWP apps will be excluded from the display
            $ExcludedAppxPackages = @(
                # Microsoft Edge
                "Microsoft.MicrosoftEdge.Stable",
                # Microsoft Visual C++ runtime framework
                "Microsoft.VCLibs.140.00",
                # AMD Radeon Software
                "AdvancedMicroDevicesInc-2.AMDRadeonSoftware",
                # Intel Graphics Control Center
                "AppUp.IntelGraphicsControlPanel",
                "AppUp.IntelGraphicsExperience",
                # ELAN Touchpad
                "ELANMicroelectronicsCorpo.ELANTouchpadforThinkpad",
                "ELANMicroelectronicsCorpo.ELANTrackPointforThinkpa",
                # Microsoft Application Compatibility Enhancements
                "Microsoft.ApplicationCompatibilityEnhancements",
                # AVC Encoder Video Extension
                "Microsoft.AVCEncoderVideoExtension",
                # Microsoft Desktop App Installer
                "Microsoft.DesktopAppInstaller",
                # Store Experience Host
                "Microsoft.StorePurchaseApp",
                # Windows Security
                "Microsoft.SecHealthUI",
                "Microsoft.Windows.SecHealthUI",
                "Microsoft.Windows.SecurityHealth",
                "Microsoft.WindowsSecurityHealth",
                # Cross Device Experience Host
                "MicrosoftWindows.CrossDevice",
                # Notepad
                "Microsoft.WindowsNotepad",
                # Microsoft Store
                "Microsoft.WindowsStore",
                # Windows Terminal
                "Microsoft.WindowsTerminal",
                "Microsoft.WindowsTerminalPreview",
                # Web Media Extensions
                "Microsoft.WebMediaExtensions",
                # AV1 Video Extension
                "Microsoft.AV1VideoExtension",
                # Windows Subsystem for Linux
                "MicrosoftCorporationII.WindowsSubsystemForLinux",
                # HEVC Video Extensions from Device Manufacturer
                "Microsoft.HEVCVideoExtension",
                "Microsoft.HEVCVideoExtensions",
                # Raw Image Extension
                "Microsoft.RawImageExtension",
                # HEIF Image Extensions
                "Microsoft.HEIFImageExtension",
                # MPEG-2 Video Extension
                "Microsoft.MPEG2VideoExtension",
                # VP9 Video Extensions
                "Microsoft.VP9VideoExtensions",
                # Webp Image Extensions
                "Microsoft.WebpImageExtension",
                # PowerShell
                "Microsoft.PowerShell",
                # NVIDIA Control Panel
                "NVIDIACorp.NVIDIAControlPanel",
                # Realtek Audio Console
                "RealtekSemiconductorCorp.RealtekAudioControl",
                # Synaptics
                "SynapticsIncorporated.SynapticsControlPanel",
                "SynapticsIncorporated.24916F58D6E7"
            )


            #region XAML Markup
            [xml]$XAML = @"
            <Window
                xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                Name="Window"
                MinHeight="400" MinWidth="415"
                SizeToContent="Width" WindowStartupLocation="CenterScreen"
                TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
                FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"
                Background="Transparent" AllowsTransparency="True" WindowStyle="None">
                <Window.Resources>
                        <Style TargetType="StackPanel">
                                <Setter Property="Orientation" Value="Horizontal"/>
                                <Setter Property="VerticalAlignment" Value="Top"/>
                        </Style>
                        <Style TargetType="CheckBox">
                                <Setter Property="Margin" Value="10, 13, 10, 10"/>
                                <Setter Property="IsChecked" Value="True"/>
                        </Style>
                        <Style TargetType="TextBlock">
                                <Setter Property="Margin" Value="0, 10, 10, 10"/>
                        </Style>
                        <Style TargetType="Button">
                                <Setter Property="Margin" Value="20"/>
                                <Setter Property="Padding" Value="10"/>
                                <Setter Property="IsEnabled" Value="False"/>
                        </Style>
                        <Style TargetType="Border">
                                <Setter Property="Grid.Row" Value="1"/>
                                <Setter Property="CornerRadius" Value="0"/>
                                <Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
                        </Style>
                        <Style TargetType="ScrollViewer">
                                <Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
                                <Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
                        </Style>
                </Window.Resources>
                <Border Name="RootBorder" CornerRadius="8" Padding="0">
                <Grid>
                        <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Name="PanelSelectAll" Grid.Column="0" HorizontalAlignment="Left">
                                        <CheckBox Name="CheckBoxSelectAll" IsChecked="False"/>
                                        <TextBlock Name="TextBlockSelectAll" Margin="10,10, 0, 10"/>
                                </StackPanel>
                                <StackPanel Name="PanelInstallForAll" Grid.Column="1" HorizontalAlignment="Right">
                                        <TextBlock Name="TextBlockInstallForAll" Margin="10,10, 0, 10"/>
                                        <CheckBox Name="CheckBoxForAllUsers" IsChecked="False"/>
                                </StackPanel>
                        </Grid>
                        <Border>
                                <ScrollViewer>
                                        <StackPanel Name="PanelContainer" Orientation="Vertical" Margin="5"/>
                                </ScrollViewer>
                        </Border>
                        <Button Name="ButtonInstall" Grid.Row="2" Content="" Margin="20" Padding="10" IsEnabled="False"/>
                </Grid>
                </Border>
            </Window>
"@
            #endregion XAML Markup

            $Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))

			if ($null -eq $Form)
            {
                # TODO: Consider replacing with Write-Log
                Write-Host "Failed to load XAML" -ForegroundColor Red
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }

            $XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
                Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
            }

			# Apply shared window chrome theming
			$bc = New-Object System.Windows.Media.BrushConverter
			$currentTheme = Get-UWPAppsPickerTheme
			$isDarkMode = Resolve-UWPAppsPickerUseDarkMode

			# Apply window chrome theme
				if (Test-Path -Path Function:\Set-GuiWindowChromeTheme)
				{
					[void](GUICommon\Set-GuiWindowChromeTheme -Window $Form -UseDarkMode:$isDarkMode)
				}

				$PanelContainer = $Form.FindName("PanelContainer")
				if ($null -eq $PanelContainer)
	            {
	                # TODO: Consider replacing with Write-Log
	                Write-Host "PanelContainer not found!" -ForegroundColor Red
	                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
	            }
				$RootBorder = $Form.FindName("RootBorder")
				& $setUWPAppsPickerSurface -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Theme $currentTheme -BrushConverter $bc -UseDarkMode $isDarkMode
	            $uwpAppsTitle               = GUICommon\Get-GuiPopupLocalizedString -Key 'Tweak_UWPApps' -Fallback 'UWP Apps (Bulk)'
	            $Form.Title                 = $uwpAppsTitle
				if (Test-Path -Path Function:\Add-GuiPopupWindowChrome)
				{
					[void](GUICommon\Add-GuiPopupWindowChrome -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Title $uwpAppsTitle -Theme $currentTheme -UseDarkMode $isDarkMode)
				}
	            $ButtonInstall.Content      = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceInstall' -Fallback 'Install'
	            $ButtonInstall.FontFamily   = [System.Windows.Media.FontFamily]::new('Segoe UI')
	            $ButtonInstall.FontSize     = 12
	            try { GUICommon\Set-GuiPopupActionButtonStyle -Button $ButtonInstall -Theme $currentTheme -UseDarkMode $isDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Install.SetPopupActionButtonStyle' }
	            $TextBlockInstallForAll.Text = GUICommon\Get-GuiPopupLocalizedString -Key 'UninstallUWPForAll' -Fallback 'For all users'
            $TextBlockSelectAll.Text     = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All'
			foreach ($headerText in @($TextBlockInstallForAll, $TextBlockSelectAll))
			{
				if ($headerText)
				{
					$headerText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
					if ($Form.Foreground) { $headerText.Foreground = $Form.Foreground }
				}
			}

			$uwpAppsInstallThemeCallback = {
				param($Window, $Theme, $UseDarkMode)

				try
				{
					& $setUWPAppsPickerSurface -Window $Window -RootBorder $RootBorder -PanelContainer $PanelContainer -Theme $Theme -BrushConverter $bc -UseDarkMode $UseDarkMode
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Install.ThemeCallback.SetSurface'
				}

				if ($ButtonInstall)
				{
					try { GUICommon\Set-GuiPopupActionButtonStyle -Button $ButtonInstall -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Install.ThemeCallback.SetPopupActionButtonStyle' }
				}

				foreach ($headerText in @($TextBlockInstallForAll, $TextBlockSelectAll))
				{
					if ($headerText)
					{
						if ($Window.Foreground) { $headerText.Foreground = $Window.Foreground }
					}
				}
			}.GetNewClosure()
			if (Test-Path -Path Function:\Register-GuiPopupThemeWindow)
			{
				[void](GUICommon\Register-GuiPopupThemeWindow -Window $Form -ThemeCallback $uwpAppsInstallThemeCallback)
			}
			& $uwpAppsInstallThemeCallback -Window $Form -Theme $currentTheme -UseDarkMode $isDarkMode

            $ButtonInstall.Add_Click({ButtonInstallClick})
            $CheckBoxForAllUsers.Add_Click({Invoke-UWPAppsInstallForAllUsersClick})
            $CheckBoxSelectAll.Add_Click({Invoke-UWPAppsInstallSelectAllClick})

            #region Functions
            function Get-MissingAppxPackages
            {
	            <#
	                .SYNOPSIS
	                Return the supported Appx packages that are currently missing.

	                .DESCRIPTION
	                Builds the Baseline package list for the current OS and returns the packages that are not installed for the current user or all users.

	                .PARAMETER AllUsers
	                Check package presence across all users when running with administrative rights.

	                .EXAMPLE
	                Get-MissingAppxPackages -AllUsers
	            #>
	[CmdletBinding()]
	param
	(
		[switch]
		$AllUsers
	)

	# Check if running as admin for AllUsers queries
	$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

			$CommonPackages = @(
				@{ Name = "Microsoft.OutlookForWindows"; DisplayName = "Microsoft Outlook" }
				@{ Name = "Microsoft.WindowsCalculator"; DisplayName = "Calculator" }
				@{ Name = "Microsoft.WindowsCamera"; DisplayName = "Camera" }
				@{ Name = "Microsoft.Windows.Photos"; DisplayName = "Photos" }
				@{ Name = "Microsoft.GamingServices"; DisplayName = "Gaming Services" }
				@{ Name = "Microsoft.YourPhone"; DisplayName = "Phone Link" }
				@{ Name = "DolbyLaboratories.DolbyAccess"; DisplayName = "Dolby Access" }
			)

			# Add Voice Recorder only for Windows 10
			$os = Get-OSInfo
			if (-not $os.IsWindows11) {
				$CommonPackages += @{ Name = "Microsoft.WindowsSoundRecorder"; DisplayName = "Voice Recorder" }
			}

	$MissingPackages = @()
	$InstalledCount = 0
	$ExcludedCount = 0

	foreach ($Package in $CommonPackages)
	{
		if ($Package.Name -in $ExcludedAppxPackages)
		{
			$ExcludedCount++
			continue
		}

		# Check if package is installed
		$Installed = $null

		if ($AllUsers)
		{
			if ($IsAdmin)
			{
				# Admin: Check all users
				$Installed = Get-AppxPackage -Name $Package.Name -AllUsers -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
			}
			else
			{
				# Non-admin: Can only check current user
				$Installed = Get-AppxPackage -Name $Package.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
				if (-not $script:AllUsersWarningShown)
				{
					LogWarning "Running without admin rights - 'All Users' mode will only check current user"
					$script:AllUsersWarningShown = $true
				}
			}
		}
		else
		{
			# Current user only
			$Installed = Get-AppxPackage -Name $Package.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		}

		if ($null -eq $Installed)
		{
			$MissingPackages += [PSCustomObject]@{
				Name = $Package.Name
				PackageFullName = $Package.Name
				DisplayName = $Package.DisplayName
			}
		}
		else
		{
			$InstalledCount++
			#LogInfo "Already installed: $($Package.DisplayName)"
		}
	}

	#LogInfo "Package scan complete: $($MissingPackages.Count) missing, $InstalledCount installed, $ExcludedCount excluded"
	return $MissingPackages | Sort-Object -Property DisplayName
            }

            <#
                .SYNOPSIS
                Runs check box for all users click.

                            #>

            function Invoke-UWPAppsInstallForAllUsersClick
            {
                $PanelContainer.Children.Clear()
                $PackagesToInstall.Clear()
                $MissingPackages = @(Get-MissingAppxPackages -AllUsers:$CheckBoxForAllUsers.IsChecked | Where-Object { $null -ne $_ })
                if ($MissingPackages.Count -gt 0)
                {
                    Add-UWPAppsInstallPickerControl -Packages $MissingPackages -Panel $PanelContainer
                }
                ButtonInstallSetIsEnabled
            }

            <#
                .SYNOPSIS
                Runs button install click.

                            #>
            function ButtonInstallClick
            {
	if ($CollectSelectionOnly)
                {
                    $script:UWPAppsSelectionResult = [PSCustomObject]@{
                        Mode = 'Install'
                        ForAllUsers = [bool]$CheckBoxForAllUsers.IsChecked
                        SelectedPackages = @($PackagesToInstall)
                    }
                    $Window.Close()
                    return
                }

                if (-not $SelectedPackagesProvided)
                {
                    foreach ($popupControl in @($ButtonInstall, $CheckBoxSelectAll, $CheckBoxForAllUsers, $PanelContainer))
                    {
                        if ($null -ne $popupControl)
                        {
                            $popupControl.IsEnabled = $false
                        }
                    }

                    $commandParameters = @{
                        Install = $true
                        ForAllUsers = [bool]$CheckBoxForAllUsers.IsChecked
                        SelectedPackages = @($PackagesToInstall)
                    }

                    if ($modulePath -and (Get-Command -Name 'Start-GuiPopupCommandAsync' -ErrorAction SilentlyContinue))
                    {
                        [void](GUICommon\Start-GuiPopupCommandAsync -Window $Form -ModulePath $modulePath -AdditionalModulePaths @($guiCommonPath) -CommandName 'UWPApps' -CommandParameters $commandParameters)
                        return
                    }
                }

	$Window.Close()

	$SuccessfulPackages = [System.Collections.Generic.List[string]]::new()
	$ManualPackages = [System.Collections.Generic.List[string]]::new()
                $scope = if ($CheckBoxForAllUsers.IsChecked) { "all users" } else { "current user" }

	# Store URLs for apps that need Store installation
	$StoreUrls = @{
		"Microsoft.WindowsCalculator" = "ms-windows-store://pdp/?productid=9WZDNCRFHVN5"
		"Microsoft.WindowsCamera" = "ms-windows-store://pdp/?productid=9WZDNCRFJBBG"
		"Microsoft.Windows.Photos" = "ms-windows-store://pdp/?productid=9WZDNCRFJBH4"
		"DolbyLaboratories.DolbyAccess" = "ms-windows-store://pdp/?productid=9N0866FS04W8"
		"Microsoft.GamingServices" = "ms-windows-store://pdp/?productid=9MWPM2CQNLHN"
		"Microsoft.OutlookForWindows" = "ms-windows-store://pdp/?productid=9NRX63209R7B"
		"MSTeams" = "ms-windows-store://pdp/?productid=XP8BT8DW290MPM"
		"Microsoft.YourPhone" = "ms-windows-store://pdp/?productid=9NMPJ99VJBWV"
	}

	# Winget package mappings
	$WingetMap = @{
		"Microsoft.WindowsCalculator" = "Microsoft.WindowsCalculator"
		"Microsoft.WindowsCamera" = "Microsoft.WindowsCamera"
		"Microsoft.Windows.Photos" = "Microsoft.Windows.Photos"
		"Microsoft.OutlookForWindows" = "Microsoft.OutlookForWindows"
		"MSTeams" = "Microsoft.Teams"
		"Microsoft.GamingServices" = "Microsoft.GamingServices"
		"Microsoft.YourPhone" = "Microsoft.YourPhone"
		"DolbyLaboratories.DolbyAccess" = "DolbyLaboratories.DolbyAccess"
	}

	foreach ($PackageName in $PackagesToInstall)
	{
		try {
			# METHOD 1: Check if package files exist and register them
			$WindowsAppsPath = "$env:ProgramFiles\WindowsApps"
			$PackageFolders = Get-ChildItem -Path $WindowsAppsPath -Directory -ErrorAction SilentlyContinue |
				Where-Object {$_.Name -like "*$PackageName*"} |
				Sort-Object LastWriteTime -Descending

			$Installed = $false
			foreach ($Folder in $PackageFolders)
			{
				$ManifestPath = Join-Path $Folder.FullName "AppXManifest.xml"
				if (Test-Path $ManifestPath)
				{
					#LogInfo "Found existing package files for $PackageName. Registering..."
					try {
						Add-AppxPackage -DisableDevelopmentMode -Register $ManifestPath -ErrorAction Stop
						Start-Sleep -Seconds 2

						$VerifyInstall = Get-AppxPackage -Name $PackageName -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
						if ($VerifyInstall)
						{
							$SuccessfulPackages.Add($PackageName)
							#LogInfo "Successfully registered $PackageName for $scope"
							$Installed = $true
							break
						}
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UwpAppsParameterSetExecution.ButtonInstallClick:catch504' -Severity Debug }

						if ($_.Exception.Message -like "*0x80073D02*")
						{
							#LogInfo "$PackageName registration failed - system components in use"
							$ManualPackages.Add($PackageName)
							$Installed = $true
							break
						}
					}
	}
			}

			if ($Installed) { continue }

			# METHOD 2: Try provisioned packages
			#LogInfo "Checking provisioned packages for $PackageName..."
			$Provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
				Where-Object {$_.DisplayName -eq $PackageName -or $_.PackageName -like "*$PackageName*"}

			if ($Provisioned)
			{
				try {
					Add-AppxProvisionedPackage -Online -PackageName $Provisioned.PackageName -SkipLicense -ErrorAction Stop | Out-Null
					Start-Sleep -Seconds 3

					$VerifyInstall = Get-AppxPackage -Name $PackageName -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
					if ($VerifyInstall)
					    {
						$SuccessfulPackages.Add($PackageName)
						#LogInfo "Successfully installed $PackageName for $scope"
						continue
					    }
                            }
				catch {
					LogWarning "Provisioned package installation did not complete for $PackageName. Trying other recovery methods."
				}
			}

			# METHOD 3: Try winget
			#LogInfo "Trying winget for $PackageName..."
			$WingetPath = Get-Command winget -ErrorAction SilentlyContinue
			if ($WingetPath)
			{
				$WingetID = $WingetMap[$PackageName]
				if ($WingetID)
				{
					if ($CheckBoxForAllUsers.IsChecked)
					{
								$WingetProcess = Invoke-BaselineProcess -FilePath 'winget' -ArgumentList @(
									'install',
									'--exact',
									'--id',
									$WingetID,
									'--scope',
									'machine',
									'--silent',
									'--accept-package-agreements',
									'--accept-source-agreements'
								) -TimeoutSeconds 1800
					}
					else
					{
								$WingetProcess = Invoke-BaselineProcess -FilePath 'winget' -ArgumentList @(
									'install',
									'--exact',
									'--id',
									$WingetID,
									'--scope',
									'user',
									'--silent',
									'--accept-package-agreements',
									'--accept-source-agreements'
								) -TimeoutSeconds 1800
					}

								if ($WingetProcess.ExitCode -ne 0)
								{
									LogWarning "winget failed to install $PackageName with exit code $($WingetProcess.ExitCode). Trying other recovery methods."
								}

					Start-Sleep -Seconds 5
					$AfterWinget = Get-AppxPackage -Name $PackageName -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

					if ($AfterWinget)
					{
						$SuccessfulPackages.Add($PackageName)
						#LogInfo "Successfully installed $PackageName for $scope"
						continue
					}
                        }
			}

			# METHOD 4: Try Microsoft Store as last resort
			$StoreUrl = $StoreUrls[$PackageName]
			if ($StoreUrl)
			{
                            if ($NonInteractive)
                            {
                                LogWarning "$PackageName requires Microsoft Store or manual follow-up in noninteractive mode."
                                $ManualPackages.Add($PackageName)
                                continue
                            }

				#LogInfo "Opening Microsoft Store for $PackageName. Please install manually..."
				Start-Process $StoreUrl

				# Show themed dialog that blocks until user clicks OK
				$messageText = "Microsoft Store has been opened for $PackageName.`n`nPlease install the app manually, then click OK to continue with the next app."
                            $manualInstallTheme = Get-UWPAppsPickerTheme
                            $isDarkMode = Resolve-UWPAppsPickerUseDarkMode
				$dialogParams = @{
                                Theme = $manualInstallTheme
                                ApplyButtonChrome = { param($Button, $Variant) }
					Title = if ($Localization.PSObject.Properties['ManualInstallRequired']) { $Localization.ManualInstallRequired } else { 'Manual Installation Required' }
					Message = $messageText
					Buttons = @('OK')
                                UseDarkMode = $isDarkMode
                                AccentButton = 'OK'
				}

				# Pass theme if available
				if (Test-Path -Path Variable:\Script:CurrentTheme)
				{
					$dialogParams['Theme'] = $Script:CurrentTheme
				}
				if (Test-Path -Path Function:\Set-ButtonChrome)
				{
					$dialogParams['ApplyButtonChrome'] = ${function:Set-ButtonChrome}
				}

                            GUICommon\Show-GuiCommonThemedDialog @dialogParams

				Start-Sleep -Seconds 2
				$AfterStore = Get-AppxPackage -Name $PackageName -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
				if ($AfterStore)
				{
					$SuccessfulPackages.Add($PackageName)
					#LogInfo "Successfully installed $PackageName for $scope"
				}
				else
				{
					$ManualPackages.Add($PackageName)
					LogWarning "$PackageName requires manual installation from the Microsoft Store."
				}
			}
			else
			{
                        LogWarning "$PackageName could not be installed automatically and needs manual follow-up."
			$ManualPackages.Add($PackageName)
			}
		}
		catch {
			LogWarning "$PackageName - Installation needs manual follow-up: $($_.Exception.Message)"
			$ManualPackages.Add($PackageName)
		}
	}

            # Log results
            if ($SuccessfulPackages.Count -gt 0)
            {
                foreach ($Package in $SuccessfulPackages)
                {
                    LogInfo "Successfully installed $Package for $scope"
                }
            }

            if ($ManualPackages.Count -gt 0)
            {
                $manualPackageList = $ManualPackages -join ', '
                if ($SuccessfulPackages.Count -gt 0)
                {
                    $message = "Partial success: Installed $($SuccessfulPackages.Count) selected UWP app(s) for $scope, but $($ManualPackages.Count) still need Microsoft Store or manual follow-up: $manualPackageList."
                    LogWarning $message
                    Set-UWPAppsExecutionResult -Outcome Partial -Message $message
                    return
                }

                $message = "Failed to install selected UWP apps for $scope. Microsoft Store or manual follow-up is still needed for: $manualPackageList."
                LogError $message
                Set-UWPAppsExecutionResult -Outcome Failed -Message $message
                return
            }

            $message = "Installed $($SuccessfulPackages.Count) selected UWP app(s) for $scope."
            LogInfo $message
            Set-UWPAppsExecutionResult -Outcome Success -Message $message
        }

            <#
                .SYNOPSIS
                Adds control.

                            #>

            function Add-UWPAppsInstallPickerControl
            {
	param($Packages, $Panel)

            $selectionSeed = @($script:UWPAppsSelectionSeed)
            $useSelectionSeed = ($selectionSeed.Count -gt 0)

	foreach ($Package in $Packages)
	{
		$CheckBox = New-Object System.Windows.Controls.CheckBox
		$CheckBox.Tag = $Package.PackageFullName
		$CheckBox.IsChecked = $(if ($useSelectionSeed) { $Package.PackageFullName -in $selectionSeed } else { $true })
		$CheckBox.Margin = "5,5,5,5"
		$CheckBox.VerticalAlignment = "Center"

		$LabelPanel = New-Object System.Windows.Controls.StackPanel
		$LabelPanel.Orientation = "Horizontal"
		$LabelPanel.VerticalAlignment = "Center"

		$TextBlock = New-Object System.Windows.Controls.TextBlock
		$TextBlock.Text = $Package.DisplayName
				$TextBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
				if ($Form -and $Form.Foreground) { $TextBlock.Foreground = $Form.Foreground }
		$TextBlock.Margin = "5,5,5,5"
		$TextBlock.VerticalAlignment = "Center"
		[void]$LabelPanel.Children.Add($TextBlock)

		$tooltipText = if ([string]::IsNullOrWhiteSpace([string]$Package.PackageFullName)) { [string]$Package.DisplayName } else { [string]$Package.PackageFullName }
		$infoIcon = GUICommon\New-GuiPopupInfoIcon -TooltipText $tooltipText -Theme $currentTheme -UseDarkMode $isDarkMode
		$infoPanel = New-Object System.Windows.Controls.StackPanel
		$infoPanel.Orientation = "Horizontal"
		$infoPanel.VerticalAlignment = "Center"
		$infoPanel.HorizontalAlignment = "Right"
		$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
		$infoPanel.Children.Add($infoIcon) | Out-Null

		$StackPanel = New-Object System.Windows.Controls.DockPanel
		$StackPanel.LastChildFill = $true
		$StackPanel.Margin = "2,2,2,2"
		[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
		$StackPanel.Children.Add($CheckBox) | Out-Null
		[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
		$StackPanel.Children.Add($infoPanel) | Out-Null
		$StackPanel.Children.Add($LabelPanel) | Out-Null

		$Panel.Children.Add($StackPanel) | Out-Null
                if ($CheckBox.IsChecked)
                {
		    $PackagesToInstall.Add($Package.PackageFullName) | Out-Null
                }

		$CheckBox.Add_Click({Invoke-UWPAppsInstallPickerCheckBoxClick})
	}
        }

            <#
                .SYNOPSIS
                Runs check box click.

                            #>

            function Invoke-UWPAppsInstallPickerCheckBoxClick
            {
	$CheckBox = $_.Source
	if ($CheckBox.IsChecked)
	{
		$PackagesToInstall.Add($CheckBox.Tag) | Out-Null
	}
	else
	{
		$PackagesToInstall.Remove($CheckBox.Tag)
	}
	ButtonInstallSetIsEnabled
            }

            <#
                .SYNOPSIS
                Runs check box select all click.

                            #>

            function Invoke-UWPAppsInstallSelectAllClick
            {
	$CheckBox = $_.Source

	if ($CheckBox.IsChecked)
	{
		$PackagesToInstall.Clear()
		foreach ($Item in $PanelContainer.Children)
		{
			$ChildCheckBox = $Item.Children[0]
			$ChildCheckBox.IsChecked = $true
			$PackagesToInstall.Add($ChildCheckBox.Tag) | Out-Null
		}
	}
	else
	{
		$PackagesToInstall.Clear()
		foreach ($Item in $PanelContainer.Children)
		{
			$Item.Children[0].IsChecked = $false
		}
	}
	ButtonInstallSetIsEnabled
            }

            <#
                .SYNOPSIS
                Runs button install set is enabled.

                            #>

            function ButtonInstallSetIsEnabled
            {
	$ButtonInstall.IsEnabled = ($PackagesToInstall.Count -gt 0)
            }
            #endregion Functions

            # Check "For all users" checkbox if specified
            if ($ForAllUsers)
            {
	$CheckBoxForAllUsers.IsChecked = $true
            }

            $PackagesToInstall = [System.Collections.Generic.List[string]]::new()
            $MissingPackages = Get-MissingAppxPackages -AllUsers:$ForAllUsers

            if ($MissingPackages.Count -eq 0)
            {
	LogWarning "Skipping UWP app install because no apps were missing for the chosen scope."
                if (-not $CollectSelectionOnly)
                {
                    Write-ConsoleStatus -Status warning
                }
                if ($CollectSelectionOnly)
                {
                    $__baselineExtractedPartReturnValue = & { [PSCustomObject]@{
                        Mode = 'Install'
                        ForAllUsers = [bool]$ForAllUsers
                        SelectedPackages = @()
                    } }; $__baselineExtractedPartHasReturnValue = $true; $__baselineExtractedPartDidReturn = $true; return
                }
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }
            else
            {
	Add-UWPAppsInstallPickerControl -Packages $MissingPackages -Panel $PanelContainer

	if ($PackagesToInstall.Count -gt 0)
	{
		$ButtonInstall.IsEnabled = $true
	}

    if ($SelectedPackagesProvided -and -not $CollectSelectionOnly)
    {
        $Window = New-Object psobject
        $Window | Add-Member -MemberType ScriptMethod -Name Close -Value { return $null } -Force
        $CheckBoxForAllUsers = [pscustomobject]@{ IsChecked = [bool]$ForAllUsers }
        $PackagesToInstall.Clear()
        foreach ($selectedPackage in @($SelectedPackages))
        {
            if (-not [string]::IsNullOrWhiteSpace([string]$selectedPackage))
            {
                $PackagesToInstall.Add([string]$selectedPackage) | Out-Null
            }
        }
        if ($PackagesToInstall.Count -gt 0)
        {
            ButtonInstallClick
        }
    }
    elseif ($Global:GUIMode -and -not $CollectSelectionOnly)
    {
        # GUI-mode runs collect the package selection on the main UI thread when this tweak starts.
    }
    else
    {
	    try
	    {
		    Initialize-WpfWindowForeground -Window $Form
		    $Form.ShowDialog() | Out-Null
	    }
	    catch
	    {
		    LogError "Install UWP Apps dialog failed to open: $($_.Exception.Message)"
            if (-not $CollectSelectionOnly)
            {
		        Write-ConsoleStatus -Status failed
            }
		    $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
	    }
    }
    }
    if ($Form.PSObject.Properties['GuiPopupOperationError'] -and $Form.GuiPopupOperationError)
    {
        $operationError = $Form.GuiPopupOperationError
        Remove-HandledErrorRecord -ErrorRecord $operationError
        LogError "Failed to install UWP apps: $($operationError.Exception.Message)"
        Write-ConsoleStatus -Status failed
        throw $operationError
    }
    if ($Form.PSObject.Properties['GuiPopupOperationResult'] -and $Form.GuiPopupOperationResult)
    {
        $script:UWPAppsExecutionResult = $Form.GuiPopupOperationResult
    }
    if ($CollectSelectionOnly)
    {
        $__baselineExtractedPartReturnValue = & { $script:UWPAppsSelectionResult }; $__baselineExtractedPartHasReturnValue = $true; $__baselineExtractedPartDidReturn = $true; return
    }
    if ($null -eq $script:UWPAppsExecutionResult)
    {
        LogWarning "Skipping UWP app install because no packages were confirmed."
        Write-ConsoleStatus -Status warning
        $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
    }
    if ($script:UWPAppsExecutionResult.Outcome -eq 'Success')
    {
        Write-ConsoleStatus -Status success
        $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
    }
    Write-ConsoleStatus -Status failed
    throw $script:UWPAppsExecutionResult.Message
}
		"Uninstall"
		{
            if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedPackagesProvided)
            {
                $selectionResult = Request-GuiUWPAppsSelection -Mode 'Uninstall' -ForAllUsersSelection ([bool]$ForAllUsers) -SeedPackages @($SelectedPackages)
                $confirmedPackages = @(Get-UWPAppsConfirmedSelectionPackages -SelectionResult $selectionResult)
                if ($confirmedPackages.Count -le 0)
                {
                    Write-ConsoleStatus -Action "Uninstalling UWP apps"
                    LogWarning "Skipping UWP app uninstall because the package picker was closed without a confirmed selection."
                    Write-ConsoleStatus -Status warning
                    $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
                }

                $ForAllUsers = [bool]$selectionResult.ForAllUsers
                $SelectedPackages = @($confirmedPackages)
                $script:UWPAppsSelectionSeed = @($SelectedPackages)
                $SelectedPackagesProvided = $true
            }

            if ($NonInteractive -and -not $SelectedPackagesProvided)
            {
                Write-ConsoleStatus -Action "Uninstalling UWP apps"
                LogWarning "Skipping UWP app uninstall because no preselected packages were provided for noninteractive execution."
                Write-ConsoleStatus -Status warning
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }

			# Show the app picker and remove the packages the user selects.
			Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop
            if (-not $CollectSelectionOnly)
            {
			    Write-ConsoleStatus -Action "Uninstalling UWP apps"
			    LogInfo "Uninstalling UWP apps:"
            }
			#region Variables
			# The following UWP apps will have their checkboxes unchecked
			$UncheckedAppxPackages = @(
				# Dolby Access
				"DolbyLaboratories.DolbyAccess",

				# Windows Media Player
				"Microsoft.ZuneMusic",

				# Screen Sketch
				"Microsoft.ScreenSketch",

				# Photos (and Video Editor)
				"Microsoft.Windows.Photos",
				"Microsoft.Photos.MediaEngineDLC",

				# Calculator
				"Microsoft.WindowsCalculator",

				# Windows Camera
				"Microsoft.WindowsCamera",

				# Microsoft Teams
				"MSTeams",

				# Xbox Identity Provider
				"Microsoft.XboxIdentityProvider",

				# Xbox Console Companion
				"Microsoft.XboxApp",

				# Xbox
				"Microsoft.GamingApp",
				"Microsoft.GamingServices",

				# Paint
				"Microsoft.Paint",

				# Xbox TCUI
				"Microsoft.Xbox.TCUI",

				# Xbox Speech To Text Overlay
				"Microsoft.XboxSpeechToTextOverlay",

				# Game Bar
				"Microsoft.XboxGamingOverlay",

				# Game Bar Plugin
				"Microsoft.XboxGameOverlay"
			)

			# The following UWP apps will be excluded from the display
			$ExcludedAppxPackages = @(
				# AMD Radeon Software
				"AdvancedMicroDevicesInc-2.AMDRadeonSoftware",

				# Intel Graphics Control Center
				"AppUp.IntelGraphicsControlPanel",
				"AppUp.IntelGraphicsExperience",

				# ELAN Touchpad
				"ELANMicroelectronicsCorpo.ELANTouchpadforThinkpad",
				"ELANMicroelectronicsCorpo.ELANTrackPointforThinkpa",

				# Microsoft Application Compatibility Enhancements
				"Microsoft.ApplicationCompatibilityEnhancements",

				# AVC Encoder Video Extension
				"Microsoft.AVCEncoderVideoExtension",

				# Microsoft Desktop App Installer
				"Microsoft.DesktopAppInstaller",

				# Store Experience Host
				"Microsoft.StorePurchaseApp",
				# Windows Security
				"Microsoft.SecHealthUI",
				"Microsoft.Windows.SecHealthUI",
				"Microsoft.Windows.SecurityHealth",
				"Microsoft.WindowsSecurityHealth",

				# Cross Device Experience Host
				"MicrosoftWindows.CrossDevice",

				# Notepad
				"Microsoft.WindowsNotepad",

				# Microsoft Store
				"Microsoft.WindowsStore",

				# Windows Terminal
				"Microsoft.WindowsTerminal",
				"Microsoft.WindowsTerminalPreview",

				# Web Media Extensions
				"Microsoft.WebMediaExtensions",

				# AV1 Video Extension
				"Microsoft.AV1VideoExtension",

				# Windows Subsystem for Linux
				"MicrosoftCorporationII.WindowsSubsystemForLinux",

				# HEVC Video Extensions from Device Manufacturer
				"Microsoft.HEVCVideoExtension",
				"Microsoft.HEVCVideoExtensions",

				# Raw Image Extension
				"Microsoft.RawImageExtension",

				# HEIF Image Extensions
				"Microsoft.HEIFImageExtension",

				# MPEG-2 Video Extension
				"Microsoft.MPEG2VideoExtension",

				# VP9 Video Extensions
				"Microsoft.VP9VideoExtensions",

				# Webp Image Extensions
				"Microsoft.WebpImageExtension",

				# PowerShell
				"Microsoft.PowerShell",

				# NVIDIA Control Panel
				"NVIDIACorp.NVIDIAControlPanel",

				# Realtek Audio Console
				"RealtekSemiconductorCorp.RealtekAudioControl",

				# Synaptics
				"SynapticsIncorporated.SynapticsControlPanel",
				"SynapticsIncorporated.24916F58D6E7"
			)

			#region XAML Markup
			# This block defines the dialog XAML used at runtime.
			[xml]$XAML = @"
			<Window
				xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
				xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
				Name="Window"
				MinHeight="400" MinWidth="415" MaxHeight="700"
				SizeToContent="Width" WindowStartupLocation="CenterScreen"
				TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
				FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"
				Background="Transparent" AllowsTransparency="True" WindowStyle="None">
				<Window.Resources>
					<Style TargetType="CheckBox">
						<Setter Property="IsChecked" Value="True"/>
					</Style>
					<Style TargetType="Button">
						<Setter Property="Margin" Value="20"/>
						<Setter Property="Padding" Value="10"/>
						<Setter Property="IsEnabled" Value="False"/>
					</Style>
					<Style TargetType="Border">
						<Setter Property="Grid.Row" Value="1"/>
						<Setter Property="CornerRadius" Value="0"/>
						<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
					</Style>
					<Style TargetType="ScrollViewer">
						<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
						<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
					</Style>
				</Window.Resources>
				<Border Name="RootBorder" CornerRadius="8" Padding="0">
				<Grid>
					<Grid.RowDefinitions>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="*"/>
						<RowDefinition Height="Auto"/>
					</Grid.RowDefinitions>
					<Grid Grid.Row="0" Margin="10,8,10,8">
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="*"/>
							<ColumnDefinition Width="Auto"/>
						</Grid.ColumnDefinitions>
						<StackPanel Name="PanelSelectAll" Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
							<CheckBox Name="CheckBoxSelectAll" IsChecked="False" VerticalAlignment="Center" Margin="0,0,6,0"/>
							<TextBlock Name="TextBlockSelectAll" VerticalAlignment="Center"/>
						</StackPanel>
						<StackPanel Name="PanelRemoveForAll" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
							<TextBlock Name="TextBlockRemoveForAll" VerticalAlignment="Center" Margin="0,0,6,0"/>
							<CheckBox Name="CheckBoxForAllUsers" IsChecked="False" VerticalAlignment="Center"/>
						</StackPanel>
					</Grid>
					<Border>
						<ScrollViewer>
							<StackPanel Name="PanelContainer" Orientation="Vertical" Margin="10,6,10,6"/>
						</ScrollViewer>
					</Border>
					<Button Name="ButtonUninstall" Grid.Row="2"/>
				</Grid>
				</Border>
			</Window>
"@
			#endregion XAML Markup

			$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
			$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
				Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
			}

			# Apply shared window chrome theming
			$bc = New-Object System.Windows.Media.BrushConverter
			$currentTheme = Get-UWPAppsPickerTheme
			$isDarkMode = Resolve-UWPAppsPickerUseDarkMode

			# Apply window chrome theme
				if (Test-Path -Path Function:\Set-GuiWindowChromeTheme)
				{
					[void](GUICommon\Set-GuiWindowChromeTheme -Window $Form -UseDarkMode:$isDarkMode)
				}

				$RootBorder = $Form.FindName("RootBorder")
				& $setUWPAppsPickerSurface -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Theme $currentTheme -BrushConverter $bc -UseDarkMode $isDarkMode

				$uwpAppsTitle               = GUICommon\Get-GuiPopupLocalizedString -Key 'Tweak_UWPApps' -Fallback 'UWP Apps (Bulk)'
				$Form.Title                 = $uwpAppsTitle
				if (Test-Path -Path Function:\Add-GuiPopupWindowChrome)
				{
					[void](GUICommon\Add-GuiPopupWindowChrome -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Title $uwpAppsTitle -Theme $currentTheme -UseDarkMode $isDarkMode)
				}
				$ButtonUninstall.Content    = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceUninstall' -Fallback 'Uninstall'
				$ButtonUninstall.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
				$ButtonUninstall.FontSize   = 12
				try { GUICommon\Set-GuiPopupActionButtonStyle -Button $ButtonUninstall -Theme $currentTheme -UseDarkMode $isDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Uninstall.SetPopupActionButtonStyle' }
			$TextBlockRemoveForAll.Text = GUICommon\Get-GuiPopupLocalizedString -Key 'UninstallUWPForAll' -Fallback 'For all users'
			$TextBlockSelectAll.Text    = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All'
			foreach ($headerText in @($TextBlockRemoveForAll, $TextBlockSelectAll))
			{
				if ($headerText)
				{
					$headerText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
					if ($Form.Foreground) { $headerText.Foreground = $Form.Foreground }
				}
			}

			$uwpAppsUninstallThemeCallback = {
				param($Window, $Theme, $UseDarkMode)

				try
				{
					& $setUWPAppsPickerSurface -Window $Window -RootBorder $RootBorder -PanelContainer $PanelContainer -Theme $Theme -BrushConverter $bc -UseDarkMode $UseDarkMode
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Uninstall.ThemeCallback.SetSurface'
				}

				if ($ButtonUninstall)
				{
					try { GUICommon\Set-GuiPopupActionButtonStyle -Button $ButtonUninstall -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Uninstall.ThemeCallback.SetPopupActionButtonStyle' }
				}

				foreach ($headerText in @($TextBlockRemoveForAll, $TextBlockSelectAll))
				{
					if ($headerText)
					{
						if ($Window.Foreground) { $headerText.Foreground = $Window.Foreground }
					}
				}
			}.GetNewClosure()
			if (Test-Path -Path Function:\Register-GuiPopupThemeWindow)
			{
				[void](GUICommon\Register-GuiPopupThemeWindow -Window $Form -ThemeCallback $uwpAppsUninstallThemeCallback)
			}
			& $uwpAppsUninstallThemeCallback -Window $Form -Theme $currentTheme -UseDarkMode $isDarkMode

			$ButtonUninstall.Add_Click({ButtonUninstallClick})
			$CheckBoxForAllUsers.Add_Click({Invoke-UWPAppsUninstallForAllUsersClick})
			$CheckBoxSelectAll.Add_Click({Invoke-UWPAppsUninstallSelectAllClick})
			#endregion Variables

			#region Functions
			function Get-AppxBundle
			{
							<#
							    .SYNOPSIS
							    Return installed Appx bundle packages for the current scope.

							    .DESCRIPTION
							    Collects installed bundle packages, adds the manual package checks Baseline needs, and filters out excluded names.

							    .PARAMETER Exclude
							    Package names to exclude from the returned list.

							    .PARAMETER AllUsers
							    Query packages across all users.

							    .EXAMPLE
							    Get-AppxBundle -AllUsers -Exclude 'Microsoft.XboxApp'
							#>
				[CmdletBinding()]
				param
				(
					[string[]]
					$Exclude,

					[switch]
					$AllUsers
				)

				$AppxPackages = @(Get-AppxPackage -PackageTypeFilter Bundle -AllUsers:$AllUsers -WarningAction SilentlyContinue | Where-Object -FilterScript { ($_.Name -notin $ExcludedAppxPackages) -and (-not (Test-UWPAppsProtectedPackage -PackageName $_.Name)) })

				# The -PackageTypeFilter Bundle doesn't contain these packages, and we need to add manually
				$Packages = @(
					# Outlook
					"Microsoft.OutlookForWindows",

					# Microsoft Teams
					"MSTeams"
				)
				foreach ($Package in $Packages)
				{
					if ((-not (Test-UWPAppsProtectedPackage -PackageName $Package)) -and (Get-AppxPackage -Name $Package -AllUsers:$AllUsers -WarningAction SilentlyContinue))
					{
						$AppxPackages += Get-AppxPackage -Name $Package -AllUsers:$AllUsers -WarningAction SilentlyContinue
					}
				}

				$PackagesIds = [Windows.Management.Deployment.PackageManager, Windows.Web, ContentType = WindowsRuntime]::new().FindPackages() | Select-Object -Property DisplayName -ExpandProperty Id | Select-Object -Property Name, DisplayName
				foreach ($AppxPackage in $AppxPackages)
				{
					$PackageId = $PackagesIds | Where-Object -FilterScript {$_.Name -eq $AppxPackage.Name}
					if (-not $PackageId)
					{
						continue
					}

					[PSCustomObject]@{
						Name            = $AppxPackage.Name
						PackageFullName = $AppxPackage.PackageFullName
						# Sometimes there's more than one package presented in Windows with the same package name like {Microsoft Teams, Microsoft Teams} and we need to display the first one
						DisplayName     = $PackageId.DisplayName | Select-Object -First 1
					}
				}
			}

			# Package names that can be reinstalled via the Install UWP Apps dialog.
			# Apps NOT in this list get a warning label in the Uninstall picker.
			$ReinstallablePackageNames = @(
				'Microsoft.OutlookForWindows'
				'Microsoft.WindowsCalculator'
				'Microsoft.WindowsCamera'
				'Microsoft.Windows.Photos'
				'Microsoft.GamingServices'
				'Microsoft.YourPhone'
				'DolbyLaboratories.DolbyAccess'
				'Microsoft.WindowsSoundRecorder'
			)

			<#
			    .SYNOPSIS
			    Creates UWP apps info icon.

						#>

			function New-UwpAppsInfoIcon
			{
				param (
					[string]$TooltipText
				)

				return GUICommon\New-GuiPopupInfoIcon -TooltipText $(if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'This item has extra information.' } else { $TooltipText }) -Theme $currentTheme -UseDarkMode $isDarkMode -Margin ([System.Windows.Thickness]::new(0, 0, 4, 0))
			}

			<#
			    .SYNOPSIS
			    Adds control.

						#>

			function Add-UWPAppsUninstallPickerControl
			{
				[CmdletBinding()]
				param
				(
					[Parameter(
						Mandatory = $true,
						ValueFromPipeline = $true
					)]
					[ValidateNotNull()]
					[PSCustomObject[]]
					$Packages
				)

				process
				{
                    $selectionSeed = @($script:UWPAppsSelectionSeed)
                    $useSelectionSeed = ($selectionSeed.Count -gt 0)
					foreach ($Package in $Packages)
					{
						$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
						$CheckBox.Tag = $Package.PackageFullName
						$CheckBox.VerticalAlignment = 'Center'
						$CheckBox.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)

						$LabelPanel = New-Object -TypeName System.Windows.Controls.StackPanel
						$LabelPanel.Orientation = 'Horizontal'
						$LabelPanel.VerticalAlignment = 'Center'
						$LabelPanel.HorizontalAlignment = 'Stretch'

						$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
						$TextBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
						if ($Form -and $Form.Foreground) { $TextBlock.Foreground = $Form.Foreground }
						$TextBlock.VerticalAlignment = 'Center'
						$TextBlock.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)

						if ($Package.DisplayName)
						{
							$TextBlock.Text = $Package.DisplayName
						}
						else
						{
							$TextBlock.Text = $Package.Name
						}

						[void]$LabelPanel.Children.Add($TextBlock)

						$rowPanel = New-Object -TypeName System.Windows.Controls.DockPanel
						$rowPanel.LastChildFill = $true
						$rowPanel.HorizontalAlignment = 'Stretch'
						$rowPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

						[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
						[void]$rowPanel.Children.Add($CheckBox)

						$infoTooltip = if ([string]::IsNullOrWhiteSpace([string]$Package.PackageFullName)) { [string]$Package.Name } else { [string]$Package.PackageFullName }
						$infoIcon = New-UwpAppsInfoIcon -TooltipText $infoTooltip

						# Warn if the app cannot be reinstalled via the Install dialog
						if ($Package.Name -notin $ReinstallablePackageNames)
						{
							$warningPanel = New-Object -TypeName System.Windows.Controls.StackPanel
							$warningPanel.Orientation = 'Horizontal'
							$warningPanel.VerticalAlignment = 'Center'
							$warningPanel.HorizontalAlignment = 'Right'
						$warningPanel.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

							$infoIcon.ToolTip = 'This app cannot be reinstalled from the Microsoft Store.'
							$warningPanel.Children.Add($infoIcon) | Out-Null

							$warnTb = New-Object -TypeName System.Windows.Controls.TextBlock
							$warnTb.Text = if ($Localization.PSObject.Properties['Warning']) { $Localization.Warning } else { 'Warning' }
							$warnTb.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
							$warnTb.Foreground = [System.Windows.Media.Brushes]::IndianRed
							$warnTb.FontSize = 12
							$warnTb.FontWeight = [System.Windows.FontWeights]::SemiBold
							$warnTb.VerticalAlignment = 'Center'
							$warnTb.ToolTip = if ($Localization.PSObject.Properties['UWPNoReinstallWarning']) { $Localization.UWPNoReinstallWarning } else { 'This app cannot be reinstalled from the Microsoft Store.' }
							$warningPanel.Children.Add($warnTb) | Out-Null

							[System.Windows.Controls.DockPanel]::SetDock($warningPanel, [System.Windows.Controls.Dock]::Right)
							[void]$rowPanel.Children.Add($warningPanel)
						}
						else
						{
							$infoPanel = New-Object -TypeName System.Windows.Controls.StackPanel
							$infoPanel.Orientation = 'Horizontal'
							$infoPanel.VerticalAlignment = 'Center'
							$infoPanel.HorizontalAlignment = 'Right'
							$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
							[void]$infoPanel.Children.Add($infoIcon)
							[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
							[void]$rowPanel.Children.Add($infoPanel)
						}

						[void]$rowPanel.Children.Add($LabelPanel)
						$PanelContainer.Children.Add($rowPanel) | Out-Null

						if ($useSelectionSeed)
                        {
                            $CheckBox.IsChecked = ($Package.PackageFullName -in $selectionSeed)
                            if ($CheckBox.IsChecked)
                            {
                                $PackagesToRemove.Add($Package.PackageFullName)
                            }
                        }
                        elseif ($UncheckedAppxPackages.Contains($Package.Name))
						{
							$CheckBox.IsChecked = $false
						}
						else
						{
							$CheckBox.IsChecked = $true
							$PackagesToRemove.Add($Package.PackageFullName)
						}

						$CheckBox.Add_Click({Invoke-UWPAppsUninstallPickerCheckBoxClick})
					}
				}
			}

			<#
			    .SYNOPSIS
			    Runs check box for all users click.

						#>

			function Invoke-UWPAppsUninstallForAllUsersClick
			{
				$PanelContainer.Children.RemoveRange(0, $PanelContainer.Children.Count)
				$PackagesToRemove.Clear()
				$AppXPackages = @(Get-AppxBundle -Exclude $ExcludedAppxPackages -AllUsers:$CheckBoxForAllUsers.IsChecked | Where-Object { $null -ne $_ })
				if ($AppXPackages.Count -gt 0)
				{
					Add-UWPAppsUninstallPickerControl -Packages $AppXPackages
				}

				ButtonUninstallSetIsEnabled
			}

			<#
			    .SYNOPSIS
			    Runs button uninstall click.

						#>
			function ButtonUninstallClick
			{
                if ($CollectSelectionOnly)
                {
                    $script:UWPAppsSelectionResult = [PSCustomObject]@{
                        Mode = 'Uninstall'
                        ForAllUsers = [bool]$CheckBoxForAllUsers.IsChecked
                        SelectedPackages = @($PackagesToRemove)
                    }
                    $Window.Close() | Out-Null
                    return
                }

                if (-not $SelectedPackagesProvided)
                {
                    foreach ($popupControl in @($ButtonUninstall, $CheckBoxSelectAll, $CheckBoxForAllUsers, $PanelContainer))
                    {
                        if ($null -ne $popupControl)
                        {
                            $popupControl.IsEnabled = $false
                        }
                    }

                    $commandParameters = @{
                        Uninstall = $true
                        ForAllUsers = [bool]$CheckBoxForAllUsers.IsChecked
                        SelectedPackages = @($PackagesToRemove)
                    }

                    if ($modulePath -and (Get-Command -Name 'Start-GuiPopupCommandAsync' -ErrorAction SilentlyContinue))
                    {
                        [void](GUICommon\Start-GuiPopupCommandAsync -Window $Form -ModulePath $modulePath -AdditionalModulePaths @($guiCommonPath) -CommandName 'UWPApps' -CommandParameters $commandParameters)
                        return
                    }
                }

				$Window.Close() | Out-Null
                $RemovedPackages = [System.Collections.Generic.List[string]]::new()
                $FailedPackages = [System.Collections.Generic.List[string]]::new()
                $AncillaryIssues = [System.Collections.Generic.List[string]]::new()
                $ProtectedPackagesSkipped = [System.Collections.Generic.List[string]]::new()
                $scope = if ($CheckBoxForAllUsers.IsChecked) { 'all users' } else { 'current user' }

				# If MSTeams is selected to uninstall, delete quietly "Microsoft Teams Meeting Add-in for Microsoft Office" too
				# & "$env:SystemRoot\System32\msiexec.exe" --% /x {A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91} /qn
				if ($PackagesToRemove -match "MSTeams")
				{
                    try
                    {
					    $MSIProcess = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x {A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91} /qn" -PassThru -WindowStyle Hidden -ErrorAction Stop
						$teamsRemovalFinished = $MSIProcess.WaitForExit(60000)
						if (-not $teamsRemovalFinished)
						{
							LogWarning "Teams Meeting Add-in removal timed out and needs manual follow-up."
                            $AncillaryIssues.Add('Teams Meeting Add-in')
							Stop-BaselineProcessTree -Process $MSIProcess -Source 'UWPApps.MsiTimeout'
						}
					    elseif ($MSIProcess.ExitCode -ne 0)
					    {
						    LogWarning "Teams Meeting Add-in removal returned exit code $($MSIProcess.ExitCode) and needs manual follow-up."
                            $AncillaryIssues.Add('Teams Meeting Add-in')
					    }
                    }
                    catch
                    {
                        LogWarning "Teams Meeting Add-in removal needs manual follow-up: $($_.Exception.Message)"
                        $AncillaryIssues.Add('Teams Meeting Add-in')
                    }
				}

                foreach ($Package in $PackagesToRemove)
				{
                    $PackageDisplayName = ([string]$Package).Split('_')[0]
                    if (Test-UWPAppsProtectedPackage -PackageName $Package)
                    {
                        $ProtectedPackagesSkipped.Add($PackageDisplayName)
                        LogWarning "Skipped protected Windows Security package: $PackageDisplayName"
                        continue
                    }

                    try
                    {
				        Invoke-SilencedProgress {
						    Remove-AppxPackage -Package $Package -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction Stop
				        }

                        Start-Sleep -Milliseconds 500
                        $RemainingPackage = Get-AppxPackage -AllUsers:$CheckBoxForAllUsers.IsChecked -ErrorAction SilentlyContinue -WarningAction SilentlyContinue |
                            Where-Object -FilterScript { $_.PackageFullName -eq $Package }
                        if ($RemainingPackage)
                        {
                            throw "Package still appears to be installed after the removal attempt."
                        }

                        $RemovedPackages.Add($PackageDisplayName)
                        LogInfo "Successfully removed $PackageDisplayName for $scope"
                    }
                    catch
                    {
                        $FailedPackages.Add($PackageDisplayName)
                        LogError "$PackageDisplayName - Removal failed: $($_.Exception.Message)"
                    }
				}

                if ($FailedPackages.Count -gt 0 -or $AncillaryIssues.Count -gt 0)
                {
                    $issueParts = @()
                    if ($FailedPackages.Count -gt 0)
                    {
                        $issueParts += "failed to remove: $($FailedPackages -join ', ')"
                    }
                    if ($AncillaryIssues.Count -gt 0)
                    {
                        $issueParts += "manual cleanup is still needed for: $($AncillaryIssues -join ', ')"
                    }

                    if ($RemovedPackages.Count -gt 0)
                    {
                        $message = "Partial success: Removed $($RemovedPackages.Count) selected UWP app(s) for $scope, but $($issueParts -join '; ')."
                        LogWarning $message
                        Set-UWPAppsExecutionResult -Outcome Partial -Message $message
                        return
                    }

                    $message = "Failed to remove selected UWP apps for $scope. $($issueParts -join '; ')."
                    LogError $message
                    Set-UWPAppsExecutionResult -Outcome Failed -Message $message
                    return
                }

                if ($ProtectedPackagesSkipped.Count -gt 0)
                {
                    $message = "Skipped protected Windows Security package(s): $($ProtectedPackagesSkipped -join ', ')."
                    if ($RemovedPackages.Count -gt 0)
                    {
                        $message = "Removed $($RemovedPackages.Count) selected UWP app(s) for $scope. $message"
                        LogWarning $message
                        Set-UWPAppsExecutionResult -Outcome Partial -Message $message
                        return
                    }

                    LogWarning $message
                    Set-UWPAppsExecutionResult -Outcome Success -Message $message
                    return
                }

                $message = "Removed $($RemovedPackages.Count) selected UWP app(s) for $scope."
                LogInfo $message
                Set-UWPAppsExecutionResult -Outcome Success -Message $message
			}

			<#
			    .SYNOPSIS
			    Runs check box click.

						#>

			function Invoke-UWPAppsUninstallPickerCheckBoxClick
			{
				$CheckBox = $_.Source

				if ($CheckBox.IsChecked)
				{
					$PackagesToRemove.Add($CheckBox.Tag) | Out-Null
				}
				else
				{
					$PackagesToRemove.Remove($CheckBox.Tag)
				}

				ButtonUninstallSetIsEnabled
			}

			<#
			    .SYNOPSIS
			    Runs check box select all click.

						#>

			function Invoke-UWPAppsUninstallSelectAllClick
			{
				$CheckBox = $_.Source

				if ($CheckBox.IsChecked)
				{
					$PackagesToRemove.Clear()

					foreach ($Item in $PanelContainer.Children)
					{
						foreach ($Child in $Item.Children)
						{
							if ($Child -is [System.Windows.Controls.CheckBox])
							{
								$Child.IsChecked = $true
								$PackagesToRemove.Add($Child.Tag)
							}
						}
					}
				}
				else
				{
					$PackagesToRemove.Clear()

					foreach ($Item in $PanelContainer.Children)
					{
						foreach ($Child in $Item.Children)
						{
							if ($Child -is [System.Windows.Controls.CheckBox])
							{
								$Child.IsChecked = $false
							}
						}
					}
				}

				ButtonUninstallSetIsEnabled
			}

			<#
			    .SYNOPSIS
			    Runs button uninstall set is enabled.

						#>

			function ButtonUninstallSetIsEnabled
			{
				if ($PackagesToRemove.Count -gt 0)
				{
					$ButtonUninstall.IsEnabled = $true
				}
				else
				{
					$ButtonUninstall.IsEnabled = $false
				}
			}
			#endregion Functions

			# Check "For all users" checkbox to uninstall packages from all accounts
			if ($ForAllUsers)
			{
				$CheckBoxForAllUsers.IsChecked = $true
			}

			$PackagesToRemove = [Collections.Generic.List[string]]::new()
			$AppXPackages = @(Get-AppxBundle -Exclude $ExcludedAppxPackages -AllUsers:$ForAllUsers | Where-Object { $null -ne $_ })
			if ($AppXPackages.Count -gt 0)
			{
				Add-UWPAppsUninstallPickerControl -Packages $AppXPackages
			}

			if ($AppXPackages.Count -eq 0)
			{
				LogWarning "Skipping UWP app uninstall because no apps were available for the chosen scope."
                if (-not $CollectSelectionOnly)
                {
                    Write-ConsoleStatus -Status warning
                }
                if ($CollectSelectionOnly)
                {
                    $__baselineExtractedPartReturnValue = & { [PSCustomObject]@{
                        Mode = 'Uninstall'
                        ForAllUsers = [bool]$ForAllUsers
                        SelectedPackages = @()
                    } }; $__baselineExtractedPartHasReturnValue = $true; $__baselineExtractedPartDidReturn = $true; return
                }
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}
			else
			{
				if ($PackagesToRemove.Count -gt 0)
				{
					$ButtonUninstall.IsEnabled = $true
				}

				# Normalize minimized dialogs before showing without reclaiming foreground focus.
                if ($SelectedPackagesProvided -and -not $CollectSelectionOnly)
                {
                    $Window = New-Object psobject
                    $Window | Add-Member -MemberType ScriptMethod -Name Close -Value { return $null } -Force
                    $CheckBoxForAllUsers = [pscustomobject]@{ IsChecked = [bool]$ForAllUsers }
                    $PackagesToRemove.Clear()
                    foreach ($selectedPackage in @($SelectedPackages))
                    {
                        if (-not [string]::IsNullOrWhiteSpace([string]$selectedPackage))
                        {
                            $PackagesToRemove.Add([string]$selectedPackage) | Out-Null
                        }
                    }
                    if ($PackagesToRemove.Count -gt 0)
                    {
                        ButtonUninstallClick
                    }
                }
                elseif ($Global:GUIMode -and -not $CollectSelectionOnly)
                {
                    # GUI-mode runs collect the package selection on the main UI thread when this tweak starts.
                }
                else
                {
				    try
				    {
					    Initialize-WpfWindowForeground -Window $Form
					    $Form.ShowDialog() | Out-Null
				    }
				    catch
				    {
					    LogError "Uninstall UWP Apps dialog failed to open: $($_.Exception.Message)"
                        if (-not $CollectSelectionOnly)
                        {
					        Write-ConsoleStatus -Status failed
                        }
					    $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
				    }
                }
			}
            if ($Form.PSObject.Properties['GuiPopupOperationError'] -and $Form.GuiPopupOperationError)
            {
                $operationError = $Form.GuiPopupOperationError
                Remove-HandledErrorRecord -ErrorRecord $operationError
                LogError "Failed to uninstall UWP apps: $($operationError.Exception.Message)"
                Write-ConsoleStatus -Status failed
                throw $operationError
            }
            if ($Form.PSObject.Properties['GuiPopupOperationResult'] -and $Form.GuiPopupOperationResult)
            {
                $script:UWPAppsExecutionResult = $Form.GuiPopupOperationResult
            }
            if ($CollectSelectionOnly)
            {
                $__baselineExtractedPartReturnValue = & { $script:UWPAppsSelectionResult }; $__baselineExtractedPartHasReturnValue = $true; $__baselineExtractedPartDidReturn = $true; return
            }
            if ($null -eq $script:UWPAppsExecutionResult)
            {
                LogWarning "Skipping UWP app uninstall because no packages were confirmed."
                Write-ConsoleStatus -Status warning
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }
            if ($script:UWPAppsExecutionResult.Outcome -eq 'Success')
            {
			    Write-ConsoleStatus -Status success
                $__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
            }
            Write-ConsoleStatus -Status failed
            throw $script:UWPAppsExecutionResult.Message
		}
	}
