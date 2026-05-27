Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Applications.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Test-ApplicationCatalogField' {
    It 'returns false for null objects' {
        Test-ApplicationCatalogField -Object $null -FieldName 'Name' | Should -Be $false
    }

    It 'returns false for blank field names' {
        Test-ApplicationCatalogField -Object ([pscustomobject]@{ Name = 'x' }) -FieldName '' | Should -Be $false
    }

    It 'detects a hashtable key' {
        $h = @{ WinGetId = 'Mozilla.Firefox' }
        Test-ApplicationCatalogField -Object $h -FieldName 'WinGetId' | Should -Be $true
        Test-ApplicationCatalogField -Object $h -FieldName 'ChocoId' | Should -Be $false
    }

    It 'detects a pscustomobject property' {
        $obj = [pscustomobject]@{ Name = 'Firefox'; WinGetId = 'Mozilla.Firefox' }
        Test-ApplicationCatalogField -Object $obj -FieldName 'Name' | Should -Be $true
        Test-ApplicationCatalogField -Object $obj -FieldName 'Missing' | Should -Be $false
    }
}

Describe 'Get-ApplicationCatalogFieldValue' {
    It 'returns null for a missing field' {
        Get-ApplicationCatalogFieldValue -Object ([pscustomobject]@{ Name = 'x' }) -FieldName 'Unknown' | Should -BeNullOrEmpty
    }

    It 'returns the hashtable value for a present key' {
        $value = Get-ApplicationCatalogFieldValue -Object @{ ChocoId = 'firefox' } -FieldName 'ChocoId'
        $value | Should -Be 'firefox'
    }

    It 'returns the property value for a pscustomobject' {
        $obj = [pscustomobject]@{ DisplayName = 'Mozilla Firefox' }
        Get-ApplicationCatalogFieldValue -Object $obj -FieldName 'DisplayName' | Should -Be 'Mozilla Firefox'
    }
}

Describe 'Get-PackageManagerAvailabilityStateValue' {
    It 'returns null when the state object is null' {
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $null -PropertyName 'WinGetAvailable' | Should -BeNullOrEmpty
    }

    It 'returns null when the property name is blank' {
        $state = [pscustomobject]@{ WinGetAvailable = $true }
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $state -PropertyName '' | Should -BeNullOrEmpty
    }

    It 'reads the property from a pscustomobject state' {
        $state = [pscustomobject]@{ WinGetAvailable = $true; ChocolateyAvailable = $false }
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $state -PropertyName 'WinGetAvailable' | Should -Be $true
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $state -PropertyName 'ChocolateyAvailable' | Should -Be $false
    }

    It 'reads the key from a hashtable state' {
        $state = @{ WinGetAvailable = $true }
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $state -PropertyName 'WinGetAvailable' | Should -Be $true
        Get-PackageManagerAvailabilityStateValue -AvailabilityState $state -PropertyName 'ChocolateyAvailable' | Should -BeNullOrEmpty
    }
}

Describe 'Application process diagnostics' {
    BeforeEach {
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
    }

    AfterEach {
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'logs exit code and captured stderr/stdout for failed package-manager processes' {
        Write-ApplicationProcessFailureDiagnostics -Result ([pscustomobject]@{
            ExitCode = 87
            FilePath = 'winget.exe'
            Arguments = 'install --id Example.App'
            StandardError = "first error`nlast error"
            StandardOutput = "first output`nlast output"
        })

        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'exitCode=87'
        $script:warningMessages[0] | Should -Match 'stderr=.*last error'
        $script:warningMessages[0] | Should -Match 'stdout=.*last output'
    }
}

Describe 'Invoke-WingetInstall failure paths' {
    BeforeEach {
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-BaselineLocalizedString {
            param([string]$Key, [string]$Fallback, [object[]]$FormatArgs = @())
            if ($FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
            return $Fallback
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineLocalizedString -ErrorAction SilentlyContinue
    }

    It 'throws when the supplied availability state reports WinGetAvailable=$false' {
        $state = [pscustomobject]@{ WinGetAvailable = $false }

        { Invoke-WingetInstall -WinGetId 'X' -DisplayName 'x' -PackageManagerAvailabilityState $state } |
            Should -Throw '*WinGet is not available*'
    }

    It 'throws when WinGet availability is not supplied and probe returns false' {
        function Test-WinGetAvailable { param([switch]$Refresh) return $false }

        try {
            { Invoke-WingetInstall -WinGetId 'X' -DisplayName 'x' } |
                Should -Throw '*WinGet is not available*'
        }
        finally {
            Remove-Item Function:\Test-WinGetAvailable -ErrorAction SilentlyContinue
        }
    }

    It 'throws when Resolve-WinGetExecutable returns null' {
        function Test-WinGetAvailable { param([switch]$Refresh) return $true }
        function Resolve-WinGetExecutable { return $null }

        try {
            { Invoke-WingetInstall -WinGetId 'X' -DisplayName 'x' } |
                Should -Throw '*WinGet is not available*'
        }
        finally {
            Remove-Item Function:\Test-WinGetAvailable -ErrorAction SilentlyContinue
            Remove-Item Function:\Resolve-WinGetExecutable -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-WingetUpdate' {
    BeforeEach {
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:streamingCalls = [System.Collections.Generic.List[object]]::new()
        function Write-ConsoleStatus { param([string]$Action, [string]$Status) }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-BaselineLocalizedString {
            param([string]$Key, [string]$Fallback, [object[]]$FormatArgs = @())
            if ($FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
            return $Fallback
        }
        function Resolve-WinGetExecutable { return 'winget.exe' }
        function Test-WinGetAvailable { param([switch]$Refresh) return $true }
        function Invoke-StreamingProcess {
            param([string]$FilePath, [string[]]$ArgumentList)
            [void]$script:streamingCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
            })
            return 0
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineLocalizedString -ErrorAction SilentlyContinue
        Remove-Item Function:\Resolve-WinGetExecutable -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-WinGetAvailable -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-StreamingProcess -ErrorAction SilentlyContinue
    }

    It 'runs winget upgrade with silent non-interactive flags' {
        Invoke-WingetUpdate -WinGetId 'Mozilla.Firefox' -DisplayName 'Mozilla Firefox'

        $script:streamingCalls.Count | Should -Be 1
        @($script:streamingCalls[0].ArgumentList) | Should -Contain 'upgrade'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain '--silent'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain 'Mozilla.Firefox'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain '--disable-interactivity'
    }

    It 'throws when availability state disables WinGet' {
        $state = [pscustomobject]@{ WinGetAvailable = $false }

        { Invoke-WingetUpdate -WinGetId 'X' -DisplayName 'x' -PackageManagerAvailabilityState $state } |
            Should -Throw '*WinGet is not available*'
    }
}

Describe 'Invoke-ChocoInstall' {
    BeforeEach {
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:streamingCalls = [System.Collections.Generic.List[object]]::new()
        $script:executionPolicyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus { param([string]$Action, [string]$Status) }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-BaselineLocalizedString {
            param([string]$Key, [string]$Fallback, [object[]]$FormatArgs = @())
            if ($FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
            return $Fallback
        }
        function Resolve-ApplicationPackageId { param([string]$PackageId) return $PackageId }
        function Resolve-ChocolateyExecutable { return 'choco.exe' }
        function Invoke-StreamingProcess {
            param([string]$FilePath, [string[]]$ArgumentList)
            [void]$script:streamingCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
            })
            return 0
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineLocalizedString -ErrorAction SilentlyContinue
        Remove-Item Function:\Resolve-ApplicationPackageId -ErrorAction SilentlyContinue
        Remove-Item Function:\Resolve-ChocolateyExecutable -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-StreamingProcess -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ExecutionPolicy -ErrorAction SilentlyContinue
    }

    It 'runs choco install with expected non-interactive flags' {
        Invoke-ChocoInstall -ChocoId 'firefox' -DisplayName 'Mozilla Firefox'

        $script:streamingCalls.Count | Should -Be 1
        @($script:streamingCalls[0].ArgumentList) | Should -Contain 'install'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain '-y'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain '--no-progress'
        @($script:streamingCalls[0].ArgumentList) | Should -Contain 'firefox'
    }

    It 'throws when Chocolatey is unavailable and bootstrap install fails to resolve' {
        function Resolve-ChocolateyExecutable { return $null }
        function Invoke-ChocolateyBootstrap {
            param([int]$TimeoutSeconds)
            [pscustomobject]@{
                Success = $false
                Error   = 'Chocolatey bootstrap failed.'
            }
        }
        function Reset-ChocolateyAvailabilityState { }

        try {
            { Invoke-ChocoInstall -ChocoId 'firefox' -DisplayName 'Firefox' } |
                Should -Throw '*Firefox Install - Failed*'
        }
        finally {
            Remove-Item Function:\Resolve-ChocolateyExecutable -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-ChocolateyBootstrap -ErrorAction SilentlyContinue
            Remove-Item Function:\Reset-ChocolateyAvailabilityState -ErrorAction SilentlyContinue
        }
    }
}
