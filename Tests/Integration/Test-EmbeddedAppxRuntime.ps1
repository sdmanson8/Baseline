$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 is required.' }
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $repoRoot ('.artifacts/support-regression/AppxRuntimeProbe-'+[guid]::NewGuid().ToString('N')+'.exe')
$sma=[powershell].Assembly.Location
Add-Type -Path @((Join-Path $repoRoot 'Launcher/BundledAssemblyResolver.cs'),(Join-Path $PSScriptRoot 'AppxRuntimeProbe.cs')) -ReferencedAssemblies @($sma,'System.dll','System.Core.dll') -OutputAssembly $out -OutputType ConsoleApplication
. (Join-Path $repoRoot 'Module/SharedHelpers/Process.Helpers.ps1')
$result=Invoke-BaselineProcess -FilePath $out -ArgumentList @((Join-Path $repoRoot 'Module/Libraries')) -CaptureOutput -TimeoutSeconds 60
Write-Host $result.StandardOutput
