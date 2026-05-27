<#
	.SYNOPSIS
	Toast notification helpers for Baseline (Windows PowerShell 5.1).

	.DESCRIPTION
	Builds and emits Windows toast notifications via WinRT
	(Windows.UI.Notifications.ToastNotificationManager). Also exposes
	registration helpers for the AppUserModelId and URL-protocol entries
	that Action Center requires for the toast's "Run" button to launch a
	scheduled task. The CleanupTask pattern is the reference.

	XML construction is intentionally separated from emission so tests can
	validate the produced toast document without requiring WinRT.
#>

<#
	.SYNOPSIS
#>

function New-BaselineToastXml
{
	<#
		.SYNOPSIS
		Builds a ToastGeneric notification XML document.

		.DESCRIPTION
		Constructs the toast XML using the System.Xml DOM (no string
		concatenation, no manual escaping). When -ActionLabel and
		-ActionProtocol are supplied, the notification surfaces a "Run"
		button that activates the supplied URL protocol; otherwise no
		actions are emitted.

		.OUTPUTS
		[string] — the OuterXml of the constructed toast document.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Title,

		[Parameter(Mandatory)]
		[string]$Body,

		[string]$ActionLabel,

		[string]$ActionProtocol,

		[ValidateSet('Short', 'Long')]
		[string]$Duration = 'Long',

		[string]$AudioSrc = 'ms-winsoundevent:notification.default'
	)

	$doc = New-Object -TypeName System.Xml.XmlDocument

	$toast = $doc.CreateElement('toast')
	$toast.SetAttribute('duration', $Duration)
	$null = $doc.AppendChild($toast)

	$visual = $doc.CreateElement('visual')
	$null = $toast.AppendChild($visual)

	$binding = $doc.CreateElement('binding')
	$binding.SetAttribute('template', 'ToastGeneric')
	$null = $visual.AppendChild($binding)

	$titleNode = $doc.CreateElement('text')
	$titleNode.InnerText = $Title
	$null = $binding.AppendChild($titleNode)

	$group = $doc.CreateElement('group')
	$null = $binding.AppendChild($group)

	$subgroup = $doc.CreateElement('subgroup')
	$null = $group.AppendChild($subgroup)

	$bodyNode = $doc.CreateElement('text')
	$bodyNode.SetAttribute('hint-style', 'body')
	$bodyNode.SetAttribute('hint-wrap', 'true')
	$bodyNode.InnerText = $Body
	$null = $subgroup.AppendChild($bodyNode)

	$audio = $doc.CreateElement('audio')
	$audio.SetAttribute('src', $AudioSrc)
	$null = $toast.AppendChild($audio)

	$hasRunAction = -not [string]::IsNullOrWhiteSpace($ActionLabel) -and -not [string]::IsNullOrWhiteSpace($ActionProtocol)
	if ($hasRunAction)
	{
		$actions = $doc.CreateElement('actions')
		$null = $toast.AppendChild($actions)

		$runAction = $doc.CreateElement('action')
		$runAction.SetAttribute('content', $ActionLabel)
		# Trailing colon is required by the URL-protocol activation contract.
		$protocolArgument = if ($ActionProtocol.EndsWith(':')) { $ActionProtocol } else { ($ActionProtocol + ':') }
		$runAction.SetAttribute('arguments', $protocolArgument)
		$runAction.SetAttribute('activationType', 'protocol')
		$null = $actions.AppendChild($runAction)

		$dismissAction = $doc.CreateElement('action')
		$dismissAction.SetAttribute('content', '')
		$dismissAction.SetAttribute('arguments', 'dismiss')
		$dismissAction.SetAttribute('activationType', 'system')
		$null = $actions.AppendChild($dismissAction)
	}

	return $doc.OuterXml
}

<#
	.SYNOPSIS
#>

function Test-BaselineToastRuntimeAvailable
{
	<#
		.SYNOPSIS
		Returns $true when the WinRT toast notification types can be loaded
		on the current host. Used as a graceful gate before emitting toasts
		on systems where the namespace is not present (e.g., Server Core).
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	try
	{
		$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
		$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
		return $true
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Toast.Helpers.Test-BaselineToastRuntimeAvailable:catch134' -Severity Debug }

		return $false
	}
}

<#
	.SYNOPSIS
#>

function Send-BaselineToastXml
{
	<#
		.SYNOPSIS
		Emits a pre-built toast XML document under the supplied AppUserModelId.

		.DESCRIPTION
		Loads the WinRT toast namespace, hydrates the supplied XML into a
		Windows.Data.Xml.Dom.XmlDocument, and invokes Show() on the
		notifier for $AppId. Returns $true on success, $false if the
		runtime is unavailable or emission fails. Does not throw.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[string]$Xml,

		[Parameter(Mandatory)]
		[string]$AppId
	)

	if (-not (Test-BaselineToastRuntimeAvailable))
	{
		$logWarningCmd = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
		if ($logWarningCmd)
		{
			LogWarning "Toast runtime unavailable; suppressing toast for AppId '$AppId'"
		}
		return $false
	}

	try
	{
		$toastDoc = [Windows.Data.Xml.Dom.XmlDocument]::New()
		$toastDoc.LoadXml($Xml)

		$toast = [Windows.UI.Notifications.ToastNotification]::New($toastDoc)
		[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
		return $true
	}
	catch
	{
		$logWarningCmd = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
		if ($logWarningCmd)
		{
			LogWarning "Toast emission failed for AppId '$AppId': $($_.Exception.Message)"
		}
		return $false
	}
}

<#
	.SYNOPSIS
#>

function Show-BaselineToast
{
	<#
		.SYNOPSIS
		Convenience wrapper that builds and emits a toast in one call.

		.OUTPUTS
		[bool] — $true if the toast was emitted, $false otherwise.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[string]$Title,

		[Parameter(Mandatory)]
		[string]$Body,

		[string]$ActionLabel,

		[string]$ActionProtocol,

		[string]$AppId = 'Baseline',

		[ValidateSet('Short', 'Long')]
		[string]$Duration = 'Long'
	)

	$xml = New-BaselineToastXml -Title $Title -Body $Body -ActionLabel $ActionLabel -ActionProtocol $ActionProtocol -Duration $Duration
	return (Send-BaselineToastXml -Xml $xml -AppId $AppId)
}

<#
	.SYNOPSIS
#>

function Register-BaselineToastApp
{
	<#
		.SYNOPSIS
		Registers an AppUserModelId so toast notifications surface in Action
		Center under a recognised application identity. Idempotent.

		.DESCRIPTION
		Writes HKCR\AppUserModelId\<AppId> with DisplayName and
		ShowInSettings values. When -ProtocolName and -ProtocolCommand are
		supplied, also registers an HKCR\<Protocol> URL-protocol handler so
		the toast's action button can activate a local command (typically
		`Start-ScheduledTask` invoked through powershell.exe). This follows the
		same scheduled-task registration pattern used by the related helpers.

		Requires HKCR write access. Most callers already run elevated for
		scheduled-task registration, so this co-locates cleanly with the
		Register-Baseline*Task functions.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$AppId,

		[Parameter(Mandatory)]
		[string]$DisplayName,

		[bool]$ShowInSettings = $false,

		[string]$ProtocolName,

		[string]$ProtocolCommand
	)

	$appKeyPath = "Registry::HKEY_CLASSES_ROOT\AppUserModelId\$AppId"
	if (-not (Test-Path -Path $appKeyPath))
	{
		$null = New-Item -Path $appKeyPath -Force
	}
	$null = New-ItemProperty -Path $appKeyPath -Name 'DisplayName' -Value $DisplayName -PropertyType String -Force
	$showInSettingsValue = if ($ShowInSettings) { 1 } else { 0 }
	$null = New-ItemProperty -Path $appKeyPath -Name 'ShowInSettings' -Value $showInSettingsValue -PropertyType DWord -Force

	$registerProtocol = -not [string]::IsNullOrWhiteSpace($ProtocolName) -and -not [string]::IsNullOrWhiteSpace($ProtocolCommand)
	if ($registerProtocol)
	{
		$protocolKeyPath = "Registry::HKEY_CLASSES_ROOT\$ProtocolName"
		$commandKeyPath = "$protocolKeyPath\shell\open\command"

		if (-not (Test-Path -Path $commandKeyPath))
		{
			$null = New-Item -Path $commandKeyPath -Force
		}

		$null = New-ItemProperty -Path $protocolKeyPath -Name '(default)' -PropertyType String -Value "URL:$ProtocolName" -Force
		$null = New-ItemProperty -Path $protocolKeyPath -Name 'URL Protocol' -PropertyType String -Value '' -Force
		# EditFlags 0x210002 (2162688) — the published value; marks the
		# protocol as a system-managed URL handler so it does not appear in
		# default-app pickers.
		$null = New-ItemProperty -Path $protocolKeyPath -Name 'EditFlags' -PropertyType DWord -Value 2162688 -Force

		$null = New-ItemProperty -Path $commandKeyPath -Name '(default)' -PropertyType String -Value $ProtocolCommand -Force
	}

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		if ($registerProtocol)
		{
			LogInfo "Registered toast AppId '$AppId' with URL protocol '$ProtocolName'"
		}
		else
		{
			LogInfo "Registered toast AppId '$AppId'"
		}
	}
}

<#
	.SYNOPSIS
#>

function Unregister-BaselineToastApp
{
	<#
		.SYNOPSIS
		Removes an AppUserModelId previously registered with
		Register-BaselineToastApp. Idempotent — missing keys are not an
		error. When -ProtocolName is supplied, also removes the matching
		URL-protocol handler.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$AppId,

		[string]$ProtocolName
	)

	$appKeyPath = "Registry::HKEY_CLASSES_ROOT\AppUserModelId\$AppId"
	if (Test-Path -Path $appKeyPath)
	{
		Remove-Item -Path $appKeyPath -Recurse -Force -ErrorAction SilentlyContinue
	}

	if (-not [string]::IsNullOrWhiteSpace($ProtocolName))
	{
		$protocolKeyPath = "Registry::HKEY_CLASSES_ROOT\$ProtocolName"
		if (Test-Path -Path $protocolKeyPath)
		{
			Remove-Item -Path $protocolKeyPath -Recurse -Force -ErrorAction SilentlyContinue
		}
	}

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Unregistered toast AppId '$AppId'"
	}
}
