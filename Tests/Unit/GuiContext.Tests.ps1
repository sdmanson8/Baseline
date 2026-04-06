Set-StrictMode -Version Latest

BeforeAll {
    # Extract functions from GuiContext.ps1 via AST - safe because ParseFile
    # only parses (no execution) and we only evaluate FunctionDefinitionAst
    # nodes, which merely define functions without side effects.
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/GuiContext.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'New-GuiContext' {
    It 'returns a hashtable with all required categories' {
        $ctx = New-GuiContext

        $ctx | Should -BeOfType [hashtable]
        $ctx.Keys | Should -Contain 'Theme'
        $ctx.Keys | Should -Contain 'Data'
        $ctx.Keys | Should -Contain 'Run'
        $ctx.Keys | Should -Contain 'Filter'
        $ctx.Keys | Should -Contain 'GameMode'
        $ctx.Keys | Should -Contain 'UI'
        $ctx.Keys | Should -Contain 'Services'
        $ctx.Keys | Should -Contain 'Config'
    }

    It 'initializes Run.InProgress to false' {
        $ctx = New-GuiContext

        $ctx.Run.InProgress | Should -Be $false
    }

    It 'initializes Filter defaults' {
        $ctx = New-GuiContext

        $ctx.Filter.Risk | Should -Be 'All'
        $ctx.Filter.Category | Should -Be 'All'
        $ctx.Filter.SafeMode | Should -Be $false
        $ctx.Filter.AdvancedMode | Should -Be $false
    }

    It 'applies overrides to nested categories' {
        $ctx = New-GuiContext -Overrides @{
            Run = @{ InProgress = $true }
            GameMode = @{ Active = $true; Profile = 'Competitive' }
        }

        $ctx.Run.InProgress | Should -Be $true
        $ctx.GameMode.Active | Should -Be $true
        $ctx.GameMode.Profile | Should -Be 'Competitive'
    }

    It 'does not remove fields not present in overrides' {
        $ctx = New-GuiContext -Overrides @{
            Run = @{ InProgress = $true }
        }

        $ctx.Run.Keys | Should -Contain 'AbortRequested'
        $ctx.Run.AbortRequested | Should -Be $false
    }
}

Describe 'Get-GuiContext' {
    It 'reads a nested field' {
        $ctx = New-GuiContext -Overrides @{ Run = @{ InProgress = $true } }

        $result = Get-GuiContext -Path 'Run.InProgress' -Context $ctx

        $result | Should -Be $true
    }

    It 'reads a whole category' {
        $ctx = New-GuiContext

        $result = Get-GuiContext -Path 'Filter' -Context $ctx

        $result | Should -BeOfType [hashtable]
        $result.Risk | Should -Be 'All'
    }

    It 'returns null for unknown category' {
        $ctx = New-GuiContext

        $result = Get-GuiContext -Path 'NonExistent.Field' -Context $ctx

        $result | Should -BeNullOrEmpty
    }

    It 'returns null for unknown field in valid category' {
        $ctx = New-GuiContext

        $result = Get-GuiContext -Path 'Run.NonExistent' -Context $ctx

        $result | Should -BeNullOrEmpty
    }

    It 'returns null for null context' {
        $result = Get-GuiContext -Path 'Run.InProgress' -Context $null

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Set-GuiContext' {
    It 'sets a nested field' {
        $ctx = New-GuiContext

        Set-GuiContext -Path 'Run.InProgress' -Value $true -Context $ctx

        $ctx.Run.InProgress | Should -Be $true
    }

    It 'throws for invalid path (no dot)' {
        $ctx = New-GuiContext

        { Set-GuiContext -Path 'NoDot' -Value 'x' -Context $ctx } | Should -Throw '*Category.Field*'
    }

    It 'throws for unknown category' {
        $ctx = New-GuiContext

        { Set-GuiContext -Path 'Fake.Field' -Value 'x' -Context $ctx } | Should -Throw '*Unknown context category*'
    }

    It 'creates new fields in existing categories' {
        $ctx = New-GuiContext

        Set-GuiContext -Path 'Run.CustomField' -Value 'test' -Context $ctx

        $ctx.Run.CustomField | Should -Be 'test'
    }
}

Describe 'Set-GuiStatusText' {
    BeforeEach {
        $script:GuiState = $null
        $script:SharedBrushConverter = $null
        $script:StatusText = [pscustomobject]@{
            Text = ''
            Visibility = 'Collapsed'
            Foreground = $null
        }
        $script:CurrentTheme = @{
            ToggleOn = '#16A34A'
            CautionText = '#B45309'
            RiskMediumBadge = '#DC2626'
            AccentBlue = '#2563EB'
            TextSecondary = '#6B7280'
        }
    }

    It 'shows the status control when text is present' {
        Set-GuiStatusText -Text 'Run failed.' -Tone 'caution'

        $script:StatusText.Text | Should -Be 'Run failed.'
        $script:StatusText.Visibility | Should -Be 'Visible'
    }

    It 'collapses the status control when text is empty' {
        Set-GuiStatusText -Text '' -Tone 'muted'

        $script:StatusText.Text | Should -Be ''
        $script:StatusText.Visibility | Should -Be 'Collapsed'
    }
}
