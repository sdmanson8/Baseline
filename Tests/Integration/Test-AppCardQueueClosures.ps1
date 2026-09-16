$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 required.' }
Add-Type -AssemblyName PresentationFramework
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Read-TestAst($RelativePath) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $RelativePath), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $ast
}
$queueAst = Read-TestAst 'Module/GUI/AppsModule/SelectionQueueState.ps1'
$definitions = foreach ($name in @('Initialize-AppsQueuedActionState', 'Get-AppQueuedAction')) {
    $queueAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true).Extent.Text
}
$cardAst = Read-TestAst 'Module/GUI/AppsModule/Build-AppsViewCards/Build-AppsViewCards.ps1'
$handlers = foreach ($name in @('primaryButton', 'updateButton')) {
    $call = $cardAst.Find({param($n)
        $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Member.Value -eq 'Add_Click' -and $n.Expression.Extent.Text -eq ('$' + $name)
    }, $true)
    $call.Extent.Text
}
$testModule = New-Module -ArgumentList ($definitions -join "`n"), $handlers -ScriptBlock {
    param($Definitions, $Handlers)
    . ([scriptblock]::Create($Definitions))
    $Script:Handlers = $Handlers
    function Set-AppQueuedAction {
        param($AppId, $Action)
        $Script:AppsQueuedActions[$AppId] = $Action
    }
    function Report-TestFailure { param($Context, $Exception, [switch]$ShowDialog) throw $Exception }
    function New-TestButtons {
        param($Id, $Action)
        $selectionKeyCapture = $Id
        $capturedPrimaryAction = $Action
        $getAppQueuedActionCommand = Get-Command Get-AppQueuedAction
        $setAppQueuedActionCommand = Get-Command Set-AppQueuedAction
        $showGuiRuntimeFailureCommand = Get-Command Report-TestFailure
        $primaryButton = New-Object System.Windows.Controls.Button
        $updateButton = New-Object System.Windows.Controls.Button
        foreach ($handler in $Script:Handlers) { . ([scriptblock]::Create($handler)) }
        [pscustomobject]@{ Primary = $primaryButton; Update = $updateButton }
    }
    function Read-TestQueue { param($Id) Get-AppQueuedAction -AppId $Id }
    Export-ModuleMember -Function New-TestButtons, Read-TestQueue
}
try {
    Import-Module $testModule
    $first = New-TestButtons -Id 'winget:first' -Action Install
    $second = New-TestButtons -Id 'winget:second' -Action Uninstall
    # Raise real WPF events after the factory scope has returned. The queue getter is private.
    foreach ($case in @(
        @($first.Primary, 'winget:first', 'Install'),
        @($second.Primary, 'winget:second', 'Uninstall'),
        @($first.Primary, 'winget:first', 'DoNothing'),
        @($first.Update, 'winget:first', 'Update'),
        @($first.Update, 'winget:first', 'DoNothing')
    )) {
        $case[0].RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        if ((Read-TestQueue -Id $case[1]) -ne $case[2]) { throw "Wrong queued action for $($case[1])." }
    }
    if ((Read-TestQueue -Id 'winget:second') -ne 'Uninstall') { throw 'Click changed another app queue.' }
    'PASS: private module queue getter resolves for Install, Uninstall, Update, cancellation, and separate cards.'
} finally { Remove-Module $testModule }
