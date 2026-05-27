<#
    .SYNOPSIS
    Shared timeout-safe external process helpers for Baseline.

    .NOTES
    Use Invoke-BaselineProcess for external tools/installers/uninstallers.
    Do not add new synchronous Start-Process wait calls for tweak/app/setup execution paths.
#>

function Stop-BaselineProcessTree
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [string]$Source = 'Stop-BaselineProcessTree'
    )

    if (-not $Process) { return }

    try
    {
        if ($Process.HasExited) { return }
    }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.HasExited') -Severity Debug
        }
    }

    # Modern .NET / PowerShell 7 supports Kill(entireProcessTree).
    try
    {
        $killTreeMethod = $Process.GetType().GetMethod('Kill', [type[]]@([bool]))
        if ($killTreeMethod)
        {
            [void]$killTreeMethod.Invoke($Process, @($true))
            try { [void]$Process.WaitForExit(1500) }
            catch
            {
                if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.KillTreeWait') -Severity Debug
                }
            }
            return
        }
    }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.KillTreeMethod') -Severity Warning
        }
    }

    # Windows PowerShell 5.1 fallback.
    $taskkillExitCode = $null
    $taskkillTimedOut = $false
    try
    {
        $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'

        if (Test-Path -LiteralPath $taskkill)
        {
            $killer = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$Process.Id, '/T', '/F') -WindowStyle Hidden -PassThru -ErrorAction Stop
            if ($killer)
            {
                try
                {
                    if ($killer.WaitForExit(5000))
                    {
                        $taskkillExitCode = [int]$killer.ExitCode
                    }
                    else
                    {
                        $taskkillTimedOut = $true
                    }
                }
                catch
                {
                    if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                    {
                        Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.TaskkillWait') -Severity Debug
                    }
                }
                try { $killer.Dispose() }
                catch
                {
                    if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                    {
                        Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.TaskkillDispose') -Severity Debug
                    }
                }
            }
        }
        else
        {
            $Process.Kill()
        }
    }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.FallbackKill') -Severity Warning
        }
    }

    try { [void]$Process.WaitForExit(1500) }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.FinalWait') -Severity Debug
        }
    }

    try
    {
        if (-not $Process.HasExited)
        {
            throw "Process tree termination did not stop process Id $($Process.Id). taskkillExitCode=$taskkillExitCode taskkillTimedOut=$taskkillTimedOut"
        }
    }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.VerifyTerminated') -Severity Warning
        }
        throw
    }
}

function ConvertTo-BaselineWindowsProcessArgument
{
    [CmdletBinding()]
    param (
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value))
    {
        return '""'
    }

    if ($Value -notmatch '[\s"]')
    {
        return $Value
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Value.ToCharArray())
    {
        if ($character -eq '\')
        {
            $backslashCount++
            continue
        }

        if ($character -eq '"')
        {
            if ($backslashCount -gt 0)
            {
                [void]$builder.Append([string]::new([char]92, ($backslashCount * 2)))
                $backslashCount = 0
            }
            [void]$builder.Append('\"')
            continue
        }

        if ($backslashCount -gt 0)
        {
            [void]$builder.Append([string]::new([char]92, $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0)
    {
        [void]$builder.Append([string]::new([char]92, ($backslashCount * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-BaselineProcessArgumentString
{
    [CmdletBinding()]
    param (
        [AllowNull()]
        [object[]]$ArgumentList
    )

    if (-not $ArgumentList -or $ArgumentList.Count -eq 0) { return '' }

    $quoted = foreach ($arg in $ArgumentList)
    {
        ConvertTo-BaselineWindowsProcessArgument -Value ([string]$arg)
    }

    return ($quoted -join ' ')
}

function Invoke-BaselineProcess
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [object[]]$ArgumentList = @(),

        [int]$TimeoutSeconds = 900,

        [switch]$CaptureOutput,

        [switch]$UseShellExecute,

        [string]$WorkingDirectory,

        [int[]]$AllowedExitCodes = @(0),

        [switch]$AllowAnyExitCode,

        [System.Diagnostics.ProcessWindowStyle]$WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $argumentDisplay = ConvertTo-BaselineProcessArgumentString -ArgumentList $ArgumentList
    $argumentListProperty = $psi.GetType().GetProperty('ArgumentList')
    if ($argumentListProperty)
    {
        foreach ($argument in @($ArgumentList))
        {
            [void]$psi.ArgumentList.Add([string]$argument)
        }
    }
    else
    {
        $psi.Arguments = $argumentDisplay
    }
    $psi.UseShellExecute = [bool]$UseShellExecute
    $psi.CreateNoWindow = -not [bool]$UseShellExecute
    $psi.WindowStyle = $WindowStyle

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory))
    {
        $psi.WorkingDirectory = $WorkingDirectory
    }

    if ($CaptureOutput -and -not $UseShellExecute)
    {
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    $stdoutTask = $null
    $stderrTask = $null
    $stdout = ''
    $stderr = ''

    try
    {
        [void]$process.Start()

        if ($CaptureOutput -and -not $UseShellExecute)
        {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        }

        if ($TimeoutSeconds -gt 0)
        {
            $completed = $process.WaitForExit([int]([TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds))
        }
        else
        {
            $process.WaitForExit()
            $completed = $true
        }

        if (-not $completed)
        {
            Stop-BaselineProcessTree -Process $process -Source 'Invoke-BaselineProcess.Timeout'
            throw ([System.TimeoutException]::new(("Process '{0}' timed out after {1} second(s)." -f $FilePath, $TimeoutSeconds)))
        }

        if ($CaptureOutput -and -not $UseShellExecute)
        {
            try { $stdout = [string]$stdoutTask.GetAwaiter().GetResult() }
            catch
            {
                if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-SwallowedException -ErrorRecord $_ -Source 'Invoke-BaselineProcess.StdoutAwait' -Severity Warning
                }
            }

            try { $stderr = [string]$stderrTask.GetAwaiter().GetResult() }
            catch
            {
                if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-SwallowedException -ErrorRecord $_ -Source 'Invoke-BaselineProcess.StderrAwait' -Severity Warning
                }
            }
        }

        if (-not $AllowAnyExitCode)
        {
            $effectiveAllowedExitCodes = @($AllowedExitCodes)
            if ($effectiveAllowedExitCodes.Count -eq 0)
            {
                $effectiveAllowedExitCodes = @(0)
            }

            if ($process.ExitCode -notin $effectiveAllowedExitCodes)
            {
                $message = "Process '$FilePath' failed with exit code $($process.ExitCode). Arguments: $argumentDisplay"
                if (-not [string]::IsNullOrWhiteSpace($stderr))
                {
                    $message += " StandardError: $stderr"
                }

                throw $message
            }
        }

        return [pscustomobject]@{
            ExitCode       = [int]$process.ExitCode
            StandardOutput = $stdout
            StandardError  = $stderr
            TimedOut       = $false
            ProcessId      = [int]$process.Id
            FilePath       = $FilePath
            Arguments      = $argumentDisplay
        }
    }
    finally
    {
        try { $process.Dispose() }
        catch
        {
            if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
            {
                Write-SwallowedException -ErrorRecord $_ -Source 'Invoke-BaselineProcess.Dispose' -Severity Debug
            }
        }
    }
}

function Invoke-UserLaunch
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [object[]]$ArgumentList = @(),

        [string]$Description = $FilePath,

        [System.Diagnostics.ProcessWindowStyle]$WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
    )

    try
    {
        $splat = @{
            FilePath = $FilePath
            ErrorAction = 'Stop'
        }

        if ($ArgumentList -and $ArgumentList.Count -gt 0)
        {
            $splat['ArgumentList'] = @($ArgumentList)
        }

        if ($WindowStyle -ne [System.Diagnostics.ProcessWindowStyle]::Normal)
        {
            $splat['WindowStyle'] = $WindowStyle
        }

        Start-Process @splat | Out-Null
        return $true
    }
    catch
    {
        $message = "Failed to launch $Description ($FilePath): $($_.Exception.Message)"
        if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
        {
            LogWarning $message
        }
        Write-Warning $message
        return $false
    }
}
