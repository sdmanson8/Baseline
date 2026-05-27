Set-StrictMode -Version Latest

BeforeAll {
    $settingsStorePath = Join-Path $PSScriptRoot '../../Module/GUICommon/SettingsStore.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($settingsStorePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Set-GuiSettingsStoreUnavailable', 'Get-GuiSettingsStoreStatus', 'Get-GuiSettingsProfileDirectory')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'GUI settings store availability' {
    BeforeEach {
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        $script:previousStateRoot = [System.Environment]::GetEnvironmentVariable('BASELINE_STATE_ROOT')
        Remove-Variable -Name GuiSettingsStoreStatus -Scope Script -ErrorAction SilentlyContinue
    }

    AfterEach {
        [System.Environment]::SetEnvironmentVariable('BASELINE_STATE_ROOT', $script:previousStateRoot, [System.EnvironmentVariableTarget]::Process)
        Remove-Variable -Name GuiSettingsStoreStatus -Scope Script -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'logs and exposes unavailable state when profile directory creation fails' {
        $stateRoot = Join-Path $TestDrive 'state-root'
        $expectedProfilePath = Join-Path $stateRoot 'Profiles'
        [System.Environment]::SetEnvironmentVariable('BASELINE_STATE_ROOT', $stateRoot, [System.EnvironmentVariableTarget]::Process)
        Mock -CommandName New-Item -MockWith { throw 'profile directory creation blocked' } -ParameterFilter {
            [string]$Path -eq $expectedProfilePath
        }

        $path = Get-GuiSettingsProfileDirectory
        $status = Get-GuiSettingsStoreStatus

        Should -Invoke -CommandName New-Item -Times 1 -Exactly
        $path | Should -Be $expectedProfilePath
        $status.Available | Should -BeFalse
        $status.Path | Should -Be $path
        $status.Message | Should -Not -BeNullOrEmpty
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'GUI settings store unavailable'
    }
}
