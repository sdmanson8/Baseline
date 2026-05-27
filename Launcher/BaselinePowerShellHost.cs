// Internal PowerShell host implementation used by the Baseline launcher.
// Keeps host/UI wiring isolated from the PowerShell entry script.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Runtime.InteropServices;
using System.Security;

namespace Baseline.RunLauncher
{
    internal sealed class BaselinePowerShellHost : PSHost, IDisposable
    {
        private readonly Guid _instanceId = Guid.NewGuid();
        private readonly BaselinePowerShellHostUserInterface _ui = new BaselinePowerShellHostUserInterface();
        private int _exitCode;
        private bool _shouldExit;

        public bool ShouldExit
        {
            get { return _shouldExit; }
        }

        public int ExitCode
        {
            get { return _exitCode; }
        }

        public override CultureInfo CurrentCulture
        {
            get { return CultureInfo.CurrentCulture; }
        }

        public override CultureInfo CurrentUICulture
        {
            get { return CultureInfo.CurrentUICulture; }
        }

        public override Guid InstanceId
        {
            get { return _instanceId; }
        }

        public override string Name
        {
            get { return "BaselineHost"; }
        }

        public override PSHostUserInterface UI
        {
            get { return _ui; }
        }

        public override Version Version
        {
            get { return new Version(1, 0); }
        }

        /// <summary>
        /// Rejects nested prompts in the launcher host.
        /// </summary>
        public override void EnterNestedPrompt()
        {
            throw new NotSupportedException("Nested prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects nested prompt exit calls in the launcher host.
        /// </summary>
        public override void ExitNestedPrompt()
        {
            throw new NotSupportedException("Nested prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Notifies the host that application execution is starting.
        /// </summary>
        public override void NotifyBeginApplication()
        {
        }

        /// <summary>
        /// Notifies the host that application execution has ended.
        /// </summary>
        public override void NotifyEndApplication()
        {
        }

        /// <summary>
        /// Captures the exit code requested by the PowerShell runtime.
        /// </summary>
        /// <param name="exitCode">The requested exit code.</param>
        public override void SetShouldExit(int exitCode)
        {
            _shouldExit = true;
            _exitCode = exitCode;
        }

        /// <summary>
        /// Disposes the launcher host.
        /// </summary>
        public void Dispose()
        {
        }
    }

    internal sealed class BaselinePowerShellHostUserInterface : PSHostUserInterface
    {
        private readonly BaselinePowerShellHostRawUserInterface _rawUi = new BaselinePowerShellHostRawUserInterface();

        public override PSHostRawUserInterface RawUI
        {
            get { return _rawUi; }
        }

        /// <summary>
        /// Rejects interactive prompts in the launcher host.
        /// </summary>
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
        {
            throw new NotSupportedException("Interactive prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects choice prompts in the launcher host.
        /// </summary>
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
        {
            throw new NotSupportedException("Interactive prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects credential prompts in the launcher host.
        /// </summary>
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        {
            throw new NotSupportedException("Credential prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects extended credential prompts in the launcher host.
        /// </summary>
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        {
            throw new NotSupportedException("Credential prompts are not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects interactive line input in the launcher host.
        /// </summary>
        public override string ReadLine()
        {
            throw new NotSupportedException("Console input is not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects secure line input in the launcher host.
        /// </summary>
        public override SecureString ReadLineAsSecureString()
        {
            throw new NotSupportedException("Console input is not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Writes text to the available console surfaces.
        /// </summary>
        /// <param name="value">The text to write.</param>
        public override void Write(string value)
        {
            WriteToAvailableConsole(value);
        }

        /// <summary>
        /// Writes text with color information when supported.
        /// </summary>
        /// <param name="foregroundColor">The foreground color.</param>
        /// <param name="backgroundColor">The background color.</param>
        /// <param name="value">The text to write.</param>
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
        {
            if (!HasConsoleWindow())
            {
                Trace.Write(value);
                return;
            }

            ConsoleColor originalForeground = Console.ForegroundColor;
            ConsoleColor originalBackground = Console.BackgroundColor;

            try
            {
                Console.ForegroundColor = foregroundColor;
                Console.BackgroundColor = backgroundColor;
                Console.Write(value);
            }
            finally
            {
                Console.ForegroundColor = originalForeground;
                Console.BackgroundColor = originalBackground;
            }
        }

        /// <summary>
        /// Writes a debug line to the available console surfaces.
        /// </summary>
        /// <param name="message">The debug message.</param>
        public override void WriteDebugLine(string message)
        {
            Trace.WriteLine(message);
            WriteLine(message);
        }

        /// <summary>
        /// Writes an error line to the available console surfaces.
        /// </summary>
        /// <param name="value">The error text.</param>
        public override void WriteErrorLine(string value)
        {
            Trace.TraceError(value);
            WriteLine(value);
        }

        /// <summary>
        /// Writes a blank line to the available console surfaces.
        /// </summary>
        public override void WriteLine()
        {
            WriteToAvailableConsole(Environment.NewLine);
        }

        /// <summary>
        /// Writes a line of text to the available console surfaces.
        /// </summary>
        /// <param name="value">The text to write.</param>
        public override void WriteLine(string value)
        {
            WriteToAvailableConsole(value + Environment.NewLine);
        }

        /// <summary>
        /// Ignores progress records in the launcher host.
        /// </summary>
        /// <param name="sourceId">The progress source identifier.</param>
        /// <param name="record">The progress record.</param>
        public override void WriteProgress(long sourceId, ProgressRecord record)
        {
        }

        /// <summary>
        /// Writes a verbose line to the available console surfaces.
        /// </summary>
        /// <param name="message">The verbose message.</param>
        public override void WriteVerboseLine(string message)
        {
            Trace.WriteLine(message);
            WriteLine(message);
        }

        /// <summary>
        /// Writes a warning line to the available console surfaces.
        /// </summary>
        /// <param name="message">The warning message.</param>
        public override void WriteWarningLine(string message)
        {
            Trace.TraceWarning(message);
            WriteLine(message);
        }

        /// <summary>
        /// Writes text to the console or debug output when available.
        /// </summary>
        /// <param name="value">The text to write.</param>
        private static void WriteToAvailableConsole(string value)
        {
            if (HasConsoleWindow())
            {
                Console.Write(value);
            }
            else
            {
                Trace.Write(value);
            }
        }

        /// <summary>
        /// Detects whether a console window is attached.
        /// </summary>
        /// <returns>True when a console window is available.</returns>
        private static bool HasConsoleWindow()
        {
            return GetConsoleWindow() != IntPtr.Zero;
        }

        [DllImport("kernel32.dll")]
        /// <summary>
        /// Retrieves the native console window handle.
        /// </summary>
        /// <returns>The console window handle.</returns>
        private static extern IntPtr GetConsoleWindow();
    }

    internal sealed class BaselinePowerShellHostRawUserInterface : PSHostRawUserInterface
    {
        private ConsoleColor _backgroundColor = ConsoleColor.Black;
        private Size _bufferSize = new Size(120, 30);
        private Coordinates _cursorPosition = new Coordinates(0, 0);
        private int _cursorSize = 25;
        private ConsoleColor _foregroundColor = ConsoleColor.White;
        private Coordinates _windowPosition = new Coordinates(0, 0);
        private Size _windowSize = new Size(120, 30);
        private string _windowTitle = "Baseline";

        public override ConsoleColor BackgroundColor
        {
            get { return _backgroundColor; }
            set { _backgroundColor = value; }
        }

        public override Size BufferSize
        {
            get { return _bufferSize; }
            set { _bufferSize = value; }
        }

        public override Coordinates CursorPosition
        {
            get { return _cursorPosition; }
            set { _cursorPosition = value; }
        }

        public override int CursorSize
        {
            get { return _cursorSize; }
            set { _cursorSize = value; }
        }

        public override ConsoleColor ForegroundColor
        {
            get { return _foregroundColor; }
            set { _foregroundColor = value; }
        }

        public override bool KeyAvailable
        {
            get { return false; }
        }

        public override Size MaxPhysicalWindowSize
        {
            get { return _windowSize; }
        }

        public override Size MaxWindowSize
        {
            get { return _windowSize; }
        }

        public override Coordinates WindowPosition
        {
            get { return _windowPosition; }
            set { _windowPosition = value; }
        }

        public override Size WindowSize
        {
            get { return _windowSize; }
            set { _windowSize = value; }
        }

        public override string WindowTitle
        {
            get { return _windowTitle; }
            set { _windowTitle = value ?? "Baseline"; }
        }

        /// <summary>
        /// Clears any buffered input for the launcher host.
        /// </summary>
        public override void FlushInputBuffer()
        {
        }

        /// <summary>
        /// Returns the requested buffer region.
        /// </summary>
        /// <param name="rectangle">The buffer rectangle to read.</param>
        /// <returns>The requested buffer contents.</returns>
        public override BufferCell[,] GetBufferContents(Rectangle rectangle)
        {
            return new BufferCell[0, 0];
        }

        /// <summary>
        /// Measures the width of text in buffer cells.
        /// </summary>
        /// <param name="source">The source text.</param>
        /// <returns>The cell width.</returns>
        public override int LengthInBufferCells(string source)
        {
            return string.IsNullOrEmpty(source) ? 0 : source.Length;
        }

        /// <summary>
        /// Rejects key input in the launcher host.
        /// </summary>
        /// <param name="options">The key read options.</param>
        /// <returns>Never returns a key in this host.</returns>
        public override KeyInfo ReadKey(ReadKeyOptions options)
        {
            throw new NotSupportedException("Console input is not available in the Baseline launcher host.");
        }

        /// <summary>
        /// Rejects scroll requests in the launcher host.
        /// </summary>
        /// <param name="source">The source rectangle.</param>
        /// <param name="destination">The destination coordinates.</param>
        /// <param name="clip">The clipping rectangle.</param>
        /// <param name="fill">The fill cell.</param>
        public override void ScrollBufferContents(Rectangle source, Coordinates destination, Rectangle clip, BufferCell fill)
        {
        }

        /// <summary>
        /// Rejects rectangular buffer writes in the launcher host.
        /// </summary>
        /// <param name="origin">The origin coordinates.</param>
        /// <param name="contents">The buffer contents.</param>
        public override void SetBufferContents(Coordinates origin, BufferCell[,] contents)
        {
        }

        /// <summary>
        /// Rejects fill-based buffer writes in the launcher host.
        /// </summary>
        /// <param name="rectangle">The target rectangle.</param>
        /// <param name="fill">The fill cell.</param>
        public override void SetBufferContents(Rectangle rectangle, BufferCell fill)
        {
        }
    }
}
