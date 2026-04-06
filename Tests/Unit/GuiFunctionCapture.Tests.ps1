Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/EventInfrastructure.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Get-GuiRuntimeCommand', 'Get-GuiFunctionCapture')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Get-GuiFunctionCapture' {
    BeforeEach {
        $Script:GuiRuntimeCommandCache = @{}
        $Script:GuiFunctionCaptureCache = @{}
    }

    It 're-resolves functions when the runtime command cache contains a stale null entry' {
        $Script:GuiRuntimeCommandCache['Function|Get-TestGuiGreeting'] = $null

        function Get-TestGuiGreeting {
            return 'hello'
        }

        $capture = Get-GuiFunctionCapture -Name 'Get-TestGuiGreeting'

        $capture | Should -Not -BeNullOrEmpty
        (& $capture) | Should -Be 'hello'
    }

    It 'preserves module-scope private function resolution when invoking captured functions' {
        $moduleName = 'GuiCaptureTestModule'
        $module = New-Module -Name $moduleName -ScriptBlock {
            function Invoke-PrivateDependency {
                param([string]$Name)
                return "private:$Name"
            }

            function Invoke-ExportedDependency {
                param([string]$Name)
                return (Invoke-PrivateDependency -Name $Name)
            }

            Export-ModuleMember -Function Invoke-ExportedDependency
        }

        try {
            Import-Module $module -Force | Out-Null

            $capture = Get-GuiFunctionCapture -Name 'Invoke-ExportedDependency'
            $capture | Should -Not -BeNullOrEmpty
            (& $capture -Name 'ok') | Should -Be 'private:ok'
        }
        finally {
            Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
        }
    }
}
