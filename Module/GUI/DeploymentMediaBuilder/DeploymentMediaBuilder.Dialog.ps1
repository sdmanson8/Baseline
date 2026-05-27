# DeploymentMediaBuilder.Dialog.ps1
# Legacy modal dialog surface retained for existing command contracts.

function Resolve-GuiDeploymentMediaDialogSupportPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Dialog', 'Execution', 'ProcessHelper')]
		[string]$Name
	)

	$candidates = [System.Collections.Generic.List[string]]::new()
	foreach ($root in @($Script:GuiExtractedRoot, $PSScriptRoot, (Split-Path -Parent $PSScriptRoot)))
	{
		if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

		switch ($Name)
		{
			'Dialog'
			{
				[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilderDialog.ps1'))
				[void]$candidates.Add((Join-Path (Split-Path -Parent ([string]$root)) 'DeploymentMediaBuilderDialog.ps1'))
			}
			'Execution'
			{
				[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder\DeploymentMediaBuilder.Execution.ps1'))
				[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder.Execution.ps1'))
				[void]$candidates.Add((Join-Path (Split-Path -Parent ([string]$root)) 'DeploymentMediaBuilder\DeploymentMediaBuilder.Execution.ps1'))
			}
			'ProcessHelper'
			{
				[void]$candidates.Add((Join-Path ([string]$root) '..\SharedHelpers\Process.Helpers.ps1'))
				[void]$candidates.Add((Join-Path (Split-Path -Parent ([string]$root)) 'SharedHelpers\Process.Helpers.ps1'))
			}
		}
	}

	foreach ($candidate in @($candidates))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
		$fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
		if (Test-Path -LiteralPath $fullPath -PathType Leaf)
		{
			return $fullPath
		}
	}

	throw ('Required Deployment Media Builder dialog support file was not found: {0}' -f $Name)
}

function Show-GuiDeploymentMediaDialogOscdimgInstallPrompt
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ErrorRecord,
		[Parameter(Mandatory = $true)]
		[string]$Title
	)

	$pageUrl = Get-GuiDeploymentMediaOscdimgInstallPageUrl
	$message = @(
		'Baseline could not install Microsoft OSCDIMG automatically.',
		'',
		[string]$ErrorRecord.Exception.Message,
		'',
		'Open the Microsoft.OSCDIMG install page, install the package, then run Start ISO Build again.'
	) -join [Environment]::NewLine

	$choice = Show-ThemedDialog -Title $Title -Message $message -Buttons @('OK', 'Open Install Page') -AccentButton 'Open Install Page'
	if ([string]$choice -ne 'Open Install Page') { return }

	try
	{
		if (-not (Invoke-UserLaunch -FilePath $pageUrl -Description 'Microsoft OSCDIMG install page'))
		{
			[void](Show-ThemedDialog -Title $Title -Message ("Failed to open the Microsoft.OSCDIMG install page.`n`n{0}" -f $pageUrl) -Buttons @('OK') -AccentButton 'OK')
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.OscdimgInstallPageLaunch' -Severity Warning
		}
		[void](Show-ThemedDialog -Title $Title -Message ("Failed to open the Microsoft.OSCDIMG install page.`n`n{0}`n`n{1}" -f $pageUrl, $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Complete-GuiDeploymentMediaDialogBackgroundOperation
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$OperationState,
		[Parameter(Mandatory = $true)]
		[object]$Operation
	)

	if ([object]::ReferenceEquals($OperationState.Operation, $Operation))
	{
		$OperationState.Operation = $null
	}

	try { if ($Operation.PowerShell) { $Operation.PowerShell.Dispose() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.BackgroundOperation.DisposePowerShell' -Severity Warning }
	try { if ($Operation.Timer) { $Operation.Timer.Stop() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.BackgroundOperation.StopTimer' -Severity Warning }
	try { if ($Operation.Runspace) { $Operation.Runspace.Dispose() } }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.BackgroundOperation.DisposeRunspace' -Severity Warning }

	if ($Operation.FinallyCallback)
	{
		& $Operation.FinallyCallback
	}
}

function Stop-GuiDeploymentMediaDialogBackgroundOperation
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$OperationState,
		[string]$Reason = 'Deployment media operation cancelled by operator.',
		[scriptblock]$StatusCallback
	)

	$operation = $OperationState.Operation
	if (-not $operation) { return $false }

	if ($operation.CancelRequested)
	{
		if ($StatusCallback) { & $StatusCallback -Message 'Cancellation is already pending for the deployment media operation.' -Tone 'warning' }
		return $true
	}

	$operation.CancelRequested = $true
	$operation.CancelRequestedUtc = [DateTime]::UtcNow
	$operation.CancelEscalationUtc = $operation.CancelRequestedUtc.AddSeconds(30)
	if ($operation.Sync)
	{
		$operation.Sync.CancelRequested = $true
		$operation.Sync.CancelReason = $Reason
		$operation.Sync.RequestedUtc = $operation.CancelRequestedUtc
		$operation.Sync.Status = 'Cancelling deployment media operation...'
	}

	if ($StatusCallback) { & $StatusCallback -Message 'Cancelling deployment media operation...' -Tone 'warning' }
	return $true
}

function Start-GuiDeploymentMediaDialogBackgroundOperation
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$OperationState,
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[scriptblock]$Worker,
		[hashtable]$Context = @{},
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 7200,
		[scriptblock]$StatusCallback,
		[Parameter(Mandatory = $true)]
		[scriptblock]$CompletedCallback,
		[Parameter(Mandatory = $true)]
		[scriptblock]$FailedCallback,
		[scriptblock]$FinallyCallback
	)

	if ($OperationState.Operation)
	{
		if ($StatusCallback) { & $StatusCallback -Message 'A deployment media operation is already running.' -Tone 'warning' }
		return $false
	}

	$syncHash = [hashtable]::Synchronized(@{
		Status = ''
		Done = $false
		CancelRequested = $false
		CancelReason = ''
		RequestedUtc = $null
		CurrentStage = ''
		StageStartedUtc = $null
	})

	$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
	$initialSessionState.ImportPSModule(@('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility'))
	$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialSessionState)
	$runspace.ApartmentState = 'STA'
	$runspace.ThreadOptions = 'ReuseThread'
	$runspace.Open()

	$ps = [System.Management.Automation.PowerShell]::Create()
	$ps.Runspace = $runspace
	$operationScript = {
		param (
			[scriptblock]$WorkerBlock,
			[hashtable]$WorkerContext,
			[hashtable]$Sync
		)

		$ErrorActionPreference = 'Stop'
		try
		{
			& $WorkerBlock -Context $WorkerContext -Sync $Sync
		}
		finally
		{
			$Sync.Done = $true
		}
	}
	$null = $ps.AddScript($operationScript).AddArgument($Worker).AddArgument($Context).AddArgument($syncHash)
	$asyncResult = $ps.BeginInvoke()
	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(150)
	$operation = [pscustomobject]@{
		Name = $Name
		PowerShell = $ps
		Runspace = $runspace
		AsyncResult = $asyncResult
		Timer = $timer
		Sync = $syncHash
		DeadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
		TimeoutSeconds = $TimeoutSeconds
		TimedOut = $false
		TerminalReported = $false
		FinallyCallback = $FinallyCallback
		CancelRequested = $false
		CancelRequestedUtc = $null
		CancelEscalationUtc = $null
		CancellationForceRequested = $false
		LastStatus = ''
	}
	$OperationState.Operation = $operation

	$timer.Add_Tick({
		$status = [string]$syncHash.Status
		if ($StatusCallback -and -not [string]::IsNullOrWhiteSpace($status) -and $status -ne [string]$operation.LastStatus)
		{
			$operation.LastStatus = $status
			& $StatusCallback -Message $status -Tone 'muted'
		}

		if (-not $operation.TimedOut -and -not $asyncResult.IsCompleted -and [DateTime]::UtcNow -ge $operation.DeadlineUtc)
		{
			$operation.TimedOut = $true
			$operation.CancelRequested = $true
			$operation.CancelRequestedUtc = [DateTime]::UtcNow
			$operation.CancelEscalationUtc = $operation.CancelRequestedUtc.AddSeconds(30)
			$syncHash.CancelRequested = $true
			$syncHash.CancelReason = ('{0} timed out after {1} second(s).' -f $Name, $TimeoutSeconds)
			$syncHash.RequestedUtc = $operation.CancelRequestedUtc
			$syncHash.Status = ('Cancelling {0} after timeout.' -f $Name)
			$timeoutException = [System.TimeoutException]::new(('{0} timed out after {1} second(s).' -f $Name, $TimeoutSeconds))
			$timeoutRecord = New-Object System.Management.Automation.ErrorRecord $timeoutException, 'DeploymentMediaBuilderDialogOperationTimeout', ([System.Management.Automation.ErrorCategory]::OperationTimeout), $Name
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				& $FailedCallback -ErrorRecord $timeoutRecord
			}
			return
		}

		if ($operation.CancelRequested -and -not $operation.CancellationForceRequested -and -not $asyncResult.IsCompleted -and $operation.CancelEscalationUtc -and [DateTime]::UtcNow -ge $operation.CancelEscalationUtc)
		{
			$operation.CancellationForceRequested = $true
			try { $null = $ps.BeginStop($null, $null) }
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.BackgroundOperation.BeginStop' -Severity Warning }
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				$cancelException = [System.OperationCanceledException]::new(('{0} cancellation did not complete within the grace period.' -f $Name))
				$cancelRecord = New-Object System.Management.Automation.ErrorRecord $cancelException, 'DeploymentMediaBuilderDialogOperationCancelled', ([System.Management.Automation.ErrorCategory]::OperationStopped), $Name
				& $FailedCallback -ErrorRecord $cancelRecord
			}
			Complete-GuiDeploymentMediaDialogBackgroundOperation -OperationState $OperationState -Operation $operation
			return
		}

		if (-not $asyncResult.IsCompleted) { return }

		$timer.Stop()
		try
		{
			$result = @($ps.EndInvoke($asyncResult))
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				if ($result.Count -eq 0) { & $CompletedCallback -Result $null }
				elseif ($result.Count -eq 1) { & $CompletedCallback -Result $result[0] }
				else { & $CompletedCallback -Result $result }
			}
		}
		catch
		{
			LogDebug ('Deployment media dialog background operation EndInvoke raised. Name="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Name, $_.Exception.GetType().FullName, $_.Exception.Message)
			if (-not $operation.TerminalReported)
			{
				$operation.TerminalReported = $true
				& $FailedCallback -ErrorRecord $_
			}
		}
		finally
		{
			Complete-GuiDeploymentMediaDialogBackgroundOperation -OperationState $OperationState -Operation $operation
		}
	}.GetNewClosure())

	$timer.Start()
	return $true
}

function Show-GuiDeploymentMediaBuilderDialog
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return @{ Cancelled = $true; Previewed = $false; Started = $false; ReportPath = $null; OutputPath = $null; BuildRoot = $null }
	}

	$theme = $Script:CurrentTheme
	$titleText = Get-UxLocalizedString -Key 'GuiDeploymentMediaBuilderTitle' -Fallback 'Deployment Media Builder'
	$subtitleText = Get-UxLocalizedString -Key 'GuiDeploymentMediaBuilderSubtitle' -Fallback 'Create an auditable Windows 10/11 setup media plan before modifying any image.'
	$previewLabel = Get-UxLocalizedString -Key 'GuiDeploymentMediaBuilderPreview' -Fallback 'Preview Build Plan'
	$startLabel = Get-UxLocalizedString -Key 'GuiDeploymentMediaBuilderStart' -Fallback 'Start ISO Build'
	$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleText"
	Width="920" Height="720"
	MinWidth="760" MinHeight="560"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8" Background="$($theme.WindowBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>
			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="16,12,10,12">
				<Grid>
					<StackPanel>
						<TextBlock Text="$titleText" FontSize="18" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
						<TextBlock Text="$subtitleText" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,4,0,0" TextWrapping="Wrap"/>
					</StackPanel>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" Width="32" Height="28" HorizontalAlignment="Right" VerticalAlignment="Top"
						Background="Transparent" BorderThickness="0" Foreground="$($theme.TextPrimary)" Cursor="Hand"/>
				</Grid>
			</Border>
			<ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="18,16,18,16">
				<Grid>
					<Grid.RowDefinitions>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="*"/>
					</Grid.RowDefinitions>
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="180"/>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>

					<TextBlock Grid.Row="0" Grid.Column="0" Text="Source ISO" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<TextBox Name="TxtSourceIso" Grid.Row="0" Grid.Column="1" MinHeight="30" Margin="0,0,8,10"/>
					<StackPanel Grid.Row="0" Grid.Column="2" Orientation="Horizontal" Margin="0,0,0,10">
						<Button Name="BtnBrowseIso" Content="Browse..." MinWidth="92" MinHeight="30" Margin="0,0,6,0"/>
						<Button Name="BtnDetectIso" Content="Detect Editions" MinWidth="110" MinHeight="30"/>
					</StackPanel>

					<TextBlock Grid.Row="1" Grid.Column="0" Text="Working directory" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<TextBox Name="TxtWorkingDirectory" Grid.Row="1" Grid.Column="1" MinHeight="30" Margin="0,0,8,10"/>
					<Button Name="BtnBrowseWorking" Grid.Row="1" Grid.Column="2" Content="Browse..." MinWidth="92" MinHeight="30" Margin="0,0,0,10"/>

					<TextBlock Grid.Row="2" Grid.Column="0" Text="Edition index" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<StackPanel Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,0,0,10">
						<TextBox Name="TxtEditionIndex" Width="90" MinHeight="30" Text="1"/>
						<ComboBox Name="CmbDetectedEdition" Width="300" MinHeight="30" Margin="8,0,0,0" IsEnabled="False" ToolTip="Run Detect Editions after selecting a source ISO."/>
						<ComboBox Name="CmbOutputMode" Width="210" MinHeight="30" Margin="8,0,0,0" SelectedIndex="0">
							<ComboBoxItem Content="Create ISO"/>
							<ComboBoxItem Content="Create USB"/>
							<ComboBoxItem Content="Export Working Folder Only"/>
						</ComboBox>
					</StackPanel>

					<TextBlock Grid.Row="3" Grid.Column="0" Text="Installation customizations" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<TextBox Name="TxtAutounattend" Grid.Row="3" Grid.Column="1" MinHeight="30" Margin="0,0,8,10"/>
					<Button Name="BtnBrowseAutounattend" Grid.Row="3" Grid.Column="2" Content="Browse..." MinWidth="92" MinHeight="30" Margin="0,0,0,10"/>

					<TextBlock Grid.Row="4" Grid.Column="0" Text="Drivers" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<StackPanel Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2" Orientation="Vertical" Margin="0,0,0,10">
						<Grid>
							<Grid.ColumnDefinitions>
								<ColumnDefinition Width="*"/>
								<ColumnDefinition Width="Auto"/>
							</Grid.ColumnDefinitions>
							<TextBox Name="TxtDriverSource" Grid.Column="0" MinHeight="30" Margin="0,0,8,0"/>
							<Button Name="BtnBrowseDrivers" Grid.Column="1" Content="Browse..." MinWidth="92" MinHeight="30"/>
						</Grid>
						<CheckBox Name="ChkBootDrivers" Content="Inject storage/network drivers into boot.wim" Foreground="$($theme.TextPrimary)" Margin="0,8,0,0"/>
						<CheckBox Name="ChkBaselineTweaks" Content="Stage selected Baseline setup customizations" Foreground="$($theme.TextPrimary)" Margin="0,4,0,0"/>
					</StackPanel>

					<TextBlock Grid.Row="5" Grid.Column="0" Text="USB target" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,0,12,10"/>
					<TextBox Name="TxtUsbTargetRoot" Grid.Row="5" Grid.Column="1" MinHeight="30" Margin="0,0,8,10" ToolTip="Root of an empty removable drive, for example E:\"/>
					<Button Name="BtnBrowseUsbTarget" Grid.Row="5" Grid.Column="2" Content="Browse..." MinWidth="92" MinHeight="30" Margin="0,0,0,10"/>

					<TextBox Name="TxtPlanPreview" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="3" MinHeight="260" AcceptsReturn="True" TextWrapping="Wrap"
						VerticalScrollBarVisibility="Auto" IsReadOnly="True"/>
				</Grid>
			</ScrollViewer>
			<Border Grid.Row="2" Background="$($theme.HeaderBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0" Padding="16,10,16,10">
				<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
					<Button Name="BtnPreview" Content="$previewLabel" MinWidth="132" MinHeight="32" Margin="0,0,8,0" IsEnabled="False"/>
					<Button Name="BtnStartBuild" Content="$startLabel" MinWidth="118" MinHeight="32" Margin="0,0,8,0" IsEnabled="False"/>
					<Button Name="BtnClose" Content="$closeLabel" MinWidth="90" MinHeight="32"/>
				</StackPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@

	$reader = New-Object System.Xml.XmlNodeReader $xaml
	$window = [Windows.Markup.XamlReader]::Load($reader)
	$window.Owner = $Script:MainForm

	$txtSourceIso = $window.FindName('TxtSourceIso')
	$txtWorkingDirectory = $window.FindName('TxtWorkingDirectory')
	$txtEditionIndex = $window.FindName('TxtEditionIndex')
	$cmbDetectedEdition = $window.FindName('CmbDetectedEdition')
	$cmbOutputMode = $window.FindName('CmbOutputMode')
	$txtAutounattend = $window.FindName('TxtAutounattend')
	$txtDriverSource = $window.FindName('TxtDriverSource')
	$txtUsbTargetRoot = $window.FindName('TxtUsbTargetRoot')
	$chkBootDrivers = $window.FindName('ChkBootDrivers')
	$chkBaselineTweaks = $window.FindName('ChkBaselineTweaks')
	$txtPlanPreview = $window.FindName('TxtPlanPreview')
	$btnPreview = $window.FindName('BtnPreview')
	$btnStartBuild = $window.FindName('BtnStartBuild')
	$btnClose = $window.FindName('BtnClose')
	$btnDlgClose = $window.FindName('BtnDlgClose')
	$btnBrowseIso = $window.FindName('BtnBrowseIso')
	$btnDetectIso = $window.FindName('BtnDetectIso')
	$btnBrowseWorking = $window.FindName('BtnBrowseWorking')
	$btnBrowseAutounattend = $window.FindName('BtnBrowseAutounattend')
	$btnBrowseDrivers = $window.FindName('BtnBrowseDrivers')
	$btnBrowseUsbTarget = $window.FindName('BtnBrowseUsbTarget')

	$result = @{ Cancelled = $true; Previewed = $false; Started = $false; ReportPath = $null; OutputPath = $null; BuildRoot = $null }
	$currentPlan = $null
	$detectedIsoInfo = $null
	$txtWorkingDirectory.Text = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\Working'
	$txtPlanPreview.Text = "Select an official Microsoft Windows 10/11 ISO, run Detect Editions, then preview or start the ISO build."
	$operationState = @{ Operation = $null }
	$updateActionAvailability = $null

	$setControlsEnabled = {
		param([bool]$Enabled)

		foreach ($control in @(
			$btnBrowseIso,
			$btnDetectIso,
			$btnBrowseWorking,
			$btnBrowseAutounattend,
			$btnBrowseDrivers,
			$btnBrowseUsbTarget,
			$btnPreview,
			$cmbOutputMode,
			$cmbDetectedEdition,
			$txtSourceIso,
			$txtWorkingDirectory,
			$txtEditionIndex,
			$txtAutounattend,
			$txtDriverSource,
			$txtUsbTargetRoot,
			$chkBootDrivers,
			$chkBaselineTweaks
		))
		{
			if ($control) { $control.IsEnabled = $Enabled }
		}

		if ($operationState.Operation)
		{
			$btnStartBuild.Content = 'Cancel Operation'
			$btnStartBuild.IsEnabled = $true
			return
		}

		$btnStartBuild.Content = $startLabel
		if ($updateActionAvailability) { & $updateActionAvailability -ControlsEnabled:$Enabled }
		else
		{
			$btnPreview.IsEnabled = $false
			$btnStartBuild.IsEnabled = $false
		}
		if ($cmbDetectedEdition) { $cmbDetectedEdition.IsEnabled = ($Enabled -and $detectedIsoInfo -and $cmbDetectedEdition.Items.Count -gt 0) }
	}.GetNewClosure()

	$setStatus = {
		param(
			[string]$Message,
			[string]$Tone = 'muted'
		)

		if (-not [string]::IsNullOrWhiteSpace($Message))
		{
			$txtPlanPreview.Text = [string]$Message
		}
		switch ($Tone)
		{
			'error' { try { LogError $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.Status.LogError' -Severity Warning } }
			'warning' { try { LogWarning $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.Status.LogWarning' -Severity Warning } }
			default { try { LogInfo $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.Status.LogInfo' -Severity Debug } }
		}
	}.GetNewClosure()

	$requestCancel = {
		[void](Stop-GuiDeploymentMediaDialogBackgroundOperation -OperationState $operationState -StatusCallback $setStatus)
		& $setControlsEnabled $false
	}.GetNewClosure()

	$browseFile = {
		param([string]$Filter)
		$dialog = New-Object Microsoft.Win32.OpenFileDialog
		$dialog.Filter = $Filter
		if ($dialog.ShowDialog($window) -eq $true) { return $dialog.FileName }
		return $null
	}
	$browseFolder = {
		Add-Type -AssemblyName System.Windows.Forms
		$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
		$dialog.ShowNewFolderButton = $true
		if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
		return $null
	}
	$getOutputMode = {
		if ($cmbOutputMode.SelectedItem -and $cmbOutputMode.SelectedItem.Content) { return [string]$cmbOutputMode.SelectedItem.Content }
		return 'Create ISO'
	}
	$getEditionName = {
		if ($cmbDetectedEdition.SelectedItem -and $cmbDetectedEdition.SelectedItem.Tag)
		{
			return [string]$cmbDetectedEdition.SelectedItem.Tag.Name
		}
		return ''
	}
	$getPlan = {
		$editionIndex = 1
		if (-not [int]::TryParse([string]$txtEditionIndex.Text, [ref]$editionIndex)) { $editionIndex = 0 }
		return New-GuiDeploymentMediaBuildPlan -SourceIso $txtSourceIso.Text -WorkingDirectory $txtWorkingDirectory.Text -EditionIndex $editionIndex -EditionName (& $getEditionName) -AutounattendPath $txtAutounattend.Text -DriverSource $txtDriverSource.Text -UsbTargetRoot $txtUsbTargetRoot.Text -IsoImageInfo $detectedIsoInfo -OutputMode (& $getOutputMode) -InjectBootDrivers:([bool]$chkBootDrivers.IsChecked) -IncludeBaselineTweaks:([bool]$chkBaselineTweaks.IsChecked)
	}
	$updateActionAvailability = {
		param([bool]$ControlsEnabled = $true)

		if ($operationState.Operation)
		{
			$btnPreview.IsEnabled = $false
			$btnStartBuild.Content = 'Cancel Operation'
			$btnStartBuild.IsEnabled = $true
			return
		}

		$currentPlan = & $getPlan
		$ready = $ControlsEnabled -and [bool]$currentPlan.IsValid
		$message = if ($ready)
		{
			'Ready to preview or start ISO build.'
		}
		elseif (@($currentPlan.Errors).Count -gt 0)
		{
			@($currentPlan.Errors) -join [Environment]::NewLine
		}
		else
		{
			'Complete required deployment media inputs before previewing or building.'
		}

		$btnPreview.IsEnabled = $ready
		$btnPreview.ToolTip = $message
		$btnStartBuild.Content = $startLabel
		$btnStartBuild.IsEnabled = $ready
		$btnStartBuild.ToolTip = $message
		if ($cmbDetectedEdition) { $cmbDetectedEdition.IsEnabled = ($ControlsEnabled -and $detectedIsoInfo -and $cmbDetectedEdition.Items.Count -gt 0) }
	}.GetNewClosure()
	$markPlanChanged = {
		$currentPlan = $null
		& $updateActionAvailability -ControlsEnabled:$true
	}.GetNewClosure()

	$btnBrowseIso.Add_Click({ $path = & $browseFile 'Windows ISO (*.iso)|*.iso'; if ($path) { $txtSourceIso.Text = $path } }.GetNewClosure())
	$btnDetectIso.Add_Click({
		if ($operationState.Operation)
		{
			& $requestCancel
			return
		}

		try
		{
			$sourceIso = ([string]$txtSourceIso.Text).Trim()
			$dialogPath = Resolve-GuiDeploymentMediaDialogSupportPath -Name 'Dialog'
			$executionPath = Resolve-GuiDeploymentMediaDialogSupportPath -Name 'Execution'
			$worker = {
				param (
					[hashtable]$Context,
					[hashtable]$Sync
				)

				. ([string]$Context.DialogPath)
				. ([string]$Context.ExecutionPath)
				$sourceIso = [string]$Context.SourceIso
				$Sync.Status = ('Detecting editions in {0}.' -f $sourceIso)
				return Get-GuiDeploymentMediaIsoImageInfo -SourceIso $sourceIso -CancellationState $Sync
			}
			$statusCallback = {
				param (
					[string]$Message,
					[string]$Tone = 'muted'
				)
				$txtPlanPreview.Text = $Message
				if ($Tone -eq 'warning') { try { LogWarning $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.DetectIso.StatusWarning' -Severity Warning } }
				else { try { LogInfo $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.DetectIso.StatusInfo' -Severity Debug } }
			}.GetNewClosure()
			$completedCallback = {
				param ([object]$Result)
				$detectedIsoInfo = $Result
				$cmbDetectedEdition.Items.Clear()
				foreach ($edition in @($detectedIsoInfo.Editions))
				{
					$item = New-Object System.Windows.Controls.ComboBoxItem
					$item.Content = ('{0}: {1}' -f $edition.Index, $edition.Name)
					$item.Tag = $edition
					[void]$cmbDetectedEdition.Items.Add($item)
				}
				if ($cmbDetectedEdition.Items.Count -gt 0)
				{
					$cmbDetectedEdition.IsEnabled = $true
					$cmbDetectedEdition.SelectedIndex = 0
					$txtEditionIndex.Text = [string]$detectedIsoInfo.Editions[0].Index
				}
				$txtPlanPreview.Text = ('Detected {0}: {1}{2}Edition count: {3}' -f $detectedIsoInfo.ImageKind, $detectedIsoInfo.ImagePath, [Environment]::NewLine, @($detectedIsoInfo.Editions).Count)
				& $updateActionAvailability -ControlsEnabled:$true
			}.GetNewClosure()
			$failedCallback = {
				param ([object]$ErrorRecord)
				$isCancelled = ($ErrorRecord.Exception -is [System.OperationCanceledException])
				$detectedIsoInfo = $null
				$cmbDetectedEdition.Items.Clear()
				$cmbDetectedEdition.IsEnabled = $false
				& $updateActionAvailability -ControlsEnabled:$true
				$txtPlanPreview.Text = ('ISO detection {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message)
				if (-not $isCancelled)
				{
					try { LogError (Format-BaselineErrorForLog -ErrorObject $ErrorRecord -Prefix 'Deployment media ISO detection failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.DetectIso.LogError' -Severity Warning }
					[void](Show-ThemedDialog -Title $titleText -Message ("ISO detection failed.`n`n{0}" -f $ErrorRecord.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}.GetNewClosure()
			$finallyCallback = { & $setControlsEnabled $true }.GetNewClosure()

			$detectedIsoInfo = $null
			$cmbDetectedEdition.Items.Clear()
			$cmbDetectedEdition.IsEnabled = $false
			$currentPlan = $null
			& $updateActionAvailability -ControlsEnabled:$false
			$txtPlanPreview.Text = 'Detecting ISO editions...'
			& $setControlsEnabled $false
			$started = Start-GuiDeploymentMediaDialogBackgroundOperation -OperationState $operationState -Name 'Deployment media ISO detection' -Worker $worker -Context @{ DialogPath = $dialogPath; ExecutionPath = $executionPath; SourceIso = $sourceIso } -TimeoutSeconds 900 -StatusCallback $statusCallback -CompletedCallback $completedCallback -FailedCallback $failedCallback -FinallyCallback $finallyCallback
			if (-not $started) { & $setControlsEnabled $true }
		}
		catch
		{
			$detectedIsoInfo = $null
			$cmbDetectedEdition.Items.Clear()
			$cmbDetectedEdition.IsEnabled = $false
			& $updateActionAvailability -ControlsEnabled:$true
			$txtPlanPreview.Text = ('ISO detection failed: {0}' -f $_.Exception.Message)
			try { LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Deployment media ISO detection failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.DetectIso.StartLogError' -Severity Warning }
			[void](Show-ThemedDialog -Title $titleText -Message ("ISO detection failed.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure())
	$cmbDetectedEdition.Add_SelectionChanged({
		if ($cmbDetectedEdition.SelectedItem -and $cmbDetectedEdition.SelectedItem.Tag)
		{
			$txtEditionIndex.Text = [string]$cmbDetectedEdition.SelectedItem.Tag.Index
			& $updateActionAvailability -ControlsEnabled:$true
		}
	}.GetNewClosure())
	$btnBrowseAutounattend.Add_Click({ $path = & $browseFile 'Answer files (*.xml)|*.xml'; if ($path) { $txtAutounattend.Text = $path; & $updateActionAvailability -ControlsEnabled:$true } }.GetNewClosure())
	$btnBrowseWorking.Add_Click({ $path = & $browseFolder; if ($path) { $txtWorkingDirectory.Text = $path; & $updateActionAvailability -ControlsEnabled:$true } }.GetNewClosure())
	$btnBrowseDrivers.Add_Click({ $path = & $browseFolder; if ($path) { $txtDriverSource.Text = $path; & $updateActionAvailability -ControlsEnabled:$true } }.GetNewClosure())
	$btnBrowseUsbTarget.Add_Click({ $path = & $browseFolder; if ($path) { $txtUsbTargetRoot.Text = [System.IO.Path]::GetPathRoot($path); & $updateActionAvailability -ControlsEnabled:$true } }.GetNewClosure())
	foreach ($textBox in @($txtSourceIso, $txtWorkingDirectory, $txtEditionIndex, $txtAutounattend, $txtDriverSource, $txtUsbTargetRoot))
	{
		if ($textBox) { $textBox.Add_TextChanged($markPlanChanged) }
	}
	if ($cmbOutputMode) { $cmbOutputMode.Add_SelectionChanged($markPlanChanged) }
	foreach ($checkBox in @($chkBootDrivers, $chkBaselineTweaks))
	{
		if ($checkBox)
		{
			$checkBox.Add_Checked($markPlanChanged)
			$checkBox.Add_Unchecked($markPlanChanged)
		}
	}

	$btnPreview.Add_Click({
		$currentPlan = & $getPlan
		$txtPlanPreview.Text = Convert-GuiDeploymentMediaBuildPlanToText -Plan $currentPlan
		& $updateActionAvailability -ControlsEnabled:$true
		$result.Previewed = $true
	}.GetNewClosure())

	$btnStartBuild.Add_Click({
		if ($operationState.Operation)
		{
			& $requestCancel
			return
		}

		$currentPlan = & $getPlan
		$txtPlanPreview.Text = Convert-GuiDeploymentMediaBuildPlanToText -Plan $currentPlan
		if (-not [bool]$currentPlan.IsValid)
		{
			$btnStartBuild.IsEnabled = $false
			return
		}
		$confirm = Show-ThemedDialog -Title $titleText -Message "Start ISO Build will copy the selected Microsoft ISO into a working folder, apply the requested media customizations, produce the selected output, and save an auditable build report. Confirm that the source ISO, edition, and output target are correct before continuing." -Buttons @('Cancel', 'Start ISO Build') -AccentButton 'Start ISO Build'
		if ($confirm -ne 'Start ISO Build') { return }
		try
		{
			$dialogPath = Resolve-GuiDeploymentMediaDialogSupportPath -Name 'Dialog'
			$executionPath = Resolve-GuiDeploymentMediaDialogSupportPath -Name 'Execution'
			$processHelperPath = Resolve-GuiDeploymentMediaDialogSupportPath -Name 'ProcessHelper'
			$operationPlan = $currentPlan
			$selectedTweaks = $null
			if ([bool]$operationPlan.IncludeBaselineTweaks)
			{
				$selectedTweaks = @(Get-GuiDeploymentMediaSelectedTweaksForSetup)
			}

			$worker = {
				param (
					[hashtable]$Context,
					[hashtable]$Sync
				)

				. ([string]$Context.ProcessHelperPath)
				. ([string]$Context.DialogPath)
				. ([string]$Context.ExecutionPath)

				$progressCallback = {
					param([object]$Progress)

					if ($Progress -and $Progress.PSObject.Properties['DisplayText'])
					{
						$Sync.Status = [string]$Progress.DisplayText
					}
					elseif ($Progress -and $Progress.PSObject.Properties['Message'])
					{
						$Sync.Status = [string]$Progress.Message
					}
					else
					{
						$Sync.Status = [string]$Progress
					}
				}.GetNewClosure()

				$buildParameters = @{
					Plan = $Context.Plan
					ProgressCallback = $progressCallback
					CancellationState = $Sync
					GlobalTimeoutSeconds = [int]$Context.GlobalTimeoutSeconds
				}
				if ($Context.ContainsKey('SelectedTweaks'))
				{
					$buildParameters['SelectedTweaks'] = @($Context.SelectedTweaks)
				}

				return Invoke-GuiDeploymentMediaBuild @buildParameters
			}
			$statusCallback = {
				param (
					[string]$Message,
					[string]$Tone = 'muted'
				)
				$txtPlanPreview.Text = (Convert-GuiDeploymentMediaBuildPlanToText -Plan $operationPlan) + [Environment]::NewLine + [Environment]::NewLine + $Message
				if ($Tone -eq 'warning') { try { LogWarning $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.StartBuild.StatusWarning' -Severity Warning } }
				else { try { LogInfo $Message } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.StartBuild.StatusInfo' -Severity Debug } }
			}.GetNewClosure()
			$completedCallback = {
				param ([object]$Result)
				$buildResult = $Result
				$result.Cancelled = $false
				$result.Started = $true
				$result.ReportPath = $buildResult.ReportPath
				$result.OutputPath = $buildResult.OutputPath
				$result.BuildRoot = $buildResult.BuildRoot
				$txtPlanPreview.Text = (Convert-GuiDeploymentMediaBuildPlanToText -Plan $operationPlan) + [Environment]::NewLine + [Environment]::NewLine + ('Build output: {0}' -f $buildResult.OutputPath) + [Environment]::NewLine + ('Build report saved: {0}' -f $buildResult.ReportPath)
			}.GetNewClosure()
			$failedCallback = {
				param ([object]$ErrorRecord)
				$isCancelled = ($ErrorRecord.Exception -is [System.OperationCanceledException])
				$txtPlanPreview.Text = (Convert-GuiDeploymentMediaBuildPlanToText -Plan $operationPlan) + [Environment]::NewLine + [Environment]::NewLine + ('Build {0}: {1}' -f $(if ($isCancelled) { 'cancelled' } else { 'failed' }), $ErrorRecord.Exception.Message)
				if (-not $isCancelled)
				{
					try { LogError (Format-BaselineErrorForLog -ErrorObject $ErrorRecord -Prefix 'Deployment media build failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.StartBuild.LogError' -Severity Warning }
					if (Test-GuiDeploymentMediaOscdimgDependencyError -ErrorRecord $ErrorRecord)
					{
						Show-GuiDeploymentMediaDialogOscdimgInstallPrompt -ErrorRecord $ErrorRecord -Title $titleText
					}
					else
					{
						[void](Show-ThemedDialog -Title $titleText -Message ("Deployment media build failed.`n`n{0}" -f $ErrorRecord.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
					}
				}
			}.GetNewClosure()
			$finallyCallback = { & $setControlsEnabled $true }.GetNewClosure()

			$context = @{
				DialogPath = $dialogPath
				ExecutionPath = $executionPath
				ProcessHelperPath = $processHelperPath
				Plan = $operationPlan
				GlobalTimeoutSeconds = 28800
			}
			if ($null -ne $selectedTweaks)
			{
				$context['SelectedTweaks'] = @($selectedTweaks)
			}

			& $setControlsEnabled $false
			$txtPlanPreview.Text = (Convert-GuiDeploymentMediaBuildPlanToText -Plan $operationPlan) + [Environment]::NewLine + [Environment]::NewLine + 'Deployment media build started.'
			$started = Start-GuiDeploymentMediaDialogBackgroundOperation -OperationState $operationState -Name 'Deployment media build' -Worker $worker -Context $context -TimeoutSeconds 28800 -StatusCallback $statusCallback -CompletedCallback $completedCallback -FailedCallback $failedCallback -FinallyCallback $finallyCallback
			if (-not $started) { & $setControlsEnabled $true }
		}
		catch
		{
			& $setControlsEnabled $true
			$txtPlanPreview.Text = (Convert-GuiDeploymentMediaBuildPlanToText -Plan $currentPlan) + [Environment]::NewLine + [Environment]::NewLine + ('Build failed: {0}' -f $_.Exception.Message)
			try { LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Deployment media build failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderDialog.StartBuild.StartLogError' -Severity Warning }
			if (Test-GuiDeploymentMediaOscdimgDependencyError -ErrorRecord $_)
			{
				Show-GuiDeploymentMediaDialogOscdimgInstallPrompt -ErrorRecord $_ -Title $titleText
			}
			else
			{
				[void](Show-ThemedDialog -Title $titleText -Message ("Deployment media build failed.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}
	}.GetNewClosure())

	$closeHandler = {
		if ($operationState.Operation)
		{
			& $requestCancel
			return
		}
		$window.Close()
	}.GetNewClosure()
	$btnClose.Add_Click($closeHandler)
	$btnDlgClose.Add_Click($closeHandler)
	$window.Add_Closing({
		param($Sender, $EventArgs)
		if ($operationState.Operation)
		{
			$EventArgs.Cancel = $true
			& $requestCancel
		}
	}.GetNewClosure())
	[void]$window.ShowDialog()

	return $result
}
