# Exercises real harmless child processes; service configuration is mocked.
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture = Join-Path $repoRoot ('.artifacts/Maintenance Completion ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
function Import-TestFunction {
    param($Path, $Name)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
    if (-not $function) { throw "Missing function $Name" }
    return $function.Extent.Text
}
Invoke-Expression (Import-TestFunction (Join-Path $repoRoot 'Module/Regions/UWPApps/AIRemoval.ps1') 'RunTrusted')
Invoke-Expression (Import-TestFunction (Join-Path $repoRoot 'Module/Regions/SystemTweaks/diskcleanup.ps1') 'Wait-CleanupProcessAndDismissNotification')
Add-Type 'namespace WinAPI { public static class DiskCleanupWindow { public static bool AcceptNotification(int id) { return false; } } }'
function LogInfo { param($Message) }
function Get-AIRemovalLogFilePath { return $null }
function Get-Service { param($Name, $ErrorAction) return $null }
function Get-CimInstance { param($ClassName, $Filter) return [pscustomobject]@{ PathName = 'original-service-command' } }
function Stop-BaselineProcessTree { param($Process, $Source) $Process.Kill(); $Process.WaitForExit() }
function Invoke-BaselineProcess {
    param($FilePath, $ArgumentList, $TimeoutSeconds, $AllowedExitCodes)
    if ($FilePath -ne 'sc.exe') { throw "Unexpected process $FilePath" }
    if ($ArgumentList[0] -eq 'config') {
        $script:serviceCommand = $ArgumentList[3]
        return
    }
    if ($ArgumentList[0] -ne 'start') { throw 'Unexpected service operation' }
    if ($script:serviceCommand -notmatch '^"([^"]+)" (.+)$') { throw 'Service must launch PowerShell directly' }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Matches[1]
    $info.Arguments = $Matches[2]
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $child = [Diagnostics.Process]::Start($info)
    try {
        if ($script:detachWorker) { Start-Sleep -Milliseconds 700 }
        elseif (-not $child.WaitForExit(10000)) { $child.Kill(); throw 'Fixture child timed out' }
    }
    finally { $child.Dispose() }
}
$originalProgramData = $env:ProgramData
$ModuleRoot = Join-Path $repoRoot 'Module'
try {
    $env:ProgramData = $fixture
    foreach ($case in @(
        @{ Command = '$null = 1'; Error = $null },
        @{ Command = 'Start-Sleep -Seconds 2'; Error = $null; Detach = $true },
        @{ Command = 'Start-Sleep -Seconds 2; exit 7'; Error = 'exited with code 7'; Detach = $true },
        @{ Command = 'throw "fixture failure"'; Error = 'fixture failure' },
        @{ Command = 'exit 7'; Error = 'process|exited' },
        @{ Command = 'this is not valid {'; Error = 'did not start within 30 seconds' }
    )) {
        $script:detachWorker = [bool]$case.Detach
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $failure = $null
        try { RunTrusted -command $case.Command }
        catch { $failure = $_.Exception.Message }
        if ($case.Error) {
            if (-not $failure -or $failure -notmatch $case.Error) { throw "Unexpected result: $failure" }
        }
        elseif ($failure) { throw $failure }
        if ($timer.Elapsed.TotalSeconds -gt 40) { throw 'Worker failure was not detected promptly' }
        if ($script:serviceCommand -ne 'original-service-command') { throw 'Service command was not restored' }
        Write-Host "PASS: privileged worker '$($case.Command)'"
    }
    foreach ($exitCode in @(0, 7)) {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $info.Arguments = "-NoProfile -NonInteractive -Command exit $exitCode"
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $child = [Diagnostics.Process]::Start($info)
        try {
            $failure = $null
            try { Wait-CleanupProcessAndDismissNotification -Process $child -TimeoutSeconds 10 }
            catch { $failure = $_.Exception.Message }
            if ($exitCode -eq 0 -and $failure) { throw $failure }
            if ($exitCode -eq 7 -and $failure -notmatch 'exited with code 7') { throw "Incorrect exit result: $failure" }
            Write-Host "PASS: cleanup exit code $exitCode"
        }
        finally { $child.Dispose() }
    }
}
finally { $env:ProgramData = $originalProgramData }
