Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/ConfigReview.Helpers.ps1'
    . $filePath

    function script:NewEntry {
        param(
            [Parameter(Mandatory)][string]$Function,
            [string]$Type = 'Toggle',
            [string]$Param,
            [object]$Value,
            [string]$GatedBy
        )
        $h = [ordered]@{ Function = $Function; Type = $Type }
        if ($PSBoundParameters.ContainsKey('Param'))   { $h.Param = $Param }
        if ($PSBoundParameters.ContainsKey('Value'))   { $h.Value = $Value }
        if ($PSBoundParameters.ContainsKey('GatedBy')) { $h.GatedBy = $GatedBy }
        return [pscustomobject]$h
    }

    function script:NewProfile {
        param([AllowEmptyCollection()][object[]]$Entries = @())
        return [pscustomobject]@{ Entries = @($Entries) }
    }
}

Describe 'ConvertTo-BaselineReviewEntryKey' {
    It 'returns Id when present' {
        ConvertTo-BaselineReviewEntryKey -Entry ([pscustomobject]@{ Id = 'X1'; Function = 'Foo' }) | Should -Be 'X1'
    }

    It 'falls back to Function when Id is missing' {
        ConvertTo-BaselineReviewEntryKey -Entry ([pscustomobject]@{ Function = 'Foo' }) | Should -Be 'Foo'
    }

    It 'falls back to Name when Id and Function are missing' {
        ConvertTo-BaselineReviewEntryKey -Entry ([pscustomobject]@{ Name = 'Bar' }) | Should -Be 'Bar'
    }

    It 'returns empty string when nothing is identifying' {
        ConvertTo-BaselineReviewEntryKey -Entry ([pscustomobject]@{ Other = 'baz' }) | Should -Be ''
    }

    It 'tolerates a $null entry' {
        ConvertTo-BaselineReviewEntryKey -Entry $null | Should -Be ''
    }
}

Describe 'ConvertTo-BaselineReviewValueText' {
    It 'returns Param for a Toggle entry' {
        ConvertTo-BaselineReviewValueText -Entry (NewEntry -Function F -Param '-Disable') | Should -Be '-Disable'
    }

    It 'returns Value for a Choice entry' {
        ConvertTo-BaselineReviewValueText -Entry (NewEntry -Function F -Type Choice -Value 'High') | Should -Be 'High'
    }

    It 'collapses AC=DC into a single value' {
        $e = [pscustomobject]@{ Function = 'F'; ACValue = '60'; DCValue = '60' }
        ConvertTo-BaselineReviewValueText -Entry $e | Should -Be '60'
    }

    It 'splits AC and DC when they differ' {
        $e = [pscustomobject]@{ Function = 'F'; ACValue = '60'; DCValue = '15' }
        ConvertTo-BaselineReviewValueText -Entry $e | Should -Be 'AC:60;DC:15'
    }

    It 'returns empty string for $null' {
        ConvertTo-BaselineReviewValueText -Entry $null | Should -Be ''
    }
}

Describe 'Compare-BaselineConfigForReview' {
    It 'returns an empty array when both inputs are empty' {
        $r = Compare-BaselineConfigForReview -Current (NewProfile -Entries @()) -Imported (NewProfile -Entries @())
        @($r).Count | Should -Be 0
    }

    It 'classifies an entry only in Imported as Add' {
        $r = Compare-BaselineConfigForReview `
            -Current (NewProfile -Entries @()) `
            -Imported (NewProfile -Entries @((NewEntry -Function F1 -Param '-Disable')))
        @($r).Count | Should -Be 1
        $r[0].Action | Should -Be 'Add'
        $r[0].ImportedValue | Should -Be '-Disable'
        $r[0].CurrentValue  | Should -Be ''
    }

    It 'classifies an entry only in Current as Remove' {
        $r = Compare-BaselineConfigForReview `
            -Current (NewProfile -Entries @((NewEntry -Function F1 -Param '-Disable'))) `
            -Imported (NewProfile -Entries @())
        @($r).Count | Should -Be 1
        $r[0].Action | Should -Be 'Remove'
        $r[0].CurrentValue  | Should -Be '-Disable'
        $r[0].ImportedValue | Should -Be ''
    }

    It 'classifies entries with the same value as Same' {
        $r = Compare-BaselineConfigForReview `
            -Current (NewProfile -Entries @((NewEntry -Function F1 -Param '-Disable'))) `
            -Imported (NewProfile -Entries @((NewEntry -Function F1 -Param '-Disable')))
        @($r).Count | Should -Be 1
        $r[0].Action | Should -Be 'Same'
    }

    It 'classifies entries with different values as Change' {
        $r = Compare-BaselineConfigForReview `
            -Current (NewProfile -Entries @((NewEntry -Function F1 -Param '-Disable'))) `
            -Imported (NewProfile -Entries @((NewEntry -Function F1 -Param '-Enable')))
        @($r).Count | Should -Be 1
        $r[0].Action | Should -Be 'Change'
        $r[0].CurrentValue  | Should -Be '-Disable'
        $r[0].ImportedValue | Should -Be '-Enable'
    }

    It 'preserves Imported declared order, then appends Current-only entries' {
        $current = NewProfile -Entries @(
            (NewEntry -Function 'A' -Param '-X'),
            (NewEntry -Function 'B' -Param '-X'),
            (NewEntry -Function 'C' -Param '-X')
        )
        $imported = NewProfile -Entries @(
            (NewEntry -Function 'B' -Param '-X'),
            (NewEntry -Function 'D' -Param '-X')
        )
        $r = Compare-BaselineConfigForReview -Current $current -Imported $imported
        @($r).Count | Should -Be 4
        $r[0].Function | Should -Be 'B'
        $r[1].Function | Should -Be 'D'
        $r[2].Function | Should -Be 'A'
        $r[3].Function | Should -Be 'C'
        $r[0].Action | Should -Be 'Same'
        $r[1].Action | Should -Be 'Add'
        $r[2].Action | Should -Be 'Remove'
        $r[3].Action | Should -Be 'Remove'
    }

    It 'echoes GatedBy from the imported entry without disabling the row (review trap)' {
        $imported = NewProfile -Entries @(
            (NewEntry -Function 'F1' -Param '-Enable' -GatedBy 'ParentToggle')
        )
        $r = Compare-BaselineConfigForReview -Current (NewProfile -Entries @()) -Imported $imported
        $r[0].GatedBy | Should -Be 'ParentToggle'
        $r[0].Action  | Should -Be 'Add'
    }

    It 'accepts a bare array (not wrapped in {Entries=...}) for Current and Imported' {
        $r = Compare-BaselineConfigForReview `
            -Current @((NewEntry -Function F1 -Param '-A')) `
            -Imported @((NewEntry -Function F1 -Param '-B'))
        @($r).Count | Should -Be 1
        $r[0].Action | Should -Be 'Change'
    }

    It 'tolerates $null on either side' {
        $r1 = Compare-BaselineConfigForReview -Current $null -Imported (NewProfile -Entries @((NewEntry -Function F1 -Param '-A')))
        @($r1).Count | Should -Be 1
        $r1[0].Action | Should -Be 'Add'
        $r2 = Compare-BaselineConfigForReview -Current (NewProfile -Entries @((NewEntry -Function F1 -Param '-A'))) -Imported $null
        @($r2).Count | Should -Be 1
        $r2[0].Action | Should -Be 'Remove'
    }
}

Describe 'Get-BaselineConfigReviewSummary' {
    It 'returns zero counts for an empty / null diff' {
        $s = Get-BaselineConfigReviewSummary -Diff @()
        $s.Total | Should -Be 0
        $s.Add | Should -Be 0
        $s.Actionable | Should -Be 0
        $s2 = Get-BaselineConfigReviewSummary -Diff $null
        $s2.Total | Should -Be 0
    }

    It 'sums Add / Remove / Change / Same and computes Actionable' {
        $diff = @(
            [pscustomobject]@{ Id = 'a'; Action = 'Add' },
            [pscustomobject]@{ Id = 'b'; Action = 'Add' },
            [pscustomobject]@{ Id = 'c'; Action = 'Remove' },
            [pscustomobject]@{ Id = 'd'; Action = 'Change' },
            [pscustomobject]@{ Id = 'e'; Action = 'Change' },
            [pscustomobject]@{ Id = 'f'; Action = 'Same' }
        )
        $s = Get-BaselineConfigReviewSummary -Diff $diff
        $s.Total      | Should -Be 6
        $s.Add        | Should -Be 2
        $s.Remove     | Should -Be 1
        $s.Change     | Should -Be 2
        $s.Same       | Should -Be 1
        $s.Actionable | Should -Be 5
    }
}

Describe 'Resolve-BaselineConfigReviewDecisions' {
    BeforeAll {
        $script:diff = @(
            [pscustomobject]@{ Id = 'a'; Function = 'a'; Action = 'Add';    ImportedEntry = [pscustomobject]@{ Function = 'a'; Param = '-A' } },
            [pscustomobject]@{ Id = 'b'; Function = 'b'; Action = 'Change'; ImportedEntry = [pscustomobject]@{ Function = 'b'; Param = '-B' } },
            [pscustomobject]@{ Id = 'c'; Function = 'c'; Action = 'Remove'; ImportedEntry = $null },
            [pscustomobject]@{ Id = 'd'; Function = 'd'; Action = 'Same';   ImportedEntry = [pscustomobject]@{ Function = 'd'; Param = '-D' } }
        )
    }

    It 'rejects everything by default (DefaultDecision=Reject) and skips Same rows' {
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions @{}
        $r.Accepted.Count | Should -Be 0
        $r.Rejected | Should -Contain 'a'
        $r.Rejected | Should -Contain 'b'
        $r.Rejected | Should -Contain 'c'
        $r.Skipped  | Should -Contain 'd'
        $r.Skipped.Count | Should -Be 1
    }

    It 'accepts everything when DefaultDecision=Accept (still skips Same)' {
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions @{} -DefaultDecision 'Accept'
        $r.Accepted.Count | Should -Be 3
        $r.Skipped  | Should -Contain 'd'
    }

    It 'accepts only the rows the user accepted (per-id override beats default)' {
        $decisions = @{
            'a' = 'Accept'
            'b' = 'Reject'
            'c' = 'Accept'
        }
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions $decisions
        $r.Accepted.Count | Should -Be 2
        @($r.Accepted | Where-Object { $_.Function -eq 'a' }).Count | Should -Be 1
        @($r.Accepted | Where-Object { $_.Function -eq 'c' }).Count | Should -Be 1
        $r.Rejected | Should -Contain 'b'
    }

    It 'accepts decisions supplied as an array of {Id; Decision} records' {
        $decisions = @(
            [pscustomobject]@{ Id = 'a'; Decision = 'Accept' }
            [pscustomobject]@{ Id = 'b'; Decision = 'Accept' }
        )
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions $decisions
        $r.Accepted.Count | Should -Be 2
    }

    It 'preserves diff order in the Accepted output' {
        $decisions = @{ 'a' = 'Accept'; 'b' = 'Accept'; 'c' = 'Accept' }
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions $decisions
        $r.Accepted[0].Function | Should -Be 'a'
        $r.Accepted[1].Function | Should -Be 'b'
        $r.Accepted[2].Function | Should -Be 'c'
    }

    It 'emits a synthetic Remove entry when an accepted Remove row had no ImportedEntry' {
        $decisions = @{ 'c' = 'Accept' }
        $r = Resolve-BaselineConfigReviewDecisions -Diff $script:diff -Decisions $decisions
        $r.Accepted.Count | Should -Be 1
        $r.Accepted[0].Function | Should -Be 'c'
        $r.Accepted[0].Action   | Should -Be 'Remove'
    }
}
