# Detection is queued from rendering; Windows queries never execute on the dispatcher.
. (Join-Path $PSScriptRoot '../GUIExecution/WorkerLifecycle.ps1')
$Script:GuiDetectionWorker = $null
$Script:GuiDetectionSubscriptions = @{}
$Script:GuiDetectionFailures = @{}

function Request-GuiBackgroundDetection {
    param([object]$Tweak)
    if (-not $Script:GuiDetectionWorker) {
        $session = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $session.ImportPSModule(@((Join-Path $PSScriptRoot '../SharedHelpers.psm1')))
        $pool = [runspacefactory]::CreateRunspacePool(1, 2, $session, $Host)
        $opening = $pool.BeginOpen($null, $null)
        $timer = [Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({ Receive-GuiBackgroundDetections })
        $Script:GuiDetectionWorker = @{Pool=$pool; Opening=$opening; OpenError=$null; Pending=@{}; Timer=$timer}
    }
    $worker = $Script:GuiDetectionWorker
    $key = [string]$Tweak.Function
    if ($worker.Pending.ContainsKey($key) -or $Script:GuiDetectionFailures.ContainsKey($key)) { return }
    $ps = [powershell]::Create()
    $ps.RunspacePool = $worker.Pool
    $null = $ps.AddScript({
        param($HelpersPath, $DetectionText)
        . $HelpersPath
        $ErrorActionPreference = 'Stop'
        $value = & ([scriptblock]::Create($DetectionText))
        [bool]$value
    }).AddArgument((Join-Path $PSScriptRoot 'DetectScriptblocks.ps1')).AddArgument($Tweak.Detect.ToString())
    try {
        $worker.Pending[$key] = @{PowerShell=$ps; Async=$null}
        $worker.Timer.Start()
    } catch { $ps.Dispose(); throw }
}

function Receive-GuiBackgroundDetections {
    $worker = $Script:GuiDetectionWorker
    if (-not $worker) { return }
    if ($worker.Opening) {
        if (-not $worker.Opening.IsCompleted) { return }
        try { $worker.Pool.EndOpen($worker.Opening) } catch { $worker.OpenError = $_.Exception.Message }
        $worker.Opening = $null
    }
    foreach ($key in @($worker.Pending.Keys)) {
        $request = $worker.Pending[$key]
        try {
            if ($worker.OpenError) { throw $worker.OpenError }
            if (-not $request.Async) { $request.Async = $request.PowerShell.BeginInvoke() }
            if (-not $request.Async.IsCompleted) { continue }
            $output = $request.PowerShell.EndInvoke($request.Async)
            if ($output.Count -ne 1) { throw "Detection for '$key' did not return one result." }
            # A scan or completed tweak may have published a newer result while
            # this query was running. Do not replace that explicit update.
            if ($null -eq (Get-CachedDetection -Function $key)) {
                Set-CachedDetection -Function $key -Value ([bool]$output[0])
            }
        } catch {
            $Script:GuiDetectionFailures[$key] = $_.Exception.Message
            Write-GuiRuntimeWarning -Context 'BackgroundDetection' -Message ("{0}: {1}" -f $key, $_.Exception.Message)
        } finally {
            if ($worker.OpenError -or -not $request.Async -or $request.Async.IsCompleted) {
                $request.PowerShell.Dispose()
                $worker.Pending.Remove($key)
            }
        }
        if ($Script:GuiDetectionSubscriptions.ContainsKey($key)) {
            & $Script:GuiDetectionSubscriptions[$key]
        }
    }
    if ($worker.Pending.Count -eq 0) { $worker.Timer.Stop() }
}

function Stop-GuiBackgroundDetection {
    $worker = $Script:GuiDetectionWorker
    if (-not $worker) { return }
    $worker.Timer.Stop()
    # Retain ownership until cancellation and disposal finish off the dispatcher.
    $pipelines = [Management.Automation.PowerShell[]]@($worker.Pending.Values | ForEach-Object { $_.PowerShell })
    [Baseline.GuiExecution.WorkerLifecycle]::StopPoolAndDispose($pipelines, $worker.Pool, $worker.Opening)
    $Script:GuiDetectionSubscriptions.Clear()
    $Script:GuiDetectionWorker = $null
}
