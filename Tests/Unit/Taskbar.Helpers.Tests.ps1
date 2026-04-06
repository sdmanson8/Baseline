Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Taskbar.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    if (-not ('WinAPI.Signature' -as [type])) {
        Add-Type -TypeDefinition @"
namespace WinAPI {
    public static class Signature {
        public static void Refresh() {}
    }
}
"@
    }

    if (-not ('WinAPI.NewsInterestsTaskbarHash' -as [type])) {
        Add-Type -TypeDefinition @"
namespace WinAPI {
    public static class NewsInterestsTaskbarHash {
        public static int HashData(byte[] pbData, int cbData, byte[] piet, int outputLen) {
            for (int i = 0; i < outputLen; i++) {
                piet[i] = (byte)(i + 1);
            }
            return 0;
        }
    }
}
"@
    }

    function LogWarning { param([string]$Message) $script:lastTaskbarWarning = $Message }
    function LogInfo {}
    function Set-RegistryValueSafe {}
    function Invoke-UCPDBypassed {
        param([scriptblock]$ScriptBlock)
        & $ScriptBlock
    }
}

Describe 'Get-TaskbarUnpinVerbCandidates' {
    It 'returns unique candidates and preserves the localized string' {
        $frenchUnpinVerb = ('D{0}tacher de la barre des t{1}ches' -f [char]0x00E9, [char]0x00E2)
        $result = @(Get-TaskbarUnpinVerbCandidates -LocalizedString 'Localized unpin')

        $result | Should -Contain 'Localized unpin'
        @($result | Select-Object -Unique).Count | Should -Be $result.Count
        $result | Should -Contain $frenchUnpinVerb
    }
}

Describe 'Invoke-TaskbarUnpin' {
    BeforeEach {
        $script:lastTaskbarWarning = $null
        $script:taskbarVerbInvoked = $false
    }

    It 'invokes the matching shell verb when it is available' {
        $verb = [pscustomobject]@{ Name = 'Unpin from taskbar' }
        $verb | Add-Member -MemberType ScriptMethod -Name DoIt -Value { $script:taskbarVerbInvoked = $true } -Force

        $shellItem = [pscustomobject]@{ Name = 'Windows Terminal' }
        $shellItem | Add-Member -MemberType ScriptMethod -Name Verbs -Value { @($verb) } -Force

        $result = Invoke-TaskbarUnpin -ShellItem $shellItem -LocalizedString 'Localized unpin'

        $result | Should -Be $true
        $script:taskbarVerbInvoked | Should -Be $true
    }

    It 'returns false and logs when the verb throws unauthorized access' {
        $verb = [pscustomobject]@{ Name = 'Unpin from taskbar' }
        $verb | Add-Member -MemberType ScriptMethod -Name DoIt -Value { throw ([System.UnauthorizedAccessException]::new('denied')) } -Force

        $shellItem = [pscustomobject]@{ Name = 'Windows Terminal' }
        $shellItem | Add-Member -MemberType ScriptMethod -Name Verbs -Value { @($verb) } -Force

        $result = Invoke-TaskbarUnpin -ShellItem $shellItem -LocalizedString 'Localized unpin'

        $result | Should -Be $false
        $script:lastTaskbarWarning | Should -Match 'denied'
    }
}

Describe 'Get-NewsInterestsTaskbarHashValue' {
    It 'uses the dedicated News and Interests hash interop type' {
        $result = Get-NewsInterestsTaskbarHashValue -MachineId 'machine-id' -ViewMode 2

        $result | Should -Be 67305985
    }
}

Describe 'Set-NewsInterestsTaskbarViewMode' {
    BeforeEach {
        Mock Get-NewsInterestsTaskbarHashValue { 424242 }
        $script:newsInterestsRegistryWrites = [System.Collections.Generic.List[object]]::new()
        Mock Set-RegistryValueSafe {
            param($Path, $Name, $Value, $Type, $AccessDeniedFallback)

            [void]$script:newsInterestsRegistryWrites.Add([pscustomobject]@{
                Path = $Path
                Name = $Name
                Value = $Value
                Type = $Type
                HasAccessDeniedFallback = ($null -ne $AccessDeniedFallback)
            })

            $true
        }
        Mock Invoke-UCPDBypassed { $global:LASTEXITCODE = 0 }
        $global:LASTEXITCODE = 0
    }

    It 'writes both required values via the safe registry helper' {
        Set-NewsInterestsTaskbarViewMode -MachineId 'machine-id' -ViewMode 2

        @($script:newsInterestsRegistryWrites | Where-Object {
            $_.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -and
            $_.Name -eq 'ShellFeedsTaskbarViewMode' -and
            $_.Type -eq 'DWord' -and
            $_.Value -eq 2 -and
            $_.HasAccessDeniedFallback
        }).Count | Should -Be 1

        @($script:newsInterestsRegistryWrites | Where-Object {
            $_.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -and
            $_.Name -eq 'EnShellFeedsTaskbarViewMode' -and
            $_.Type -eq 'DWord' -and
            $_.Value -eq 424242 -and
            $_.HasAccessDeniedFallback
        }).Count | Should -Be 1
    }

    It 'uses the UCPD-bypassed fallback when direct writes are denied' {
        Mock Set-RegistryValueSafe {
            param($Path, $Name, $Value, $Type, $AccessDeniedFallback)

            & $AccessDeniedFallback $Path $Name $Value $Type | Out-Null
            return $true
        }

        Set-NewsInterestsTaskbarViewMode -MachineId 'machine-id' -ViewMode 2

        Assert-MockCalled Invoke-UCPDBypassed -Times 2
    }
}
