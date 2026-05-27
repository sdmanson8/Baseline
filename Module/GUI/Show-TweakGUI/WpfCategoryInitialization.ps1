
# Purpose: WPF loading and category/index initialization.
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
	Add-Type -AssemblyName System.Windows.Forms, System.Drawing, WindowsFormsIntegration

	Ensure-SheenProgressBarType
	& $traceGuiStartup 'WPF assemblies ready'

	if (-not $Script:ExplicitPresetSelections) {
		$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}
	if (-not $Script:ExplicitPresetSelectionDefinitions) {
		$Script:ExplicitPresetSelectionDefinitions = @{}
	}

	$Script:GuiModuleBasePath = $null
	$Script:GuiPresetDirectoryPath = $null
	$Script:GuiLocalizationDirectoryPath = $null

	try { $Script:GuiModuleBasePath = $MyInvocation.MyCommand.Module.ModuleBase } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveModuleBase.ModuleBase' }
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent $PSCommandPath } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveModuleBase.PSCommandPath' }
	}
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveModuleBase.MyInvocationPath' }
	}
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveModuleBase.PSScriptRoot' }
	}
		. (Join-Path $PSScriptRoot 'ModulePathResolution.ps1')

	if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		$Script:GuiPresetDirectoryPath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Data\Presets'
		$Script:GuiLocalizationDirectoryPath = Resolve-BaselineLocalizationDirectory -BasePath $Script:GuiModuleBasePath
	}

	# Primary category tabs (top tier)
	$Script:PrimaryCategories = [ordered]@{
		"Initial Setup"        = @()
		"Privacy & Telemetry"  = @()
		"Security"             = @("Security", "OS Hardening")
		"System"               = @("System", "System Tweaks", "Start Menu", "Start Menu Apps")
		"Customizations"       = @()
		"UI & Personalization" = @("UI & Personalization", "Taskbar", "Taskbar Clock", "Cursors")
		"UWP Apps"             = @("UWP Apps", "OneDrive")
		"Gaming"               = @()
		"Context Menu"         = @()
	}
	$PrimaryCategories = $Script:PrimaryCategories

	# Map manifest categories to primary tabs
	$Script:CategoryToPrimary = @{}
	$CategoryToPrimary = $Script:CategoryToPrimary
		. (Join-Path $PSScriptRoot 'CategoryPathMapping.ps1')
	$Script:UpdatesPrimaryTabFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		. (Join-Path $PSScriptRoot 'AvailabilityStateOverrides.ps1')

	# Ensure all manifest categories map somewhere
	foreach ($t in $Script:TweakManifest)
	{
		if (-not $Script:CategoryToPrimary.ContainsKey($t.Category))
		{
			$Script:CategoryToPrimary[$t.Category] = $t.Category
		}
	}

	# Pre-compute search haystacks once so Test-TweakMatchesCurrentFilters never
	# rebuilds them on every keystroke. All fields are static tweak metadata.
	# Also index tweak rows by primary tab so filter population can avoid
	# scanning the full manifest for normal tab-scoped filter updates.
	$Script:TweakSearchHaystacks = @{}
	$Script:TweakIndicesByPrimaryTab = @{}
		. (Join-Path $PSScriptRoot 'PrimaryTabTweakIndex.ps1')
	Remove-Variable -Name __hi, __t, __owning, __sb, __p, __tags -ErrorAction SilentlyContinue
	& $traceGuiStartup 'Search indexes ready'

	. (Join-Path $Script:GuiExtractedRoot 'ThemeManagement.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'IconRegistry.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'IconFactory.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'TweakAnalysis.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ComponentFactory.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'FilteringLogic.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ApplicationsView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'SystemScan.ps1')
	& $traceGuiStartup 'Phase 2 GUI scripts loaded'


