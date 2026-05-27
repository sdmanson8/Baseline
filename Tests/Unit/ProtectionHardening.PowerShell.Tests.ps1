Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('PowerShellTranscription','PowerShellV2')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'PowerShellTranscription' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[object]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:existingPaths = [System.Collections.Generic.HashSet[string]]::new()
        $script:throwOnSet = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:existingPaths.Contains($Path) }
        function New-Item {
            param([string]$Path, [string]$ItemType, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add([pscustomobject]@{ Path = $Path; ItemType = $ItemType })
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

    It 'creates the transcript directory and policy key, then writes the three values' {
        PowerShellTranscription

        # Two New-Item calls: directory and registry key, neither pre-existing
        $script:newItemCalls.Count | Should -Be 2
        $script:newItemCalls[0].Path | Should -Match 'PSTranscripts$'
        $script:newItemCalls[0].ItemType | Should -Be 'Directory'
        $script:newItemCalls[1].Path | Should -Match 'PowerShell\\Transcription$'

        $script:setItemPropertyCalls.Count | Should -Be 3
        $names = $script:setItemPropertyCalls | ForEach-Object { $_.Name }
        $names | Should -Contain 'EnableTranscripting'
        $names | Should -Contain 'EnableInvocationHeader'
        $names | Should -Contain 'OutputDirectory'
        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'EnableTranscripting' }).Value | Should -Be 1
        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'EnableInvocationHeader' }).Value | Should -Be 1
        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'OutputDirectory' }).Value | Should -Match 'PSTranscripts$'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips New-Item when both the directory and policy key already exist' {
        [void]$script:existingPaths.Add("$env:SystemDrive\PSTranscripts")
        [void]$script:existingPaths.Add('HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription')

        PowerShellTranscription

        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 3
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed and logs error when Set-ItemProperty throws' {
        [void]$script:existingPaths.Add("$env:SystemDrive\PSTranscripts")
        [void]$script:existingPaths.Add('HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription')
        $script:throwOnSet = $true

        PowerShellTranscription

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}

Describe 'PowerShellV2' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:processCalls = [System.Collections.Generic.List[object]]::new()
        $script:throwOnFeature = $null

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$LiteralPath, [object]$PathType) return $true }
        function Invoke-BaselineProcess {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds,
                [int[]]$AllowedExitCodes,
                [switch]$CaptureOutput
            )

            $featureName = ([string[]]$ArgumentList | Where-Object { $_ -like '/FeatureName:*' } | Select-Object -First 1) -replace '^/FeatureName:', ''
            if ($script:throwOnFeature -and $FeatureName -eq $script:throwOnFeature) {
                throw "feature $FeatureName denied"
            }
            [void]$script:processCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
                AllowedExitCodes = @($AllowedExitCodes)
                CaptureOutput = [bool]$CaptureOutput
                FeatureName = $featureName
            })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','Invoke-BaselineProcess')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'disables both V2 features through bounded DISM processes when both calls succeed' {
        PowerShellV2

        $script:processCalls.Count | Should -Be 2
        $script:processCalls.FeatureName | Should -Contain 'MicrosoftWindowsPowerShellV2'
        $script:processCalls.FeatureName | Should -Contain 'MicrosoftWindowsPowerShellV2Root'
        $script:processCalls[0].FilePath | Should -Match 'dism\.exe$'
        $script:processCalls[0].ArgumentList | Should -Contain '/Online'
        $script:processCalls[0].ArgumentList | Should -Contain '/Disable-Feature'
        $script:processCalls[0].ArgumentList | Should -Contain '/NoRestart'
        $script:processCalls[0].TimeoutSeconds | Should -Be 300
        $script:processCalls[0].AllowedExitCodes | Should -Contain 0
        $script:processCalls[0].AllowedExitCodes | Should -Contain 3010
        $script:processCalls[0].CaptureOutput | Should -BeTrue
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'continues to the second feature when the first call throws and reports failed' {
        $script:throwOnFeature = 'MicrosoftWindowsPowerShellV2'

        PowerShellV2

        $script:processCalls.Count | Should -Be 1
        $script:processCalls[0].FeatureName | Should -Be 'MicrosoftWindowsPowerShellV2Root'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'MicrosoftWindowsPowerShellV2'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }

    It 'reports failed when the V2Root feature throws but still disables V2' {
        $script:throwOnFeature = 'MicrosoftWindowsPowerShellV2Root'

        PowerShellV2

        $script:processCalls.Count | Should -Be 1
        $script:processCalls[0].FeatureName | Should -Be 'MicrosoftWindowsPowerShellV2'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'MicrosoftWindowsPowerShellV2Root'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }
}
