<#
	.SYNOPSIS
	Records a session-log error when the WPF dispatcher stops responding.
#>

$Script:GuiResponsivenessWatchdogTypeInitialized = $false

function Initialize-GuiResponsivenessWatchdogType
{
	[CmdletBinding()]
	param()

	if ($Script:GuiResponsivenessWatchdogTypeInitialized -and ('Baseline.GuiResponsivenessWatchdog' -as [type]))
	{
		return
	}

	if ('Baseline.GuiResponsivenessWatchdog' -as [type])
	{
		$Script:GuiResponsivenessWatchdogTypeInitialized = $true
		return
	}

	$source = @'
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Threading;

namespace Baseline
{
    public sealed class GuiResponsivenessWatchdog : IDisposable
    {
        private readonly Dispatcher dispatcher;
        private readonly string logPath;
        private readonly string runIdShort;
        private readonly int intervalMilliseconds;
        private readonly long thresholdTicks;
        private readonly string windowTitle;
        private readonly int processId;
        private readonly object gate = new object();
        private readonly Thread worker;

        private volatile bool stopRequested;
        private long pendingSinceUtcTicks;
        private int pendingHeartbeatId;
        private bool hangLogged;
        private int loggedHangHeartbeatId;
        private long loggedHangStartedUtcTicks;
        private bool internalFailureLogged;

        public GuiResponsivenessWatchdog(
            Dispatcher dispatcher,
            string logPath,
            string runIdShort,
            int intervalMilliseconds,
            int thresholdMilliseconds,
            string windowTitle)
        {
            if (dispatcher == null) { throw new ArgumentNullException("dispatcher"); }
            if (String.IsNullOrWhiteSpace(logPath)) { throw new ArgumentException("A log path is required.", "logPath"); }

            this.dispatcher = dispatcher;
            this.logPath = logPath;
            this.runIdShort = String.IsNullOrWhiteSpace(runIdShort) ? "unknown" : runIdShort;
            this.intervalMilliseconds = Math.Max(100, intervalMilliseconds);
            this.thresholdTicks = TimeSpan.FromMilliseconds(Math.Max(1000, thresholdMilliseconds)).Ticks;
            this.windowTitle = String.IsNullOrWhiteSpace(windowTitle) ? "Baseline" : windowTitle;
            this.processId = Process.GetCurrentProcess().Id;
            this.worker = new Thread(this.Run);
            this.worker.IsBackground = true;
            this.worker.Name = "Baseline GUI responsiveness watchdog";
        }

        public void Start()
        {
            this.worker.Start();
        }

        public void Stop()
        {
            this.stopRequested = true;
            if (this.worker.IsAlive && !this.worker.Join(2000))
            {
                this.AppendLogLine("WARNING", "GUI responsiveness watchdog did not stop within 2000 ms.");
            }
        }

        public void Dispose()
        {
            this.Stop();
        }

        private void Run()
        {
            while (!this.stopRequested)
            {
                try
                {
                    this.Tick();
                }
                catch (Exception ex)
                {
                    this.LogInternalFailure(ex);
                }

                Thread.Sleep(this.intervalMilliseconds);
            }
        }

        private void Tick()
        {
            if (this.dispatcher.HasShutdownStarted || this.dispatcher.HasShutdownFinished)
            {
                this.stopRequested = true;
                return;
            }

            bool shouldPostHeartbeat = false;
            bool shouldLogHang = false;
            int heartbeatId = 0;
            double elapsedSeconds = 0;
            long nowTicks = DateTime.UtcNow.Ticks;

            lock (this.gate)
            {
                if (this.pendingSinceUtcTicks == 0)
                {
                    this.pendingSinceUtcTicks = nowTicks;
                    this.pendingHeartbeatId++;
                    heartbeatId = this.pendingHeartbeatId;
                    shouldPostHeartbeat = true;
                }
                else
                {
                    long elapsedTicks = nowTicks - this.pendingSinceUtcTicks;
                    if (!this.hangLogged && elapsedTicks >= this.thresholdTicks)
                    {
                        this.hangLogged = true;
                        this.loggedHangHeartbeatId = this.pendingHeartbeatId;
                        this.loggedHangStartedUtcTicks = this.pendingSinceUtcTicks;
                        elapsedSeconds = TimeSpan.FromTicks(elapsedTicks).TotalSeconds;
                        shouldLogHang = true;
                    }
                }
            }

            if (shouldLogHang)
            {
                string message = String.Format(
                    CultureInfo.InvariantCulture,
                    "GUI responsiveness failure: WPF dispatcher heartbeat {0} has not completed for {1:0.0}s (threshold {2:0.0}s). Windows may show the Not Responding / Close now or wait dialog. Treating this as a GUI crash/hang. ProcessId={3}; Window='{4}'.",
                    this.loggedHangHeartbeatId,
                    elapsedSeconds,
                    TimeSpan.FromTicks(this.thresholdTicks).TotalSeconds,
                    this.processId,
                    this.windowTitle);
                this.AppendLogLine("DEBUG", message);
            }

            if (shouldPostHeartbeat)
            {
                try
                {
					this.dispatcher.BeginInvoke(
						DispatcherPriority.Send,
						new Action(delegate { this.CompleteHeartbeat(heartbeatId); }));
                }
                catch (Exception ex)
                {
                    this.LogInternalFailure(ex);
                }
            }
        }

        private void CompleteHeartbeat(int heartbeatId)
        {
            bool shouldLogRecovery = false;
            double elapsedSeconds = 0;

            lock (this.gate)
            {
                if (heartbeatId != this.pendingHeartbeatId)
                {
                    return;
                }

                if (this.hangLogged && this.loggedHangHeartbeatId == heartbeatId)
                {
                    elapsedSeconds = TimeSpan.FromTicks(DateTime.UtcNow.Ticks - this.loggedHangStartedUtcTicks).TotalSeconds;
                    shouldLogRecovery = true;
                    this.hangLogged = false;
                    this.loggedHangHeartbeatId = 0;
                    this.loggedHangStartedUtcTicks = 0;
                }

                this.pendingSinceUtcTicks = 0;
            }

            if (shouldLogRecovery)
            {
                this.AppendLogLine(
                    "DEBUG",
                    String.Format(CultureInfo.InvariantCulture, "GUI dispatcher recovered after {0:0.0}s of unresponsiveness.", elapsedSeconds));
            }
        }

        private void LogInternalFailure(Exception exception)
        {
            if (this.internalFailureLogged) { return; }
            this.internalFailureLogged = true;
            string message = "GUI responsiveness watchdog failed: " + exception.GetType().FullName + ": " + exception.Message;
            this.AppendLogLine("WARNING", message);
        }

        private void AppendLogLine(string level, string message)
        {
            try
            {
                string directory = Path.GetDirectoryName(this.logPath);
                if (!String.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                string line = String.Format(
                    CultureInfo.InvariantCulture,
                    "{0} {1}: [RunId={2}] [GUI] {3}{4}",
                    DateTime.Now.ToString("dd-MM-yyyy HH:mm", CultureInfo.InvariantCulture),
                    level,
                    this.runIdShort,
                    message,
                    Environment.NewLine);
                File.AppendAllText(this.logPath, line, Encoding.UTF8);
            }
            catch
            {
            }
        }
    }
}
'@

	Add-Type -AssemblyName WindowsBase -ErrorAction Stop
	$windowsBaseAssembly = [System.Windows.Threading.Dispatcher].Assembly.Location
	Add-Type -TypeDefinition $source -ReferencedAssemblies $windowsBaseAssembly -ErrorAction Stop
	$Script:GuiResponsivenessWatchdogTypeInitialized = $true
}

function Start-GuiResponsivenessWatchdog
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[string]$LogPath = [string]$global:LogFilePath,

		[string]$RunIdShort = $(if (Get-Command -Name 'Get-BaselineRunIdShort' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineRunIdShort } else { 'unknown' }),

		[int]$HeartbeatIntervalMilliseconds = 1000,

		[int]$HangThresholdMilliseconds = 4000
	)

	if (-not $Window -or -not $Window.Dispatcher)
	{
		return $null
	}

	Initialize-GuiResponsivenessWatchdogType

	$title = try { [string]$Window.Title } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GuiResponsivenessWatchdog.Start-GuiResponsivenessWatchdog:catch276' -Severity Debug }
	 'Baseline' }
	$watchdog = [Baseline.GuiResponsivenessWatchdog]::new(
		$Window.Dispatcher,
		$LogPath,
		$RunIdShort,
		$HeartbeatIntervalMilliseconds,
		$HangThresholdMilliseconds,
		$title)
	$watchdog.Start()
	return $watchdog
}

function Stop-GuiResponsivenessWatchdog
{
	[CmdletBinding()]
	param(
		[object]$Watchdog
	)

	if (-not $Watchdog)
	{
		return
	}

	try { $Watchdog.Stop() }
	finally
	{
		if ($Watchdog -is [System.IDisposable])
		{
			$Watchdog.Dispose()
		}
	}
}
