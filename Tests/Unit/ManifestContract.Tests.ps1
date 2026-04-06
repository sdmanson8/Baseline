Set-StrictMode -Version Latest

# Populate manifest entries at script scope before Pester discovery so that
# -ForEach data-driven tests can reference $script:ManifestEntries.
# Must use @{} hashtables (not [PSCustomObject]) so Pester v5 unpacks
# properties into test-scoped variables correctly.
$script:ManifestEntries = & {
    $dataDir = Join-Path $PSScriptRoot '../../Module/Data'
    foreach ($jsonFile in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' -File | Sort-Object Name)) {
        $payload = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not $payload.PSObject.Properties['Entries']) { continue }
        foreach ($entry in @($payload.Entries)) {
            if (-not $entry) { continue }
            @{
                FileName  = $jsonFile.Name
                Name      = [string]$entry.Name
                Function  = [string]$entry.Function
                Entry     = $entry
            }
        }
    }
}

BeforeAll {
    $script:ValidRiskValues = @('Low', 'Medium', 'High')
    $script:ValidRecoveryLevels = @('Direct', 'DefaultsOnly', 'RestorePoint', 'Manual')
    $script:ValidImpactValues = @('Low', 'Medium', 'High')
    $script:ValidTypeValues = @('Toggle', 'Choice', 'Action')
    $script:RequiredGuiFields = @('Name', 'Function', 'Type', 'Risk', 'Impact', 'Safe', 'RequiresRestart', 'Restorable', 'RecoveryLevel', 'WhyThisMatters', 'Tags')
}

Describe 'Manifest-to-UI contract' {
    Describe 'High-risk entries must have CautionReason' {
        It '<FileName> :: <Name> (Risk=High) has non-empty CautionReason' -ForEach @(
            $script:ManifestEntries | Where-Object { [string]$_.Entry.Risk -eq 'High' }
        ) {
            $value = $Entry.CautionReason
            $value | Should -Not -BeNullOrEmpty -Because "'$Name' in $FileName has Risk=High and must explain why via CautionReason"
            [string]::IsNullOrWhiteSpace([string]$value) | Should -Be $false -Because "'$Name' in $FileName CautionReason must not be whitespace-only"
        }
    }

    Describe 'Manual recovery entries must have WhyThisMatters' {
        It '<FileName> :: <Name> (RecoveryLevel=Manual) has non-empty WhyThisMatters' -ForEach @(
            $script:ManifestEntries | Where-Object { [string]$_.Entry.RecoveryLevel -eq 'Manual' }
        ) {
            $value = $Entry.WhyThisMatters
            $value | Should -Not -BeNullOrEmpty -Because "'$Name' in $FileName has RecoveryLevel=Manual and must provide recovery guidance via WhyThisMatters"
            [string]::IsNullOrWhiteSpace([string]$value) | Should -Be $false -Because "'$Name' in $FileName WhyThisMatters must not be whitespace-only"
        }
    }

    Describe 'Action and removal entries must have WhyThisMatters' {
        It '<FileName> :: <Name> (action/removal) has non-empty WhyThisMatters' -ForEach @(
            $script:ManifestEntries | Where-Object {
                [string]$_.Entry.Type -eq 'Action' -or
                [string]$_.Entry.Function -match '(?i)(Uninstall|Remove)'
            }
        ) {
            $value = $Entry.WhyThisMatters
            $value | Should -Not -BeNullOrEmpty -Because "'$Name' in $FileName is an action or removal entry and must provide preview language via WhyThisMatters"
            [string]::IsNullOrWhiteSpace([string]$value) | Should -Be $false -Because "'$Name' in $FileName WhyThisMatters must not be whitespace-only"
        }
    }

    Describe 'Required GUI display fields' {
        It '<FileName> :: <Name> has all required GUI fields' -ForEach @(
            $script:ManifestEntries
        ) {
            foreach ($field in $script:RequiredGuiFields) {
                $Entry.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty -Because "'$Name' in $FileName is missing required GUI field '$field'"
            }
        }
    }

    Describe 'Risk value validation' {
        It '<FileName> :: <Name> has a valid Risk value' -ForEach @(
            $script:ManifestEntries
        ) {
            $risk = [string]$Entry.Risk
            $risk | Should -BeIn $script:ValidRiskValues -Because "'$Name' in $FileName has Risk='$risk' which is not one of: $($script:ValidRiskValues -join ', ')"
        }
    }

    Describe 'RecoveryLevel value validation' {
        It '<FileName> :: <Name> has a valid RecoveryLevel value' -ForEach @(
            $script:ManifestEntries
        ) {
            $level = [string]$Entry.RecoveryLevel
            $level | Should -BeIn $script:ValidRecoveryLevels -Because "'$Name' in $FileName has RecoveryLevel='$level' which is not one of: $($script:ValidRecoveryLevels -join ', ')"
        }
    }

    Describe 'Impact value validation' {
        It '<FileName> :: <Name> has a valid Impact value' -ForEach @(
            $script:ManifestEntries
        ) {
            $impact = [string]$Entry.Impact
            $impact | Should -BeIn $script:ValidImpactValues -Because "'$Name' in $FileName has Impact='$impact' which is not one of: $($script:ValidImpactValues -join ', ')"
        }
    }

    Describe 'Type value validation' {
        It '<FileName> :: <Name> has a valid Type value' -ForEach @(
            $script:ManifestEntries
        ) {
            $type = [string]$Entry.Type
            $type | Should -BeIn $script:ValidTypeValues -Because "'$Name' in $FileName has Type='$type' which is not one of: $($script:ValidTypeValues -join ', ')"
        }
    }
}
