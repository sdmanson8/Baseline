Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/ObservableState.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'New-ObservableState' {
    It 'creates a state container with Get/Set/Subscribe/SetBatch methods' {
        $state = New-ObservableState -InitialValues @{ Foo = 'bar' }

        $state | Should -BeOfType [hashtable]
        $state.Get | Should -BeOfType [scriptblock]
        $state.Set | Should -BeOfType [scriptblock]
        $state.Subscribe | Should -BeOfType [scriptblock]
        $state.SetBatch | Should -BeOfType [scriptblock]
    }

    It 'Get returns initial values' {
        $state = New-ObservableState -InitialValues @{ Name = 'test'; Count = 42 }

        (& $state.Get 'Name') | Should -Be 'test'
        (& $state.Get 'Count') | Should -Be 42
    }

    It 'Set updates the value' {
        $state = New-ObservableState -InitialValues @{ Name = 'old' }

        & $state.Set 'Name' 'new'

        (& $state.Get 'Name') | Should -Be 'new'
    }

    It 'Subscribe fires handler on change' {
        $state = New-ObservableState -InitialValues @{ Value = 0 }
        $captured = @{ New = $null; Old = $null }

        & $state.Subscribe 'Value' {
            param ($new, $old)
            $captured.New = $new
            $captured.Old = $old
        }

        & $state.Set 'Value' 42

        $captured.New | Should -Be 42
        $captured.Old | Should -Be 0
    }

    It 'does not fire subscriber when value is unchanged' {
        $state = New-ObservableState -InitialValues @{ Flag = $true }
        $callCount = @{ Count = 0 }

        & $state.Subscribe 'Flag' {
            $callCount.Count++
        }

        & $state.Set 'Flag' $true  # same value

        $callCount.Count | Should -Be 0
    }

    It 'supports multiple subscribers for one property' {
        $state = New-ObservableState -InitialValues @{ X = 0 }
        $results = @{ A = $null; B = $null }

        & $state.Subscribe 'X' { param($n) $results.A = $n }
        & $state.Subscribe 'X' { param($n) $results.B = $n }

        & $state.Set 'X' 99

        $results.A | Should -Be 99
        $results.B | Should -Be 99
    }

    It 'SetBatch updates multiple properties and fires subscribers' {
        $state = New-ObservableState -InitialValues @{ A = 1; B = 2 }
        $captured = @{ A = $null; B = $null }

        & $state.Subscribe 'A' { param($n) $captured.A = $n }
        & $state.Subscribe 'B' { param($n) $captured.B = $n }

        & $state.SetBatch @{ A = 10; B = 20 }

        (& $state.Get 'A') | Should -Be 10
        (& $state.Get 'B') | Should -Be 20
        $captured.A | Should -Be 10
        $captured.B | Should -Be 20
    }

    It 'SetBatch skips unchanged properties' {
        $state = New-ObservableState -InitialValues @{ X = 1; Y = 2 }
        $callCount = @{ X = 0; Y = 0 }

        & $state.Subscribe 'X' { $callCount.X++ }
        & $state.Subscribe 'Y' { $callCount.Y++ }

        & $state.SetBatch @{ X = 1; Y = 99 }  # X unchanged, Y changed

        $callCount.X | Should -Be 0
        $callCount.Y | Should -Be 1
    }

    It 'works without dispatcher (synchronous mode)' {
        $state = New-ObservableState -InitialValues @{ Val = 'a' }
        $fired = @{ Done = $false }

        & $state.Subscribe 'Val' { $fired.Done = $true }
        & $state.Set 'Val' 'b'

        $fired.Done | Should -Be $true
    }

    It 'Subscribe creates property entry if not pre-declared' {
        $state = New-ObservableState -InitialValues @{}
        $captured = @{ Val = $null }

        & $state.Subscribe 'NewProp' { param($n) $captured.Val = $n }
        & $state.Set 'NewProp' 'hello'

        $captured.Val | Should -Be 'hello'
    }
}
