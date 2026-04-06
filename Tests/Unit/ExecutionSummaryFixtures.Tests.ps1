Set-StrictMode -Version Latest

BeforeAll {
    $Script:FixtureRoot = Join-Path $PSScriptRoot '../Fixtures/ExecutionSummary'

    $Script:RequiredFields = @(
        'Key', 'Order', 'Name', 'Function', 'Category', 'Risk',
        'Type', 'TypeKind', 'TypeLabel', 'TypeBadgeLabel', 'TypeTone',
        'Selection', 'ToggleParam', 'Restorable', 'RequiresRestart',
        'CurrentState', 'CurrentStateTone', 'StateDetail', 'MatchesDesired',
        'ScenarioTags', 'ReasonIncluded', 'BlastRadius', 'IsRemoval',
        'RecoveryLevel', 'GamingPreviewGroup', 'TroubleshootingOnly',
        'FromGameMode', 'GameModeProfile', 'GameModeOperation',
        'Impact', 'PresetTier',
        'OutcomeState', 'OutcomeReason', 'FailureCategory', 'FailureCode',
        'IsRecoverable', 'RetryAvailability', 'RetryReason', 'RecoveryHint',
        'Status', 'Detail'
    )

    $Script:ValidStatuses = @(
        'Pending', 'Running', 'Success', 'Failed',
        'Skipped', 'NotApplicable', 'NotRun'
    )

    function Load-Fixture {
        param ([string]$Name)
        $path = Join-Path $Script:FixtureRoot "$Name.json"
        Get-Content -Path $path -Raw | ConvertFrom-Json
    }
}

Describe 'Fixture schema validation' {
    BeforeAll {
        $Script:AllFixtures = @(
            @{ Name = 'CleanSuccess' }
            @{ Name = 'PartialFailure' }
            @{ Name = 'RestoreDefaults' }
            @{ Name = 'GameModeRun' }
            @{ Name = 'RetryableFailure' }
        )
    }

    It '<Name>.json is valid JSON and loads as an array' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name

        $records | Should -Not -BeNullOrEmpty
        @($records).Count | Should -BeGreaterThan 0
    }

    It '<Name>.json records contain all required fields' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name

        foreach ($record in @($records)) {
            foreach ($field in $Script:RequiredFields) {
                $record.PSObject.Properties.Name | Should -Contain $field -Because "record '$($record.Key)' should have field '$field'"
            }
        }
    }

    It '<Name>.json records have Status in the valid set' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name

        foreach ($record in @($records)) {
            $Script:ValidStatuses | Should -Contain $record.Status -Because "record '$($record.Key)' Status '$($record.Status)' should be a valid status"
        }
    }

    It '<Name>.json records have sequential Order values starting at 1' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name

        $orders = @($records) | ForEach-Object { $_.Order }
        $expected = 1..(@($records).Count)
        $orders | Should -Be $expected
    }

    It '<Name>.json Failed records have non-empty FailureCategory' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name
        $failed = @($records) | Where-Object { $_.Status -eq 'Failed' }

        foreach ($record in @($failed)) {
            $record.FailureCategory | Should -Not -BeNullOrEmpty -Because "failed record '$($record.Key)' must have a FailureCategory"
            $record.FailureCode | Should -Not -BeNullOrEmpty -Because "failed record '$($record.Key)' must have a FailureCode"
        }
    }

    It '<Name>.json Success records have null FailureCategory' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name
        $succeeded = @($records) | Where-Object { $_.Status -eq 'Success' }

        foreach ($record in @($succeeded)) {
            $record.FailureCategory | Should -BeNullOrEmpty -Because "success record '$($record.Key)' should not have a FailureCategory"
            $record.FailureCode | Should -BeNullOrEmpty -Because "success record '$($record.Key)' should not have a FailureCode"
        }
    }

    It '<Name>.json records with IsRecoverable=true have RetryAvailability set' -ForEach @(
        @{ Name = 'CleanSuccess' }
        @{ Name = 'PartialFailure' }
        @{ Name = 'RestoreDefaults' }
        @{ Name = 'GameModeRun' }
        @{ Name = 'RetryableFailure' }
    ) {
        $records = Load-Fixture -Name $Name
        $recoverable = @($records) | Where-Object { $_.IsRecoverable -eq $true }

        foreach ($record in @($recoverable)) {
            $record.RetryAvailability | Should -Not -BeNullOrEmpty -Because "recoverable record '$($record.Key)' must have RetryAvailability"
        }
    }
}

Describe 'CleanSuccess fixture invariants' {
    BeforeAll {
        $Script:CleanRecords = Load-Fixture -Name 'CleanSuccess'
    }

    It 'contains exactly 10 records' {
        @($Script:CleanRecords).Count | Should -Be 10
    }

    It 'every record has Status=Success' {
        foreach ($record in @($Script:CleanRecords)) {
            $record.Status | Should -Be 'Success' -Because "CleanSuccess record '$($record.Key)' should be Success"
        }
    }

    It 'includes Toggle, Choice, and Action type records' {
        $types = @($Script:CleanRecords) | ForEach-Object { $_.Type } | Sort-Object -Unique
        $types | Should -Contain 'Toggle'
        $types | Should -Contain 'Choice'
        $types | Should -Contain 'Action'
    }

    It 'spans multiple categories' {
        $categories = @($Script:CleanRecords) | ForEach-Object { $_.Category } | Sort-Object -Unique
        $categories.Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'PartialFailure fixture invariants' {
    BeforeAll {
        $Script:PartialRecords = Load-Fixture -Name 'PartialFailure'
    }

    It 'contains exactly 10 records' {
        @($Script:PartialRecords).Count | Should -Be 10
    }

    It 'has exactly 6 Success records' {
        $count = @(@($Script:PartialRecords) | Where-Object { $_.Status -eq 'Success' }).Count
        $count | Should -Be 6
    }

    It 'has exactly 2 Failed records' {
        $count = @(@($Script:PartialRecords) | Where-Object { $_.Status -eq 'Failed' }).Count
        $count | Should -Be 2
    }

    It 'has exactly 1 Skipped record' {
        $count = @(@($Script:PartialRecords) | Where-Object { $_.Status -eq 'Skipped' }).Count
        $count | Should -Be 1
    }

    It 'has exactly 1 NotApplicable record' {
        $count = @(@($Script:PartialRecords) | Where-Object { $_.Status -eq 'NotApplicable' }).Count
        $count | Should -Be 1
    }

    It 'contains an access-denied failure' {
        $accessDenied = @($Script:PartialRecords) | Where-Object { $_.FailureCode -eq 'access_denied' }
        @($accessDenied).Count | Should -Be 1
    }

    It 'contains a missing-dependency failure' {
        $dep = @($Script:PartialRecords) | Where-Object { $_.FailureCode -eq 'missing_dependency' }
        @($dep).Count | Should -Be 1
    }
}

Describe 'RestoreDefaults fixture invariants' {
    BeforeAll {
        $Script:RestoreRecords = Load-Fixture -Name 'RestoreDefaults'
    }

    It 'contains exactly 8 records' {
        @($Script:RestoreRecords).Count | Should -Be 8
    }

    It 'every record has Status=Success' {
        foreach ($record in @($Script:RestoreRecords)) {
            $record.Status | Should -Be 'Success' -Because "RestoreDefaults record '$($record.Key)' should be Success"
        }
    }

    It 'every record has restore-specific OutcomeReason wording' {
        foreach ($record in @($Script:RestoreRecords)) {
            $record.OutcomeReason | Should -BeLike '*Restored to Windows default*' -Because "RestoreDefaults record '$($record.Key)' should use restore wording"
        }
    }
}

Describe 'GameModeRun fixture invariants' {
    BeforeAll {
        $Script:GameModeRecords = Load-Fixture -Name 'GameModeRun'
    }

    It 'contains exactly 5 records' {
        @($Script:GameModeRecords).Count | Should -Be 5
    }

    It 'every record has FromGameMode=true' {
        foreach ($record in @($Script:GameModeRecords)) {
            $record.FromGameMode | Should -Be $true -Because "GameModeRun record '$($record.Key)' should have FromGameMode"
        }
    }

    It 'every record has GameModeProfile=Competitive' {
        foreach ($record in @($Script:GameModeRecords)) {
            $record.GameModeProfile | Should -Be 'Competitive' -Because "GameModeRun record '$($record.Key)' should have Competitive profile"
        }
    }

    It 'every record Key starts with gamemode:: prefix' {
        foreach ($record in @($Script:GameModeRecords)) {
            $record.Key | Should -BeLike 'gamemode::*' -Because "GameModeRun record Key should use gamemode:: prefix"
        }
    }

    It 'contains a mix of Success and non-Success outcomes' {
        $statuses = @($Script:GameModeRecords) | ForEach-Object { $_.Status } | Sort-Object -Unique
        $statuses | Should -Contain 'Success'
        $statuses.Count | Should -BeGreaterThan 1
    }
}

Describe 'RetryableFailure fixture invariants' {
    BeforeAll {
        $Script:RetryRecords = Load-Fixture -Name 'RetryableFailure'
    }

    It 'contains exactly 8 records' {
        @($Script:RetryRecords).Count | Should -Be 8
    }

    It 'has exactly 4 Success records' {
        $count = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Success' }).Count
        $count | Should -Be 4
    }

    It 'has exactly 4 Failed records' {
        $count = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Failed' }).Count
        $count | Should -Be 4
    }

    It 'has exactly 2 recoverable Failed records' {
        $recoverable = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Failed' -and $_.IsRecoverable -eq $true })
        $recoverable.Count | Should -Be 2
    }

    It 'has exactly 2 non-recoverable Failed records' {
        $nonRecoverable = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Failed' -and $_.IsRecoverable -eq $false })
        $nonRecoverable.Count | Should -Be 2
    }

    It 'recoverable records have RetryAvailability set' {
        $recoverable = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Failed' -and $_.IsRecoverable -eq $true })

        foreach ($record in $recoverable) {
            $record.RetryAvailability | Should -Not -BeNullOrEmpty -Because "recoverable record '$($record.Key)' must have RetryAvailability"
            $record.RetryReason | Should -Not -BeNullOrEmpty -Because "recoverable record '$($record.Key)' must have RetryReason"
        }
    }

    It 'non-recoverable records have null RetryAvailability' {
        $nonRecoverable = @(@($Script:RetryRecords) | Where-Object { $_.Status -eq 'Failed' -and $_.IsRecoverable -eq $false })

        foreach ($record in $nonRecoverable) {
            $record.RetryAvailability | Should -BeNullOrEmpty -Because "non-recoverable record '$($record.Key)' should not have RetryAvailability"
        }
    }
}
