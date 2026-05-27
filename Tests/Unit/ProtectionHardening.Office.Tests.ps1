Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('MacroRuntimeScanScope','RtfDocuments','OneNoteEmbeds')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'MacroRuntimeScanScope' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnSet = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnSet) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes MacroRuntimeScanScope=2 for the six Office 16.0 apps and creates missing keys' {
        $script:pathExists = $false

        MacroRuntimeScanScope

        $script:newItemCalls.Count | Should -Be 6
        $script:setItemPropertyCalls.Count | Should -Be 6
        foreach ($call in $script:setItemPropertyCalls) {
            $call.Name | Should -Be 'MacroRuntimeScanScope'
            $call.Value | Should -Be 2
            $call.Path | Should -Match 'Office\\16\.0\\(Word|Excel|PowerPoint|Publisher|Visio|Access)\\Security$'
        }

        $apps = $script:setItemPropertyCalls | ForEach-Object {
            ($_.Path -replace '.*Office\\16\.0\\','') -replace '\\Security$',''
        }
        $apps | Should -Contain 'Word'
        $apps | Should -Contain 'Excel'
        $apps | Should -Contain 'PowerPoint'
        $apps | Should -Contain 'Publisher'
        $apps | Should -Contain 'Visio'
        $apps | Should -Contain 'Access'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when Set-ItemProperty throws' {
        $script:pathExists = $true
        $script:throwOnSet = $true

        MacroRuntimeScanScope

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}

Describe 'RtfDocuments' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnSet = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnSet) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes RtfFiles=2 + OpenInProtectedView=0 across Word 14.0/15.0/16.0' {
        $script:pathExists = $false

        RtfDocuments

        # 3 versions, 2 settings each -> 6 Set-ItemProperty calls; 3 New-Item calls
        $script:newItemCalls.Count | Should -Be 3
        $script:setItemPropertyCalls.Count | Should -Be 6

        $rtf = $script:setItemPropertyCalls | Where-Object { $_.Name -eq 'RtfFiles' }
        $opv = $script:setItemPropertyCalls | Where-Object { $_.Name -eq 'OpenInProtectedView' }
        $rtf.Count | Should -Be 3
        $opv.Count | Should -Be 3
        ($rtf | ForEach-Object { $_.Value }) | Should -Be @(2,2,2)
        ($opv | ForEach-Object { $_.Value }) | Should -Be @(0,0,0)
        foreach ($call in $script:setItemPropertyCalls) {
            $call.Path | Should -Match 'Office\\(14|15|16)\.0\\Word\\Security\\FileBlock$'
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when Set-ItemProperty throws' {
        $script:pathExists = $true
        $script:throwOnSet = $true

        RtfDocuments

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}

Describe 'OneNoteEmbeds' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnSet = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnSet) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes DisableEmbeddedFiles=1 + BlockedExtensions across OneNote 14.0/15.0/16.0' {
        $script:pathExists = $false

        OneNoteEmbeds

        $script:newItemCalls.Count | Should -Be 3
        $script:setItemPropertyCalls.Count | Should -Be 6

        $disable = $script:setItemPropertyCalls | Where-Object { $_.Name -eq 'DisableEmbeddedFiles' }
        $blocked = $script:setItemPropertyCalls | Where-Object { $_.Name -eq 'BlockedExtensions' }
        $disable.Count | Should -Be 3
        $blocked.Count | Should -Be 3
        ($disable | ForEach-Object { $_.Value }) | Should -Be @(1,1,1)
        foreach ($call in $blocked) {
            $call.Value | Should -Match '\.exe'
            $call.Value | Should -Match '\.ps1'
            $call.Value | Should -Match '\.lnk'
            $call.Value | Should -Match '\.iso'
        }
        foreach ($call in $script:setItemPropertyCalls) {
            $call.Path | Should -Match 'Office\\(14|15|16)\.0\\OneNote\\Options$'
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when Set-ItemProperty throws' {
        $script:pathExists = $true
        $script:throwOnSet = $true

        OneNoteEmbeds

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}
