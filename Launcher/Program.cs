// Internal launcher entrypoint for the Baseline run host.
// Resolves the embedded PowerShell workflow and starts it inside a managed host.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Threading;
using System.Text;

namespace Baseline.RunLauncher
{
    internal static class Program
    {
        private const string LauncherRelativePath = @"Bootstrap\Baseline.ps1";
        private const string EmbeddedHostVar = "BASELINE_EMBEDDED_HOST";
        private const string LauncherPathVar = "BASELINE_LAUNCHER_PATH";
        private const string StateRootVar = "BASELINE_STATE_ROOT";
        private const string PortableModeVar = "BASELINE_PORTABLE_MODE";
        private const string PortableMarkerFileName = "Baseline.portable";
        private const string InstallerModeVar = "BASELINE_INSTALLER_MODE";
        private const string IntegrityModeVar = "BASELINE_INTEGRITY_MODE";
        private const string LanguageVar = "BASELINE_LANGUAGE";
        private const string PowerShellExecutionPolicyPreferenceVar = "PSExecutionPolicyPreference";
        private const string PayloadPrefix = "BaselinePayload/";
        private const string HydrationSentinel = ".baseline-runtime-ready";
        private const string HydrationManifest = ".baseline-runtime-manifest.sha256";
        private const string RuntimeCacheSchema = "4";
        private const string RuntimeCacheFolderName = "RC";
        private const string StagingSuffix = ".s";
        private const string LauncherGuiInstanceMutexPrefix = @"Local\Baseline-GuiInstance-";
        private const string ConsoleGuiArgumentName = "ConsoleGui";
        private static readonly byte[] Utf8Bom = new byte[] { 0xEF, 0xBB, 0xBF };
        private const int DefaultPowerShellTimeoutSeconds = 1800;
        private const string PowerShellTimeoutSecondsVar = "BASELINE_POWERSHELL_TIMEOUT_SECONDS";
        private static readonly string[] HeadlessPowerShellArguments = new[]
        {
            "Functions",
            "Preset",
            "GameModeProfile",
            "ScenarioProfile",
            "ApplyProfile",
            "Run",
            "ScheduledRun",
            "ProfilePath",
            "ConfigFile",
            "ComplianceCheck",
            "NoGui",
            "ListPresets",
            "ApplyPreset",
            "LifecycleOperation",
            "TargetComputer"
        };
        private static readonly HashSet<string> BootstrapPowerShellParameterNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Functions",
            "Include",
            "Preset",
            "GameModeProfile",
            "ScenarioProfile",
            "GameModeDecisionOverrides",
            "DryRun",
            "ComplianceCheck",
            "ApplyProfile",
            "Run",
            "ScheduledRun",
            "ProfilePath",
            "ConfigFile",
            "ReadOnly",
            "OutputFormat",
            "Apply",
            "NoGui",
            "ConsoleGui",
            "Design",
            "ListPresets",
            "ApplyPreset",
            "LogPath",
            "LifecycleOperation",
            "LifecycleInstallerPath",
            "LifecycleRollbackProfilePath",
            "LifecycleSupportBundlePath",
            "LifecycleOutputPath",
            "LifecycleExecute",
            "TargetComputer",
            "RemoteCredential"
        };
        private static readonly HashSet<string> BootstrapSwitchParameterNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "DryRun",
            "ComplianceCheck",
            "ApplyProfile",
            "Run",
            "ScheduledRun",
            "ReadOnly",
            "Apply",
            "NoGui",
            "ConsoleGui",
            "Design",
            "ListPresets",
            "LifecycleExecute"
        };
        private static readonly HashSet<string> BootstrapArrayParameterNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Functions",
            "Include",
            "TargetComputer"
        };
        private static readonly Dictionary<string, string> BootstrapParameterAliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "Run", "ApplyProfile" },
            { "ConfigFile", "ProfilePath" }
        };

        private sealed class PayloadEntry
        {
            internal string ResourceName { get; set; }
            internal string RelativePath { get; set; }
            internal string Sha256 { get; set; }
        }

        /// <summary>
        /// Displays a native message box for fatal launcher errors.
        /// </summary>
        /// <param name="hWnd">The owner window handle.</param>
        /// <param name="text">The message text.</param>
        /// <param name="caption">The window caption.</param>
        /// <param name="type">The message box type flags.</param>
        /// <returns>The native message-box result.</returns>
        [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
        private static extern int NativeMsgBox(IntPtr hWnd, string text, string caption, uint type);
        private const uint MB_OK = 0x00000000;
        private const uint MB_ICONERROR = 0x00000010;
        private const uint MB_ICONWARNING = 0x00000030;

        /// <summary>
        /// Internal launcher entrypoint for Baseline.
        /// </summary>
        /// <param name="args">Command-line arguments forwarded to the embedded PowerShell workflow.</param>
        /// <returns>An exit code suitable for the host process.</returns>
        [STAThread]
        private static int Main(string[] args)
        {
            Mutex launcherGuiInstanceMutex = null;
            try
            {
                var normalizedArgs = NormalizePowerShellArguments(args);
                if (RequiresLauncherGuiInstanceLock(normalizedArgs) && !TryAcquireLauncherGuiInstance(out launcherGuiInstanceMutex))
                {
                    NativeMsgBox(
                        IntPtr.Zero,
                        "Baseline is already running for this Windows user.\n\nClose the existing Baseline window before starting another one.",
                        "Baseline",
                        MB_OK | MB_ICONWARNING);
                    return 0;
                }

                // Verify Windows PowerShell 5.1 (System.Management.Automation) is
                // reachable before doing anything else.  The launcher loads the
                // assembly from the GAC_MSIL path so the architecture stays neutral.
                var smaPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    @"Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll");

                if (!File.Exists(smaPath))
                {
                    NativeMsgBox(IntPtr.Zero,
                        "Baseline requires Windows PowerShell 5.1, which was not found on this machine.\n\n" +
                        $"Expected location:\n{smaPath}\n\n" +
                        "Please ensure Windows PowerShell 5.1 is installed and try again.",
                        "Baseline – Windows PowerShell Not Found",
                        MB_OK | MB_ICONERROR);
                    return 1;
                }

                var language = Environment.GetEnvironmentVariable(LanguageVar);
                var installerMode = Environment.GetEnvironmentVariable(InstallerModeVar) == "1";

                var launcherPath = Assembly.GetExecutingAssembly().Location;
                if (string.IsNullOrWhiteSpace(launcherPath))
                {
                    launcherPath = Path.Combine(AppContext.BaseDirectory, "Baseline.exe");
                }
                launcherPath = Path.GetFullPath(launcherPath);
                var hydratedRoot = EnsureHydratedRuntime(launcherPath);
                var stateRoot = ResolveStateRoot(AppContext.BaseDirectory, out var portableMode);
                var launcherScript = Path.Combine(hydratedRoot, LauncherRelativePath);

                if (!File.Exists(launcherScript))
                {
                    NativeMsgBox(IntPtr.Zero, $"Launcher helper missing:\n{launcherScript}", "Baseline", MB_OK | MB_ICONERROR);
                    return 1;
                }

                return StartEmbeddedPowerShell(launcherScript, launcherPath, hydratedRoot, stateRoot, portableMode, installerMode, language, args);
            }
            catch (Exception ex)
            {
                NativeMsgBox(IntPtr.Zero, $"Failed to bootstrap Baseline:\n{ex.Message}", "Baseline", MB_OK | MB_ICONERROR);
                return 1;
            }
            finally
            {
                ReleaseLauncherGuiInstance(launcherGuiInstanceMutex);
            }
        }

        /// <summary>
        /// Acquires the process-lifetime mutex used by the native launcher to
        /// reject duplicate WPF GUI instances before runtime hydration starts.
        /// </summary>
        /// <param name="mutex">The acquired mutex, which must be held until process exit.</param>
        /// <returns>True when the current process owns the GUI-instance mutex.</returns>
        private static bool TryAcquireLauncherGuiInstance(out Mutex mutex)
        {
            mutex = null;
            var mutexName = GetLauncherGuiInstanceMutexName();
            bool createdNew;
            Mutex candidate = null;
            try
            {
                candidate = new Mutex(true, mutexName, out createdNew);
                if (createdNew)
                {
                    mutex = candidate;
                    return true;
                }

                try
                {
                    if (candidate.WaitOne(0))
                    {
                        mutex = candidate;
                        return true;
                    }
                }
                catch (AbandonedMutexException)
                {
                    mutex = candidate;
                    return true;
                }

                candidate.Dispose();
                return false;
            }
            catch
            {
                if (candidate != null)
                {
                    candidate.Dispose();
                }

                throw;
            }
        }

        /// <summary>
        /// Releases a launcher GUI-instance mutex acquired by the current thread.
        /// </summary>
        /// <param name="mutex">The mutex to release and dispose.</param>
        private static void ReleaseLauncherGuiInstance(Mutex mutex)
        {
            if (mutex == null)
            {
                return;
            }

            try
            {
                mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // The current thread no longer owns the mutex.
            }
            finally
            {
                mutex.Dispose();
            }
        }

        /// <summary>
        /// Builds the per-user mutex name for the launcher-level GUI lock.
        /// </summary>
        /// <returns>The named mutex used to identify the current user's GUI instance.</returns>
        private static string GetLauncherGuiInstanceMutexName()
        {
            return LauncherGuiInstanceMutexPrefix + GetMutexSafeUserName(Environment.UserName);
        }

        /// <summary>
        /// Normalizes the user name portion of a kernel object name.
        /// </summary>
        /// <param name="userName">The raw Windows user name.</param>
        /// <returns>A lowercase user token containing only mutex-safe characters.</returns>
        private static string GetMutexSafeUserName(string userName)
        {
            var normalized = (userName ?? string.Empty).ToLowerInvariant();
            var builder = new StringBuilder(normalized.Length);
            var hasAlphaNumeric = false;
            foreach (var ch in normalized)
            {
                if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'))
                {
                    builder.Append(ch);
                    hasAlphaNumeric = true;
                    continue;
                }

                if (ch == '.' || ch == '_' || ch == '-')
                {
                    builder.Append(ch);
                    continue;
                }

                builder.Append('_');
            }

            if (builder.Length == 0 || !hasAlphaNumeric)
            {
                return "unknown";
            }

            return builder.ToString();
        }

        // ── Runtime hydration ─────────────────────────────────────────────────────

        /// <summary>
        /// Ensures the embedded runtime payload is hydrated and ready to execute.
        /// </summary>
        /// <returns>The hydrated runtime root directory.</returns>
        private static string EnsureHydratedRuntime(string launcherPath)
        {
            var asm = Assembly.GetExecutingAssembly();
            var payloadManifest = GetEmbeddedPayloadManifest(asm);
            if (payloadManifest.Length == 0)
            {
                throw new InvalidOperationException("Embedded runtime payload is missing.");
            }

            var launcherFingerprint = GetLauncherCacheFingerprint(launcherPath);
            var scriptRoot = AppContext.BaseDirectory;
            if (IsRuntimeReady(scriptRoot, payloadManifest, launcherFingerprint)) return scriptRoot;

            var version = GetBundleVersion(asm);
            var buildId = GetBundleBuildId(asm);
            var cacheRoot = GetRestrictedRuntimeCacheRoot();
            var runtimeRoot = Path.Combine(cacheRoot, version, RuntimeCacheSchema, buildId, launcherFingerprint);
            if (IsRuntimeReady(runtimeRoot, payloadManifest, launcherFingerprint)) return runtimeRoot;

            using (var hydrationLock = new FileStream(Path.Combine(cacheRoot, ".hydrate.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            {
                if (IsRuntimeReady(runtimeRoot, payloadManifest, launcherFingerprint)) return runtimeRoot;

                var runtimeParent = Path.GetDirectoryName(runtimeRoot);
                if (!string.IsNullOrWhiteSpace(runtimeParent))
                {
                    Directory.CreateDirectory(runtimeParent);
                }

                if (Directory.Exists(runtimeRoot)) Directory.Delete(runtimeRoot, true);
                var staging = runtimeRoot + StagingSuffix;
                if (Directory.Exists(staging)) Directory.Delete(staging, true);
                Directory.CreateDirectory(staging);

                foreach (var payload in payloadManifest)
                {
                    var target = Path.Combine(staging, payload.RelativePath);
                    using (var rs = asm.GetManifestResourceStream(payload.ResourceName))
                    {
                        if (rs == null)
                        {
                            throw new InvalidOperationException("Embedded runtime payload stream could not be opened: " + payload.ResourceName);
                        }

                        WriteHydratedResource(target, rs);
                    }
                }

                File.WriteAllText(
                    Path.Combine(staging, HydrationSentinel),
                    RuntimeCacheSchema + Environment.NewLine +
                    version + Environment.NewLine +
                    buildId + Environment.NewLine +
                    launcherFingerprint + Environment.NewLine);
                WriteHydrationManifest(staging, payloadManifest);
                Directory.Move(staging, runtimeRoot);
            }

            return runtimeRoot;
        }

        /// <summary>
        /// Gets the manifest resource names that belong to the embedded runtime payload.
        /// </summary>
        /// <param name="asm">The launcher assembly.</param>
        /// <returns>The sorted runtime payload resource names.</returns>
        private static string[] GetEmbeddedPayloadResourceNames(Assembly asm)
        {
            return asm.GetManifestResourceNames()
                .Where(n => n.StartsWith(PayloadPrefix, StringComparison.Ordinal))
                .OrderBy(n => n, StringComparer.Ordinal)
                .ToArray();
        }

        /// <summary>
        /// Builds the embedded payload manifest used to verify hydrated files before reuse.
        /// </summary>
        /// <param name="asm">The launcher assembly.</param>
        /// <returns>The sorted runtime payload entries with hydrated SHA-256 hashes.</returns>
        private static PayloadEntry[] GetEmbeddedPayloadManifest(Assembly asm)
        {
            return GetEmbeddedPayloadResourceNames(asm)
                .Select(resourceName =>
                {
                    var relativePath = GetPayloadRelativePath(resourceName);
                    return new PayloadEntry
                    {
                        ResourceName = resourceName,
                        RelativePath = relativePath,
                        Sha256 = ComputeHydratedResourceSha256(asm, resourceName, relativePath)
                    };
                })
                .ToArray();
        }

        /// <summary>
        /// Maps an embedded payload resource name to its relative runtime file path.
        /// </summary>
        /// <param name="resourceName">The manifest resource name.</param>
        /// <returns>The relative path inside the hydrated runtime root.</returns>
        private static string GetPayloadRelativePath(string resourceName)
        {
            return resourceName.Substring(PayloadPrefix.Length).Replace('/', Path.DirectorySeparatorChar);
        }

        /// <summary>
        /// Writes an embedded resource stream to the hydrated runtime.
        /// </summary>
        /// <param name="target">The destination file path.</param>
        /// <param name="resourceStream">The embedded resource stream.</param>
        private static void WriteHydratedResource(string target, Stream resourceStream)
        {
            var dir = Path.GetDirectoryName(target);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            using (var fs = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                if (ShouldPrependUtf8Bom(target, resourceStream) && !ResourceStartsWithUtf8Bom(resourceStream))
                {
                    fs.Write(Utf8Bom, 0, Utf8Bom.Length);
                }

                resourceStream.CopyTo(fs);
            }
        }

        /// <summary>
        /// Writes the expected hydrated payload hash manifest into the runtime root.
        /// </summary>
        /// <param name="runtimeRoot">The hydrated runtime root.</param>
        /// <param name="payloadManifest">The embedded payload manifest.</param>
        private static void WriteHydrationManifest(string runtimeRoot, PayloadEntry[] payloadManifest)
        {
            var manifestPath = Path.Combine(runtimeRoot, HydrationManifest);
            var lines = payloadManifest
                .OrderBy(entry => entry.RelativePath, StringComparer.OrdinalIgnoreCase)
                .Select(entry => entry.Sha256 + "  " + entry.RelativePath.Replace(Path.DirectorySeparatorChar, '/'))
                .ToArray();
            File.WriteAllLines(manifestPath, lines, new UTF8Encoding(false));
        }

        /// <summary>
        /// Determines whether a hydrated resource should be written with a UTF-8 BOM.
        /// </summary>
        /// <param name="target">The destination file path.</param>
        /// <param name="resourceStream">The embedded resource stream.</param>
        /// <returns>True when the file should be prefixed with a BOM.</returns>
        private static bool ShouldPrependUtf8Bom(string target, Stream resourceStream)
        {
            if (!RequiresPowerShellUtf8Bom(target) || !resourceStream.CanSeek || resourceStream.Length == 0)
            {
                return false;
            }

            var originalPosition = resourceStream.Position;
            try
            {
                resourceStream.Position = 0;
                var sampleLength = checked((int)resourceStream.Length);
                var sample = new byte[sampleLength];
                var bytesRead = resourceStream.Read(sample, 0, sample.Length);
                if (bytesRead <= Utf8Bom.Length)
                {
                    return false;
                }

                var hasNonAsciiByte = false;
                for (var i = 0; i < bytesRead; i++)
                {
                    if (sample[i] == 0)
                    {
                        return false;
                    }

                    if (sample[i] > 127)
                    {
                        hasNonAsciiByte = true;
                    }
                }

                // ASCII-only scripts are safe without a BOM. Only preserve UTF-8 BOMs
                // for PowerShell script resources that actually contain non-ASCII bytes.
                if (!hasNonAsciiByte)
                {
                    return false;
                }

                try
                {
                    _ = new UTF8Encoding(false, true).GetString(sample, 0, bytesRead);
                    return bytesRead > 0;
                }
                catch (DecoderFallbackException)
                {
                    return false;
                }
            }
            finally
            {
                resourceStream.Position = originalPosition;
            }
        }

        /// <summary>
        /// Determines whether a resource type relies on a UTF-8 BOM when hydrated.
        /// </summary>
        /// <param name="target">The destination file path.</param>
        /// <returns>True when the resource is a PowerShell script/module file.</returns>
        private static bool RequiresPowerShellUtf8Bom(string target)
        {
            if (string.IsNullOrWhiteSpace(target))
            {
                return false;
            }

            var extension = Path.GetExtension(target);
            return extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".psm1", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".psd1", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Checks whether an embedded resource already starts with a UTF-8 BOM.
        /// </summary>
        /// <param name="resourceStream">The embedded resource stream.</param>
        /// <returns>True when the stream starts with a UTF-8 BOM.</returns>
        private static bool ResourceStartsWithUtf8Bom(Stream resourceStream)
        {
            if (!resourceStream.CanSeek || resourceStream.Length < Utf8Bom.Length)
            {
                return false;
            }

            var originalPosition = resourceStream.Position;
            try
            {
                resourceStream.Position = 0;
                var prefix = new byte[Utf8Bom.Length];
                var bytesRead = resourceStream.Read(prefix, 0, prefix.Length);
                return bytesRead == Utf8Bom.Length
                    && prefix[0] == Utf8Bom[0]
                    && prefix[1] == Utf8Bom[1]
                    && prefix[2] == Utf8Bom[2];
            }
            finally
            {
                resourceStream.Position = originalPosition;
            }
        }

        /// <summary>
        /// Tests whether the hydrated runtime root has already been prepared.
        /// </summary>
        /// <param name="root">The runtime root path.</param>
        /// <param name="payloadResources">The embedded runtime payload resource names.</param>
        /// <returns>True when the runtime sentinel is present.</returns>
        private static bool IsRuntimeReady(string root, PayloadEntry[] payloadManifest, string launcherFingerprint)
        {
            if (!Directory.Exists(root) || payloadManifest.Length == 0)
            {
                return false;
            }

            var sentinelPath = Path.Combine(root, HydrationSentinel);
            if (!File.Exists(sentinelPath))
            {
                return false;
            }

            var sentinelLines = File.ReadAllLines(sentinelPath);
            if (sentinelLines.Length != 4)
            {
                return false;
            }

            if (!string.Equals(sentinelLines[0], RuntimeCacheSchema, StringComparison.Ordinal) ||
                string.IsNullOrWhiteSpace(sentinelLines[1]) ||
                string.IsNullOrWhiteSpace(sentinelLines[2]) ||
                !string.Equals(sentinelLines[3], launcherFingerprint, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (!HydrationManifestMatches(root, payloadManifest))
            {
                return false;
            }

            foreach (var payload in payloadManifest)
            {
                var filePath = Path.Combine(root, payload.RelativePath);
                if (!File.Exists(filePath) || !FileMatchesSha256(filePath, payload.Sha256))
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Verifies the hydrated manifest file matches the embedded payload manifest.
        /// </summary>
        /// <param name="root">The runtime root path.</param>
        /// <param name="payloadManifest">The expected embedded payload manifest.</param>
        /// <returns>True when the hydrated manifest exists and matches.</returns>
        private static bool HydrationManifestMatches(string root, PayloadEntry[] payloadManifest)
        {
            var manifestPath = Path.Combine(root, HydrationManifest);
            if (!File.Exists(manifestPath))
            {
                return false;
            }

            var expected = payloadManifest
                .OrderBy(entry => entry.RelativePath, StringComparer.OrdinalIgnoreCase)
                .Select(entry => entry.Sha256 + "  " + entry.RelativePath.Replace(Path.DirectorySeparatorChar, '/'))
                .ToArray();
            var actual = File.ReadAllLines(manifestPath);
            return expected.SequenceEqual(actual, StringComparer.Ordinal);
        }

        /// <summary>
        /// Computes the SHA-256 hash for the bytes that will be written during hydration.
        /// </summary>
        /// <param name="asm">The launcher assembly.</param>
        /// <param name="resourceName">The embedded resource name.</param>
        /// <param name="relativePath">The hydrated relative path.</param>
        /// <returns>The uppercase SHA-256 hash.</returns>
        private static string ComputeHydratedResourceSha256(Assembly asm, string resourceName, string relativePath)
        {
            using (var stream = asm.GetManifestResourceStream(resourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Embedded runtime payload stream could not be opened: " + resourceName);
                }

                using (var sha256 = SHA256.Create())
                {
                    if (ShouldPrependUtf8Bom(relativePath, stream) && !ResourceStartsWithUtf8Bom(stream))
                    {
                        sha256.TransformBlock(Utf8Bom, 0, Utf8Bom.Length, null, 0);
                    }

                    if (stream.CanSeek)
                    {
                        stream.Position = 0;
                    }

                    var buffer = new byte[81920];
                    int bytesRead;
                    while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        sha256.TransformBlock(buffer, 0, bytesRead, null, 0);
                    }

                    sha256.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
                    return ToHex(sha256.Hash);
                }
            }
        }

        /// <summary>
        /// Verifies a hydrated file against its embedded SHA-256 hash.
        /// </summary>
        /// <param name="path">The hydrated file path.</param>
        /// <param name="expectedSha256">The expected SHA-256 hash.</param>
        /// <returns>True when the file hash matches.</returns>
        private static bool FileMatchesSha256(string path, string expectedSha256)
        {
            using (var stream = File.OpenRead(path))
            using (var sha256 = SHA256.Create())
            {
                var hash = sha256.ComputeHash(stream);
                return string.Equals(ToHex(hash), expectedSha256, StringComparison.OrdinalIgnoreCase);
            }
        }

        /// <summary>
        /// Converts hash bytes to uppercase hexadecimal.
        /// </summary>
        /// <param name="bytes">The hash bytes.</param>
        /// <returns>The uppercase hexadecimal string.</returns>
        private static string ToHex(byte[] bytes)
        {
            var builder = new StringBuilder(bytes.Length * 2);
            foreach (var value in bytes)
            {
                builder.Append(value.ToString("X2"));
            }

            return builder.ToString();
        }

        /// <summary>
        /// Resolves and creates the elevated runtime cache root with restricted ACLs.
        /// </summary>
        /// <returns>The restricted runtime cache root.</returns>
        private static string GetRestrictedRuntimeCacheRoot()
        {
            var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            if (string.IsNullOrWhiteSpace(programData))
            {
                throw new InvalidOperationException("ProgramData could not be resolved for the elevated runtime cache.");
            }

            var cacheRoot = Path.Combine(programData, "Baseline", "RuntimeCache", RuntimeCacheFolderName);
            EnsureRestrictedDirectory(cacheRoot);
            return cacheRoot;
        }

        /// <summary>
        /// Creates a directory that grants full control only to Administrators and SYSTEM.
        /// </summary>
        /// <param name="path">The directory path to secure.</param>
        private static void EnsureRestrictedDirectory(string path)
        {
            Directory.CreateDirectory(path);

            var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(admins, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));

            new DirectoryInfo(path).SetAccessControl(security);
        }

        /// <summary>
        /// Computes a cache fingerprint for the launcher executable contents.
        /// </summary>
        /// <param name="launcherPath">The launcher executable path.</param>
        /// <returns>The executable fingerprint used to invalidate stale caches.</returns>
        private static string GetLauncherCacheFingerprint(string launcherPath)
        {
            if (string.IsNullOrWhiteSpace(launcherPath))
            {
                throw new ArgumentException("Launcher path is required.", nameof(launcherPath));
            }

            using (var stream = new FileStream(launcherPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var sha256 = SHA256.Create())
            {
                var hash = sha256.ComputeHash(stream);
                var fingerprint = BitConverter.ToString(hash).Replace("-", string.Empty);
                return fingerprint.Substring(0, 12);
            }
        }

        /// <summary>
        /// Reads the bundle version from assembly metadata.
        /// </summary>
        /// <param name="asm">The assembly to inspect.</param>
        /// <returns>The bundle version string.</returns>
        private static string GetBundleVersion(Assembly asm)
        {
            var v = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                 ?? asm.GetName().Version?.ToString()
                 ?? "0.0.0";

            // Strip build metadata so the cache path only reflects the public bundle version.
            var plusIndex = v.IndexOf('+');
            if (plusIndex > 0)
            {
                v = v.Substring(0, plusIndex);
            }

            var bad = Path.GetInvalidFileNameChars();
            return new string(v.Select(c => bad.Contains(c) ? '_' : c).ToArray());
        }

        /// <summary>
        /// Reads the bundle build identifier from assembly metadata.
        /// </summary>
        /// <param name="asm">The assembly to inspect.</param>
        /// <returns>The bundle build identifier.</returns>
        private static string GetBundleBuildId(Assembly asm)
        {
            var buildId = asm.ManifestModule.ModuleVersionId.ToString("N");
            return buildId;
        }

        // ── State root ────────────────────────────────────────────────────────────

        /// <summary>
        /// Resolves the Baseline state root and portability mode.
        /// </summary>
        /// <param name="appBase">The application base directory.</param>
        /// <param name="portable">Outputs whether portable mode is active.</param>
        /// <returns>The resolved state root path.</returns>
        private static string ResolveStateRoot(string appBase, out bool portable)
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                localAppData = Path.Combine(Path.GetTempPath(), "Baseline_LocalAppData");
            }

            if (IsExplicitPortableModeRequested(appBase))
            {
                var p = Path.Combine(appBase, "Data");
                if (CanWrite(p, out var portableFailure))
                {
                    portable = true;
                    return p;
                }

                throw new InvalidOperationException(
                    $"Portable mode was requested by {PortableMarkerFileName} or {PortableModeVar}, but the portable data directory is not writable: {p}. {portableFailure}");
            }

            string localAppDataFailure = null;
            if (!string.IsNullOrWhiteSpace(localAppData))
            {
                var s = Path.Combine(localAppData, "Baseline", "UserState");
                if (CanWrite(s, out localAppDataFailure))
                {
                    portable = false;
                    return s;
                }
            }

            var tmp = Path.Combine(Path.GetTempPath(), "Baseline", "UserState");
            if (!CanWrite(tmp, out var tempFailure))
            {
                var details = string.IsNullOrWhiteSpace(localAppDataFailure)
                    ? tempFailure
                    : $"LocalAppData: {localAppDataFailure}; Temp: {tempFailure}";
                throw new InvalidOperationException($"No writable state directory available. {details}");
            }

            portable = false;
            return tmp;
        }

        /// <summary>
        /// Determines whether portable mode was explicitly requested.
        /// </summary>
        /// <returns>True when the environment flag or portable marker is present.</returns>
        private static bool IsExplicitPortableModeRequested(string appBase)
        {
            var envValue = Environment.GetEnvironmentVariable(PortableModeVar);
            if (IsTruthyEnvironmentValue(envValue))
            {
                return true;
            }

            if (string.IsNullOrWhiteSpace(appBase))
            {
                return false;
            }

            var markerPath = Path.Combine(appBase, PortableMarkerFileName);
            return File.Exists(markerPath);
        }

        /// <summary>
        /// Determines whether an environment value is an explicit truthy flag.
        /// </summary>
        private static bool IsTruthyEnvironmentValue(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return false;
            }

            var normalized = value.Trim();
            return string.Equals(normalized, "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(normalized, "true", StringComparison.OrdinalIgnoreCase)
                || string.Equals(normalized, "yes", StringComparison.OrdinalIgnoreCase)
                || string.Equals(normalized, "on", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Determines whether a path can be written to.
        /// </summary>
        /// <param name="path">The path to test.</param>
        /// <returns>True when write access is available.</returns>
        private static bool CanWrite(string path, out string failure)
        {
            try
            {
                Directory.CreateDirectory(path);
                var probe = Path.Combine(path, ".write-probe");
                File.WriteAllText(probe, "ok");
                File.Delete(probe);
                failure = null;
                return true;
            }
            catch (Exception ex)
            {
                failure = ex.Message;
                return false;
            }
        }

        // ── PowerShell invocation ─────────────────────────────────────────────────

        /// <summary>
        /// Starts the embedded PowerShell runtime with the hydrated launcher script.
        /// </summary>
        /// <param name="launcherScript">The PowerShell entry script path.</param>
        /// <param name="launcherPath">The launcher executable path.</param>
        /// <param name="hydratedRoot">The hydrated runtime root.</param>
        /// <param name="stateRoot">The Baseline state root.</param>
        /// <param name="portableMode">Whether portable mode is enabled.</param>
        /// <param name="installerMode">Whether installer mode is enabled.</param>
        /// <param name="language">The selected language code.</param>
        /// <param name="args">The original command-line arguments.</param>
        /// <returns>The launcher exit code.</returns>
        private static int StartEmbeddedPowerShell(
            string launcherScript,
            string launcherPath,
            string hydratedRoot,
            string stateRoot,
            bool portable,
            bool installer,
            string lang,
            string[] args)
        {
            var normalizedArgs = NormalizePowerShellArguments(args);
            Environment.SetEnvironmentVariable(StateRootVar, stateRoot, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable(EmbeddedHostVar, "1", EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable(LauncherPathVar, launcherPath, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable(PortableModeVar, portable ? "1" : "0", EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable(InstallerModeVar, installer ? "1" : "0", EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable(PowerShellExecutionPolicyPreferenceVar, "Bypass", EnvironmentVariableTarget.Process);
            if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(IntegrityModeVar)))
            {
                Environment.SetEnvironmentVariable(IntegrityModeVar, "Strict", EnvironmentVariableTarget.Process);
            }
            if (!string.IsNullOrWhiteSpace(lang))
            {
                Environment.SetEnvironmentVariable(LanguageVar, lang, EnvironmentVariableTarget.Process);
            }
            Environment.CurrentDirectory = hydratedRoot;

            using (var host = new BaselinePowerShellHost())
            {
                var initialSessionState = InitialSessionState.CreateDefault();
                initialSessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;

                using (var runspace = RunspaceFactory.CreateRunspace(host, initialSessionState))
                {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                    runspace.Open();

                    using (var powershell = PowerShell.Create())
                    {
                        powershell.Runspace = runspace;
                        powershell.AddCommand(launcherScript);
                        BindPowerShellInvocationArguments(powershell, normalizedArgs);

                        var timeout = GetPowerShellInvokeTimeout(normalizedArgs);
                        var asyncResult = powershell.BeginInvoke();
                        var completed = timeout.HasValue
                            ? asyncResult.AsyncWaitHandle.WaitOne(timeout.Value)
                            : asyncResult.AsyncWaitHandle.WaitOne();
                        if (!completed)
                        {
                            try
                            {
                                powershell.Stop();
                            }
                            catch
                            {
                                // Stop is best effort only.
                            }

                            NativeMsgBox(
                                IntPtr.Zero,
                                $"Baseline timed out while running the PowerShell workflow after {timeout.Value.TotalMinutes:0} minute(s).",
                                "Baseline",
                                MB_OK | MB_ICONERROR);
                            return 1;
                        }

                        PSDataCollection<PSObject> output;
                        try
                        {
                            output = powershell.EndInvoke(asyncResult);
                        }
                        catch (PipelineStoppedException)
                        {
                            return 1;
                        }

                        if (host.ShouldExit)
                        {
                            return host.ExitCode;
                        }

                        if (powershell.HadErrors)
                        {
                            return 1;
                        }

                        for (var i = output.Count - 1; i >= 0; i--)
                        {
                            var value = output[i] != null ? output[i].BaseObject : null;
                            if (value is int exitCode)
                            {
                                return exitCode;
                            }

                            if (value is long exitCodeLong)
                            {
                                return unchecked((int)exitCodeLong);
                            }
                        }
                    }
                }
            }

            return 0;
        }

        /// <summary>
        /// Normalizes GNU-style long switches to the PowerShell parameter names
        /// consumed by the embedded launcher script.
        /// </summary>
        /// <param name="args">The original command-line arguments.</param>
        /// <returns>The normalized argument list.</returns>
        private static string[] NormalizePowerShellArguments(string[] args)
        {
            if (args == null || args.Length == 0)
            {
                return Array.Empty<string>();
            }

            var normalized = new string[args.Length];
            for (var i = 0; i < args.Length; i++)
            {
                normalized[i] = NormalizePowerShellArgument(args[i]);
            }

            return normalized;
        }

        /// <summary>
        /// Binds normalized process arguments through the PowerShell SDK parameter APIs.
        /// </summary>
        /// <param name="powershell">The PowerShell instance with the bootstrap command already added.</param>
        /// <param name="normalizedArgs">The normalized process arguments.</param>
        private static void BindPowerShellInvocationArguments(PowerShell powershell, string[] normalizedArgs)
        {
            if (normalizedArgs == null || normalizedArgs.Length == 0)
            {
                return;
            }

            for (var i = 0; i < normalizedArgs.Length; i++)
            {
                var argument = normalizedArgs[i];
                if (TrySplitPowerShellParameterAssignment(argument, out var assignmentName, out var assignmentValue))
                {
                    AddBoundPowerShellParameter(powershell, assignmentName, new[] { assignmentValue });
                    continue;
                }

                if (!TryGetPowerShellParameterName(argument, out var parameterName))
                {
                    powershell.AddArgument(argument);
                    continue;
                }

                var canonicalName = GetCanonicalPowerShellParameterName(parameterName);
                if (BootstrapSwitchParameterNames.Contains(canonicalName))
                {
                    powershell.AddParameter(canonicalName, true);
                    continue;
                }

                var values = new List<string>();
                while ((i + 1) < normalizedArgs.Length && !IsKnownPowerShellParameterToken(normalizedArgs[i + 1]))
                {
                    i++;
                    values.Add(normalizedArgs[i]);
                }

                AddBoundPowerShellParameter(powershell, canonicalName, values.ToArray());
            }
        }

        /// <summary>
        /// Adds one named parameter to the PowerShell command using the expected value shape.
        /// </summary>
        /// <param name="powershell">The PowerShell command builder.</param>
        /// <param name="parameterName">The parameter name.</param>
        /// <param name="values">The literal CLI values.</param>
        private static void AddBoundPowerShellParameter(PowerShell powershell, string parameterName, string[] values)
        {
            var canonicalName = GetCanonicalPowerShellParameterName(parameterName);
            if (BootstrapSwitchParameterNames.Contains(canonicalName))
            {
                var value = values != null && values.Length > 0 ? values[0] : "true";
                powershell.AddParameter(canonicalName, ParseSwitchValue(value));
                return;
            }

            if (BootstrapArrayParameterNames.Contains(canonicalName))
            {
                powershell.AddParameter(canonicalName, values ?? Array.Empty<string>());
                return;
            }

            powershell.AddParameter(canonicalName, values != null && values.Length > 0 ? values[0] : null);
        }

        /// <summary>
        /// Parses a command-line switch value without evaluating PowerShell syntax.
        /// </summary>
        /// <param name="value">The literal switch value.</param>
        /// <returns>The boolean switch value.</returns>
        private static bool ParseSwitchValue(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return true;
            }

            var text = value.Trim().TrimStart('$');
            if (string.Equals(text, "false", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "0", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "no", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return true;
        }

        /// <summary>
        /// Splits long-form parameter assignments such as -OutputFormat=Json.
        /// </summary>
        /// <param name="argument">The argument to inspect.</param>
        /// <param name="parameterName">The emitted parameter token.</param>
        /// <param name="parameterValue">The emitted string value.</param>
        /// <returns>True when the argument was a known parameter assignment.</returns>
        private static bool TrySplitPowerShellParameterAssignment(string argument, out string parameterName, out string parameterValue)
        {
            parameterName = null;
            parameterValue = null;

            if (string.IsNullOrWhiteSpace(argument))
            {
                return false;
            }

            if (!TryGetPowerShellParameterName(argument, out var candidateName, out var separatorIndex))
            {
                return false;
            }

            if (separatorIndex <= 1)
            {
                return false;
            }

            parameterName = candidateName;
            parameterValue = argument.Substring(separatorIndex + 1);
            return true;
        }

        /// <summary>
        /// Determines whether a token is a named parameter accepted by Bootstrap/Baseline.ps1.
        /// </summary>
        /// <param name="argument">The argument token.</param>
        /// <returns>True when the token names a bootstrap parameter or supported alias.</returns>
        private static bool IsKnownPowerShellParameterToken(string argument)
        {
            return TryGetPowerShellParameterName(argument, out _);
        }

        /// <summary>
        /// Extracts a known bootstrap parameter name from a token.
        /// </summary>
        /// <param name="argument">The argument token.</param>
        /// <param name="parameterName">The canonical parameter or alias name.</param>
        /// <returns>True when the token names a supported bootstrap parameter.</returns>
        private static bool TryGetPowerShellParameterName(string argument, out string parameterName)
        {
            return TryGetPowerShellParameterName(argument, out parameterName, out _);
        }

        /// <summary>
        /// Extracts a known bootstrap parameter name and separator position from a token.
        /// </summary>
        /// <param name="argument">The argument token.</param>
        /// <param name="parameterName">The canonical parameter or alias name.</param>
        /// <param name="separatorIndex">The inline value separator index, or -1.</param>
        /// <returns>True when the token names a supported bootstrap parameter.</returns>
        private static bool TryGetPowerShellParameterName(string argument, out string parameterName, out int separatorIndex)
        {
            parameterName = null;
            separatorIndex = -1;

            if (string.IsNullOrWhiteSpace(argument))
            {
                return false;
            }

            var text = argument.TrimStart();
            if (!text.StartsWith("-", StringComparison.Ordinal))
            {
                return false;
            }

            text = text.TrimStart('-');
            if (string.IsNullOrWhiteSpace(text))
            {
                return false;
            }

            separatorIndex = text.IndexOfAny(new[] { ':', '=' });
            parameterName = separatorIndex >= 0 ? text.Substring(0, separatorIndex) : text;
            if (!BootstrapPowerShellParameterNames.Contains(parameterName))
            {
                return false;
            }

            separatorIndex = separatorIndex >= 0 ? argument.Length - text.Length + separatorIndex : -1;
            parameterName = GetCanonicalPowerShellParameterName(parameterName);
            return true;
        }

        /// <summary>
        /// Resolves a bootstrap parameter alias to its declared parameter name.
        /// </summary>
        /// <param name="parameterName">The parameter or alias name.</param>
        /// <returns>The canonical parameter name.</returns>
        private static string GetCanonicalPowerShellParameterName(string parameterName)
        {
            return BootstrapParameterAliases.TryGetValue(parameterName, out var canonicalName) ? canonicalName : parameterName;
        }

        /// <summary>
        /// Normalizes a single command-line argument for PowerShell parameter binding.
        /// </summary>
        /// <param name="argument">The argument to normalize.</param>
        /// <returns>The normalized argument.</returns>
        private static string NormalizePowerShellArgument(string argument)
        {
            if (string.IsNullOrWhiteSpace(argument))
            {
                return argument;
            }

            if (argument == "--" || argument == "--%")
            {
                return argument;
            }

            if (!argument.StartsWith("--", StringComparison.Ordinal))
            {
                return argument;
            }

            var normalizedText = argument.Substring(2);
            if (string.IsNullOrWhiteSpace(normalizedText))
            {
                return argument;
            }

            var valueSeparatorIndex = normalizedText.IndexOf('=');
            var valueSuffix = string.Empty;
            if (valueSeparatorIndex >= 0)
            {
                valueSuffix = normalizedText.Substring(valueSeparatorIndex);
                normalizedText = normalizedText.Substring(0, valueSeparatorIndex);
            }

            var segments = normalizedText.Split(new[] { '-' }, StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length == 0)
            {
                return "-" + normalizedText + valueSuffix;
            }

            var builder = new StringBuilder();
            foreach (var segment in segments)
            {
                if (string.IsNullOrWhiteSpace(segment))
                {
                    continue;
                }

                builder.Append(char.ToUpperInvariant(segment[0]));
                if (segment.Length > 1)
                {
                    builder.Append(segment.Substring(1));
                }
            }

            if (builder.Length == 0)
            {
                return "-" + normalizedText + valueSuffix;
            }

            return "-" + builder.ToString() + valueSuffix;
        }

        /// <summary>
        /// Resolves the PowerShell invocation timeout for the embedded workflow.
        /// </summary>
        /// <param name="normalizedArgs">The normalized command-line arguments passed to the PowerShell workflow.</param>
        /// <returns>The timeout to apply before stopping the pipeline, or null when the GUI should run until closed.</returns>
        private static TimeSpan? GetPowerShellInvokeTimeout(string[] normalizedArgs)
        {
            if (IsGuiPowerShellInvocation(normalizedArgs))
            {
                return null;
            }

            var raw = Environment.GetEnvironmentVariable(PowerShellTimeoutSecondsVar);
            if (int.TryParse(raw, out var timeoutSeconds) && timeoutSeconds > 0)
            {
                return TimeSpan.FromSeconds(timeoutSeconds);
            }

            return TimeSpan.FromSeconds(DefaultPowerShellTimeoutSeconds);
        }

        /// <summary>
        /// Determines whether the embedded workflow is the interactive GUI path.
        /// </summary>
        /// <param name="normalizedArgs">The normalized command-line arguments passed to the PowerShell workflow.</param>
        /// <returns>True when no known headless entry-point argument was supplied.</returns>
        private static bool IsGuiPowerShellInvocation(string[] normalizedArgs)
        {
            if (normalizedArgs == null || normalizedArgs.Length == 0)
            {
                return true;
            }

            return !normalizedArgs.Any(IsHeadlessPowerShellArgument);
        }

        /// <summary>
        /// Determines whether the native launcher must hold the WPF GUI
        /// single-instance lock for this invocation.
        /// </summary>
        /// <param name="normalizedArgs">The normalized command-line arguments passed to the PowerShell workflow.</param>
        /// <returns>True when the invocation can open the WPF GUI.</returns>
        private static bool RequiresLauncherGuiInstanceLock(string[] normalizedArgs)
        {
            if (normalizedArgs == null || normalizedArgs.Length == 0)
            {
                return true;
            }

            return !normalizedArgs.Any(IsNonWpfPowerShellArgument);
        }

        /// <summary>
        /// Determines whether an argument selects a path that bypasses the WPF GUI.
        /// </summary>
        /// <param name="argument">The normalized argument text.</param>
        /// <returns>True when the argument selects headless automation or the console menu.</returns>
        private static bool IsNonWpfPowerShellArgument(string argument)
        {
            return IsHeadlessPowerShellArgument(argument) || IsEnabledPowerShellSwitchArgument(argument, ConsoleGuiArgumentName);
        }

        /// <summary>
        /// Determines whether an argument selects a headless workflow.
        /// </summary>
        /// <param name="argument">The normalized argument text.</param>
        /// <returns>True when the argument is a known headless entry-point parameter.</returns>
        private static bool IsHeadlessPowerShellArgument(string argument)
        {
            if (!TryGetPowerShellParameterName(argument, out var parameterName))
            {
                return false;
            }

            return HeadlessPowerShellArguments.Any(
                name => string.Equals(name, parameterName, StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>
        /// Determines whether an argument enables a specific PowerShell switch.
        /// </summary>
        /// <param name="argument">The normalized argument text.</param>
        /// <param name="expectedName">The parameter name to match.</param>
        /// <returns>True when the argument enables the requested switch.</returns>
        private static bool IsEnabledPowerShellSwitchArgument(string argument, string expectedName)
        {
            if (string.IsNullOrWhiteSpace(expectedName))
            {
                return false;
            }

            if (!TryGetPowerShellParameterName(argument, out var parameterName) ||
                !string.Equals(parameterName, expectedName, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return !TrySplitPowerShellParameterAssignment(argument, out _, out var parameterValue) ||
                ParseSwitchValue(parameterValue);
        }
    }
}
