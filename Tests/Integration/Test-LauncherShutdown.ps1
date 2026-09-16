$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 required'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture=Join-Path $root ('.artifacts/shutdown-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
$launcher=Join-Path $fixture 'Baseline.exe'
Copy-Item (Join-Path $root 'Baseline.exe') $launcher
$probe=Join-Path $fixture 'ShutdownProbe.exe'
Add-Type -AssemblyName WindowsBase
Add-Type -Path (Join-Path $PSScriptRoot 'LauncherShutdownProbe.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.Threading.Dispatcher].Assembly.Location) -OutputAssembly $probe -OutputType ConsoleApplication
. (Join-Path $root 'Module/SharedHelpers/Process.Helpers.ps1')
$watch=[Diagnostics.Stopwatch]::StartNew()
$result=Invoke-BaselineProcess -FilePath $probe -ArgumentList @($launcher,$root,(Join-Path $PSScriptRoot 'ShutdownWindowFixture.ps1'),$fixture) -CaptureOutput -TimeoutSeconds 25
foreach($path in @($launcher,$probe)) {
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $stream.Dispose()
}
Write-Host "PASS: actual launcher host exited in $([Math]::Round($watch.Elapsed.TotalSeconds,2))s; GUI dispatcher and all test workers closed; both executable files released"
