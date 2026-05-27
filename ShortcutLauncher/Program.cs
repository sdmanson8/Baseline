// Internal GUI-only shortcut launcher that locates Baseline.exe and starts it.
// Used by the installer and desktop shortcut flow.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace Baseline.ShortcutLauncher
{
    internal static class Program
    {
        /// <summary>
        /// Displays a native message box for launcher errors.
        /// </summary>
        /// <param name="hWnd">The owner window handle.</param>
        /// <param name="text">The message text.</param>
        /// <param name="caption">The window caption.</param>
        /// <param name="type">The message box type flags.</param>
        /// <returns>The native message-box result.</returns>
        [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
        private static extern int NativeMsgBox(IntPtr hWnd, string text, string caption, uint type);
        private const uint MB_OK        = 0x00000000;
        private const uint MB_ICONERROR = 0x00000010;

        /// <summary>
        /// Internal GUI-only shortcut launcher entrypoint for Baseline.
        /// </summary>
        /// <param name="args">Command-line arguments; unsupported by this GUI-only helper.</param>
        /// <returns>An exit code suitable for the host process.</returns>
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                if (args != null && args.Length > 0)
                {
                    NativeMsgBox(IntPtr.Zero,
                        "Baseline shortcut launcher does not accept command-line arguments. Run Baseline.exe directly for CLI workflows.",
                        "Baseline", MB_OK | MB_ICONERROR);
                    return 2;
                }

                var exeDir = Path.GetDirectoryName(
                    System.Reflection.Assembly.GetExecutingAssembly().Location) ?? string.Empty;
                var script = Path.Combine(exeDir, "Bootstrap", "Baseline.ps1");

                if (!File.Exists(script))
                {
                    NativeMsgBox(IntPtr.Zero,
                        "Could not find launcher script:\n" + script,
                        "Baseline", MB_OK | MB_ICONERROR);
                    return 1;
                }

                var shell = FindShell();

                // UseShellExecute=true so Windows honours the requireAdministrator manifest
                // embedded in this exe — PowerShell inherits the elevated token.
                var psi = new ProcessStartInfo
                {
                    FileName         = shell,
                    Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"",
                    UseShellExecute  = true,
                    WorkingDirectory = exeDir
                };

                var proc = Process.Start(psi);
                return proc == null ? 1 : 0;
            }
            catch (Exception ex)
            {
                NativeMsgBox(IntPtr.Zero,
                    "Baseline failed to start:\n" + ex.Message,
                    "Baseline", MB_OK | MB_ICONERROR);
                return 1;
            }
        }

        /// <summary>
        /// Locates a usable PowerShell executable.
        /// </summary>
        /// <returns>The resolved trusted shell path.</returns>
        private static string FindShell()
        {
            var windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            var candidates = new[]
            {
                Path.Combine(windowsDir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
                Path.Combine(windowsDir, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe")
            };

            foreach (var path in candidates)
            {
                if (File.Exists(path)) return path;
            }

            throw new FileNotFoundException(
                "Windows PowerShell 5.1 (powershell.exe) was not found at the trusted System32 path.",
                candidates[0]);
        }
    }
}
