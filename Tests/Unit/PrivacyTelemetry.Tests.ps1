Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


	$privacyDataPath = Join-Path $PSScriptRoot '../../Module/Data/PrivacyTelemetry.json'
	$basicPresetPath = Join-Path $PSScriptRoot '../../Module/Data/Presets/Basic.json'
	$balancedPresetPath = Join-Path $PSScriptRoot '../../Module/Data/Presets/Balanced.json'
	$advancedPresetPath = Join-Path $PSScriptRoot '../../Module/Data/Presets/Advanced.json'
	$filePath = Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.PrivacySettings.psm1'

	$script:PrivacyTelemetryData = Get-BaselineTestSourceText -Path $privacyDataPath | ConvertFrom-Json
	$script:BasicPreset = Get-BaselineTestSourceText -Path $basicPresetPath | ConvertFrom-Json
	$script:BalancedPreset = Get-BaselineTestSourceText -Path $balancedPresetPath | ConvertFrom-Json
	$script:AdvancedPreset = Get-BaselineTestSourceText -Path $advancedPresetPath | ConvertFrom-Json

	$ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
	$functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
	foreach ($fn in $functions) {
		if ($fn.Name -in @(
			'OnlineSpeechRecognition',
			'NarratorOnlineServices',
			'NarratorScriptingSupport',
			'InkingAndTypingPersonalization',
			'DeviceSearchHistory',
			'CloudContentSearch',
			'WorkplaceJoinMessages',
			'BitLockerAutoEncryption'
		)) {
			Invoke-Expression $fn.Extent.Text
		}
	}
}

Describe 'Privacy telemetry registry toggles' {
	BeforeEach {
		$script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
		$script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
		$script:newItemCalls = [System.Collections.Generic.List[string]]::new()
		$script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
		$script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()

		<#
		    .SYNOPSIS
		#>

		function Write-ConsoleStatus {
			param(
				[string]$Action,
				[string]$Status
			)
		}

		<#
		    .SYNOPSIS
		#>
		function LogInfo {
			param([string]$Message)
			[void]$script:loggedInfoMessages.Add($Message)
		}

		<#
		    .SYNOPSIS
		#>
		function LogError {
			param([string]$Message)
			[void]$script:loggedErrorMessages.Add($Message)
		}

		<#
		    .SYNOPSIS
		#>

		function Test-Path {
			param([string]$Path)
			return $false
		}

		<#
		    .SYNOPSIS
		#>
		function New-Item {
			param(
				[string]$Path,
				[switch]$Force,
				[object]$ErrorAction
			)

			[void]$script:newItemCalls.Add($Path)
		}

		<#
		    .SYNOPSIS
		#>

		function New-ItemProperty {
			param(
				[string]$Path,
				[string]$Name,
				[string]$PropertyType,
				[object]$Value,
				[switch]$Force,
				[object]$ErrorAction
			)

			[void]$script:newItemPropertyCalls.Add([pscustomobject]@{
				Path         = $Path
				Name         = $Name
				PropertyType = $PropertyType
				Value        = $Value
			})
		}

		<#
		    .SYNOPSIS
		#>

		function Remove-ItemProperty {
			param(
				[string]$Path,
				[object]$Name,
				[switch]$Force,
				[object]$ErrorAction
			)

			[void]$script:removedPropertyCalls.Add([pscustomobject]@{
				Path = $Path
				Name = $Name
			})
		}
	}

	AfterEach {
		Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
		Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
		Remove-Item Function:\LogError -ErrorAction SilentlyContinue
		Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
		Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
		Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
		Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
	}

	Describe 'OnlineSpeechRecognition' {
		It 'enables online speech recognition' {
			OnlineSpeechRecognition -Enable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'HasAccepted'
			$script:newItemPropertyCalls[0].Value | Should -Be 1
		}

		It 'disables online speech recognition' {
			OnlineSpeechRecognition -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'HasAccepted'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}

	Describe 'NarratorOnlineServices' {
		It 'enables Narrator online services by clearing the user value' {
			NarratorOnlineServices -Enable

			$script:removedPropertyCalls.Count | Should -Be 1
			$script:removedPropertyCalls[0].Path | Should -Be 'HKCU:\Software\Microsoft\Narrator\NoRoam'
			$script:removedPropertyCalls[0].Name | Should -Be 'OnlineServicesEnabled'
			$script:newItemCalls.Count | Should -Be 0
			$script:newItemPropertyCalls.Count | Should -Be 0
		}

		It 'disables Narrator online services' {
			NarratorOnlineServices -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Narrator\NoRoam'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'OnlineServicesEnabled'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}

	Describe 'NarratorScriptingSupport' {
		It 'enables Narrator scripting support by clearing the user value' {
			NarratorScriptingSupport -Enable

			$script:removedPropertyCalls.Count | Should -Be 1
			$script:removedPropertyCalls[0].Path | Should -Be 'HKCU:\Software\Microsoft\Narrator\NoRoam'
			$script:removedPropertyCalls[0].Name | Should -Be 'ScriptingEnabled'
			$script:newItemCalls.Count | Should -Be 0
			$script:newItemPropertyCalls.Count | Should -Be 0
		}

		It 'disables Narrator scripting support' {
			NarratorScriptingSupport -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Narrator\NoRoam'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'ScriptingEnabled'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}

	Describe 'InkingAndTypingPersonalization' {
		It 'enables inking and typing personalization' {
			InkingAndTypingPersonalization -Enable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'Value'
			$script:newItemPropertyCalls[0].Value | Should -Be 1
		}

		It 'disables inking and typing personalization' {
			InkingAndTypingPersonalization -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'Value'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}

	Describe 'DeviceSearchHistory' {
		It 'enables device search history by clearing the user value' {
			DeviceSearchHistory -Enable

			$script:removedPropertyCalls.Count | Should -Be 1
			$script:removedPropertyCalls[0].Path | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
			$script:removedPropertyCalls[0].Name | Should -Be 'IsDeviceSearchHistoryEnabled'
			$script:newItemCalls.Count | Should -Be 0
			$script:newItemPropertyCalls.Count | Should -Be 0
		}

		It 'disables device search history' {
			DeviceSearchHistory -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'IsDeviceSearchHistoryEnabled'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}

	Describe 'CloudContentSearch' {
		It 'enables cloud content search by clearing both user values' {
			CloudContentSearch -Enable

			$script:removedPropertyCalls.Count | Should -Be 2
			@($script:removedPropertyCalls.Name) | Should -Be @('IsMSACloudSearchEnabled', 'IsAADCloudSearchEnabled')
			@($script:removedPropertyCalls.Path) | Should -Be @(
				'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings',
				'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
			)
			$script:newItemCalls.Count | Should -Be 0
			$script:newItemPropertyCalls.Count | Should -Be 0
		}

		It 'disables cloud content search' {
			CloudContentSearch -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
			$script:newItemPropertyCalls.Count | Should -Be 2
			@($script:newItemPropertyCalls.Name) | Should -Be @('IsMSACloudSearchEnabled', 'IsAADCloudSearchEnabled')
			@($script:newItemPropertyCalls.Value) | Should -Be @(0, 0)
		}
	}

	Describe 'WorkplaceJoinMessages' {
		It 'enables workplace join message blocking for machine and user policy paths' {
			WorkplaceJoinMessages -Enable

			$script:newItemCalls.Count | Should -Be 2
			@($script:newItemCalls) | Should -Be @(
				'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin',
				'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
			)
			$script:newItemPropertyCalls.Count | Should -Be 2
			@($script:newItemPropertyCalls.Path) | Should -Be @(
				'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin',
				'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
			)
			@($script:newItemPropertyCalls.Name) | Should -Be @('BlockAADWorkplaceJoin', 'BlockAADWorkplaceJoin')
			@($script:newItemPropertyCalls.Value) | Should -Be @(1, 1)
		}

		It 'disables workplace join message blocking by clearing both policy values' {
			WorkplaceJoinMessages -Disable

			$script:removedPropertyCalls.Count | Should -Be 2
			@($script:removedPropertyCalls.Path) | Should -Be @(
				'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin',
				'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
			)
			@($script:removedPropertyCalls.Name) | Should -Be @('BlockAADWorkplaceJoin', 'BlockAADWorkplaceJoin')
			$script:newItemCalls.Count | Should -Be 0
			$script:newItemPropertyCalls.Count | Should -Be 0
		}
	}

	Describe 'BitLockerAutoEncryption' {
		It 'enables BitLocker auto encryption prevention' {
			BitLockerAutoEncryption -Enable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'PreventDeviceEncryption'
			$script:newItemPropertyCalls[0].Value | Should -Be 1
		}

		It 'disables BitLocker auto encryption prevention' {
			BitLockerAutoEncryption -Disable

			$script:newItemCalls.Count | Should -Be 1
			$script:newItemCalls[0] | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'
			$script:newItemPropertyCalls.Count | Should -Be 1
			$script:newItemPropertyCalls[0].Name | Should -Be 'PreventDeviceEncryption'
			$script:newItemPropertyCalls[0].Value | Should -Be 0
		}
	}
}

Describe 'Privacy telemetry metadata' {
	It 'contains the new privacy rows with the expected default states' {
		$expected = @(
			@{ Function = 'OnlineSpeechRecognition'; Name = 'Online Speech Recognition'; Default = $false; WinDefault = $true },
			@{ Function = 'NarratorOnlineServices'; Name = 'Narrator Online Services'; Default = $false; WinDefault = $true },
			@{ Function = 'NarratorScriptingSupport'; Name = 'Narrator Scripting Support'; Default = $false; WinDefault = $true },
			@{ Function = 'InkingAndTypingPersonalization'; Name = 'Inking and Typing Personalization'; Default = $false; WinDefault = $true },
			@{ Function = 'DeviceSearchHistory'; Name = 'Device Search History'; Default = $false; WinDefault = $true },
			@{ Function = 'CloudContentSearch'; Name = 'Cloud Content Search'; Default = $false; WinDefault = $true },
			@{ Function = 'WorkplaceJoinMessages'; Name = 'Block Workplace Join Messages'; Default = $true; WinDefault = $false },
			@{ Function = 'BitLockerAutoEncryption'; Name = 'Prevent BitLocker Auto Encryption'; Default = $true; WinDefault = $false }
		)

		foreach ($entry in $expected)
		{
			$match = @($script:PrivacyTelemetryData.Entries | Where-Object Function -eq $entry.Function)
			$match.Count | Should -Be 1
			$match[0].Name | Should -Be $entry.Name
			$match[0].Type | Should -Be 'Toggle'
			$match[0].Default | Should -Be $entry.Default
			$match[0].WinDefault | Should -Be $entry.WinDefault
			$match[0].SourceRegion | Should -Be 'PrivacyTelemetry'
		}
	}
}

Describe 'Privacy telemetry presets' {
	It 'include the new entries in the standard presets' {
		$expectedEntries = @(
			'OnlineSpeechRecognition -Disable',
			'NarratorOnlineServices -Disable',
			'NarratorScriptingSupport -Disable',
			'InkingAndTypingPersonalization -Disable',
			'DeviceSearchHistory -Disable',
			'CloudContentSearch -Disable',
			'WorkplaceJoinMessages -Enable',
			'BitLockerAutoEncryption -Enable'
		)

		foreach ($preset in @($script:BasicPreset, $script:BalancedPreset, $script:AdvancedPreset))
		{
			foreach ($entry in $expectedEntries)
			{
				@($preset.Entries) | Should -Contain $entry
			}
		}
	}
}
