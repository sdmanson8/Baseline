Set-StrictMode -Version Latest

Describe 'Windows Update runtime panel callback scopes' {
	BeforeAll {
		Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
		$script:UpdatesPanelPath = Join-Path $PSScriptRoot '../../Module/GUI/UpdatesPanel.ps1'
	}

	BeforeEach {
		$script:Diagnostics = [System.Collections.Generic.List[string]]::new()
		$script:Errors = [System.Collections.Generic.List[string]]::new()
		$script:WindowsUpdateAvailableUpdates = $null
		$script:WindowsUpdateSelectionControls = $null
		$script:WindowsUpdateSelectionState = $null
		$script:WindowsUpdateHistoryEntries = $null
		$script:WindowsUpdateOperationInProgress = $false
		$script:BtnWindowsUpdateScan = $null
		$script:BtnWindowsUpdateHistory = $null
		$script:BtnWindowsUpdateDownload = $null
		$script:BtnWindowsUpdateInstall = $null
		$script:GuiLayout = [pscustomobject]@{
			CardCornerRadius = 4
			FontSizeBody    = 12
			FontSizeSmall   = 10
			FontSizeLabel   = 13
		}

		function script:LogDebug {
			param (
				[string]$Message,
				[string]$Scope,
				[switch]$Always
			)

			[void]$script:Diagnostics.Add($Message)
		}

		function script:LogError {
			param (
				[object]$Message
			)

			[void]$script:Errors.Add([string]$Message)
		}

		function script:Write-SwallowedException {
			param (
				[object]$ErrorRecord,
				[string]$Source
			)
		}

		function script:Format-BaselineErrorForLog {
			param (
				[object]$ErrorObject,
				[string]$Prefix
			)

			return $Prefix
		}

		function script:Get-GuiCurrentTheme {
			return [pscustomobject]@{
				CardBg        = '#FFFFFFFF'
				CardBorder    = '#FFCCCCCC'
				TextPrimary   = '#FF111111'
				TextSecondary = '#FF555555'
				CautionText   = '#FFAA6600'
				DangerText    = '#FFAA0000'
				SuccessText   = '#FF008800'
			}
		}
	}

	It 'keeps update row checkbox callbacks usable after the local source scope exits' {
		function New-TestWindowsUpdateCheckBoxFromLocalScope {
			. $script:UpdatesPanelPath
			Initialize-GuiWindowsUpdateRuntimeState

			$update = [pscustomobject]@{
				Id             = 'update-id'
				RevisionNumber = 1
				Title          = 'Test Update'
				KBArticleIDs   = @()
				MsrcSeverity   = ''
				Type           = 'Software'
			}

			$row = New-GuiWindowsUpdateUpdateRow -Update $update
			return $row.Child
		}

		$checkBox = New-TestWindowsUpdateCheckBoxFromLocalScope
		$checkBox.IsChecked = $false
		$checkBox.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))

		$script:Errors.Count | Should -Be 0
		$script:WindowsUpdateSelectionState['update-id|1'] | Should -BeFalse
		@($script:Diagnostics | Where-Object { $_ -like 'Windows Update action state:*selected=0*' }).Count | Should -Be 1
	}

	It 'updates the operation busy flag through a captured module-scope setter' {
		function New-TestWindowsUpdateBusyCompletionCallbackFromLocalScope {
			. $script:UpdatesPanelPath
			Set-GuiWindowsUpdateOperationInProgress -InProgress $true

			$setBusy = ${function:Set-GuiWindowsUpdateOperationInProgress}
			return { & $setBusy -InProgress $false }.GetNewClosure()
		}

		$completionCallback = New-TestWindowsUpdateBusyCompletionCallbackFromLocalScope
		$script:WindowsUpdateOperationInProgress | Should -BeTrue

		& $completionCallback

		$script:WindowsUpdateOperationInProgress | Should -BeFalse
	}

	It 'removes installed selections from the available list and recommends restart from update state' {
		. $script:UpdatesPanelPath
		Initialize-GuiWindowsUpdateRuntimeState

		$script:TxtWindowsUpdateRuntimeStatus = New-Object System.Windows.Controls.TextBlock
		$script:WindowsUpdateAvailableListPanel = New-Object System.Windows.Controls.StackPanel
		$script:WindowsUpdateHistoryList = New-Object System.Windows.Controls.ListView

		$selectedUpdate = [pscustomobject]@{
			Id             = 'selected-id'
			RevisionNumber = 1
			Title          = 'Installed update'
			KBArticleIDs   = @()
			MsrcSeverity   = ''
			Classification = 'Security'
			Type           = 'Software'
		}
		$remainingUpdate = [pscustomobject]@{
			Id             = 'remaining-id'
			RevisionNumber = 1
			Title          = 'Remaining update'
			KBArticleIDs   = @()
			MsrcSeverity   = ''
			Classification = 'Optional'
			Type           = 'Software'
		}

		[void]$script:WindowsUpdateAvailableUpdates.Add($selectedUpdate)
		[void]$script:WindowsUpdateAvailableUpdates.Add($remainingUpdate)

		$payload = [pscustomobject]@{
			Action         = 'Install'
			DownloadResult = [pscustomobject]@{
				Succeeded   = $true
				Result      = 'Succeeded'
				UpdateCount = 1
			}
			InstallResult  = [pscustomobject]@{
				Succeeded      = $true
				Result         = 'Succeeded'
				UpdateCount    = 1
				RebootRequired = $false
			}
			Updates        = @($remainingUpdate)
			History        = @([pscustomobject]@{ Title = 'Installed update'; Result = 'Succeeded' })
			RebootRequired = $true
		}

		Complete-GuiWindowsUpdateOperation -Payload $payload

		$script:WindowsUpdateAvailableUpdates.Count | Should -Be 1
		$script:WindowsUpdateAvailableUpdates[0].Title | Should -Be 'Remaining update'
		$script:WindowsUpdateSelectionState.ContainsKey('selected-id|1') | Should -BeFalse
		$script:WindowsUpdateHistoryEntries.Count | Should -Be 1
		$script:TxtWindowsUpdateRuntimeStatus.Text | Should -Match 'Restart Windows to finish applying updates'
	}
}
