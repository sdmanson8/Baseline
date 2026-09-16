using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Threading;

public static class LauncherShutdownProbe
{
    [STAThread]
    public static int Main(string[] args)
    {
        try
        {
            Environment.SetEnvironmentVariable("BASELINE_SHUTDOWN_TEST_ROOT", args[1]);
            Environment.SetEnvironmentVariable("BASELINE_SHUTDOWN_TEST_THREAD", Thread.CurrentThread.ManagedThreadId.ToString());
            Environment.SetEnvironmentVariable("BASELINE_SHUTDOWN_TEST_LOG", Path.Combine(args[3], "shutdown.log"));
            File.AppendAllText(Path.Combine(args[3], "shutdown.log"), "native entry\n");
            Assembly launcher = Assembly.LoadFrom(args[0]);
            Type program = launcher.GetType("Baseline.RunLauncher.Program", true);
            MethodInfo entry = program.GetMethod("StartEmbeddedPowerShell", BindingFlags.NonPublic | BindingFlags.Static);
            int result = (int)entry.Invoke(null, new object[] {
                args[2], args[0], args[1], args[3], false, false, "en-US", new string[0]
            });
            Dispatcher dispatcher = Dispatcher.FromThread(Thread.CurrentThread);
            File.AppendAllText(Path.Combine(args[3], "shutdown.log"), "native workflow returned\n");
            if (dispatcher != null && !dispatcher.HasShutdownFinished)
                throw new Exception("Launcher returned without shutting down its GUI dispatcher.");
            File.AppendAllText(Path.Combine(args[3], "shutdown.log"), "main returning " + result + "\n");
            return result;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
