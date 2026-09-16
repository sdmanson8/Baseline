using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace Baseline.RunLauncher
{
    // Explicit binding policy for the four framework support libraries shipped
    // with Markdig and referenced by the Windows Appx/WinRT projection. Keep the
    // supported upper versions aligned with the packaged NuGet dependencies.
    internal static class BundledAssemblyResolver
    {
        private static readonly Dictionary<string, Version> Versions = new Dictionary<string, Version>(StringComparer.OrdinalIgnoreCase)
        {
            { "System.Numerics.Vectors", new Version(4, 1, 6, 0) },
            { "System.Runtime.CompilerServices.Unsafe", new Version(6, 0, 3, 0) },
            { "System.Memory", new Version(4, 0, 5, 0) },
            { "System.Buffers", new Version(4, 0, 5, 0) }
        };

        internal static void Install(string librariesRoot)
        {
            var paths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var identities = new Dictionary<string, AssemblyName>(StringComparer.OrdinalIgnoreCase);
            foreach (var policy in Versions)
            {
                var path = Path.Combine(librariesRoot, policy.Key + ".dll");
                var identity = AssemblyName.GetAssemblyName(path);
                if (identity.Version != policy.Value)
                    throw new InvalidOperationException("Bundled assembly binding policy requires review: " + identity.FullName);
                paths.Add(policy.Key, path);
                identities.Add(policy.Key, identity);
            }
            AppDomain.CurrentDomain.AssemblyResolve += (sender, args) =>
            {
                var requested = new AssemblyName(args.Name);
                AssemblyName bundled;
                return identities.TryGetValue(requested.Name, out bundled)
                    ? Resolve(paths[requested.Name], bundled, requested) : ResolvePowerShellAssembly(requested);
            };
        }

        // powershell.exe normally probes these framework facades from its own
        // application directory. An embedded host must supply that same location.
        internal static Assembly ResolvePowerShellAssembly(AssemblyName requested)
        {
            if (String.IsNullOrEmpty(requested.Name)
                || requested.Name.IndexOfAny(new[] { '/', '\\', ':' }) >= 0
                || requested.GetPublicKeyToken() == null || requested.GetPublicKeyToken().Length == 0)
                return null;
            var path = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", requested.Name + ".dll");
            if (!File.Exists(path)) return null;
            AssemblyName installed;
            try { installed = AssemblyName.GetAssemblyName(path); }
            catch (BadImageFormatException) { return null; }
            if (!String.Equals(installed.FullName, requested.FullName, StringComparison.OrdinalIgnoreCase)) return null;
            return Assembly.LoadFrom(path);
        }
        internal static Assembly Resolve(string path, AssemblyName bundled, AssemblyName requested)
        {
            Version supported;
            if (!Versions.TryGetValue(bundled.Name, out supported)
                || !String.Equals(requested.Name, bundled.Name, StringComparison.OrdinalIgnoreCase)
                || !String.Equals(requested.CultureName ?? "", bundled.CultureName ?? "", StringComparison.OrdinalIgnoreCase)
                || BitConverter.ToString(requested.GetPublicKeyToken() ?? new byte[0]) != BitConverter.ToString(bundled.GetPublicKeyToken() ?? new byte[0])
                || requested.Version == null
                || requested.Version < new Version(4, 0, 0, 0)
                || requested.Version > supported
                || bundled.Version != supported)
                return null;
            return Assembly.LoadFrom(path);
        }
    }
}
