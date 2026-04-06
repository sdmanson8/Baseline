# Reactive state container - tracks a handful of GUI properties and notifies
# registered callbacks on change. Dispatches to the UI thread when off-thread.
#
#   $state = New-ObservableState -Dispatcher $Form.Dispatcher -InitialValues @{ StatusText = '' }
#   & $state.Subscribe 'StatusText' { param($new, $old) $StatusText.Text = $new }
#   & $state.Set 'StatusText' 'Hello'

	function New-ObservableState
	{
		param (
			[hashtable]$InitialValues = @{},
			[object]$Dispatcher = $null
		)

		$state = @{
			_values      = @{}
			_subscribers = @{}
			_dispatcher  = $Dispatcher
		}

		$canUseDispatcher = {
			param ([object]$Candidate)

			return (
				$null -ne $Candidate -and
				$null -ne $Candidate.PSObject.Methods['CheckAccess'] -and
				$null -ne $Candidate.PSObject.Methods['Invoke']
			)
		}.GetNewClosure()

		# Cache the dispatcher capability check once at creation time so Set/SetBatch
		# don't re-evaluate PSObject.Methods reflection on every call.
		$hasDispatcher = [bool](& $canUseDispatcher $Dispatcher)

		$invokeDispatcher = {
			param (
				[Parameter(Mandatory = $true)]
				[object]$TargetDispatcher,

				[Parameter(Mandatory = $true)]
				[scriptblock]$Action
			)

			$actionDelegate = [System.Action]$Action
			$dispatcherPriorityType = 'System.Windows.Threading.DispatcherPriority' -as [type]
			if ($dispatcherPriorityType)
			{
				$TargetDispatcher.Invoke($actionDelegate, $dispatcherPriorityType::DataBind)
				return
			}

			$TargetDispatcher.Invoke($actionDelegate)
		}.GetNewClosure()

		$reportSubscriberError = {
			param (
				[string]$Property,
				[System.Exception]$Exception
			)

			$message = "ObservableState subscriber failed for property '{0}': {1}" -f $Property, $Exception.Message
			if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
			{
				LogWarning $message
			}
			else
			{
				Write-Warning $message
			}
		}.GetNewClosure()

		foreach ($key in $InitialValues.Keys)
		{
			$state._values[$key] = $InitialValues[$key]
			$state._subscribers[$key] = [System.Collections.Generic.List[scriptblock]]::new()
		}

		$state.Get = {
			param ([string]$Property)
			return $state._values[$Property]
		}.GetNewClosure()

		$state.Set = {
			param ([string]$Property, $Value)

			$oldValue = $state._values[$Property]
			$state._values[$Property] = $Value

			if ($oldValue -eq $Value) { return }

			$subs = $state._subscribers[$Property]
			if (-not $subs -or $subs.Count -eq 0) { return }

			$notifyAction = {
				foreach ($cb in $subs)
				{
					try { & $cb $Value $oldValue } catch { & $reportSubscriberError $Property $_.Exception }
				}
			}.GetNewClosure()

			if ($hasDispatcher -and $state._dispatcher.CheckAccess() -eq $false)
			{
				& $invokeDispatcher $state._dispatcher $notifyAction
			}
			else
			{
				& $notifyAction
			}
		}.GetNewClosure()

		$state.Subscribe = {
			param (
				[string]$Property,
				[scriptblock]$Handler
			)

			if (-not $state._subscribers.ContainsKey($Property))
			{
				$state._subscribers[$Property] = [System.Collections.Generic.List[scriptblock]]::new()
			}

			$state._subscribers[$Property].Add($Handler)
		}.GetNewClosure()

		$state.SetBatch = {
			param ([hashtable]$Updates)

			$changedEntries = [System.Collections.Generic.List[object]]::new()
			foreach ($key in $Updates.Keys)
			{
				$oldValue = $state._values[$key]
				$state._values[$key] = $Updates[$key]
				if ($oldValue -ne $Updates[$key])
				{
					$subs = $state._subscribers[$key]
					if (-not $subs)
					{
						$subs = [System.Collections.Generic.List[scriptblock]]::new()
						$state._subscribers[$key] = $subs
					}

					$changedEntries.Add([pscustomobject]@{
						Property    = $key
						NewValue    = $Updates[$key]
						OldValue    = $oldValue
						Subscribers = @($subs)
					})
				}
			}

			if ($changedEntries.Count -eq 0) { return }

			$notifyAction = {
				foreach ($change in $changedEntries)
				{
					if ($change.Subscribers.Count -gt 0)
					{
						foreach ($cb in $change.Subscribers)
						{
							try { & $cb $change.NewValue $change.OldValue } catch { & $reportSubscriberError ([string]$change.Property) $_.Exception }
						}
					}
				}
			}.GetNewClosure()

			if ($hasDispatcher -and $state._dispatcher.CheckAccess() -eq $false)
			{
				& $invokeDispatcher $state._dispatcher $notifyAction
			}
			else
			{
				& $notifyAction
			}
		}.GetNewClosure()

		$state.Dispose = {
			foreach ($propertyName in @($state._subscribers.Keys))
			{
				$subs = $state._subscribers[$propertyName]
				if ($subs -and $subs.PSObject.Methods['Clear']) { $subs.Clear() }
			}
			$state._dispatcher = $null
		}.GetNewClosure()

		return $state
	}

