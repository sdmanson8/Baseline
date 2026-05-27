Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $modulePath = Join-Path $PSScriptRoot '../../Module/GUIExecution.psm1'
    Import-Module $modulePath -Force

    $script:ExecutionContent = Get-BaselineTestSourceText -Path $modulePath
    $orchestrationPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration.ps1'
    $orchestrationSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration'
    $script:OrchestrationContent = Get-BaselineTestSourceText -Path @(
        $orchestrationPath
        (Join-Path $orchestrationSplitRoot 'ExecutionStateSummary.ps1')
        (Join-Path $orchestrationSplitRoot 'ExecutionView.ps1')
        (Join-Path $orchestrationSplitRoot 'ExecutionRunOrchestration.ps1')
    )
}

Describe 'Resolve-GuiExecutionAvailabilityGate' {
    It 'returns Allow when Availability is missing (back-compat for older entries)' {
        $entry = [pscustomobject]@{ Name = 'Foo'; Function = 'Foo' }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry
        $r.Decision | Should -Be 'Allow'
        $r.Reason | Should -Be ''
    }

    It 'returns Allow when Availability.Available is $true' {
        $entry = [pscustomobject]@{
            Name = 'Foo'; Function = 'Foo'
            Availability = [pscustomobject]@{ Available = $true; Reason = '' }
        }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry
        $r.Decision | Should -Be 'Allow'
    }

    It 'returns Block when Availability.Available is $false and ForceUnsupported is not set' {
        $entry = [pscustomobject]@{
            Name = 'OnlyOnWin11'; Function = 'OnlyOnWin11'
            Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows 10.' }
        }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry
        $r.Decision | Should -Be 'Block'
        $r.Reason | Should -Be 'Not available on Windows 10.'
    }

    It 'returns Force when Availability.Available is $false and ForceUnsupported is set' {
        $entry = [pscustomobject]@{
            Name = 'OnlyOnWin11'; Function = 'OnlyOnWin11'
            Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows 10.' }
        }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry -ForceUnsupported
        $r.Decision | Should -Be 'Force'
        $r.Reason | Should -Be 'Not available on Windows 10.'
    }

    It 'falls back to a generic reason when Availability.Reason is blank' {
        $entry = [pscustomobject]@{
            Name = 'NoReason'; Function = 'NoReason'
            Availability = [pscustomobject]@{ Available = $false; Reason = '' }
        }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry
        $r.Decision | Should -Be 'Block'
        $r.Reason | Should -Be 'Not available on this OS.'
    }

    It 'accepts a hashtable-style Availability block (IDictionary path)' {
        $entry = @{
            Name = 'HashEntry'
            Function = 'HashEntry'
            Availability = @{ Available = $false; Reason = 'Not available on Windows Server.' }
        }
        $r = Resolve-GuiExecutionAvailabilityGate -Entry $entry
        $r.Decision | Should -Be 'Block'
        $r.Reason | Should -Be 'Not available on Windows Server.'
    }

    It 'evaluates 2 available + 2 unavailable entries correctly without ForceUnsupported' {
        $entries = @(
            [pscustomobject]@{ Name = 'A1'; Function = 'A1'; Availability = [pscustomobject]@{ Available = $true;  Reason = '' } }
            [pscustomobject]@{ Name = 'A2'; Function = 'A2'; Availability = [pscustomobject]@{ Available = $true;  Reason = '' } }
            [pscustomobject]@{ Name = 'U1'; Function = 'U1'; Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows 10.' } }
            [pscustomobject]@{ Name = 'U2'; Function = 'U2'; Availability = [pscustomobject]@{ Available = $false; Reason = 'Requires Windows build 26100 or newer.' } }
        )
        $decisions = $entries | ForEach-Object { (Resolve-GuiExecutionAvailabilityGate -Entry $_).Decision }
        @($decisions) | Should -Be @('Allow', 'Allow', 'Block', 'Block')
    }

    It 'evaluates 2 available + 2 unavailable entries correctly with ForceUnsupported' {
        $entries = @(
            [pscustomobject]@{ Name = 'A1'; Function = 'A1'; Availability = [pscustomobject]@{ Available = $true;  Reason = '' } }
            [pscustomobject]@{ Name = 'A2'; Function = 'A2'; Availability = [pscustomobject]@{ Available = $true;  Reason = '' } }
            [pscustomobject]@{ Name = 'U1'; Function = 'U1'; Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows 10.' } }
            [pscustomobject]@{ Name = 'U2'; Function = 'U2'; Availability = [pscustomobject]@{ Available = $false; Reason = 'Requires Windows build 26100 or newer.' } }
        )
        $decisions = $entries | ForEach-Object { (Resolve-GuiExecutionAvailabilityGate -Entry $_ -ForceUnsupported).Decision }
        @($decisions) | Should -Be @('Allow', 'Allow', 'Force', 'Force')
    }
}

Describe 'Worker availability gate (Start-GuiExecutionWorker source-pattern checks)' {
    It 'declares the ForceUnsupported switch parameter on Start-GuiExecutionWorker' {
        $script:ExecutionContent | Should -Match '\[switch\]\$ForceUnsupported'
    }

    It 'plumbs ForceUnsupported through SessionStateProxy as bgForceUnsupported' {
        $script:ExecutionContent | Should -Match "SetVariable\('bgForceUnsupported'"
        $script:ExecutionContent | Should -Match '\[bool\]\$ForceUnsupported'
    }

    It 'invokes the gate before running the tweak function' {
        $script:ExecutionContent | Should -Match 'Resolve-GuiExecutionAvailabilityGate -Entry \$tweak -ForceUnsupported:\$bgForceUnsupported'
    }

    It 'enqueues a not-applicable _TweakCompleted entry when the gate blocks' {
        $script:ExecutionContent | Should -Match 'Skipped - not available on this system: \{0\} - \{1\}'
        $script:ExecutionContent | Should -Match "Status\s*=\s*'not applicable'"
    }

    It 'logs a warning when the gate forces an unavailable entry' {
        $script:ExecutionContent | Should -Match 'Forcing execution of unavailable entry: \{0\} - \{1\}'
    }

    It 'exports Resolve-GuiExecutionAvailabilityGate from the GUIExecution module' {
        $script:ExecutionContent | Should -Match "'Resolve-GuiExecutionAvailabilityGate'"
    }
}

Describe 'Start-GuiExecutionRun ForceUnsupported plumbing' {
    It 'declares the ForceUnsupported switch on the public entry point' {
        $script:OrchestrationContent | Should -Match '\[switch\]\$ForceUnsupported'
    }

    It 'forwards ForceUnsupported into the worker invocation' {
        $script:OrchestrationContent | Should -Match '-ForceUnsupported:\$ForceUnsupported'
    }
}

Describe 'GUIExecution worker tracing' {
    It 'routes worker trace writes through Write-Warning' {
        $script:ExecutionContent | Should -Match 'Write-Warning \("GUIExecution worker trace write failed: " \+ \$_.Exception.Message\)'
    }
}
