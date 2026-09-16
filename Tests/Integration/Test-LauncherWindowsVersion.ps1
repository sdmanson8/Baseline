$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Requires Windows PowerShell 5.1.' }
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $repoRoot ('.artifacts/version-probe-' + [guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $output
# Keep the production compatibility declarations. A read-only console probe
# needs no elevation or WPF window, so it uses asInvoker for sandbox execution.
$probeManifest=Join-Path $output 'probe.manifest'
$manifest=[IO.File]::ReadAllText((Join-Path $repoRoot 'Launcher/Baseline.manifest'))
[IO.File]::WriteAllText($probeManifest,$manifest.Replace('level="requireAdministrator"','level="asInvoker"'))
$source=@'
using System;
public static class VersionProbe {
    public static void Main() { Console.WriteLine(Environment.OSVersion.Version); }
}
'@
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
try {
    foreach ($mode in @('Unmanifested','Manifested')) {
        $parameters=New-Object CodeDom.Compiler.CompilerParameters
        $parameters.GenerateExecutable=$true
        $parameters.OutputAssembly=Join-Path $output ($mode+'.exe')
        if ($mode -eq 'Manifested') { $parameters.CompilerOptions='/win32manifest:"'+$probeManifest+'"' }
        $compiled=$provider.CompileAssemblyFromSource($parameters,$source)
        if ($compiled.Errors.HasErrors) { throw ($compiled.Errors | Out-String) }
        $version=& $parameters.OutputAssembly
        if ($LASTEXITCODE -ne 0) { throw "Version probe failed: $LASTEXITCODE" }
        Write-Output "$mode : $version"
        if ($mode -eq 'Manifested' -and ([version]$version).Major -lt 10) { throw 'Manifested host still reports a pre-Windows-10 version.' }
    }
} finally { $provider.Dispose() }
