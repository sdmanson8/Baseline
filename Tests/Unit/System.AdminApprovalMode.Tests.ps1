Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'AdminApprovalMode') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'AdminApprovalMode' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setPolicyCalls = [System.Collections.Generic.List[object]]::new()

        <#
            .SYNOPSIS
        #>

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )
        }

        <#
            .SYNOPSIS
        #>
        function LogInfo {
            param([string]$Message)
            [void]$script:loggedInfoMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function LogError {
            param([string]$Message)
            [void]$script:loggedErrorMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>

        function New-ItemProperty {
            param(
                [string]$Path,
                [string]$Name,
                [string]$PropertyType,
                [object]$Value,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{
                Path         = $Path
                Name         = $Name
                PropertyType = $PropertyType
                Value        = $Value
            })
        }

        <#
            .SYNOPSIS
        #>

        function Set-Policy {
            param(
                [string]$Scope,
                [string]$Path,
                [string]$Name,
                [string]$Type,
                [object]$Value
            )

            [void]$script:setPolicyCalls.Add([pscustomobject]@{
                Scope = $Scope
                Path  = $Path
                Name  = $Name
                Type  = $Type
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
    }

    It 'sets the correct registry values for <ParameterSet>' -ForEach @(
        @{
            ParameterSet = 'PromptForCredentials'
            ConsentValue = 1
            SecureDesktopValue = 1
            Message = "Setting UAC to 'Prompt for Credentials'"
        }
        @{
            ParameterSet = 'AlwaysNotify'
            ConsentValue = 2
            SecureDesktopValue = 1
            Message = "Setting UAC to 'Always notify'"
        }
        @{
            ParameterSet = 'Default'
            ConsentValue = 5
            SecureDesktopValue = 1
            Message = "Setting UAC to 'Notify when apps try to make changes'"
        }
        @{
            ParameterSet = 'NoDim'
            ConsentValue = 5
            SecureDesktopValue = 0
            Message = "Setting UAC to 'Notify when apps try to make changes (no dim)'"
        }
        @{
            ParameterSet = 'Never'
            ConsentValue = 0
            SecureDesktopValue = 0
            Message = "Setting UAC to 'Never notify'"
        }
    ) {
        $invokeArgs = @{}
        $invokeArgs[$ParameterSet] = $true

        AdminApprovalMode @invokeArgs

        $consentWrites = @($script:newItemPropertyCalls | Where-Object Name -eq 'ConsentPromptBehaviorAdmin')
        $secureWrites = @($script:newItemPropertyCalls | Where-Object Name -eq 'PromptOnSecureDesktop')

        $consentWrites.Count | Should -Be 1
        $secureWrites.Count | Should -Be 1
        $consentWrites[0].Value | Should -Be $ConsentValue
        $secureWrites[0].Value | Should -Be $SecureDesktopValue
        @($script:loggedInfoMessages) | Should -Contain $Message
    }

    It 'declares the full five-state UAC choice selector in the manifest' {
        $systemDataPath = Join-Path $PSScriptRoot '../../Module/Data/System.json'
        $systemData = Get-BaselineTestSourceText -Path $systemDataPath | ConvertFrom-Json -ErrorAction Stop
        $entry = @($systemData.Entries | Where-Object Function -eq 'AdminApprovalMode' | Select-Object -First 1)

        $entry | Should -Not -BeNullOrEmpty
        @($entry.Options) | Should -Be @('PromptForCredentials', 'AlwaysNotify', 'Default', 'NoDim', 'Never')
        @($entry.DisplayOptions) | Should -Be @(
            'Prompt for Credentials',
            'Always notify',
            'Notify when apps try to make changes',
            'Notify when apps try to make changes (no dim)',
            'Never notify'
        )
        $entry.Default | Should -Be 'Default'
        $entry.WinDefault | Should -Be 'Default'
    }
}
