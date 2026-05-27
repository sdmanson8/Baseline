# Event handler infrastructure: safe property setter, scoped error handling, event registration/cleanup, command caching

	<#
	    .SYNOPSIS
	#>

	function Set-GuiControlProperty
	{
		param (
			[object]$Control,
			[string]$PropertyName,
			[object]$Value,
			[string]$Context = 'GUI'
		)

		if (-not $Control -or [string]::IsNullOrWhiteSpace($PropertyName)) { return $false }

		$property = $null
		try { $property = $Control.PSObject.Properties[$PropertyName] } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Set-GuiControlProperty:catch19' -Severity Debug }
		 $property = $null }
		if (-not $property)
		{
			return $false
		}

		try
		{
			$Control.$PropertyName = $Value
			return $true
		}
		catch
		{
			$propertyType = try
			{
				if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.TypeNameOfValue))
				{
					[string]$property.TypeNameOfValue
				}
				else
				{
					'unknown'
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Set-GuiControlProperty:catch43' -Severity Debug }

				'unknown'
			}
			$valueType = if ($null -eq $Value)
			{
				'<null>'
			}
			else
			{
				try { [string]$Value.GetType().FullName } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Set-GuiControlProperty:catch53' -Severity Debug }
				 'unknown' }
			}
			$warningPrefix = "Failed to set property '{0}' on {1} (expected {2}, actual {3})" -f `
				$PropertyName, `
				$(try { $Control.GetType().FullName } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Set-GuiControlProperty:catch57' -Severity Debug }
				 'unknown' }), `
				$propertyType, `
				$valueType
			$warningMessage = Format-BaselineErrorForLog -ErrorObject $_ -Prefix $warningPrefix

			$warningKey = '{0}|{1}' -f $Context, $warningMessage
			$shouldLog = $true
			if ($Script:GuiRuntimeWarnings)
			{
				try { $shouldLog = $Script:GuiRuntimeWarnings.Add($warningKey) } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Set-GuiControlProperty:catch66' -Severity Debug }
				 $shouldLog = $true }
			}
			if ($shouldLog)
			{
				$warningText = "GUI runtime safeguard [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $warningMessage
				if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
				{
					LogWarning $warningText
				}
				else
				{
					Write-Warning $warningText
				}
			}
			return $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Show-ScopedGuiRuntimeFailure
	{
		param (
			[string]$Context = 'GUI',
			[System.Exception]$Exception,
			[switch]$ShowDialog
		)

		if (-not $Exception) { return $null }

		$debugTrail = if ($Script:GuiPresetDebugTrail -and $Script:GuiPresetDebugTrail.Count -gt 0) {
			@($Script:GuiPresetDebugTrail)
		} else { @() }

		$errorText = Get-GuiRuntimeFailureDetails -Context $Context -Exception $Exception -DebugTrail $debugTrail
		$loggedViaCommand = $false
		if (Get-Command -Name 'LogError' -ErrorAction SilentlyContinue)
		{
			try { LogError $errorText; $loggedViaCommand = $true } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Show-ScopedGuiRuntimeFailure:catch106' -Severity Debug }
			 $loggedViaCommand = $false }
		}
		if (-not $loggedViaCommand -and $Global:LogFilePath)
		{
			# Last-resort direct append: the LogError alias may not be
			# resolvable inside a WPF dispatcher closure, and Write-Warning
			# vanishes when the console is hidden. Write straight to the file
			# so GUI-GENERIC-001 reports always leave a trail.
			try
			{
				$timestamp = Get-Date -Format 'dd-MM-yyyy HH:mm'
				$line = "$timestamp ERROR: $errorText"
				Add-Content -LiteralPath $Global:LogFilePath -Value $line -Encoding UTF8 -ErrorAction Stop
			}
			catch
			{
				Write-Warning $errorText
			}
		}
		elseif (-not $loggedViaCommand)
		{
			Write-Warning $errorText
		}

		if ($ShowDialog -and $Script:MainForm)
		{
			try
			{
				$friendlyError = Get-BaselineErrorInfo -Exception $Exception -Context $Context
				$friendlyTitle = if ($friendlyError -and (Test-GuiObjectField -Object $friendlyError -FieldName 'Title')) { [string]$friendlyError.Title } else { 'GUI Error' }
				$friendlyMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyError -LogPath $Global:LogFilePath -IncludeLogPath
				[void](Show-ThemedDialog -Title $friendlyTitle -Message $friendlyMessage -Buttons @('OK') -AccentButton 'OK')
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Show-ScopedGuiRuntimeFailure:catch139' -Severity Debug }

				$null = $_
			}
		}

		return $errorText
	}

	<#
	    .SYNOPSIS
	#>

	function Invoke-GuiRuntimeFailureReport
	{
		param (
			[string]$Context = 'GUI',
			[System.Exception]$Exception,
			[switch]$ShowDialog
		)

		return (Show-ScopedGuiRuntimeFailure -Context $Context -Exception $Exception -ShowDialog:$ShowDialog)
	}

	<#
	    .SYNOPSIS
	#>

	function Invoke-GuiSafeAction
	{
		param (
			[scriptblock]$Action,
			[string]$Context = 'GUI',
			[switch]$ShowDialog
		)

		if (-not $Action) { return }

		try
		{
			& $Action
		}
		catch
		{
			$null = Invoke-GuiRuntimeFailureReport -Context $Context -Exception $_.Exception -ShowDialog:$ShowDialog
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Ensure-GuiEventHandlerStore
	{
		if (-not ($Script:GuiEventHandlerStore -is [System.Collections.Generic.List[object]]))
		{
			$Script:GuiEventHandlerStore = [System.Collections.Generic.List[object]]::new()
		}
	}

	function Get-GuiEventAccessorMethod
	{
		param (
			[object]$Source,
			[Parameter(Mandatory = $true)]
			[string]$AccessorName
		)

		if (-not $Source -or [string]::IsNullOrWhiteSpace($AccessorName))
		{
			return $null
		}

		try
		{
			$matchedMethods = $Source.PSObject.Methods.Match($AccessorName)
			if ($matchedMethods -and $matchedMethods.Count -gt 0)
			{
				return $matchedMethods[0]
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Get-GuiEventAccessorMethod:catch220' -Severity Debug }

			return $null
		}

		return $null
	}

	# Cache event reflection metadata per (Type, EventName) to avoid repeated
	# GetEvent / PSObject.Methods.Match lookups on the same control types.
	if (-not ($Script:EventAccessorCache -is [hashtable])) { $Script:EventAccessorCache = @{} }

	<#
	    .SYNOPSIS
	#>

	function Register-GuiEventHandler
	{
		param (
			[object]$Source,
			[Parameter(Mandatory = $true)]
			[string]$EventName,
			[Parameter(Mandatory = $true)]
			[scriptblock]$Handler
		)

		if (-not $Source -or [string]::IsNullOrWhiteSpace($EventName) -or -not $Handler)
		{
			return $null
		}

		$sourceType = $null
		try { $sourceType = $Source.GetType() } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Register-GuiEventHandler:catch252' -Severity Debug }
		 $sourceType = $null }
		if (-not $sourceType)
		{
			Write-GuiRuntimeWarning -Context 'Register-GuiEventHandler' -Message ("Could not resolve type for event '{0}'." -f $EventName)
			return $null
		}

		# Fast path: check the per-type accessor cache before doing reflection.
		$cacheKey = '{0}|{1}' -f $sourceType.FullName, $EventName
		$cachedAccessorName = $Script:EventAccessorCache[$cacheKey]
		$addAccessor = $null
		if ($cachedAccessorName)
		{
			$addAccessor = Get-GuiEventAccessorMethod -Source $Source -AccessorName $cachedAccessorName
		}

		if (-not $addAccessor)
		{
			$eventInfo = $null
			try
			{
				$bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::NonPublic
				$eventInfo = $sourceType.GetEvent($EventName, $bindingFlags)
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Register-GuiEventHandler:catch276' -Severity Debug }

				$eventInfo = $null
			}
			if (-not $eventInfo)
			{
				Write-GuiRuntimeWarning -Context 'Register-GuiEventHandler' -Message ("Could not resolve event '{0}' on {1}." -f $EventName, $sourceType.FullName)
				return $null
			}

			$addAccessorName = 'add_{0}' -f $EventName
			$addAccessor = Get-GuiEventAccessorMethod -Source $Source -AccessorName $addAccessorName
			if (-not $addAccessor)
			{
				Write-GuiRuntimeWarning -Context 'Register-GuiEventHandler' -Message ("Could not access add accessor '{0}' for event '{1}' on {2}." -f $addAccessorName, $EventName, $sourceType.FullName)
				return $null
			}
			$Script:EventAccessorCache[$cacheKey] = $addAccessorName
		}

		try
		{
			[void]$addAccessor.Invoke($Handler)
		}
		catch
		{
			throw "Register-GuiEventHandler could not attach handler for event '$EventName' on $($sourceType.FullName): $($_.Exception.Message)"
		}
		if (-not ($Script:GuiEventHandlerStore -is [System.Collections.Generic.List[object]])) { Ensure-GuiEventHandlerStore }

		try
		{
			[void]$Script:GuiEventHandlerStore.Add([pscustomobject]@{
				Source    = $Source
				EventName = $EventName
				Handler   = $Handler
			})
		}
		catch
		{
			$storeType = if ($null -eq $Script:GuiEventHandlerStore)
			{
				'<null>'
			}
			else
			{
				try { $Script:GuiEventHandlerStore.GetType().FullName } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Register-GuiEventHandler:catch322' -Severity Debug }
				 'unknown' }
			}
				$sourceTypeName = if ($null -eq $Source)
				{
					'<null>'
				}
				else
				{
					try { $Source.GetType().FullName } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Register-GuiEventHandler:catch330' -Severity Debug }
					 'unknown' }
				}
				throw "Register-GuiEventHandler/StoreAppend failed for event '$EventName' on $sourceTypeName with store type ${storeType}: $($_.Exception.Message)"
			}

			return $Handler
		}

		<#
		    .SYNOPSIS
		#>

		function Unregister-GuiEventHandler
		{
			param (
				[object]$Source,
				[Parameter(Mandatory = $true)]
				[string]$EventName,
				[Parameter(Mandatory = $true)]
				[scriptblock]$Handler
			)

			if (-not $Source -or [string]::IsNullOrWhiteSpace($EventName) -or -not $Handler)
			{
				return $false
			}

			$removeAccessorName = 'remove_{0}' -f $EventName
			$removeAccessor = Get-GuiEventAccessorMethod -Source $Source -AccessorName $removeAccessorName
			if (-not $removeAccessor)
			{
				Write-GuiRuntimeWarning -Context 'Unregister-GuiEventHandler' -Message ("Could not access remove accessor '{0}' for event '{1}' on {2}." -f $removeAccessorName, $EventName, $(try { $Source.GetType().FullName } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Unregister-GuiEventHandler:catch361' -Severity Debug }
				 'unknown' }))
				return $false
			}

			try
			{
				[void]$removeAccessor.Invoke($Handler)
				return $true
			}
			catch
			{
				throw "Unregister-GuiEventHandler could not detach handler for event '$EventName' on $($(try { $Source.GetType().FullName } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EventInfrastructure.Unregister-GuiEventHandler:catch372' -Severity Debug }
				 'unknown' })): $($_.Exception.Message)"
			}
		}

		<#
		    .SYNOPSIS
		#>

		function Unregister-GuiEventHandlers
		{
			if (-not ($Script:GuiEventHandlerStore -is [System.Collections.Generic.List[object]]) -or $Script:GuiEventHandlerStore.Count -eq 0)
		{
			return
		}

		for ($index = $Script:GuiEventHandlerStore.Count - 1; $index -ge 0; $index--)
		{
			$registration = $Script:GuiEventHandlerStore[$index]
			if (-not $registration -or -not $registration.Source -or -not $registration.Handler)
			{
				continue
			}

			try
			{
				[void](Unregister-GuiEventHandler -Source $registration.Source -EventName ([string]$registration.EventName) -Handler $registration.Handler)
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Unregister-GuiEventHandlers' -Message ("Failed to remove event '{0}': {1}" -f [string]$registration.EventName, $_.Exception.Message)
			}
		}

		$Script:GuiEventHandlerStore.Clear()
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRuntimeCommand
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Name,
			[string]$CommandType = 'Function'
		)

		if (-not ($Script:GuiRuntimeCommandCache -is [hashtable]))
		{
			$Script:GuiRuntimeCommandCache = @{}
		}

		$cacheKey = '{0}|{1}' -f $CommandType, $Name
		if ($Script:GuiRuntimeCommandCache.ContainsKey($cacheKey))
		{
			$cachedCommand = $Script:GuiRuntimeCommandCache[$cacheKey]
			if ($null -ne $cachedCommand)
			{
				return $cachedCommand
			}

			[void]$Script:GuiRuntimeCommandCache.Remove($cacheKey)
		}

		$resolvedCommand = @(
			Get-Command -Name $Name -CommandType $CommandType -ErrorAction SilentlyContinue
		) | Select-Object -First 1

		if ($null -ne $resolvedCommand)
		{
			$Script:GuiRuntimeCommandCache[$cacheKey] = $resolvedCommand
		}

		return $resolvedCommand
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiFunctionCapture
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Name
		)

		if (-not ($Script:GuiFunctionCaptureCache -is [hashtable]))
		{
			$Script:GuiFunctionCaptureCache = @{}
		}

		if ($Script:GuiFunctionCaptureCache.ContainsKey($Name))
		{
			$cachedCapture = $Script:GuiFunctionCaptureCache[$Name]
			if ($null -ne $cachedCapture)
			{
				return $cachedCapture
			}

			[void]$Script:GuiFunctionCaptureCache.Remove($Name)
		}

		$commandInfo = Get-GuiRuntimeCommand -Name $Name -CommandType 'Function'
		if (-not $commandInfo)
		{
			return $null
		}

		# Capture the underlying ScriptBlock for functions instead of the
		# FunctionInfo wrapper so later WPF/dispatcher callbacks always invoke a
		# stable scriptblock object.
		$capturedCommand = if (
			(Test-GuiObjectField -Object $commandInfo -FieldName 'ScriptBlock') -and
			$commandInfo.ScriptBlock -is [scriptblock]
		) {
			$commandInfo.ScriptBlock
		}
		else
		{
			$commandInfo
		}
		$Script:GuiFunctionCaptureCache[$Name] = {
			& $capturedCommand @args
		}.GetNewClosure()

		return $Script:GuiFunctionCaptureCache[$Name]
	}

	<#
	    .SYNOPSIS
	#>

	function Invoke-CapturedFunction
	{
		<#
		.SYNOPSIS Looks up a captured function by name and invokes it with the given parameters.
		.DESCRIPTION
			Combines Get-GuiFunctionCapture (cached lookup + .GetNewClosure()) with
			invocation, reducing the two-step capture-then-call boilerplate that
			event handlers must otherwise repeat.

			If the function cannot be resolved, this is a silent no-op unless
			-ErrorOnMissing is specified, in which case it throws.
		.PARAMETER Name
			The function name to resolve via Get-GuiFunctionCapture.
		.PARAMETER Parameters
			A hashtable splatted to the resolved function.  Defaults to an empty
			hashtable so callers can omit it for parameter-less functions.
		.PARAMETER ErrorOnMissing
			When set, throws if the function cannot be resolved instead of
			returning $null silently.
		.EXAMPLE
			Invoke-CapturedFunction -Name 'Set-SearchInputStyle'
		.EXAMPLE
			Invoke-CapturedFunction -Name 'Set-GUITheme' -Parameters @{ Theme = $Script:LightTheme }
		#>
		param (
			[Parameter(Mandatory = $true)]
			[string]$Name,
			[hashtable]$Parameters = @{},
			[switch]$ErrorOnMissing
		)

		$fn = Get-GuiFunctionCapture -Name $Name
		if ($fn)
		{
			return & $fn @Parameters
		}

		if ($ErrorOnMissing)
		{
			throw "Invoke-CapturedFunction: function '$Name' could not be resolved."
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Clear-GuiWindowRuntimeState
	{
		if ($Script:GuiState -and $Script:GuiState.ContainsKey('Dispose'))
		{
			try { & $Script:GuiState.Dispose } catch { Write-GuiRuntimeWarning -Context 'Clear-GuiWindowRuntimeState/GuiState' -Message $_.Exception.Message }
		}

		try { Unregister-GuiEventHandlers } catch { Write-GuiRuntimeWarning -Context 'Clear-GuiWindowRuntimeState/Events' -Message $_.Exception.Message }
		try { Clear-TabContentCache } catch { Write-GuiRuntimeWarning -Context 'Clear-GuiWindowRuntimeState/Cache' -Message $_.Exception.Message }

		try
		{
			if ($ContentScroll)
			{
				$ContentScroll.Content = $null
			}
		}
		catch
		{
			Write-GuiRuntimeWarning -Context 'Clear-GuiWindowRuntimeState/ContentScroll' -Message $_.Exception.Message
		}

		try
		{
			if ($PrimaryTabs)
			{
				$PrimaryTabs.Items.Clear()
			}
		}
		catch
		{
			Write-GuiRuntimeWarning -Context 'Clear-GuiWindowRuntimeState/PrimaryTabs' -Message $_.Exception.Message
		}

		$Script:PresetStatusBadge = $null
		$Script:ExecutionLogBox = $null
		$Script:ExecutionProgressHost = $null
		$Script:ExecutionProgressBar = $null
		$Script:ExecutionProgressText = $null
		$Script:ExecutionSubProgressBar = $null
		$Script:ExecutionSubProgressText = $null
		$Script:TxtAppsProgressText = $null
		$Script:AppsProgressBar = $null
		$Script:PresetProgressHost = $null
		$Script:PresetProgressBar = $null
		$Script:SecondaryActionGroupBorder = $null
		$Script:AbortRunButton = $null
		$Script:GuiRuntimeCommandCache = @{}
		$Script:GuiFunctionCaptureCache = @{}
	}
