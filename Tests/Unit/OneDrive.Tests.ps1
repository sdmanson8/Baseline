Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OneDrive.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'OneDrive' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:startProcessCalls = [System.Collections.Generic.List[object]]::new()
        $script:stopProcessCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:installedPackage = $null
        $script:userEmail = $null
        $script:setupPathExists = $true
        $script:webRequestCalls = [System.Collections.Generic.List[object]]::new()
        $script:scheduledTaskCalls = [System.Collections.Generic.List[string]]::new()

        $Script:Localization = [pscustomobject]@{
            OneDriveUninstalling = 'Uninstalling OneDrive'
            OneDriveInstalling = 'Installing OneDrive'
        }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Path = $Path; Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string[]]$Name, [switch]$Force, [object]$ErrorAction)
            foreach ($n in @($Name)) {
                [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $n })
            }
        }
        function Remove-Item {
            param([string[]]$Path, [switch]$Recurse, [switch]$Force, [object]$ErrorAction)
            foreach ($p in @($Path)) {
                [void]$script:removeItemCalls.Add($p)
            }
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string[]]$Name)
        }
        function Get-Package {
            param([string]$Name, [string]$ProviderName, [switch]$Force, [object]$ErrorAction, [object]$WarningAction)
            if ($null -eq $script:installedPackage) { return }
            return $script:installedPackage
        }
        function Get-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            if ($Name -eq 'UserEmail') {
                if ($script:userEmail) { return [pscustomobject]@{ UserEmail = $script:userEmail } }
                return $null
            }
            return $null
        }
        function Get-ItemPropertyValue {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            return $null
        }
        function Get-OneDriveSetupPath {
            if ($script:setupPathExists) { return 'C:\Windows\System32\OneDriveSetup.exe' }
            return $null
        }
        function Test-Path {
            param([string]$LiteralPath, [string]$Path)
            if ($LiteralPath -match 'OneDriveSetup\.exe') { return $script:setupPathExists }
            return $false
        }
        function Stop-Process {
            param([string[]]$Name, [switch]$Force, [object]$ErrorAction)
            foreach ($n in @($Name)) {
                [void]$script:stopProcessCalls.Add($n)
            }
        }
        function Start-Process {
            param([string]$FilePath, [object[]]$ArgumentList, [switch]$Wait, [switch]$PassThru, [object]$ErrorAction)
            [void]$script:startProcessCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
            })
            [pscustomobject]@{ ExitCode = 0 }
        }
        function Invoke-BaselineProcess {
            param([string]$FilePath, [object[]]$ArgumentList, [int]$TimeoutSeconds)
            [void]$script:startProcessCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
            })
            [pscustomobject]@{ ExitCode = 0 }
        }
        function Get-ChildItem {
            param([string]$Path, [object]$ErrorAction)
            return @()
        }
        function Unregister-ScheduledTask {
            param([string]$TaskName, [switch]$Confirm, [object]$ErrorAction)
            [void]$script:scheduledTaskCalls.Add("Unregister:$TaskName")
        }
        function Enable-ScheduledTask { param([Parameter(ValueFromPipeline=$true)]$InputObject) }
        function Start-ScheduledTask { param([Parameter(ValueFromPipeline=$true)]$InputObject) }
        function Get-ScheduledTask {
            param([string]$TaskName, [object]$ErrorAction)
            return @()
        }
        function Invoke-WebRequest {
            param([string]$Uri, [string]$OutFile, [int]$TimeoutSec, [object]$ErrorAction)
            [void]$script:webRequestCalls.Add([pscustomobject]@{ Uri = $Uri; OutFile = $OutFile })
        }
        function Start-Sleep { param([int]$Seconds) }
        function Get-Process {
            param([string]$Name, [object]$ErrorAction)
            return @()
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Set-Policy','Remove-ItemProperty','Remove-Item','Remove-RegistryValueSafe','Get-Package','Get-ItemProperty','Get-ItemPropertyValue','Get-OneDriveSetupPath','Test-Path','Stop-Process','Start-Process','Invoke-BaselineProcess','Get-ChildItem','Unregister-ScheduledTask','Enable-ScheduledTask','Start-ScheduledTask','Get-ScheduledTask','Invoke-WebRequest','Start-Sleep','Get-Process')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires either Install or Uninstall' {
        { OneDrive } | Should -Throw
    }

    It 'treats Uninstall as already satisfied when OneDrive is not installed' {
        $script:installedPackage = $null
        OneDrive -Uninstall

        $script:warningMessages.Count | Should -Be 0
        $script:infoMessages | Should -Contain 'Skipping OneDrive uninstall because the app is not currently installed.'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:startProcessCalls.Count | Should -Be 0
    }

    It 'skips Uninstall when the user is still signed in' {
        $pkg = [pscustomobject]@{
            Meta = [pscustomobject]@{ Attributes = @{ 'UninstallString' = 'C:\Windows\System32\OneDriveSetup.exe /uninstall' } }
        }
        $script:installedPackage = $pkg
        $script:userEmail = 'user@example.com'

        OneDrive -Uninstall

        $script:warningMessages.Count | Should -BeGreaterThan 0
        $script:warningMessages | Should -Contain 'Skipping OneDrive uninstall because the current user is still signed in. Sign out of OneDrive first, then retry if removal is still desired.'
        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:startProcessCalls.Count | Should -Be 0
    }

    It 'runs the uninstall executable when the package is installed and no user is signed in' {
        $pkg = [pscustomobject]@{
            Meta = [pscustomobject]@{ Attributes = @{ 'UninstallString' = 'C:\Windows\System32\OneDriveSetup.exe /uninstall' } }
        }
        $script:installedPackage = $pkg
        $script:userEmail = $null
        $script:setupPathExists = $true

        OneDrive -Uninstall

        $script:startProcessCalls.Count | Should -Be 1
        $script:startProcessCalls[0].FilePath | Should -Match 'OneDriveSetup\.exe$'
        @($script:startProcessCalls[0].ArgumentList) | Should -Contain '/uninstall'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:stopProcessCalls | Should -Contain 'OneDrive'
    }

    It 'treats Install as already satisfied when OneDrive is already installed' {
        $script:installedPackage = [pscustomobject]@{ Name = 'Microsoft OneDrive' }

        OneDrive -Install

        $script:warningMessages.Count | Should -Be 0
        $script:infoMessages | Should -Contain 'Skipping OneDrive install because the app is already installed.'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:startProcessCalls.Count | Should -Be 0
    }

    It 'runs Install silently when a setup executable is available' {
        $script:installedPackage = $null
        $script:setupPathExists = $true

        OneDrive -Install

        $script:startProcessCalls.Count | Should -Be 1
        @($script:startProcessCalls[0].ArgumentList) | Should -Contain '/silent'
        @($script:startProcessCalls[0].ArgumentList) | Should -Not -Contain '/allusers'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'passes /allusers when Install -AllUsers is requested' {
        $script:installedPackage = $null
        $script:setupPathExists = $true

        OneDrive -Install -AllUsers

        @($script:startProcessCalls[0].ArgumentList) | Should -Be @('/silent', '/allusers')
    }

    It 'always clears the OneDrive sync policy before doing anything else' {
        $script:installedPackage = $null
        $script:setupPathExists = $true

        OneDrive -Install

        $script:policyCalls.Count | Should -BeGreaterThan 0
        $script:policyCalls[0].Type | Should -Be 'CLEAR'
        $script:policyCalls[0].Name | Should -Be 'DisableFileSyncNGSC'
    }
}
