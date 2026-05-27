Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.Startup.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Re-publish the module-scope tables that Get-BaselineStartupEntries reads via
    # $script:BaselineStartupRunPaths / $script:BaselineStartupFolderPaths. The AST
    $script:BaselineStartupRunPaths = @(
        [pscustomobject]@{ Source='HKLM\Run';     Scope='Machine';     Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                ApprovedKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   IsRunOnce=$false }
        [pscustomobject]@{ Source='HKLM\RunOnce'; Scope='Machine';     Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';            ApprovedKey=$null;                                                                              IsRunOnce=$true  }
        [pscustomobject]@{ Source='HKLM\Run32';   Scope='Machine';     Path='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';    ApprovedKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; IsRunOnce=$false }
        [pscustomobject]@{ Source='HKCU\Run';     Scope='CurrentUser'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                ApprovedKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   IsRunOnce=$false }
        [pscustomobject]@{ Source='HKCU\RunOnce'; Scope='CurrentUser'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';            ApprovedKey=$null;                                                                              IsRunOnce=$true  }
    )
    $script:BaselineStartupFolderPaths = @(
        [pscustomobject]@{ Source='StartupFolder\CurrentUser'; Scope='CurrentUser'; FolderEnvVar='APPDATA';     FolderRelative='Microsoft\Windows\Start Menu\Programs\Startup'; ApprovedKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
        [pscustomobject]@{ Source='StartupFolder\AllUsers';    Scope='Machine';     FolderEnvVar='ProgramData'; FolderRelative='Microsoft\Windows\Start Menu\Programs\Startup'; ApprovedKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )
}

Describe 'New-BaselineStartupApprovedBytes' {
    It 'returns 12 bytes leading 0x02 when -Enable:$true' {
        $bytes = New-BaselineStartupApprovedBytes -Enable:$true
        $bytes.Length | Should -Be 12
        $bytes[0] | Should -Be 0x02
        for ($i = 1; $i -lt 12; $i++) { $bytes[$i] | Should -Be 0 }
    }

    It 'returns 12 bytes leading 0x03 + non-zero FILETIME when -Enable:$false' {
        $bytes = New-BaselineStartupApprovedBytes -Enable:$false
        $bytes.Length | Should -Be 12
        $bytes[0] | Should -Be 0x03
        $ftSum = 0
        for ($i = 4; $i -lt 12; $i++) { $ftSum += $bytes[$i] }
        $ftSum | Should -BeGreaterThan 0
    }
}

Describe 'Get-BaselineStartupApprovedState' {
    BeforeEach {
        $script:approvedExists = $true
        $script:approvedBytes = ,([byte[]](0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        $script:approvedHasValueName = $true

        function Test-Path { param([string]$Path, [string]$LiteralPath) return $script:approvedExists }
        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Name)
            if (-not $script:approvedHasValueName) { throw "value not found" }
            $obj = [pscustomobject]@{}
            Add-Member -InputObject $obj -MemberType NoteProperty -Name $Name -Value $script:approvedBytes[0]
            return $obj
        }
    }

    AfterEach {
        foreach ($n in @('Test-Path','Get-ItemProperty')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'returns enabled when ApprovedKey is null/empty' {
        Get-BaselineStartupApprovedState -ApprovedKey $null -ValueName 'foo' | Should -Be 'enabled'
        Get-BaselineStartupApprovedState -ApprovedKey '' -ValueName 'foo' | Should -Be 'enabled'
    }

    It 'returns enabled when ApprovedKey path does not exist' {
        $script:approvedExists = $false
        Get-BaselineStartupApprovedState -ApprovedKey 'HKLM:\Bogus' -ValueName 'foo' | Should -Be 'enabled'
    }

    It 'returns enabled when value name is absent under the key' {
        $script:approvedHasValueName = $false
        Get-BaselineStartupApprovedState -ApprovedKey 'HKLM:\Bogus' -ValueName 'foo' | Should -Be 'enabled'
    }

    It 'returns enabled when first byte clears the 0x01 bit' {
        $script:approvedBytes = ,([byte[]](0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        Get-BaselineStartupApprovedState -ApprovedKey 'HKLM:\Bogus' -ValueName 'foo' | Should -Be 'enabled'
    }

    It 'returns disabled when first byte sets the 0x01 bit' {
        $script:approvedBytes = ,([byte[]](0x03, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8))
        Get-BaselineStartupApprovedState -ApprovedKey 'HKLM:\Bogus' -ValueName 'foo' | Should -Be 'disabled'
    }
}

Describe 'Get-BaselineStartupEntries' {
    BeforeEach {
        $script:savedAppData = $env:APPDATA
        $script:savedProgramData = $env:ProgramData
        # Point folder enumeration at non-existent paths so registry side is isolated by default.
        $env:APPDATA = 'C:\Baseline_TestNoSuchPath_AppData'
        $env:ProgramData = 'C:\Baseline_TestNoSuchPath_ProgramData'

        $script:registry = @{}    # path -> @{ name = command }
        $script:approved = @{}    # approvedKey -> @{ name = byte[] }

        function Test-Path {
            param([string]$Path, [string]$LiteralPath)
            $p = if ($LiteralPath) { $LiteralPath } else { $Path }
            return ($script:registry.ContainsKey($p) -or $script:approved.ContainsKey($p))
        }
        function Get-Item {
            [CmdletBinding()]
            param([string]$LiteralPath)
            if (-not $script:registry.ContainsKey($LiteralPath)) { throw "no such key $LiteralPath" }
            $values = $script:registry[$LiteralPath]
            $obj = [pscustomobject]@{}
            Add-Member -InputObject $obj -MemberType ScriptMethod -Name GetValueNames -Value ([scriptblock]::Create("@('$([string]::Join("','", @($values.Keys)))')"))
            $obj | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
                param($n, $default, $opts)
                $vals = $script:registry[$LiteralPathCaptured]
                if ($vals.ContainsKey($n)) { return $vals[$n] }
                return $default
            }.GetNewClosure()
            # Capture path into closure-friendly variable
            $LiteralPathCaptured = $LiteralPath
            $obj | Add-Member -MemberType ScriptMethod -Name GetValue -Force -Value ([scriptblock]::Create(@"
                param(`$n, `$default, `$opts)
                `$vals = `$script:registry['$LiteralPath']
                if (`$vals.ContainsKey(`$n)) { return `$vals[`$n] }
                return `$default
"@))
            return $obj
        }
        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Name)
            if (-not $script:approved.ContainsKey($LiteralPath)) { throw "no approved key $LiteralPath" }
            $vals = $script:approved[$LiteralPath]
            if (-not $vals.ContainsKey($Name)) { throw "no value $Name" }
            $obj = [pscustomobject]@{}
            Add-Member -InputObject $obj -MemberType NoteProperty -Name $Name -Value $vals[$Name]
            return $obj
        }
        function Get-ChildItem {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Filter, [switch]$File)
            return @()
        }
    }

    AfterEach {
        $env:APPDATA = $script:savedAppData
        $env:ProgramData = $script:savedProgramData
        foreach ($n in @('Test-Path','Get-Item','Get-ItemProperty','Get-ChildItem')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'returns an empty array when no Run keys and no startup folders exist' {
        $entries = Get-BaselineStartupEntries
        @($entries).Count | Should -Be 0
    }

    It 'enumerates a single HKCU\Run value as enabled when no StartupApproved entry exists' {
        $script:registry['HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'] = @{ 'MyApp' = 'C:\app.exe' }

        $entries = @(Get-BaselineStartupEntries)
        $entries.Count | Should -Be 1
        $entries[0].EntryId | Should -Be 'HKCU\Run|MyApp'
        $entries[0].Source  | Should -Be 'HKCU\Run'
        $entries[0].Scope   | Should -Be 'CurrentUser'
        $entries[0].Name    | Should -Be 'MyApp'
        $entries[0].Command | Should -Be 'C:\app.exe'
        $entries[0].Enabled | Should -BeTrue
        $entries[0].Kind    | Should -Be 'RegistryRun'
        $entries[0].IsRunOnce | Should -BeFalse
    }

    It 'reports Enabled=$false when StartupApproved bit is set' {
        $script:registry['HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'] = @{ 'OffApp' = 'C:\off.exe' }
        $script:approved['HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'] = @{
            'OffApp' = ([byte[]](0x03,0,0,0, 1,2,3,4, 5,6,7,8))
        }

        $entries = @(Get-BaselineStartupEntries)
        $entries.Count | Should -Be 1
        $entries[0].Enabled | Should -BeFalse
    }

    It 'enumerates StartupFolder .lnk files when APPDATA folder exists' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline_startup_test_" + [guid]::NewGuid().ToString('N'))
        $startupDir = Join-Path $tmp 'Microsoft\Windows\Start Menu\Programs\Startup'
        New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
        $env:APPDATA = $tmp
        try {
            # Override Get-ChildItem to return synthetic .lnk for the APPDATA path.
            function Get-ChildItem {
                [CmdletBinding()]
                param([string]$LiteralPath, [string]$Filter, [switch]$File)
                return @([pscustomobject]@{ Name = 'Foo.lnk'; FullName = (Join-Path $LiteralPath 'Foo.lnk') })
            }
            # Test-Path needs to allow the APPDATA folder path through, but reject the AllUsers branch.
            $script:appDataFolderPath = $startupDir
            function Test-Path {
                param([string]$Path, [string]$LiteralPath)
                $p = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($p -eq $script:appDataFolderPath) { return $true }
                return ($script:registry.ContainsKey($p) -or $script:approved.ContainsKey($p))
            }

            $entries = @(Get-BaselineStartupEntries)
            $entries.Count | Should -Be 1
            $entries[0].Source | Should -Be 'StartupFolder\CurrentUser'
            $entries[0].Name   | Should -Be 'Foo.lnk'
            $entries[0].Kind   | Should -Be 'StartupFolder'
            $entries[0].Enabled | Should -BeTrue
        }
        finally {
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Set-BaselineStartupEntryEnabled' {
    BeforeEach {
        $script:savedAppData = $env:APPDATA
        $script:savedProgramData = $env:ProgramData
        $env:APPDATA = 'C:\Baseline_TestNoSuchPath_AppData'
        $env:ProgramData = 'C:\Baseline_TestNoSuchPath_ProgramData'

        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:approvedKeyExists = $true
        $script:setThrows = $false

        # Pre-stage a single HKCU\Run entry so Get-BaselineStartupEntries finds it.
        $script:registry = @{
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' = @{ 'MyApp' = 'C:\app.exe' }
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' = @{ 'OnceApp' = 'C:\once.exe' }
        }
        $script:approved = @{}

        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path {
            param([string]$Path, [string]$LiteralPath)
            $p = if ($LiteralPath) { $LiteralPath } else { $Path }
            if ($p -like '*\StartupApproved\*') { return $script:approvedKeyExists }
            return $script:registry.ContainsKey($p)
        }
        function Get-Item {
            [CmdletBinding()]
            param([string]$LiteralPath)
            if (-not $script:registry.ContainsKey($LiteralPath)) { throw "no such key" }
            $values = $script:registry[$LiteralPath]
            $obj = [pscustomobject]@{}
            $obj | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value ([scriptblock]::Create("@('$([string]::Join("','", @($values.Keys)))')"))
            $obj | Add-Member -MemberType ScriptMethod -Name GetValue -Value ([scriptblock]::Create(@"
                param(`$n, `$default, `$opts)
                `$vals = `$script:registry['$LiteralPath']
                if (`$vals.ContainsKey(`$n)) { return `$vals[`$n] }
                return `$default
"@))
            return $obj
        }
        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Name)
            throw "no value $Name"
        }
        function Get-ChildItem {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Filter, [switch]$File)
            return @()
        }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Name, [object]$Value, [string]$Type)
            if ($script:setThrows) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ LiteralPath = $LiteralPath; Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        $env:APPDATA = $script:savedAppData
        $env:ProgramData = $script:savedProgramData
        foreach ($n in @('LogError','Test-Path','Get-Item','Get-ItemProperty','Get-ChildItem','New-Item','Set-ItemProperty')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'returns $false and logs error when EntryId is not found' {
        $result = Set-BaselineStartupEntryEnabled -EntryId 'HKCU\Run|NotReal' -Disable
        $result | Should -BeFalse
        $script:errorMessages[0] | Should -Match 'no entry'
    }

    It 'returns $false and logs error for RunOnce entries (no ApprovedKey)' {
        $result = Set-BaselineStartupEntryEnabled -EntryId 'HKCU\RunOnce|OnceApp' -Disable
        $result | Should -BeFalse
        $script:errorMessages[0] | Should -Match 'StartupApproved'
    }

    It 'creates the StartupApproved key when missing on -Disable' {
        $script:approvedKeyExists = $false
        $result = Set-BaselineStartupEntryEnabled -EntryId 'HKCU\Run|MyApp' -Disable
        $result | Should -BeTrue
        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Match 'StartupApproved\\Run$'
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Type | Should -Be 'Binary'
        $script:setItemPropertyCalls[0].Value[0] | Should -Be 0x03
    }

    It 'writes 0x02 leading byte when -Enable' {
        $script:approvedKeyExists = $true
        $result = Set-BaselineStartupEntryEnabled -EntryId 'HKCU\Run|MyApp' -Enable
        $result | Should -BeTrue
        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Value[0] | Should -Be 0x02
        $script:setItemPropertyCalls[0].Name | Should -Be 'MyApp'
    }

    It 'returns $false and logs when Set-ItemProperty throws' {
        $script:setThrows = $true
        $result = Set-BaselineStartupEntryEnabled -EntryId 'HKCU\Run|MyApp' -Disable
        $result | Should -BeFalse
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}

Describe 'Reset-BaselineStartupEntries' {
    It 'calls Set-BaselineStartupEntryEnabled -Enable for each EntryId and returns the count of successes' {
        $script:reEnableCalls = [System.Collections.Generic.List[string]]::new()
        function Set-BaselineStartupEntryEnabled {
            [CmdletBinding(DefaultParameterSetName='Disable')]
            param(
                [Parameter(Mandatory=$true)][string]$EntryId,
                [Parameter(Mandatory=$true, ParameterSetName='Enable')][switch]$Enable,
                [Parameter(Mandatory=$true, ParameterSetName='Disable')][switch]$Disable
            )
            [void]$script:reEnableCalls.Add($EntryId)
            return ($EntryId -ne 'fail-id')
        }
        try {
            $count = Reset-BaselineStartupEntries -EntryIdsDisabledByThisRun @('HKCU\Run|A','HKCU\Run|B','fail-id')
            $count | Should -Be 2
            $script:reEnableCalls.Count | Should -Be 3
            $script:reEnableCalls[0] | Should -Be 'HKCU\Run|A'
        }
        finally {
            Microsoft.PowerShell.Management\Remove-Item Function:\Set-BaselineStartupEntryEnabled -ErrorAction SilentlyContinue
        }
    }

    It 'skips empty / whitespace EntryIds without invoking Set-' {
        $script:reEnableCalls = [System.Collections.Generic.List[string]]::new()
        function Set-BaselineStartupEntryEnabled {
            [CmdletBinding(DefaultParameterSetName='Disable')]
            param(
                [Parameter(Mandatory=$true)][string]$EntryId,
                [Parameter(Mandatory=$true, ParameterSetName='Enable')][switch]$Enable,
                [Parameter(Mandatory=$true, ParameterSetName='Disable')][switch]$Disable
            )
            [void]$script:reEnableCalls.Add($EntryId)
            return $true
        }
        try {
            $count = Reset-BaselineStartupEntries -EntryIdsDisabledByThisRun @('','   ',$null,'HKCU\Run|Real')
            $count | Should -Be 1
            $script:reEnableCalls.Count | Should -Be 1
            $script:reEnableCalls[0] | Should -Be 'HKCU\Run|Real'
        }
        finally {
            Microsoft.PowerShell.Management\Remove-Item Function:\Set-BaselineStartupEntryEnabled -ErrorAction SilentlyContinue
        }
    }
}
