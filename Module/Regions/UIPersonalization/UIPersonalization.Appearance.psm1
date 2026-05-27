<#
	.SYNOPSIS
	Configures appearance and pointer precision settings.



.DESCRIPTION

Applies Baseline's appearance and pointer precision settings in GUI and headless runs.
	.PARAMETER Enable
	Enable enhanced pointer precision

	.PARAMETER Disable
	Disable enhanced pointer precision (default value)

	.EXAMPLE
	EnhPointerPrecision -Enable

	.EXAMPLE
	EnhPointerPrecision -Disable

	.NOTES
	Current user
#>
function EnhPointerPrecision
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
			Write-ConsoleStatus -Action "Enabling enhanced pointer precision"
			LogInfo "Enabling enhanced pointer precision"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseSpeed" `
					-Value "1" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseThreshold1" `
					-Value "6" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseThreshold2" `
					-Value "10" `
					-Type String
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable enhanced pointer precision: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling enhanced pointer precision"
			LogInfo "Disabling enhanced pointer precision"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseSpeed" `
					-Value "0" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseThreshold1" `
					-Value "0" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" `
					-Name "MouseThreshold2" `
					-Value "0" `
					-Type String
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable enhanced pointer precision: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Play or disable Windows startup sound



.DESCRIPTION

Applies the Baseline behavior for play or disable Windows startup sound.
	.PARAMETER Enable
	Play Windows startup sound

	.PARAMETER Disable
	Do not play Windows startup sound (default value)

	.EXAMPLE
	StartupSound -Enable

	.EXAMPLE
	StartupSound -Disable

	.NOTES
	Current user
#>
function StartupSound
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
			Write-ConsoleStatus -Action "Enabling Windows startup sound"
			LogInfo "Enabling Windows startup sound"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" `
					-Name "DisableStartupSound" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows startup sound: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows startup sound"
			LogInfo "Disabling Windows startup sound"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" `
					-Name "DisableStartupSound" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows startup sound: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Control the volume ducking preference used when Windows detects communications activity



.DESCRIPTION

Applies the Baseline behavior for control the volume ducking preference used when Windows detects communications activity.
	.PARAMETER MuteAll
	Mute all other sounds

	.PARAMETER Reduce80
	Reduce the volume of other sounds by 80%

	.PARAMETER Reduce50
	Reduce the volume of other sounds by 50%

	.PARAMETER DoNothing
	Do nothing when communications activity is detected (default value)

	.EXAMPLE
	SoundDuckingPreference -DoNothing

	.EXAMPLE
	SoundDuckingPreference -Reduce80

	.NOTES
	Current user
#>

function SoundDuckingPreference
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "MuteAll"
		)]
		[switch]
		$MuteAll,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Reduce80"
		)]
		[switch]
		$Reduce80,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Reduce50"
		)]
		[switch]
		$Reduce50,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "DoNothing"
		)]
		[switch]
		$DoNothing
	)

	$audioPath = "HKCU:\Software\Microsoft\Multimedia\Audio"
	if (-not (Test-Path -Path $audioPath))
	{
		New-Item -Path $audioPath -Force -ErrorAction Stop | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"MuteAll"
		{
			Write-ConsoleStatus -Action "Setting communications volume ducking to mute all other sounds"
			LogInfo "Setting communications volume ducking to mute all other sounds"
			try
			{
				Set-RegistryValueSafe -Path $audioPath `
					-Name "UserDuckingPreference" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set communications volume ducking to mute all other sounds: $($_.Exception.Message)"
			}
		}
		"Reduce80"
		{
			Write-ConsoleStatus -Action "Setting communications volume ducking to reduce other sounds by 80%"
			LogInfo "Setting communications volume ducking to reduce other sounds by 80%"
			try
			{
				Set-RegistryValueSafe -Path $audioPath `
					-Name "UserDuckingPreference" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set communications volume ducking to reduce other sounds by 80%: $($_.Exception.Message)"
			}
		}
		"Reduce50"
		{
			Write-ConsoleStatus -Action "Setting communications volume ducking to reduce other sounds by 50%"
			LogInfo "Setting communications volume ducking to reduce other sounds by 50%"
			try
			{
				Set-RegistryValueSafe -Path $audioPath `
					-Name "UserDuckingPreference" `
					-Value 2 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set communications volume ducking to reduce other sounds by 50%: $($_.Exception.Message)"
			}
		}
		"DoNothing"
		{
			Write-ConsoleStatus -Action "Setting communications volume ducking to do nothing"
			LogInfo "Setting communications volume ducking to do nothing"
			try
			{
				Set-RegistryValueSafe -Path $audioPath `
					-Name "UserDuckingPreference" `
					-Value 3 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set communications volume ducking to do nothing: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Allow or prevent Narrator from ducking audio while it speaks



.DESCRIPTION

Applies the Baseline behavior for allow or prevent Narrator from ducking audio while it speaks.
	.PARAMETER Enable
	Allow Narrator to lower the volume of other apps while speaking

	.PARAMETER Disable
	Prevent Narrator from lowering the volume of other apps while speaking (default value)

	.EXAMPLE
	NarratorAudioDucking -Enable

	.EXAMPLE
	NarratorAudioDucking -Disable

	.NOTES
	Current user
#>
function NarratorAudioDucking
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

	$accessibilityPath = "HKCU:\Software\Microsoft\Narrator\NoRoam"
	if (-not (Test-Path -Path $accessibilityPath))
	{
		New-Item -Path $accessibilityPath -Force -ErrorAction Stop | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Narrator audio ducking"
			LogInfo "Enabling Narrator audio ducking"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "DuckAudio" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Narrator audio ducking: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Narrator audio ducking"
			LogInfo "Disabling Narrator audio ducking"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "DuckAudio" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Narrator audio ducking: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Allow or prevent SpeechOneCore voice activation for apps



.DESCRIPTION

Applies the Baseline behavior for allow or prevent SpeechOneCore voice activation for apps.
	.PARAMETER Enable
	Allow voice activation for apps using the SpeechOneCore stack

	.PARAMETER Disable
	Prevent voice activation for apps using the SpeechOneCore stack (default value)

	.EXAMPLE
	SpeechOneCoreVoiceActivation -Enable

	.EXAMPLE
	SpeechOneCoreVoiceActivation -Disable

	.NOTES
	Machine-wide
#>
function SpeechOneCoreVoiceActivation
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

	$speechOneCorePath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\SpeechOneCore\Settings"
	if (-not (Test-Path -Path $speechOneCorePath))
	{
		New-Item -Path $speechOneCorePath -Force -ErrorAction Stop | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling SpeechOneCore voice activation"
			LogInfo "Enabling SpeechOneCore voice activation"
			try
			{
				Set-RegistryValueSafe -Path $speechOneCorePath `
					-Name "AgentActivationEnabled" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable SpeechOneCore voice activation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling SpeechOneCore voice activation"
			LogInfo "Disabling SpeechOneCore voice activation"
			try
			{
				Set-RegistryValueSafe -Path $speechOneCorePath `
					-Name "AgentActivationEnabled" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable SpeechOneCore voice activation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Play or disable accessibility activation sounds



.DESCRIPTION

Applies the Baseline behavior for play or disable accessibility activation sounds.
	.PARAMETER Enable
	Play sounds when accessibility features are activated

	.PARAMETER Disable
	Do not play sounds when accessibility features are activated (default value)

	.EXAMPLE
	AccessibilityActivationSounds -Enable

	.EXAMPLE
	AccessibilityActivationSounds -Disable

	.NOTES
	Current user
#>
function AccessibilityActivationSounds
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

	$accessibilityPath = "HKCU:\Control Panel\Accessibility"
	if (-not (Test-Path -Path $accessibilityPath))
	{
		New-Item -Path $accessibilityPath -Force -ErrorAction Stop | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling accessibility activation sounds"
			LogInfo "Enabling accessibility activation sounds"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "Sound on Activation" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable accessibility activation sounds: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling accessibility activation sounds"
			LogInfo "Disabling accessibility activation sounds"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "Sound on Activation" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable accessibility activation sounds: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Play or disable accessibility warning sounds



.DESCRIPTION

Applies the Baseline behavior for play or disable accessibility warning sounds.
	.PARAMETER Enable
	Play warning sounds when accessibility features are used

	.PARAMETER Disable
	Do not play warning sounds when accessibility features are used (default value)

	.EXAMPLE
	AccessibilityWarningSounds -Enable

	.EXAMPLE
	AccessibilityWarningSounds -Disable

	.NOTES
	Current user
#>
function AccessibilityWarningSounds
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

	$accessibilityPath = "HKCU:\Control Panel\Accessibility"
	if (-not (Test-Path -Path $accessibilityPath))
	{
		New-Item -Path $accessibilityPath -Force -ErrorAction Stop | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling accessibility warning sounds"
			LogInfo "Enabling accessibility warning sounds"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "Warning Sounds" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable accessibility warning sounds: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling accessibility warning sounds"
			LogInfo "Disabling accessibility warning sounds"
			try
			{
				Set-RegistryValueSafe -Path $accessibilityPath `
					-Name "Warning Sounds" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable accessibility warning sounds: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Window title bar color adapts to the prevalent background color



.DESCRIPTION

Applies the Baseline behavior for window title bar color adapts to the prevalent background color.
	.PARAMETER Enable
	Enable title bar color to match prevalent background color

	.PARAMETER Disable
	Disable title bar color adaptation to background (default value)

	.EXAMPLE
	TitleBarColor -Enable

	.EXAMPLE
	TitleBarColor -Disable

	.NOTES
	Current user
#>
function TitleBarColor
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
			Write-ConsoleStatus -Action "Enabling title bar color adaptation to background"
			LogInfo "Enabling title bar color adaptation to background"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\DWM" `
					-Name "ColorPrevalence" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable title bar color adaptation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling title bar color adaptation to background"
			LogInfo "Disabling title bar color adaptation to background"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\DWM" `
					-Name "ColorPrevalence" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable title bar color adaptation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows visual effects performance and appearance settings



.DESCRIPTION

Applies the Baseline behavior for windows visual effects performance and appearance settings.
	.PARAMETER Performance
	Adjust visual effects for best performance

	.PARAMETER Appearance
	Adjust visual effects for best appearance (default value)

	.EXAMPLE
	VisualFX -Performance

	.EXAMPLE
	VisualFX -Appearance

	.NOTES
	Current user
#>
function VisualFX
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Performance"
		)]
		[switch]
		$Performance,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Appearance"
		)]
		[switch]
		$Appearance
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Performance"
		# Adjusts visual effects for performance - Disables animations, transparency etc. but leaves font smoothing and miniatures enabled
		{
			Write-ConsoleStatus -Action "Adjusting visual effects for performance"
			LogInfo "Adjusting visual effects for performance"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "DragFullWindows" `
					-Value 0 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "MenuShowDelay" `
					-Value 0 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "UserPreferencesMask" `
					-Value ([byte[]](144,18,3,128,16,0,0,0)) `
					-Type Binary
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop\WindowMetrics" `
					-Name "MinAnimate" `
					-Value 0 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Keyboard" `
					-Name "KeyboardDelay" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ListviewAlphaSelect" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ListviewShadow" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TaskbarAnimations" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
					-Name "VisualFXSetting" `
					-Value 3 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\DWM" `
					-Name "EnableAeroPeek" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to adjust visual effects for performance: $($_.Exception.Message)"
			}
		}
		"Appearance"
		# Adjusts visual effects for appearance
		{
			Write-ConsoleStatus -Action "Adjusting visual effects for appearance"
			LogInfo "Adjusting visual effects for appearance"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "DragFullWindows" `
					-Value 1 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "MenuShowDelay" `
					-Value 400 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "UserPreferencesMask" `
					-Value ([byte[]](158,30,7,128,18,0,0,0)) `
					-Type Binary
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop\WindowMetrics" `
					-Name "MinAnimate" `
					-Value 1 `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Keyboard" `
					-Name "KeyboardDelay" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ListviewAlphaSelect" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ListviewShadow" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TaskbarAnimations" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
					-Name "VisualFXSetting" `
					-Value 3 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\DWM" `
					-Name "EnableAeroPeek" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to adjust visual effects for appearance: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Title bar window shake



.DESCRIPTION

Applies the Baseline behavior for title bar window shake.
	.PARAMETER Enable
	When I grab a windows's title bar and shake it, minimize all other windows

	.PARAMETER Disable
	When I grab a windows's title bar and shake it, don't minimize all other windows (default value)

	.EXAMPLE
	AeroShaking -Enable

	.EXAMPLE
	AeroShaking -Disable

	.NOTES
	Current user
#>
function AeroShaking
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
	Remove-RegistryValueSafe -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\Software\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Title bar window shake"
			LogInfo "Enabling Title bar window shake"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "DisallowShaking" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Title bar window shake: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Title bar window shake"
			LogInfo "Disabling Title bar window shake"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "DisallowShaking" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Title bar window shake: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The default app mode



.DESCRIPTION

Applies the Baseline behavior for the default app mode.
	.PARAMETER Dark
	Set the default app mode to dark

	.PARAMETER Light
	Set the default app mode to light (default value)

	.EXAMPLE
	AppColorMode -Dark

	.EXAMPLE
	AppColorMode -Light

	.NOTES
	Current user
#>
function AppColorMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Dark"
		)]
		[switch]
		$Dark,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Light"
		)]
		[switch]
		$Light
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Dark"
		{
			Write-ConsoleStatus -Action "Setting Apps to use Dark Mode"
			LogInfo "Setting Apps to use Dark Mode"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
					-Name "AppsUseLightTheme" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set app color mode to Dark: $($_.Exception.Message)"
			}
		}
		"Light"
		{
			Write-ConsoleStatus -Action "Setting Apps to use Light Mode"
			LogInfo "Setting Apps to use Light Mode"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
					-Name "AppsUseLightTheme" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set app color mode to Light: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Hide the Spotlight "About this picture" desktop icon.

	.DESCRIPTION
	Removes the Spotlight namespace entry from the desktop and sets the matching
	HideDesktopIcons value so the icon stays hidden for the current user.

	.EXAMPLE
	DesktopRegistry

	.NOTES
	Current user
#>
function DesktopRegistry
{
	# Write-Host: intentional - user-visible progress indicator
	Write-Host 'Removing "About this Picture" from Desktop - ' -NoNewline
	LogInfo 'Removing "About this Picture" from Desktop'
	$namespaceKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
	$hideIconsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
	$valueName = "{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
	$valueData = 1

	try
	{
		Remove-Item -Path $namespaceKeyPath -Force -ErrorAction SilentlyContinue | Out-Null
	}
	catch
	{
		LogError "Registry key not found or could not be removed: $namespaceKeyPath"
	}

	try
	{
		if (-not (Test-Path -Path $hideIconsPath))
		{
			New-Item -Path $hideIconsPath -Force -ErrorAction Stop | Out-Null
		}
		Set-RegistryValueSafe -Path $hideIconsPath -Name $valueName -Value $valueData -Type DWord | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to set registry value: $valueName"
	}
}

<#
    .SYNOPSIS
    Windows build number and edition display on desktop



.DESCRIPTION

Applies the Baseline behavior for windows build number and edition display on desktop.
    .PARAMETER Enable
    Enable the build number and edition display

    .PARAMETER Disable
    Disable the build number and edition display (default value)

    .EXAMPLE
    BuildNumberOnDesktop -Enable

    .EXAMPLE
    BuildNumberOnDesktop -Disable

    .NOTES
    Current user
#>
function BuildNumberOnDesktop
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
			Write-ConsoleStatus -Action "Enabling build number and edition display on the Desktop"
			LogInfo "Enabling build number and edition display on the Desktop"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "PaintDesktopVersion" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable build number and edition display on the Desktop: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling build number and edition display on the Desktop"
			LogInfo "Disabling build number and edition display on the Desktop"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" `
					-Name "PaintDesktopVersion" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable build number and edition display on the Desktop: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	A different input method for each app window



.DESCRIPTION

Applies the Baseline behavior for a different input method for each app window.
	.PARAMETER Enable
	Let me use a different input method for each app window

	.PARAMETER Disable
	Do not use a different input method for each app window (default value)

	.EXAMPLE
	AppsLanguageSwitch -Enable

	.EXAMPLE
	AppsLanguageSwitch -Disable

	.NOTES
	Current user
#>
function AppsLanguageSwitch
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
			Write-ConsoleStatus -Action "Enabling a different input method for each app window"
			LogInfo "Enabling a different input method for each app window"
			try
			{
				Set-WinLanguageBarOption -UseLegacySwitchMode -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable a different input method for each app window: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling a different input method for each app window"
			LogInfo "Disabling a different input method for each app window"
			try
			{
				Set-WinLanguageBarOption -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable a different input method for each app window: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Print screen button usage



.DESCRIPTION

Applies the Baseline behavior for the Print screen button usage.
	.PARAMETER Enable
	Use the Print screen button to open screen snipping

	.PARAMETER Disable
	Do not use the Print screen button to open screen snipping (default value)

	.EXAMPLE
	PrtScnSnippingTool -Enable

	.EXAMPLE
	PrtScnSnippingTool -Disable

	.NOTES
	Current user
#>
function PrtScnSnippingTool
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
			Write-ConsoleStatus -Action "Enabling the Print screen button to open screen snipping"
			LogInfo "Enabling the Print screen button to open screen snipping"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Keyboard" `
					-Name "PrintScreenKeyForSnippingEnabled" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Print Screen for screen snipping: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Print screen button to open screen snipping"
			LogInfo "Disabling the Print screen button to open screen snipping"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Keyboard" `
					-Name "PrintScreenKeyForSnippingEnabled" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Print Screen for screen snipping: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Dynamic Lighting RGB control



.DESCRIPTION

Applies the Baseline behavior for dynamic Lighting RGB control.
	.PARAMETER Enable
	Enable Dynamic Lighting RGB control for compatible devices

	.PARAMETER Disable
	Disable Dynamic Lighting RGB control

	.EXAMPLE
	Set-DynamicLighting -Enable

	.EXAMPLE
	Set-DynamicLighting -Disable

	.NOTES
	Current user. Controls HKCU\Software\Microsoft\Lighting settings.
	Windows 11 with compatible hardware only.
#>
function Set-DynamicLighting
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
			Write-ConsoleStatus -Action "Enabling Dynamic Lighting RGB control"
			LogInfo "Enabling Dynamic Lighting RGB control for compatible devices"
			try
			{
				$path = "HKCU:\Software\Microsoft\Lighting"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}

				Set-RegistryValueSafe -Path $path `
					-Name "Disabled" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Dynamic Lighting: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Dynamic Lighting RGB control"
			LogInfo "Disabling Dynamic Lighting RGB control"
			try
			{
				$path = "HKCU:\Software\Microsoft\Lighting"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}

				Set-RegistryValueSafe -Path $path `
					-Name "Disabled" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Dynamic Lighting: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'AccessibilityActivationSounds',
    'AccessibilityWarningSounds',
    'AeroShaking',
    'AppColorMode',
    'AppsLanguageSwitch',
    'BuildNumberOnDesktop',
    'DesktopRegistry',
    'EnhPointerPrecision',
    'NarratorAudioDucking',
    'PrtScnSnippingTool',
    'Set-DynamicLighting',
    'SoundDuckingPreference',
    'SpeechOneCoreVoiceActivation',
    'StartupSound',
    'TitleBarColor',
    'VisualFX'
)
Export-ModuleMember -Function $ExportedFunctions