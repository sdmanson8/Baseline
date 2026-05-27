Set-StrictMode -Version Latest

Describe 'HKCU registry value removals' {
    It 'routes direct HKCU value removals through Remove-RegistryValueSafe' {
        $root = Resolve-Path (Join-Path $PSScriptRoot '../..')
        $files = Get-ChildItem -Path (Join-Path $root 'Module/Regions') -Recurse -File -Include '*.ps1', '*.psm1'
        $violations = [System.Collections.Generic.List[string]]::new()

        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors -and $errors.Count -gt 0) {
                continue
            }

            $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Remove-ItemProperty' -and
                    $node.Extent.Text -like '*HKCU:*'
                }, $true) | ForEach-Object {
                [void]$violations.Add(('{0}:{1}: {2}' -f $file.FullName, $_.Extent.StartLineNumber, $_.Extent.Text.Trim()))
            }
        }

        $violations | Should -Be @()
    }
}
