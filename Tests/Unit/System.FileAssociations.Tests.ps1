Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.FileAssociations.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    # Pick only the top-level function definitions (skip nested ones which are
    # re-defined inside their parent at call time).
    $functions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and
        ($node.Parent -isnot [System.Management.Automation.Language.NamedBlockAst] -or $node.Parent.Parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst])
    }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Shared Localization used by WinPrtScrFolder's "skip" branches.
    $Script:Localization = [pscustomobject]@{
        OneDriveWarning = 'OneDriveWarning: {0}'
        Skipped         = 'Skipped: {0}'
    }
}

Describe 'Export-Associations' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:dismExitCode = 1  # simulate failure so we don't reach the XML/registry walk

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        # Shim Dism.exe by exposing a function with that name. PowerShell will
        # resolve it before searching PATH.
        function Dism.exe {
            $global:LASTEXITCODE = $script:dismExitCode
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Dism.exe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'reports failed and logs an error when Dism returns a non-zero exit code' {
        $script:dismExitCode = 5

        Export-Associations

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -BeGreaterOrEqual 1
        $script:errorMessages[0] | Should -Match 'export application associations'
    }
}

Describe 'Import-Associations (cancelled dialog)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setAssociationCalls = [System.Collections.Generic.List[object]]::new()
        $Script:Localization = [pscustomobject]@{ AllFilesFilter = 'All files' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) }
        # If the inner code reaches Set-Association we want to know about it
        function Set-Association {
            param([string]$ProgramPath, [string]$Extension, [string]$Icon)
            [void]$script:setAssociationCalls.Add([pscustomobject]@{ ProgramPath = $ProgramPath; Extension = $Extension; Icon = $Icon })
        }
        # Add-Type is required inside the function; make it a no-op because
        # System.Windows.Forms may not load in every test host.
        function Add-Type { param([string]$AssemblyName) }
        # Replace New-Object for the specific dialog/form types so
        # OpenFileDialog.FileName comes back empty (user cancelled).
        function New-Object {
            [CmdletBinding(DefaultParameterSetName='Default')]
            param(
                [Parameter(Position=0)][string]$TypeName,
                [Parameter(ValueFromRemainingArguments=$true)][object[]]$Remaining
            )
            switch -Wildcard ($TypeName) {
                'System.Windows.Forms.OpenFileDialog' {
                    return [pscustomobject]@{
                        Filter          = ''
                        InitialDirectory = ''
                        Multiselect     = $false
                        FileName        = ''
                    } | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value { return 'Cancel' } -PassThru
                }
                default {
                    throw "New-Object shim received unexpected TypeName: $TypeName"
                }
            }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-Association','Add-Type','New-Object')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'does not invoke Set-Association when the user cancels the dialog' {
        Import-Associations

        $script:setAssociationCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'WinPrtScrFolder' {
    BeforeEach {
        $Script:Localization = [pscustomobject]@{
            OneDriveWarning = 'OneDriveWarning: {0}'
            Skipped         = 'Skipped: {0}'
        }
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        $script:oneDriveSignedIn = $false
        $script:oneDriveInstalled = $null
        $script:presetName = ''
        $script:callStack = @()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-TweakSkipLabel { param($Invocation) return 'WinPrtScrFolder' }

        function Get-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            if ($script:oneDriveSignedIn) { return [pscustomobject]@{ UserEmail = 'test@example.com' } }
            return $null
        }
        function Get-ItemPropertyValue {
            param([string]$Path, [string]$Name)
            return 'C:\Users\Test\Desktop'
        }
        function Get-Package {
            param([string]$Name, [string]$ProviderName, [switch]$Force, [object]$ErrorAction, [object]$WarningAction)
            return $script:oneDriveInstalled
        }
        function Select-String {
            param([string]$Path, [string]$Pattern, [switch]$SimpleMatch)
            return $null
        }
        function Get-Variable {
            param([string]$Name, [string]$Scope, [object]$ErrorAction)
            if ($Name -eq 'MyInvocation') {
                return [pscustomobject]@{ Value = [pscustomobject]@{ PSCommandPath = $script:presetName } }
            }
            if ($Name -eq 'BaselineHeadlessCommands') {
                return $null
            }
            return $null
        }
        function Get-PSCallStack {
            return @([pscustomobject]@{ Position = [pscustomobject]@{ Text = ($script:callStack -join "`n") } })
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Remove-RegistryValueSafe {
            param([string[]]$Path, [string[]]$Name)
            foreach ($singlePath in @($Path)) {
                foreach ($singleName in @($Name)) {
                    [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $singlePath; Name = $singleName })
                }
            }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-TweakSkipLabel',
                         'Get-ItemProperty','Get-ItemPropertyValue','Get-Package','Select-String',
                         'Get-Variable','Get-PSCallStack','New-ItemProperty','Remove-ItemProperty','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Desktop or Default' {
        { WinPrtScrFolder } | Should -Throw
    }

    It 'skips and logs a warning for -Desktop when OneDrive is signed in' {
        $script:oneDriveSignedIn = $true

        WinPrtScrFolder -Desktop

        $script:warningMessages.Count | Should -BeGreaterOrEqual 1
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'removes the redirection property on -Default' {
        WinPrtScrFolder -Default

        $script:removeItemPropertyCalls.Count | Should -Be 1
        $script:removeItemPropertyCalls[0].Name | Should -Be '{B7BEDE81-DF94-4682-A7D8-57A52620B86F}'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
