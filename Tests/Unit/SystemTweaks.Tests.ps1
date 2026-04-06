Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks.psm1'
    $script:systemTweaksAst = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $script:systemTweaksAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'LanmanWorkstationGuestAuthPolicy') {
            Invoke-Expression $fn.Extent.Text
        }
    }

    # Also scan extracted sub-modules (e.g. SystemTweaks.SMBRepair.psm1)
    $subModuleDir = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks'
    if (Test-Path $subModuleDir) {
        foreach ($subFile in (Get-ChildItem -LiteralPath $subModuleDir -Filter '*.psm1' -File)) {
            $subAst = [System.Management.Automation.Language.Parser]::ParseFile($subFile.FullName, [ref]$null, [ref]$null)
            $subFns = $subAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $subFns) {
                if ($fn.Name -eq 'LanmanWorkstationGuestAuthPolicy') {
                    Invoke-Expression $fn.Extent.Text
                }
            }
            # Keep the combined AST for downstream tests (e.g. ServicesManual metadata)
            if (-not $script:systemTweaksAst) { $script:systemTweaksAst = $subAst }
        }
    }
}

Describe 'LanmanWorkstationGuestAuthPolicy' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )
        }

        function LogInfo {
            param([string]$Message)
            [void]$script:loggedInfoMessages.Add($Message)
        }

        function LogError {
            param([string]$Message)
        }

        function Set-Policy {
            param(
                [string]$Scope,
                [string]$Path,
                [string]$Name,
                [string]$Type,
                [object]$Value
            )
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
    }

    It 'logs the disable operation in the correct past tense' {
        LanmanWorkstationGuestAuthPolicy -Disable

        @($script:loggedInfoMessages) | Should -Contain 'Disabled LanmanWorkstation guest-auth policy (AllowInsecureGuestAuth = 0)'
    }

    It 'logs the enable operation in the correct past tense' {
        LanmanWorkstationGuestAuthPolicy -Enable

        @($script:loggedInfoMessages) | Should -Contain 'Enabled LanmanWorkstation guest-auth policy (AllowInsecureGuestAuth = 1)'
    }
}

Describe 'ServicesManual metadata' {
    It 'does not contain case-insensitive duplicate service names' {
        $serviceFunction = $script:systemTweaksAst.Find({
            param($node)
            ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and $node.Name -eq 'ServicesManual'
        }, $true)

        $serviceNames = @(
            [regex]::Matches($serviceFunction.Extent.Text, '@\{\s*Name\s*=\s*"([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value }
        )

        $duplicates = @(
            $serviceNames |
                Group-Object { $_.ToLowerInvariant() } |
                Where-Object Count -gt 1 |
                ForEach-Object Name
        )

        $duplicates | Should -BeNullOrEmpty
    }
}