// Read-only integration host: same CLR/runspace model as Baseline.exe.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Baseline.RunLauncher;
public static class AppxRuntimeProbe {
    [STAThread]
    public static int Main(string[] args) {
        try {
            BundledAssemblyResolver.Install(args[0]);
            using (var runspace = RunspaceFactory.CreateRunspace()) {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.Open();
                using (var ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddScript(@"
param($libraries)
$ErrorActionPreference = 'Stop'
foreach ($file in @('System.Buffers.dll','System.Runtime.CompilerServices.Unsafe.dll','System.Numerics.Vectors.dll','System.Memory.dll','Markdig.dll','Markdig.Wpf.dll')) { Add-Type -Path (Join-Path $libraries $file) }
$packages = @(Get-AppxPackage -ErrorAction Stop)
$bundles = @(Get-AppxPackage -PackageTypeFilter Bundle -ErrorAction Stop)
'Appx enumeration succeeded: {0} packages, {1} bundles; PowerShell {2}' -f $packages.Count,$bundles.Count,$PSVersionTable.PSVersion
").AddArgument(args[0]);
                    foreach (var result in ps.Invoke()) Console.WriteLine(result);
                    if (ps.HadErrors) { foreach (var error in ps.Streams.Error) Console.Error.WriteLine(error); return 1; }
                }
            }
            return 0;
        } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
}
