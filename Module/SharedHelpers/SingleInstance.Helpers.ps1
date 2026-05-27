# Single-instance launcher helpers.
#
# Launcher single-instance contract (HandleSingleInstance via
# AppInstance.FindOrRegisterForKey + RedirectActivationToAsync +
# IsIconic/ShowWindow(SW_RESTORE)/SetForegroundWindow). The launcher
# does not currently ship this - double-clicking the launcher while a copy is
# already running starts a second instance, which is the worst common form
# of user confusion (two windows competing to write to the same daily log).
#
# Implementation notes:
#   - Use a *per-user* named Mutex ("Local\\..." prefix) so two users on the
#     same RDS host can each run their own Baseline instance.
#     can be unit-tested without spawning a real second process.

<#
    .SYNOPSIS
#>

function Get-BaselineSingleInstanceMutexName
{
	<#
		.SYNOPSIS
		Returns the canonical per-user mutex name used by the
		single-instance lock.

		.DESCRIPTION
		Format: `Local\Baseline-SingleInstance-<sanitized-username>`. The
		`Local\` prefix scopes the mutex to the current logon session so two
		different users on a multi-user host (RDS, fast user switching,
		`runas` between admin and standard accounts) each get their own
		lock. Username is lowercased and stripped of characters that are
		invalid in mutex names so e.g. a username with a backslash from a
		domain prefix doesn't accidentally introduce a path component.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[string]$UserName = [System.Environment]::UserName
	)

	$normalized = ([string]$UserName).ToLowerInvariant()
	$sanitized = ($normalized -replace '[^a-z0-9._-]', '_')
	# Fall back to 'unknown' when nothing identifying survives sanitization -
	# either empty/whitespace or a string composed entirely of replacement
	# underscores (e.g. '???' -> '___'). 'first_admin' is preserved because it
	# still contains alphanumerics.
	if ([string]::IsNullOrWhiteSpace($sanitized) -or ($sanitized -notmatch '[a-z0-9]'))
	{
		$sanitized = 'unknown'
	}
	return ('Local\Baseline-SingleInstance-{0}' -f $sanitized)
}

<#
    .SYNOPSIS
#>

function Test-BaselineSingleInstanceLockAvailable
{
	<#
		.SYNOPSIS
		Tries to acquire the single-instance mutex; returns whether the
		lock is now ours, plus the mutex object so the caller can release
		it on shutdown.

		.DESCRIPTION
		Wraps `[System.Threading.Mutex]::new($initiallyOwned, $name, [out]$createdNew)`.
		Returns:
		  Acquired   : $true if this process now owns the lock
		  CreatedNew : $true on the first acquisition (no existing instance)
		  Mutex      : the mutex object - keep the reference alive for the
		               lifetime of the process; releasing/disposing it
		               relinquishes the lock
		  Error      : exception message if anything went wrong; Acquired
		               will be $false in that case

		The function never throws - failures (rare; usually permissions on
		a locked-down session 0 service account) are folded into the result
		so the caller can decide whether to fall back to "allow multiple"
		or surface a warning.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[string]$MutexName
	)

	try
	{
		$createdNew = $false
		$mutex = [System.Threading.Mutex]::new($true, $MutexName, [ref]$createdNew)
		if ($createdNew)
		{
			return [pscustomobject]@{
				Acquired = $true
				CreatedNew = $true
				Mutex = $mutex
				Error = $null
			}
		}

		# We constructed it but did not create - try to actually acquire it
		# with a zero-timeout WaitOne. If the existing owner is alive, we
		# get $false back and we do NOT own the mutex.
		$gotIt = $false
		try { $gotIt = $mutex.WaitOne(0) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Test-BaselineSingleInstanceLockAvailable:catch108' -Severity Debug }
		 $gotIt = $false }
		if ($gotIt)
		{
			return [pscustomobject]@{
				Acquired = $true
				CreatedNew = $false
				Mutex = $mutex
				Error = 'Recovered abandoned mutex.'
			}
		}

		try { $mutex.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Mutex.Dispose' }
		return [pscustomobject]@{
			Acquired = $false
			CreatedNew = $false
			Mutex = $null
			Error = $null
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Test-BaselineSingleInstanceLockAvailable:catch127' -Severity Debug }

		return [pscustomobject]@{
			Acquired = $false
			CreatedNew = $false
			Mutex = $null
			Error = $_.Exception.Message
		}
	}
}

<#
    .SYNOPSIS
#>

function Acquire-BaselineSingleInstance
{
	<#
		.SYNOPSIS
		Convenience wrapper that resolves the mutex name, acquires the
		lock, discovers a running instance when needed, and resolves the
		final single-instance decision in one call.

		.DESCRIPTION
		Returns a pscustomobject with the mutex name, acquisition result,
		discovered running instance, decision, and foreground attempt
		result. The wrapper never throws; failures remain inside the
		result object so callers can log or continue according to their
		own policy.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[string]$MutexName = (Get-BaselineSingleInstanceMutexName),

		[Parameter()]
		[AllowNull()]
		[object]$RunningInstance,

		[Parameter()]
		[switch]$AllowMultipleInstances,

		[Parameter()]
		[scriptblock]$ProcessLister
	)

	$resolvedMutexName = if ([string]::IsNullOrWhiteSpace($MutexName)) { Get-BaselineSingleInstanceMutexName } else { [string]$MutexName }
	$lockResult = Test-BaselineSingleInstanceLockAvailable -MutexName $resolvedMutexName
	$resolvedRunningInstance = $RunningInstance
	if (-not $AllowMultipleInstances -and -not $PSBoundParameters.ContainsKey('RunningInstance') -and -not $resolvedRunningInstance)
	{
		if ($ProcessLister)
		{
			$resolvedRunningInstance = Find-BaselineRunningInstance -ProcessLister $ProcessLister
		}
		else
		{
			$resolvedRunningInstance = Find-BaselineRunningInstance
		}
	}

	$decision = Resolve-BaselineSingleInstanceDecision -LockResult $lockResult -RunningInstance $resolvedRunningInstance -AllowMultipleInstances:$AllowMultipleInstances
	$foregroundResult = $null
	if ($decision.Action -eq 'HandoffAndExit' -and $decision.TargetHandle -and $decision.TargetHandle -ne [IntPtr]::Zero)
	{
		$foregroundResult = Invoke-BaselineSingleInstanceForeground -WindowHandle $decision.TargetHandle
	}

	return [pscustomobject]@{
		MutexName         = $resolvedMutexName
		LockResult        = $lockResult
		RunningInstance   = $resolvedRunningInstance
		Decision          = $decision
		ForegroundResult  = $foregroundResult
	}
}

<#
    .SYNOPSIS
#>

function Find-BaselineRunningInstance
{
	<#
		.SYNOPSIS
		Finds the running Baseline process (excluding the current PID) and
		returns its window handle so the caller can foreground it.

		.DESCRIPTION
		Pure helper modulo `Get-Process` - accepts a `-ProcessLister` script
		block override so tests can inject synthetic process lists. The
		default scans for processes named like the launcher
		('Baseline','Baseline.exe', or any name starting with 'Baseline')
		whose `MainWindowHandle` is non-zero, excluding the current PID.

		Returns the first match (lowest PID - deterministic on a host that
		legitimately has more than one slot in flight, e.g. an in-progress
		shutdown) as a pscustomobject:
		  ProcessId        : [int]
		  MainWindowHandle : [IntPtr]
		  ProcessName      : [string]
		Returns `$null` when nothing matches.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[int]$CurrentProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id,

		[Parameter()]
		[string[]]$ProcessNamePatterns = @('Baseline'),

		[Parameter()]
		[scriptblock]$ProcessLister
	)

	$candidates = @()
	if ($ProcessLister)
	{
		try { $candidates = @(& $ProcessLister) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Find-BaselineRunningInstance:catch247' -Severity Debug }
		 $candidates = @() }
	}
	else
	{
		try
		{
			$candidates = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
				$pname = [string]$_.ProcessName
				if ([string]::IsNullOrWhiteSpace($pname)) { return $false }
				foreach ($pattern in $ProcessNamePatterns)
				{
					if ($pname -like ("$pattern*")) { return $true }
				}
				return $false
			})
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Find-BaselineRunningInstance:catch263' -Severity Debug }

			$candidates = @()
		}
	}

	$matches = @()
	foreach ($p in $candidates)
	{
		if (-not $p) { continue }
		try
		{
			if ([int]$p.Id -eq [int]$CurrentProcessId) { continue }
			$pname = [string]$p.ProcessName
			if ([string]::IsNullOrWhiteSpace($pname)) { continue }
			$nameMatched = $false
			foreach ($pattern in $ProcessNamePatterns)
			{
				if ($pname -like ("$pattern*")) { $nameMatched = $true; break }
			}
			if (-not $nameMatched) { continue }
			$handle = [IntPtr]::Zero
			try { $handle = [IntPtr]$p.MainWindowHandle } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Find-BaselineRunningInstance:catch285' -Severity Debug }
			 $handle = [IntPtr]::Zero }
			if ($handle -eq [IntPtr]::Zero) { continue }
			$matches += [pscustomobject]@{
				ProcessId = [int]$p.Id
				MainWindowHandle = $handle
				ProcessName = $pname
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Find-BaselineRunningInstance:catch293' -Severity Debug }

			$null = $_
		}
	}

	if ($matches.Count -eq 0) { return $null }
	return ($matches | Sort-Object ProcessId | Select-Object -First 1)
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineSingleInstanceDecision
{
	<#
		.SYNOPSIS
		Pure decision helper: given a lock-acquisition result and a
		discovered running-instance record (or $null), returns the action
		the launcher should take.

		.DESCRIPTION
		Returns a pscustomobject with:
		  Action : 'Continue' | 'HandoffAndExit' | 'WarnAndContinue'
		  Reason : human-friendly explanation suitable for log output
		  TargetProcessId, TargetHandle : populated only when Action='HandoffAndExit'

		Decision matrix:
		  AllowMultipleInstances=$true               -> Continue (CI/test escape hatch)
		  Lock acquired                              -> Continue
		  Lock not acquired AND running instance     -> HandoffAndExit
		  Lock not acquired AND no running instance  -> HandoffAndExit
		    (the lock is held by another startup path before the WPF main
		     window can be discovered; exit instead of opening a second GUI)
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[object]$LockResult,

		[Parameter()]
		[AllowNull()]
		[object]$RunningInstance,

		[Parameter()]
		[switch]$AllowMultipleInstances
	)

	if ($AllowMultipleInstances)
	{
		return [pscustomobject]@{
			Action = 'Continue'
			Reason = 'AllowMultipleInstances opt-out is set.'
			TargetProcessId = $null
			TargetHandle = $null
		}
	}

	if ($LockResult -and $LockResult.PSObject.Properties['Acquired'] -and [bool]$LockResult.Acquired)
	{
		return [pscustomobject]@{
			Action = 'Continue'
			Reason = 'Single-instance lock acquired.'
			TargetProcessId = $null
			TargetHandle = $null
		}
	}

	if ($RunningInstance -and $RunningInstance.PSObject.Properties['ProcessId'] -and $RunningInstance.PSObject.Properties['MainWindowHandle'])
	{
		return [pscustomobject]@{
			Action = 'HandoffAndExit'
			Reason = ("Found running instance pid={0}; handing off." -f [int]$RunningInstance.ProcessId)
			TargetProcessId = [int]$RunningInstance.ProcessId
			TargetHandle = $RunningInstance.MainWindowHandle
		}
	}

	return [pscustomobject]@{
		Action = 'HandoffAndExit'
		Reason = 'Single-instance lock is held and no foregrounding target was found; exiting to preserve one GUI instance.'
		TargetProcessId = $null
		TargetHandle = $null
	}
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineSingleInstanceForeground
{
	<#
		.SYNOPSIS
		Restores (un-minimizes) and brings to the foreground the supplied
		window handle. Wraps user32!IsIconic / ShowWindow / SetForegroundWindow.

		.DESCRIPTION
		Best-effort by design - never throws. Win32 SetForegroundWindow has
		notoriously twitchy success criteria (the calling process must own
		the foreground or have just received input), so any failure mode
		(missing handle, sealed window, focus stolen by another app) is
		swallowed and reported as `Succeeded=$false` in the result rather
		than propagated to the launcher (which has nothing useful to do
		with the failure beyond logging it).
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[IntPtr]$WindowHandle
	)

	if ($WindowHandle -eq [IntPtr]::Zero)
	{
		return [pscustomobject]@{
			Succeeded = $false
			Reason = 'Window handle was zero.'
		}
	}

	try
	{
		if (-not ('Baseline.SingleInstance.NativeMethods' -as [type]))
		{
			$signature = @'
using System;
using System.Runtime.InteropServices;

namespace Baseline.SingleInstance
{
	public static class NativeMethods
	{
		public const int SW_RESTORE = 9;

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool IsIconic(IntPtr hWnd);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetForegroundWindow(IntPtr hWnd);
	}
}
'@
			Add-Type -TypeDefinition $signature -Language CSharp -ErrorAction Stop
		}

		if ([Baseline.SingleInstance.NativeMethods]::IsIconic($WindowHandle))
		{
			[void][Baseline.SingleInstance.NativeMethods]::ShowWindow($WindowHandle, [Baseline.SingleInstance.NativeMethods]::SW_RESTORE)
		}
		$brought = [Baseline.SingleInstance.NativeMethods]::SetForegroundWindow($WindowHandle)
		return [pscustomobject]@{
			Succeeded = [bool]$brought
			Reason = if ($brought) { 'Window brought to foreground.' } else { 'SetForegroundWindow returned false (focus stolen / blocked by foreground rules).' }
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SingleInstance.Helpers.Invoke-BaselineSingleInstanceForeground:catch457' -Severity Debug }

		return [pscustomobject]@{
			Succeeded = $false
			Reason = $_.Exception.Message
		}
	}
}
