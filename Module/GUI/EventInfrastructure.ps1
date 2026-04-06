# Event handler infrastructure: safe property setter, scoped error handling, event registration/cleanup, command caching

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
		try { $property = $Control.PSObject.Properties[$PropertyName] } catch { $property = $null }
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
				'unknown'
			}
			$valueType = if ($null -eq $Value)
			{
				'<null>'
			}
			else
			{
				try { [string]$Value.GetType().FullName } catch { 'unknown' }
			}
			$warningMessage = "Failed to set property '{0}' on {1} (expected {2}, actual {3}): {4}" -f `
				$PropertyName, `
				$(try { $Control.GetType().FullName } catch { 'unknown' }), `
				$propertyType, `
				$valueType, `
				$_.Exception.Message

			$warningKey = '{0}|{1}' -f $Context, $warningMessage
			$shouldLog = $true
			if ($Script:GuiRuntimeWarnings)
			{
				try { $shouldLog = $Script:GuiRuntimeWarnings.Add($warningKey) } catch { $shouldLog = $true }
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
		if (Get-Command -Name 'LogError' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogError $errorText
		}
		else
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
				$null = $_
			}
		}

		return $errorText
	}

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
			$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
			if ($showGuiRuntimeFailureScript)
			{
				$null = & $showGuiRuntimeFailureScript -Context $Context -Exception $_.Exception -ShowDialog:$ShowDialog
			}
			else
			{
				Write-Warning ("GUI event failed [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $_.Exception.Message)
			}
		}
	}

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
			return $null
		}

		return $null
	}

	# Cache event reflection metadata per (Type, EventName) to avoid repeated
	# GetEvent / PSObject.Methods.Match lookups on the same control types.
	if (-not ($Script:EventAccessorCache -is [hashtable])) { $Script:EventAccessorCache = @{} }

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
		try { $sourceType = $Source.GetType() } catch { $sourceType = $null }
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
				try { $Script:GuiEventHandlerStore.GetType().FullName } catch { 'unknown' }
			}
				$sourceTypeName = if ($null -eq $Source)
				{
					'<null>'
				}
				else
				{
					try { $Source.GetType().FullName } catch { 'unknown' }
				}
				throw "Register-GuiEventHandler/StoreAppend failed for event '$EventName' on $sourceTypeName with store type ${storeType}: $($_.Exception.Message)"
			}

			return $Handler
		}

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
				Write-GuiRuntimeWarning -Context 'Unregister-GuiEventHandler' -Message ("Could not access remove accessor '{0}' for event '{1}' on {2}." -f $removeAccessorName, $EventName, $(try { $Source.GetType().FullName } catch { 'unknown' }))
				return $false
			}

			try
			{
				[void]$removeAccessor.Invoke($Handler)
				return $true
			}
			catch
			{
				throw "Unregister-GuiEventHandler could not detach handler for event '$EventName' on $($(try { $Source.GetType().FullName } catch { 'unknown' })): $($_.Exception.Message)"
			}
		}

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
		$Script:ExecutionProgressBar = $null
		$Script:ExecutionProgressText = $null
		$Script:ExecutionSubProgressBar = $null
		$Script:ExecutionSubProgressText = $null
		$Script:SecondaryActionGroupBorder = $null
		$Script:AbortRunButton = $null
		$Script:GuiRuntimeCommandCache = @{}
		$Script:GuiFunctionCaptureCache = @{}
	}
