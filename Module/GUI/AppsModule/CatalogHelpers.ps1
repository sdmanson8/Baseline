
function Get-ApplicationEntityType
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry
	)

	$validEntityTypes = @('winget', 'choco', 'store', 'direct', 'command', 'uwp', 'feature', 'system', 'placeholder')

	if ($Entry -and $Entry.PSObject.Properties['EntityType'])
	{
		$explicitType = [string]$Entry.EntityType
		if (-not [string]::IsNullOrWhiteSpace($explicitType))
		{
			$normalizedType = $explicitType.Trim().ToLowerInvariant()
			if ($validEntityTypes -contains $normalizedType)
			{
				return $normalizedType
			}
		}
	}

	if ($Entry -and $Entry.PSObject.Properties['Type'])
	{
		$explicitType = [string]$Entry.Type
		if (-not [string]::IsNullOrWhiteSpace($explicitType))
		{
			$normalizedType = $explicitType.Trim().ToLowerInvariant()
			if ($validEntityTypes -contains $normalizedType)
			{
				return $normalizedType
			}
		}
	}

	$topLevelWinGetId = $null
	$topLevelChocoId = $null
	try
	{
		if ($Entry.PSObject.Properties['WinGetId'])
		{
			$topLevelWinGetId = [string]$Entry.WinGetId
		}
		if ($Entry.PSObject.Properties['ChocoId'])
		{
			$topLevelChocoId = [string]$Entry.ChocoId
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationEntityType:catch51' -Severity Debug }

		$null = $_
	}

	if (-not [string]::IsNullOrWhiteSpace($topLevelWinGetId))
	{
		return 'winget'
	}

	if (-not [string]::IsNullOrWhiteSpace($topLevelChocoId))
	{
		return 'choco'
	}

	$winGetId = $null
	$chocoId = $null
	try
	{
		if ($Entry.ExtraArgs)
		{
			if ($Entry.ExtraArgs.PSObject.Properties['WinGetId'])
			{
				$winGetId = [string]$Entry.ExtraArgs.WinGetId
			}
			if ($Entry.ExtraArgs.PSObject.Properties['ChocoId'])
			{
				$chocoId = [string]$Entry.ExtraArgs.ChocoId
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationEntityType:catch82' -Severity Debug }

		$null = $_
	}

	if (-not [string]::IsNullOrWhiteSpace($winGetId))
	{
		return 'winget'
	}

	if (-not [string]::IsNullOrWhiteSpace($chocoId))
	{
		return 'choco'
	}

	return 'placeholder'
}

<#
    .SYNOPSIS
#>

function Get-AppsCatalogItemsBySearchStatusAndSourceFilters
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[string]$SearchQuery = $null,
		[string]$Category = $null,
		[switch]$SkipPackageManagerAvailabilityRefresh
	)

	$hasExplicitCategory = -not [string]::IsNullOrWhiteSpace([string]$Category)
	$previousCatalogVariable = $null
	$previousCategoryVariable = $null
	if ($hasExplicitCategory)
	{
		$previousCatalogVariable = Get-Variable -Name 'BaselineApplicationsCatalog' -Scope Script -ErrorAction SilentlyContinue
		$previousCategoryVariable = Get-Variable -Name 'BaselineApplicationsCatalogCategory' -Scope Script -ErrorAction SilentlyContinue
	}

	try
	{
		$catalog = if ($hasExplicitCategory)
		{
			@(Get-BaselineApplicationsCatalog -Category $Category -SkipPackageManagerAvailabilityRefresh:$SkipPackageManagerAvailabilityRefresh)
		}
		else
		{
			@(Get-BaselineApplicationsCatalog -SkipPackageManagerAvailabilityRefresh:$SkipPackageManagerAvailabilityRefresh)
		}
	}
	finally
	{
		if ($hasExplicitCategory)
		{
			if ($previousCatalogVariable)
			{
				$Script:BaselineApplicationsCatalog = $previousCatalogVariable.Value
			}
			else
			{
				Remove-Variable -Name 'BaselineApplicationsCatalog' -Scope Script -ErrorAction SilentlyContinue
			}

			if ($previousCategoryVariable)
			{
				$Script:BaselineApplicationsCatalogCategory = $previousCategoryVariable.Value
			}
			else
			{
				Remove-Variable -Name 'BaselineApplicationsCatalogCategory' -Scope Script -ErrorAction SilentlyContinue
			}
		}
	}

	if ($catalog.Count -eq 0)
	{
		return @()
	}

	$activeSearchQuery = if ([string]::IsNullOrWhiteSpace([string]$SearchQuery)) { '' } else { [string]$SearchQuery.Trim() }
	$searchTerms = @()
	if (-not [string]::IsNullOrWhiteSpace($activeSearchQuery))
	{
		$searchTerms = @(
			$activeSearchQuery -split '\s+' |
				Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
				ForEach-Object { [string]$_.Trim().ToLowerInvariant() }
		)
	}

	$activeStatusFilter = if ([string]::IsNullOrWhiteSpace([string]$Script:AppsStatusFilter)) { 'All' } else { [string]$Script:AppsStatusFilter.Trim() }
	$installedWingetCache = $null
	$installedChocolateyCache = $null
	$wingetUpdateCache = $null
	$chocolateyUpdateCache = $null
	if ($activeStatusFilter -ne 'All')
	{
		try
		{
			$installedCacheSnapshot = Get-ApplicationCacheSnapshot -CacheState $Script:InstalledAppsCache
			$installedWingetCache = $installedCacheSnapshot.WinGet
			$installedChocolateyCache = $installedCacheSnapshot.Chocolatey
			$wingetUpdateCache = $installedCacheSnapshot.WinGetUpdates
			$chocolateyUpdateCache = $installedCacheSnapshot.ChocolateyUpdates
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Get-ApplicationCacheSnapshot.CacheSnapshot' }
	}

	$activeSourceFilter = if ([string]::IsNullOrWhiteSpace([string]$Script:AppsSourceFilter)) { 'All' } else { [string]$Script:AppsSourceFilter.Trim() }

	$matchesSearch = {
		param($entry)
		if ($searchTerms.Count -eq 0) { return $true }
		$searchIndex = if ((Test-GuiObjectField -Object $entry -FieldName 'SearchIndex')) { [string]$entry.SearchIndex } else { $null }
		if ([string]::IsNullOrWhiteSpace($searchIndex)) { return $false }
		foreach ($term in @($searchTerms))
		{
			if ($searchIndex.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
		}
		return $true
	}

	$matchesStatus = {
		param($entry)
		if ($activeStatusFilter -eq 'All') { return $true }
		$entryState = Get-ApplicationExecutionState -Entry $entry -WinGetInstalledCache $installedWingetCache -ChocolateyInstalledCache $installedChocolateyCache -WinGetUpdateCache $wingetUpdateCache -ChocolateyUpdateCache $chocolateyUpdateCache -PreferredSource $Script:AppsPackageSourcePreference
		switch ($activeStatusFilter)
		{
			'Installed'       { return [bool]$entryState.IsInstalled }
			'NotInstalled'    { return -not [bool]$entryState.IsInstalled }
			'UpdateAvailable' { return [bool]$entryState.UpdateAvailable }
			default           { return $true }
		}
	}

	$matchesSource = {
		param($entry)
		if ($activeSourceFilter -eq 'All') { return $true }
		$entryWinGetId = $null
		$entryChocoId = $null
		if ($entry.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.WinGetId))
		{
			$entryWinGetId = [string]$entry.WinGetId
		}
		elseif ($entry.ExtraArgs -and $entry.ExtraArgs.PSObject.Properties['WinGetId'])
		{
			$entryWinGetId = [string]$entry.ExtraArgs.WinGetId
		}
		if ($entry.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.ChocoId))
		{
			$entryChocoId = [string]$entry.ChocoId
		}
		elseif ($entry.ExtraArgs -and $entry.ExtraArgs.PSObject.Properties['ChocoId'])
		{
			$entryChocoId = [string]$entry.ExtraArgs.ChocoId
		}
		switch ($activeSourceFilter)
		{
			'winget' { return -not [string]::IsNullOrWhiteSpace($entryWinGetId) }
			'choco'  { return -not [string]::IsNullOrWhiteSpace($entryChocoId) }
			default  { return $true }
		}
	}

	return @(
		$catalog |
			Where-Object {
				(& $matchesSearch $_) -and (& $matchesStatus $_) -and (& $matchesSource $_)
			}
	)
}

<#
    .SYNOPSIS
#>

function Test-ApplicationExecutionSupport
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry
	)

	if ($Entry -and $Entry.PSObject.Properties['SupportsExecution'] -and -not [bool]$Entry.SupportsExecution)
	{
		return $false
	}

	$entityType = Get-ApplicationEntityType -Entry $Entry
	$winGetId = $null
	$chocoId = $null
	$storeUri = $null
	$directUrl = $null
	$command = $null

	try
	{
		if ($Entry.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.WinGetId))
		{
			$winGetId = [string]$Entry.WinGetId
		}
		elseif ($Entry.ExtraArgs -and $Entry.ExtraArgs.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.WinGetId))
		{
			$winGetId = [string]$Entry.ExtraArgs.WinGetId
		}

		if ($Entry.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ChocoId))
		{
			$chocoId = [string]$Entry.ChocoId
		}
		elseif ($Entry.ExtraArgs -and $Entry.ExtraArgs.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.ChocoId))
		{
			$chocoId = [string]$Entry.ExtraArgs.ChocoId
		}

		if ($Entry.ExtraArgs)
		{
			if ($Entry.ExtraArgs.PSObject.Properties['StoreUri'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.StoreUri))
			{
				$storeUri = [string]$Entry.ExtraArgs.StoreUri
			}
			if ($Entry.ExtraArgs.PSObject.Properties['DirectUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.DirectUrl))
			{
				$directUrl = [string]$Entry.ExtraArgs.DirectUrl
			}
			if ($Entry.ExtraArgs.PSObject.Properties['Command'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.Command))
			{
				$command = [string]$Entry.ExtraArgs.Command
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Test-ApplicationExecutionSupport:catch315' -Severity Debug }

		$null = $_
	}

	switch ($entityType)
	{
		'store' { return (-not [string]::IsNullOrWhiteSpace($storeUri)) }
		'direct' { return (-not [string]::IsNullOrWhiteSpace($directUrl)) }
		'command' { return (-not [string]::IsNullOrWhiteSpace($command)) }
		'uwp' { return $false }
		'feature' { return $false }
		'system' { return $false }
		'placeholder' { return $false }
		default
		{
			if (-not [string]::IsNullOrWhiteSpace($storeUri) -or -not [string]::IsNullOrWhiteSpace($directUrl) -or -not [string]::IsNullOrWhiteSpace($command))
			{
				return $true
			}

			if (-not [string]::IsNullOrWhiteSpace($chocoId))
			{
				return $true
			}

			if (-not [string]::IsNullOrWhiteSpace($winGetId))
			{
				if (Get-Command -Name 'Test-WinGetAvailable' -CommandType Function -ErrorAction SilentlyContinue)
				{
					try
					{
						return [bool](Test-WinGetAvailable)
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Test-ApplicationExecutionSupport:catch349' -Severity Debug }

						return $false
					}
				}

				return $true
			}

			return $false
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-ApplicationCatalogIdentityKey
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry
	)

	$entityType = Get-ApplicationEntityType -Entry $Entry
	$topLevelWinGetId = $null
	$topLevelChocoId = $null
	try
	{
		if ($Entry.PSObject.Properties['WinGetId'])
		{
			$topLevelWinGetId = [string]$Entry.WinGetId
		}
		if ($Entry.PSObject.Properties['ChocoId'])
		{
			$topLevelChocoId = [string]$Entry.ChocoId
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationCatalogIdentityKey:catch389' -Severity Debug }

		$null = $_
	}

	if (-not [string]::IsNullOrWhiteSpace($topLevelWinGetId))
	{
		return ("winget:{0}" -f [string]$topLevelWinGetId.Trim().ToLowerInvariant())
	}

	if (-not [string]::IsNullOrWhiteSpace($topLevelChocoId))
	{
		return ("choco:{0}" -f [string]$topLevelChocoId.Trim().ToLowerInvariant())
	}

	if ($Entry.ExtraArgs)
	{
		try
		{
			if ($Entry.ExtraArgs.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.WinGetId))
			{
				return ("winget:{0}" -f [string]$Entry.ExtraArgs.WinGetId.Trim().ToLowerInvariant())
			}
			if ($Entry.ExtraArgs.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.ChocoId))
			{
				return ("choco:{0}" -f [string]$Entry.ExtraArgs.ChocoId.Trim().ToLowerInvariant())
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationCatalogIdentityKey:catch417' -Severity Debug }

			$null = $_
		}
	}

	$name = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.Name)) { [string]$Entry.Name.Trim().ToLowerInvariant() } else { '<unknown>' }
	$subCategory = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.SubCategory)) { [string]$Entry.SubCategory.Trim().ToLowerInvariant() } else { '<none>' }
	return ("{0}:{1}:{2}" -f $entityType, $subCategory, $name)
}

<#
    .SYNOPSIS
#>

function Get-ApplicationExecutionState
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry,

		[hashtable]$WinGetInstalledCache = @{},

		[hashtable]$ChocolateyInstalledCache = @{},

		[hashtable]$WinGetUpdateCache = @{},

		[hashtable]$ChocolateyUpdateCache = @{},

		[string]$PreferredSource = $null
	)

	$entityType = Get-ApplicationEntityType -Entry $Entry
	$selectionKey = Get-ApplicationCatalogIdentityKey -Entry $Entry
	$supportsExecution = Test-ApplicationExecutionSupport -Entry $Entry
	$normalizedPreferredSource = if ([string]::IsNullOrWhiteSpace([string]$PreferredSource))
	{
		$null
	}
	else
	{
		switch ([string]$PreferredSource.Trim().ToLowerInvariant())
		{
			'winget' { 'winget' }
			'choco' { 'choco' }
			'chocolatey' { 'choco' }
			default { $null }
		}
	}
	$sourceForState = $null
	$winGetId = $null
	$chocoId = $null
	$storeUri = $null
	$directUrl = $null
	$command = $null
	$packageId = $null
	$updateKey = $null
	$isInstalled = $false
	$hasUpdateAvailable = $false

	if ($Entry.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.WinGetId))
	{
		$winGetId = [string]$Entry.WinGetId
	}
	elseif ($Entry.ExtraArgs -and $Entry.ExtraArgs.PSObject.Properties['WinGetId'])
	{
		$winGetId = [string]$Entry.ExtraArgs.WinGetId
	}

	if ($Entry.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ChocoId))
	{
		$chocoId = [string]$Entry.ChocoId
	}
	elseif ($Entry.ExtraArgs -and $Entry.ExtraArgs.PSObject.Properties['ChocoId'])
	{
		$chocoId = [string]$Entry.ExtraArgs.ChocoId
	}

	if ($Entry.ExtraArgs)
	{
		if ($Entry.ExtraArgs.PSObject.Properties['StoreUri'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.StoreUri))
		{
			$storeUri = [string]$Entry.ExtraArgs.StoreUri
		}
		if ($Entry.ExtraArgs.PSObject.Properties['DirectUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.DirectUrl))
		{
			$directUrl = [string]$Entry.ExtraArgs.DirectUrl
		}
		if ($Entry.ExtraArgs.PSObject.Properties['Command'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.Command))
		{
			$command = [string]$Entry.ExtraArgs.Command
		}
	}

	$wingetAvailable = $true
	if (-not [string]::IsNullOrWhiteSpace($winGetId) -and (Get-Command -Name 'Test-WinGetAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try
		{
			$wingetAvailable = [bool](Test-WinGetAvailable)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationExecutionState:catch519' -Severity Debug }

			$wingetAvailable = $false
		}
	}
	$chocolateyAvailable = $true
	if (-not [string]::IsNullOrWhiteSpace($chocoId) -and (Get-Command -Name 'Test-ChocolateyAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try
		{
			$chocolateyAvailable = [bool](Test-ChocolateyAvailable)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationExecutionState:catch531' -Severity Debug }

			$chocolateyAvailable = $false
		}
	}

	if ($normalizedPreferredSource -eq 'winget' -and -not [string]::IsNullOrWhiteSpace($winGetId))
	{
		$sourceForState = 'winget'
	}
	elseif ($normalizedPreferredSource -eq 'choco' -and -not [string]::IsNullOrWhiteSpace($chocoId))
	{
		$sourceForState = 'choco'
	}
	elseif ($entityType -eq 'winget' -and -not [string]::IsNullOrWhiteSpace($winGetId))
	{
		$sourceForState = 'winget'
	}
	elseif ($entityType -eq 'choco' -and -not [string]::IsNullOrWhiteSpace($chocoId))
	{
		$sourceForState = 'choco'
	}
	elseif ($entityType -eq 'store' -and -not [string]::IsNullOrWhiteSpace($storeUri))
	{
		$sourceForState = 'store'
	}
	elseif ($entityType -eq 'direct' -and -not [string]::IsNullOrWhiteSpace($directUrl))
	{
		$sourceForState = 'direct'
	}
	elseif ($entityType -eq 'command' -and -not [string]::IsNullOrWhiteSpace($command))
	{
		$sourceForState = 'command'
	}
	elseif (-not [string]::IsNullOrWhiteSpace($winGetId))
	{
		$sourceForState = 'winget'
	}
	elseif (-not [string]::IsNullOrWhiteSpace($chocoId))
	{
		$sourceForState = 'choco'
	}
	else
	{
		$sourceForState = $entityType
	}

	switch ($sourceForState)
	{
		'winget'
		{
			$packageId = $winGetId
			if (-not [string]::IsNullOrWhiteSpace($packageId))
			{
				if (-not $wingetAvailable)
				{
					if (-not [string]::IsNullOrWhiteSpace($chocoId) -and $chocolateyAvailable)
					{
						$sourceForState = 'choco'
						$packageId = $chocoId
						$isInstalled = [bool](Test-ApplicationPackageIdInCache -PackageId $packageId -Cache $ChocolateyInstalledCache)
						$updateKey = [string]$packageId
						$hasUpdateAvailable = $isInstalled -and [bool](Test-ApplicationPackageIdInCache -PackageId $updateKey -Cache $ChocolateyUpdateCache)
					}
					else
					{
						$sourceForState = 'unsupported'
						$packageId = $null
						$supportsExecution = $false
					}
				}
				else
				{
					$isInstalled = [bool](Test-ApplicationPackageIdInCache -PackageId $packageId -Cache $WinGetInstalledCache)
					$updateKey = [string]$packageId
					$hasUpdateAvailable = $isInstalled -and [bool](Test-ApplicationPackageIdInCache -PackageId $updateKey -Cache $WinGetUpdateCache)
				}
			}
			else
			{
				$supportsExecution = $false
			}
		}
		'choco'
		{
			$packageId = $chocoId
			if (-not [string]::IsNullOrWhiteSpace($packageId))
			{
				$isInstalled = [bool](Test-ApplicationPackageIdInCache -PackageId $packageId -Cache $ChocolateyInstalledCache)
				$updateKey = [string]$packageId
				$hasUpdateAvailable = $isInstalled -and [bool](Test-ApplicationPackageIdInCache -PackageId $updateKey -Cache $ChocolateyUpdateCache)
				if (-not $chocolateyAvailable)
				{
					if (-not [string]::IsNullOrWhiteSpace($winGetId) -and $wingetAvailable)
					{
						$sourceForState = 'winget'
						$packageId = $winGetId
						$isInstalled = [bool](Test-ApplicationPackageIdInCache -PackageId $packageId -Cache $WinGetInstalledCache)
						$updateKey = [string]$packageId
						$hasUpdateAvailable = $isInstalled -and [bool](Test-ApplicationPackageIdInCache -PackageId $updateKey -Cache $WinGetUpdateCache)
					}
					else
					{
						$sourceForState = 'unsupported'
						$packageId = $null
						$isInstalled = $false
						$hasUpdateAvailable = $false
						$supportsExecution = $false
					}
				}
			}
			else
			{
				$sourceForState = 'unsupported'
				$packageId = $null
				$supportsExecution = $false
			}
		}
		'store'
		{
			$packageId = $storeUri
			if (-not [string]::IsNullOrWhiteSpace($packageId))
			{
				$supportsExecution = [bool]$supportsExecution
			}
			else
			{
				$supportsExecution = $false
			}
		}
		'direct'
		{
			$packageId = $directUrl
			if (-not [string]::IsNullOrWhiteSpace($packageId))
			{
				$supportsExecution = [bool]$supportsExecution
			}
			else
			{
				$supportsExecution = $false
			}
		}
		'command'
		{
			$packageId = $command
			if (-not [string]::IsNullOrWhiteSpace($packageId))
			{
				$supportsExecution = [bool]$supportsExecution
			}
			else
			{
				$supportsExecution = $false
			}
		}
		default
		{
			$supportsExecution = $false
			$isInstalled = $false
			$hasUpdateAvailable = $false
		}
	}

	$state = if (-not $supportsExecution)
	{
		'Unsupported'
	}
	elseif ($hasUpdateAvailable)
	{
		'Update available'
	}
	elseif ($isInstalled)
	{
		'Installed'
	}
	else
	{
		'Not installed'
	}

	$primaryAction = if (-not $supportsExecution)
	{
		$null
	}
	elseif ($hasUpdateAvailable)
	{
		'Update'
	}
	elseif ($isInstalled)
	{
		'Uninstall'
	}
	else
	{
		'Install'
	}

	$route = $null
	if ($supportsExecution -and (Get-Command -Name 'Resolve-ApplicationExecutionRoute' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try
		{
			$route = Resolve-ApplicationExecutionRoute -Application $Entry -PreferredSource $PreferredSource -Action $(if ([string]::IsNullOrWhiteSpace($primaryAction)) { 'Install' } else { $primaryAction })
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-ApplicationExecutionState:catch734' -Severity Debug }

			$route = $null
		}
	}

	return [pscustomobject]@{
		SelectionKey = $selectionKey
		EntityType = $entityType
		SupportsExecution = [bool]$supportsExecution
		State = $state
		IsInstalled = [bool]$isInstalled
		UpdateAvailable = [bool]$hasUpdateAvailable
		PackageId = $packageId
		PreferredSource = if ($route -and $route.PSObject.Properties['PreferredSource']) { [string]$route.PreferredSource } else { $normalizedPreferredSource }
		SelectedSource = if ($route -and $route.PSObject.Properties['SelectedSource']) { [string]$route.SelectedSource } else { $sourceForState }
		AvailableSources = if ($route -and $route.PSObject.Properties['AvailableSources']) { @($route.AvailableSources) } else { @() }
		Route = if ($route -and $route.PSObject.Properties['Route']) { [string]$route.Route } else { $sourceForState }
		Action = $primaryAction
	}
}

<#
    .SYNOPSIS
#>

function Get-ApplicationCacheSnapshot
{
	[CmdletBinding()]
	param (
		[object]$CacheState
	)

	$snapshot = [pscustomobject]@{
		WinGet = @{}
		Chocolatey = @{}
		WinGetUpdates = @{}
		ChocolateyUpdates = @{}
	}

	if ($CacheState -is [hashtable])
	{
		$snapshot.WinGet = $CacheState
		return $snapshot
	}

	if ($CacheState -and $CacheState.PSObject.Properties['WinGet'])
	{
		if ($CacheState.WinGet -is [hashtable])
		{
			$snapshot.WinGet = $CacheState.WinGet
		}
		if ($CacheState.PSObject.Properties['Chocolatey'] -and ($CacheState.Chocolatey -is [hashtable]))
		{
			$snapshot.Chocolatey = $CacheState.Chocolatey
		}
		if ($CacheState.PSObject.Properties['WinGetUpdates'] -and ($CacheState.WinGetUpdates -is [hashtable]))
		{
			$snapshot.WinGetUpdates = $CacheState.WinGetUpdates
		}
		if ($CacheState.PSObject.Properties['ChocolateyUpdates'] -and ($CacheState.ChocolateyUpdates -is [hashtable]))
		{
			$snapshot.ChocolateyUpdates = $CacheState.ChocolateyUpdates
		}
	}

	return $snapshot
}

<#
    .SYNOPSIS
#>

function Get-AppsDefaultCatalogCategory
{
	[CmdletBinding()]
	param ()

	return 'Browsers'
}

function Resolve-AppsCatalogCategory
{
	[CmdletBinding()]
	param (
		[string]$Category = $null
	)

	$resolved = if ([string]::IsNullOrWhiteSpace([string]$Category)) { [string]$Script:AppsCategoryFilter } else { [string]$Category }
	if ([string]::IsNullOrWhiteSpace([string]$resolved) -or $resolved.Trim() -eq 'All')
	{
		return (Get-AppsDefaultCatalogCategory)
	}

	return [string]$resolved.Trim()
}

function Get-AppsCatalogCandidateDirectories
{
	[CmdletBinding()]
	param ()

	$candidateCatalogDirectories = [System.Collections.Generic.List[string]]::new()
	$candidateModuleRoots = [System.Collections.Generic.List[string]]::new()
	$addCandidateModuleRoot = {
		param ([string]$Path)

		if ([string]::IsNullOrWhiteSpace([string]$Path))
		{
			return
		}

		try
		{
			[void]$candidateModuleRoots.Add([System.IO.Path]::GetFullPath([string]$Path))
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-AppsCatalogCandidateDirectories:catch850' -Severity Debug }

			$null = $_
		}
	}.GetNewClosure()

	foreach ($basePath in @($Script:GuiModuleBasePath))
	{
		if ([string]::IsNullOrWhiteSpace([string]$basePath))
		{
			continue
		}

		try
		{
			& $addCandidateModuleRoot $basePath

			$basePathLeaf = Split-Path -Path $basePath -Leaf
			if (($basePathLeaf -ieq 'Regions') -or ($basePathLeaf -ieq 'GUI'))
			{
				$moduleRoot = Split-Path -Path $basePath -Parent
				if (-not [string]::IsNullOrWhiteSpace([string]$moduleRoot))
				{
					& $addCandidateModuleRoot $moduleRoot
				}
			}
			else
			{
				$parentPath = Split-Path -Path $basePath -Parent
				if (-not [string]::IsNullOrWhiteSpace([string]$parentPath) -and ((Split-Path -Path $parentPath -Leaf) -ieq 'GUI'))
				{
					$moduleRoot = Split-Path -Path $parentPath -Parent
					if (-not [string]::IsNullOrWhiteSpace([string]$moduleRoot))
					{
						& $addCandidateModuleRoot $moduleRoot
					}
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-AppsCatalogCandidateDirectories:catch889' -Severity Debug }

			$null = $_
		}
	}

	foreach ($moduleRoot in @($candidateModuleRoots | Select-Object -Unique))
	{
		try
		{
			[void]$candidateCatalogDirectories.Add((Join-Path -Path $moduleRoot -ChildPath 'Data\AppsCategory'))
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-AppsCatalogCandidateDirectories:catch901' -Severity Debug }

			$null = $_
		}
	}

	return @($candidateCatalogDirectories | Select-Object -Unique)
}

function Get-AppsCatalogCategoryNames
{
	[CmdletBinding()]
	param ()

	foreach ($candidateDirectory in @(Get-AppsCatalogCandidateDirectories))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidateDirectory) -or -not (Test-Path -LiteralPath $candidateDirectory -PathType Container))
		{
			continue
		}

		$names = @(
			Get-ChildItem -LiteralPath $candidateDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue |
				ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
				Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
				Sort-Object -Unique
		)
		if ($names.Count -gt 0)
		{
			$defaultCategory = Get-AppsDefaultCatalogCategory
			return @(
				$names | Where-Object { [string]$_ -eq $defaultCategory }
				$names | Where-Object { [string]$_ -ne $defaultCategory }
			)
		}
	}

	return @()
}

function Get-AppsCatalogFilesForCategory
{
	[CmdletBinding()]
	param (
		[string]$Category = $null
	)

	$resolvedCategory = Resolve-AppsCatalogCategory -Category $Category
	foreach ($candidateDirectory in @(Get-AppsCatalogCandidateDirectories))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidateDirectory) -or -not (Test-Path -LiteralPath $candidateDirectory -PathType Container))
		{
			continue
		}

		$categoryFile = Join-Path -Path $candidateDirectory -ChildPath ('{0}.json' -f $resolvedCategory)
		if (Test-Path -LiteralPath $categoryFile -PathType Leaf)
		{
			return @(Get-Item -LiteralPath $categoryFile -ErrorAction Stop)
		}
	}

	return @()
}

function Get-LoadedBaselineApplicationsCatalog
{
	[CmdletBinding()]
	param ()

	$catalog = [System.Collections.Generic.List[object]]::new()
	$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	if ((Get-Variable -Name 'BaselineApplicationsCatalogByCategory' -Scope Script -ErrorAction SilentlyContinue) -and ($Script:BaselineApplicationsCatalogByCategory -is [hashtable]))
	{
		foreach ($categoryCatalog in @($Script:BaselineApplicationsCatalogByCategory.Values))
		{
			foreach ($entry in @($categoryCatalog))
			{
				if (-not $entry) { continue }
				$key = Get-ApplicationCatalogIdentityKey -Entry $entry
				if (-not [string]::IsNullOrWhiteSpace([string]$key) -and $seen.Add([string]$key))
				{
					[void]$catalog.Add($entry)
				}
			}
		}
	}

	if ($catalog.Count -eq 0 -and $Script:BaselineApplicationsCatalog)
	{
		foreach ($entry in @($Script:BaselineApplicationsCatalog))
		{
			if (-not $entry) { continue }
			$key = Get-ApplicationCatalogIdentityKey -Entry $entry
			if (-not [string]::IsNullOrWhiteSpace([string]$key) -and $seen.Add([string]$key))
			{
				[void]$catalog.Add($entry)
			}
		}
	}

	return @($catalog)
}

function Get-BaselineApplicationsCatalog
{
	[CmdletBinding()]
	param (
		[switch]$Force,
		[string]$Category = $null,
		[switch]$SkipPackageManagerAvailabilityRefresh
	)

	if (-not $SkipPackageManagerAvailabilityRefresh -and (Get-Command -Name 'Test-WinGetAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try { $null = Test-WinGetAvailable -Refresh } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Get-BaselineApplicationsCatalog.TestWinGetAvailable' }
	}
	if (-not $SkipPackageManagerAvailabilityRefresh -and (Get-Command -Name 'Test-ChocolateyAvailable' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try { $null = Test-ChocolateyAvailable -Refresh } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Get-BaselineApplicationsCatalog.TestChocolateyAvailable' }
	}

	$effectiveCategory = Resolve-AppsCatalogCategory -Category $Category
	if (-not (Get-Variable -Name 'BaselineApplicationsCatalogByCategory' -Scope Script -ErrorAction SilentlyContinue) -or -not ($Script:BaselineApplicationsCatalogByCategory -is [hashtable]))
	{
		$Script:BaselineApplicationsCatalogByCategory = @{}
	}
	if ($Force)
	{
		$Script:BaselineApplicationsCatalogByCategory.Clear()
	}
	if (-not $Force -and $Script:BaselineApplicationsCatalogByCategory.ContainsKey($effectiveCategory))
	{
		$Script:BaselineApplicationsCatalog = @($Script:BaselineApplicationsCatalogByCategory[$effectiveCategory])
		$Script:BaselineApplicationsCatalogCategory = $effectiveCategory
		return $Script:BaselineApplicationsCatalog
	}

	$catalogFiles = @(Get-AppsCatalogFilesForCategory -Category $effectiveCategory)

	if (-not $catalogFiles -or $catalogFiles.Count -eq 0)
	{
		LogError (Get-UxBilingualLocalizedString -Key 'GuiLogApplicationsCatalogNotFound' -Fallback 'Applications catalog not found: {0}' -FormatArgs @($effectiveCategory))
		$Script:BaselineApplicationsCatalog = @()
		$Script:BaselineApplicationsCatalogCategory = $effectiveCategory
		$Script:BaselineApplicationsCatalogByCategory[$effectiveCategory] = @()
		return $Script:BaselineApplicationsCatalog
	}

	try
	{
		$catalogFilesJson = foreach ($catalogFile in $catalogFiles)
		{
			[pscustomobject]@{
				Path = [string]$catalogFile.FullName
				Json = (Get-Content -LiteralPath $catalogFile.FullName -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop)
			}
		}
	}
	catch
	{
		LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogApplicationsCatalogLoadFailed' -Fallback 'Failed to load applications catalog'))
		$Script:BaselineApplicationsCatalog = @()
		return $Script:BaselineApplicationsCatalog
	}

	$catalogFilesJson = @($catalogFilesJson)

	# Wire user-added catalog entries from %LOCALAPPDATA%\Baseline\UserApps\*.json
	# into the External Software tab. Built-ins always win on conflict
	# (same Name / WinGetId / ChocoId) per the Merge- helper contract.
	try
	{
		if (Get-Command -Name 'Get-BaselineUserAppEntries' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$userAppsResult = Get-BaselineUserAppEntries
			if ($userAppsResult)
			{
				foreach ($warning in @($userAppsResult.Warnings))
				{
					if (-not [string]::IsNullOrWhiteSpace([string]$warning)) { LogWarning $warning }
				}

				$userEntriesNormalized = @()
				if (@($userAppsResult.Entries).Count -gt 0)
				{
					$userEntriesNormalized = @($userAppsResult.Entries | ForEach-Object {
						# Inject safe defaults so the projection below produces
						# sensible values (Risk=Low, Safe=true) for user-supplied
						# entries that don't carry the manifest metadata fields.
						$bag = [ordered]@{}
						foreach ($prop in $_.PSObject.Properties) { $bag[$prop.Name] = $prop.Value }
						if (-not $bag.Contains('Risk') -or [string]::IsNullOrWhiteSpace([string]$bag['Risk'])) { $bag['Risk'] = 'Low' }
						if (-not $bag.Contains('Safe')) { $bag['Safe'] = $true }
						if (-not $bag.Contains('RequiresRestart')) { $bag['RequiresRestart'] = $false }
						if (-not $bag.Contains('Caution')) { $bag['Caution'] = $false }
						if (-not $bag.Contains('SourceRegion')) { $bag['SourceRegion'] = 'User' }
						if (-not $bag.Contains('Function')) { $bag['Function'] = 'AppInstall' }
						[pscustomobject]$bag
					})
				}

				if ($userEntriesNormalized.Count -gt 0 -and (Get-Command -Name 'Merge-BaselineUserAppEntries' -CommandType Function -ErrorAction SilentlyContinue))
				{
					$builtInRawEntries = @($catalogFilesJson | ForEach-Object { @($_.Json.Entries) } | Where-Object { $null -ne $_ })
					$mergeResult = Merge-BaselineUserAppEntries -BuiltInEntries $builtInRawEntries -UserEntries $userEntriesNormalized
					foreach ($warning in @($mergeResult.Warnings))
					{
						if (-not [string]::IsNullOrWhiteSpace([string]$warning)) { LogWarning $warning }
					}
					$acceptedUserEntries = @($mergeResult.Entries | Where-Object {
						$_ -and
						$_.PSObject.Properties['Source'] -and ([string]$_.Source -eq 'User') -and
						$_.PSObject.Properties['SubCategory'] -and ([string]$_.SubCategory -eq $effectiveCategory)
					})
					if ($acceptedUserEntries.Count -gt 0)
					{
						$catalogFilesJson += [pscustomobject]@{
							Path = '<UserApps>'
							Json = [pscustomobject]@{ Entries = $acceptedUserEntries }
						}
					}
				}
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Catalog.UserAppsLoad'
		}
		else { $null = $_ }
	}

	$dedupe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$catalog = [System.Collections.Generic.List[object]]::new()

	foreach ($catalogFile in @($catalogFilesJson))
	{
		foreach ($entry in @($catalogFile.Json.Entries))
		{
			if (-not $entry) { continue }

			$winGetId = $null
			$chocoId = $null
			try
			{
				if ($entry.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.WinGetId))
				{
					$winGetId = [string]$entry.WinGetId
				}
				if ($entry.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.ChocoId))
				{
					$chocoId = [string]$entry.ChocoId
				}
				if ($entry.ExtraArgs)
				{
					if ($entry.ExtraArgs.PSObject.Properties['WinGetId'])
					{
						$winGetId = [string]$entry.ExtraArgs.WinGetId
					}
					if ($entry.ExtraArgs.PSObject.Properties['ChocoId'])
					{
						$chocoId = [string]$entry.ExtraArgs.ChocoId
					}
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CatalogHelpers.Get-BaselineApplicationsCatalog:catch1170' -Severity Debug }

				$null = $_
			}

			$identityKey = Get-ApplicationCatalogIdentityKey -Entry $entry
			if (-not $dedupe.Add($identityKey)) { continue }

			$displayName = if (-not [string]::IsNullOrWhiteSpace([string]$entry.Name)) { [string]$entry.Name } else { $(if (-not [string]::IsNullOrWhiteSpace($winGetId)) { $winGetId } elseif (-not [string]::IsNullOrWhiteSpace($chocoId)) { $chocoId } else { 'Unknown application' }) }
			$entityType = Get-ApplicationEntityType -Entry $entry
			$supportsExecution = Test-ApplicationExecutionSupport -Entry $entry
			$descriptionKey = $null
			if ($entry.PSObject.Properties['DescriptionKey'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.DescriptionKey))
			{
				$descriptionKey = [string]$entry.DescriptionKey
			}
			else
			{
				$identitySlug = (($identityKey -replace '[^A-Za-z0-9]+', '_').Trim('_'))
				if (-not [string]::IsNullOrWhiteSpace([string]$identitySlug))
				{
					$descriptionKey = 'GuiAppDescription_{0}' -f $identitySlug
				}
			}
			$resolvedDescription = if (-not [string]::IsNullOrWhiteSpace([string]$descriptionKey))
			{
				Get-UxLocalizedString -Key $descriptionKey -Fallback ([string]$entry.Description)
			}
			else
			{
				[string]$entry.Description
			}
			$searchIndex = @(
				$displayName
				$winGetId
				$chocoId
				$entityType
				$resolvedDescription
				$entry.Detail
				$entry.SubCategory
				($entry.Tags -join ' ')
				$entry.Risk
				$entry.Impact
				$entry.WhyThisMatters
				$entry.SourceRegion
			)
			if ($entry.ExtraArgs)
			{
				$searchIndex += @(
					$entry.ExtraArgs.WinGetId
					$entry.ExtraArgs.ChocoId
					$entry.ExtraArgs.StoreUri
					$entry.ExtraArgs.DirectUrl
					$entry.ExtraArgs.Command
				)
			}
			$searchIndex = @($searchIndex | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }) -join ' '

			[void]$catalog.Add([pscustomobject]@{
				Name = $displayName
				WinGetId = $winGetId
				ChocoId = $chocoId
				Type = $entityType
				EntityType = $entityType
				SupportsExecution = [bool]$supportsExecution
				Description = [string]$resolvedDescription
				DescriptionKey = [string]$descriptionKey
				Detail = [string]$entry.Detail
				SubCategory = [string]$entry.SubCategory
				Tags = @($entry.Tags)
				Risk = [string]$entry.Risk
				Safe = [bool]$entry.Safe
				Impact = [string]$entry.Impact
				RequiresRestart = [bool]$entry.RequiresRestart
				Caution = [bool]$entry.Caution
				WhyThisMatters = [string]$entry.WhyThisMatters
				SourceRegion = [string]$entry.SourceRegion
				ExtraArgs = $entry.ExtraArgs
				SearchIndex = [string]$searchIndex.ToLowerInvariant()
			})
		}
	}

	$Script:BaselineApplicationsCatalog = @($catalog)
	$Script:BaselineApplicationsCatalogCategory = $effectiveCategory
	$Script:BaselineApplicationsCatalogByCategory[$effectiveCategory] = @($catalog)
	return $Script:BaselineApplicationsCatalog
}
