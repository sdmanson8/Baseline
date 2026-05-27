<#
    .SYNOPSIS
#>
function Initialize-GuiDpiAwareness
{
	param ()

	if (-not ('WinAPI.GuiDpiHelper' -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class GuiDpiHelper
	{
		// PROCESS_PER_MONITOR_DPI_AWARE_V2 = 2 (Windows 10 1703+)
		// Falls back to PROCESS_PER_MONITOR_DPI_AWARE = 2 via shcore on older builds
		[DllImport("user32.dll", SetLastError = true)]
		public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

		[DllImport("shcore.dll", SetLastError = true)]
		public static extern int SetProcessDpiAwareness(int awareness);

		public static void Enable()
		{
			try
			{
				// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
				if (!SetProcessDpiAwarenessContext(new IntPtr(-4)))
				{
					// Fallback: PROCESS_PER_MONITOR_DPI_AWARE = 2
					SetProcessDpiAwareness(2);
				}
			}
			catch
			{
				try { SetProcessDpiAwareness(2); }
				catch (Exception ex)
				{
					System.Diagnostics.Debug.WriteLine("Baseline DPI fallback failed: " + ex.Message);
				}
			}
		}
	}
}
"@ -ErrorAction Stop | Out-Null
	}

	try { [WinAPI.GuiDpiHelper]::Enable() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DpiAwareness.Initialize-GuiDpiAwareness.Enable' }
}

