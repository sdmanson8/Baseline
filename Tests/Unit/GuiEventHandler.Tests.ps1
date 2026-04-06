Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/EventInfrastructure.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Ensure-GuiEventHandlerStore', 'Get-GuiEventAccessorMethod', 'Register-GuiEventHandler', 'Unregister-GuiEventHandler', 'Unregister-GuiEventHandlers', 'Get-GuiRuntimeCommand', 'Get-GuiFunctionCapture')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    function Write-GuiRuntimeWarning {
        param(
            [string]$Context,
            [string]$Message
        )
    }

    Add-Type -TypeDefinition @'
using System;

public class GuiEventHandlerTestEventArgs : EventArgs
{
    public string Name { get; set; }
}

public class GuiKeyboardFocusChangedEventArgs : EventArgs
{
    public string Name { get; set; }
}

public delegate void GuiEventHandlerTestDelegate(object sender, GuiEventHandlerTestEventArgs e);
public delegate void GuiKeyboardFocusChangedDelegate(object sender, GuiKeyboardFocusChangedEventArgs e);

public class GuiEventHandlerTestSource
{
    public event GuiEventHandlerTestDelegate GotKeyboardFocus;
    public event GuiEventHandlerTestDelegate LostKeyboardFocus;

    public void RaiseGotKeyboardFocus()
    {
        var handler = GotKeyboardFocus;
        if (handler != null)
        {
            handler(this, new GuiEventHandlerTestEventArgs { Name = "got" });
        }
    }

    public void RaiseLostKeyboardFocus()
    {
        var handler = LostKeyboardFocus;
        if (handler != null)
        {
            handler(this, new GuiEventHandlerTestEventArgs { Name = "lost" });
        }
    }
}

public class GuiMixedEventSource
{
    public event GuiEventHandlerTestDelegate MouseEnter;
    public event GuiKeyboardFocusChangedDelegate GotKeyboardFocus;

    public void RaiseMouseEnter()
    {
        var handler = MouseEnter;
        if (handler != null)
        {
            handler(this, new GuiEventHandlerTestEventArgs { Name = "mouse" });
        }
    }

    public void RaiseGotKeyboardFocus()
    {
        var handler = GotKeyboardFocus;
        if (handler != null)
        {
            handler(this, new GuiKeyboardFocusChangedEventArgs { Name = "focus" });
        }
    }
}
'@
}

Describe 'Register-GuiEventHandler' {
    BeforeEach {
        $script:GuiEventHandlerStore = $null
        $script:GuiRuntimeCommandCache = $null
        $script:GuiFunctionCaptureCache = $null
    }

    It 'registers custom focus handlers and stores them for cleanup' {
        $source = [GuiEventHandlerTestSource]::new()
        $script:eventsSeen = [System.Collections.Generic.List[string]]::new()

        $gotHandler = Register-GuiEventHandler -Source $source -EventName 'GotKeyboardFocus' -Handler {
            param($sender, $eventArgs)
            [void]$script:eventsSeen.Add([string]$eventArgs.Name)
        }

        $lostHandler = Register-GuiEventHandler -Source $source -EventName 'LostKeyboardFocus' -Handler {
            param($sender, $eventArgs)
            [void]$script:eventsSeen.Add([string]$eventArgs.Name)
        }

        $gotHandler | Should -BeOfType ([scriptblock])
        $lostHandler | Should -BeOfType ([scriptblock])

        $source.RaiseGotKeyboardFocus()
        $source.RaiseLostKeyboardFocus()

        @($script:eventsSeen) | Should -Be @('got', 'lost')
        $script:GuiEventHandlerStore.Count | Should -Be 2
    }

    It 'registers closure-captured handlers across different event delegate types' {
        $source = [GuiMixedEventSource]::new()
        $eventsSeen = [System.Collections.Generic.List[string]]::new()

        $mouseLabel = 'mouse'
        $focusLabel = 'focus'

        Register-GuiEventHandler -Source $source -EventName 'MouseEnter' -Handler ({
            param($sender, $eventArgs)
            [void]$eventsSeen.Add($mouseLabel)
        }.GetNewClosure()) | Out-Null

        Register-GuiEventHandler -Source $source -EventName 'GotKeyboardFocus' -Handler ({
            param($sender, $eventArgs)
            [void]$eventsSeen.Add($focusLabel)
        }.GetNewClosure()) | Out-Null

        $source.RaiseMouseEnter()
        $source.RaiseGotKeyboardFocus()

        @($eventsSeen) | Should -Be @('mouse', 'focus')

        Unregister-GuiEventHandlers
        $source.RaiseMouseEnter()
        $source.RaiseGotKeyboardFocus()

        @($eventsSeen) | Should -Be @('mouse', 'focus')
    }

    It 'unregisters stored handlers cleanly' {
        $source = [GuiEventHandlerTestSource]::new()
        $script:eventCount = 0

        Register-GuiEventHandler -Source $source -EventName 'GotKeyboardFocus' -Handler {
            param($sender, $eventArgs)
            $script:eventCount++
        } | Out-Null

        $source.RaiseGotKeyboardFocus()
        $script:eventCount | Should -Be 1

        Unregister-GuiEventHandlers
        $source.RaiseGotKeyboardFocus()

        $script:eventCount | Should -Be 1
        $script:GuiEventHandlerStore.Count | Should -Be 0
    }

    It 'captures local functions for later invocation' {
        function Get-TestGuiGreeting {
            param(
                [string]$Name
            )

            return "hello $Name"
        }

        $capture = Get-GuiFunctionCapture -Name 'Get-TestGuiGreeting'

        Remove-Item -Path Function:\Get-TestGuiGreeting

        (& $capture -Name 'world') | Should -Be 'hello world'
    }

    It 'resolves local functions with sibling dependencies through runtime commands' {
        function Get-TestGuiInner {
            param(
                [string]$Name
            )

            return "hello $Name"
        }

        function Invoke-TestGuiOuter {
            param(
                [string]$Name
            )

            return (Get-TestGuiInner -Name $Name)
        }

        $command = Get-GuiRuntimeCommand -Name 'Invoke-TestGuiOuter' -CommandType 'Function'

        (& $command -Name 'world') | Should -Be 'hello world'
    }
}
