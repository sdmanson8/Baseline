Set-StrictMode -Version Latest

# Tracked issues #12 / #586 — guard against the Settings app's "..." → Uninstall flow
# silently breaking after Baseline runs. The reported root cause is a
# critical service or AppX dependency being set to Disabled. This suite pins
# the safe state (Manual or higher) for the services Microsoft Settings/AppX
# tooling depends on so a future preset edit can't reintroduce the regression.

BeforeAll {
    $script:protectedServices = @(
        'InstallService',
        'AppXSvc',
        'StateRepository',
        'ClipSVC',
        'LicenseManager'
    )

    $script:hardwarePowerPath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.HardwarePower.psm1'
    $script:hardwarePowerAst = [System.Management.Automation.Language.Parser]::ParseFile($script:hardwarePowerPath, [ref]$null, [ref]$null)

    function Get-ServicesManualHashtables {
        param([System.Management.Automation.Language.Ast]$RootAst)

        $fn = $RootAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'ServicesManual'
        }, $true) | Select-Object -First 1

        if (-not $fn) { return @() }

        $tables = $fn.Body.FindAll({
            param($node) $node -is [System.Management.Automation.Language.HashtableAst]
        }, $true)

        $result = @()
        foreach ($table in $tables) {
            $kv = @{}
            foreach ($pair in $table.KeyValuePairs) {
                $key = [string]$pair.Item1.SafeGetValue()
                $value = $null
                $stmt = $pair.Item2
                if ($stmt -is [System.Management.Automation.Language.PipelineAst] -and $stmt.PipelineElements.Count -eq 1) {
                    $expr = $stmt.PipelineElements[0]
                    if ($expr -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        try { $value = $expr.Expression.SafeGetValue() } catch { $value = $null }
                    }
                }
                $kv[$key] = $value
            }
            if ($kv.ContainsKey('Name')) { $result += [pscustomobject]$kv }
        }
        return $result
    }
}

Describe 'Settings-app dependent services' {
    It 'parses the ServicesManual hashtable list' {
        $services = Get-ServicesManualHashtables -RootAst $script:hardwarePowerAst
        $services.Count | Should -BeGreaterThan 50
    }

    It 'never sets InstallService to Disabled in ServicesManual' {
        $services = Get-ServicesManualHashtables -RootAst $script:hardwarePowerAst
        $entry = @($services | Where-Object { $_.Name -eq 'InstallService' })
        $entry.Count | Should -Be 1
        $entry[0].StartupType | Should -Not -Be 'Disabled'
    }

    It 'never sets LicenseManager to Disabled in ServicesManual' {
        $services = Get-ServicesManualHashtables -RootAst $script:hardwarePowerAst
        $entry = @($services | Where-Object { $_.Name -eq 'LicenseManager' })
        $entry.Count | Should -Be 1
        $entry[0].StartupType | Should -Not -Be 'Disabled'
    }

    It 'never disables any of the protected Settings/AppX dependencies in the services table' {
        $services = Get-ServicesManualHashtables -RootAst $script:hardwarePowerAst
        $violations = @($services | Where-Object {
            $script:protectedServices -contains $_.Name -and $_.StartupType -eq 'Disabled'
        } | ForEach-Object { "{0} -> {1}" -f $_.Name, $_.StartupType })

        $violations.Count | Should -Be 0 -Because (
            "Tracked issue #586: setting any of [{0}] to Disabled silently breaks the Settings app's Uninstall flow. Violations: {1}" -f
            ($script:protectedServices -join ', '),
            ($violations -join '; ')
        )
    }
}

Describe 'Preset bundles do not disable protected services' {
    BeforeAll {
        $script:presetDir = Join-Path $PSScriptRoot '../../Module/Data/Presets'
        $script:presetFiles = @(Get-ChildItem -LiteralPath $script:presetDir -Filter '*.json' -ErrorAction SilentlyContinue)
    }

    It 'finds at least one preset file' {
        $script:presetFiles.Count | Should -BeGreaterThan 0
    }

    It 'no preset references a protected service name with a -Disable parameter' {
        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $script:presetFiles) {
            $raw = Get-Content -Raw -LiteralPath $file.FullName
            $preset = $null
            try { $preset = $raw | ConvertFrom-Json } catch { $preset = $null }
            if ($null -eq $preset) { continue }
            if (-not $preset.PSObject.Properties['Entries']) { continue }
            foreach ($entry in @($preset.Entries)) {
                $token = [string]$entry
                foreach ($svc in $script:protectedServices) {
                    $pattern = '\b' + [regex]::Escape($svc) + '\b'
                    if (($token -match $pattern) -and ($token -match '-Disable\b')) {
                        [void]$violations.Add(("{0}: {1}" -f $file.Name, $token))
                    }
                }
            }
        }
        $violations.Count | Should -Be 0
    }
}
