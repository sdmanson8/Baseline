Set-StrictMode -Version Latest

# NOTE: Tests in the Get-ScenarioProfilePlan and Get-ScenarioProfileCommandList
# Describe blocks depend on the live production manifest (via Import-TweakManifestFromData).
# They guard with `if ($manifest.Count -lt 10) { Set-ItResult -Skipped }` so they
# degrade gracefully in CI or environments where data files are absent. If these
# tests start failing, check that the manifest JSON files are intact.
BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-ScenarioProfileDefinitions' {
    It 'returns at least 3 profiles' {
        $profiles = Get-ScenarioProfileDefinitions

        $profiles.Count | Should -BeGreaterOrEqual 3
    }

    It 'includes Workstation, Privacy, and Recovery profiles' {
        $profiles = Get-ScenarioProfileDefinitions
        $names = @($profiles | ForEach-Object { $_.Name })

        $names | Should -Contain 'Workstation'
        $names | Should -Contain 'Privacy'
        $names | Should -Contain 'Recovery'
    }

    It 'each profile has Name, Label, Summary, and Functions' {
        $profiles = Get-ScenarioProfileDefinitions

        foreach ($profile in $profiles) {
            $profile.Name | Should -Not -BeNullOrEmpty
            $profile.Label | Should -Not -BeNullOrEmpty
            $profile.Summary | Should -Not -BeNullOrEmpty
            $profile.Functions | Should -Not -BeNullOrEmpty
            $profile.Functions.Count | Should -BeGreaterThan 0
        }
    }

    It 'profiles have no duplicate function names' {
        $profiles = Get-ScenarioProfileDefinitions

        foreach ($profile in $profiles) {
            $unique = @($profile.Functions | Select-Object -Unique)
            $unique.Count | Should -Be $profile.Functions.Count -Because "profile '$($profile.Name)' should have no duplicate functions"
        }
    }
}

Describe 'Get-ScenarioProfilePlan' {
    It 'returns empty array for empty manifest' {
        $plan = @(Get-ScenarioProfilePlan -Manifest @() -ProfileName 'Workstation')

        $plan.Count | Should -Be 0
    }

    It 'builds a non-empty plan when manifest has matching entries' {
        $manifest = @(Import-TweakManifestFromData)
        if ($manifest.Count -lt 10) { Set-ItResult -Skipped -Because 'Manifest did not load fully on this platform' ; return }

        $plan = @(Get-ScenarioProfilePlan -Manifest $manifest -ProfileName 'Workstation')

        $plan.Count | Should -BeGreaterThan 0
    }

    It 'each plan entry has required fields' {
        $manifest = @(Import-TweakManifestFromData)
        if ($manifest.Count -lt 10) { Set-ItResult -Skipped -Because 'Manifest did not load fully on this platform' ; return }

        $plan = @(Get-ScenarioProfilePlan -Manifest $manifest -ProfileName 'Privacy')
        if ($plan.Count -eq 0) { Set-ItResult -Skipped -Because 'No plan entries on this platform' ; return }

        foreach ($entry in $plan) {
            $entry.Function | Should -Not -BeNullOrEmpty
            $entry.Name | Should -Not -BeNullOrEmpty
            $entry.Profile | Should -Be 'Privacy'
            $entry.Command | Should -Not -BeNullOrEmpty
            $entry.ReasonIncluded | Should -Not -BeNullOrEmpty
        }
    }

    It 'produces no duplicate functions in a plan' {
        $manifest = @(Import-TweakManifestFromData)
        if ($manifest.Count -lt 10) { Set-ItResult -Skipped -Because 'Manifest did not load fully on this platform' ; return }

        $plan = @(Get-ScenarioProfilePlan -Manifest $manifest -ProfileName 'Recovery')
        if ($plan.Count -eq 0) { Set-ItResult -Skipped -Because 'No plan entries on this platform' ; return }
        $functions = @($plan | ForEach-Object { $_.Function })
        $unique = @($functions | Select-Object -Unique)

        $unique.Count | Should -Be $functions.Count
    }
}

Describe 'Get-ScenarioProfileCommandList' {
    It 'returns command strings for a valid profile' {
        $manifest = @(Import-TweakManifestFromData)
        if ($manifest.Count -lt 10) { Set-ItResult -Skipped -Because 'Manifest did not load fully on this platform' ; return }

        $commands = @(Get-ScenarioProfileCommandList -Manifest $manifest -ProfileName 'Workstation')

        $commands.Count | Should -BeGreaterThan 0
        foreach ($cmd in $commands) {
            $cmd | Should -Not -BeNullOrEmpty
            $cmd | Should -BeOfType [string]
        }
    }
}
