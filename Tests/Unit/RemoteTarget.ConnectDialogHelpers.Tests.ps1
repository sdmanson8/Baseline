Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemoteTarget.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $wanted = @(
        'ConvertFrom-BaselineRemoteTargetInput'
        'New-BaselineRemoteTargetCredential'
        'Format-BaselineRemoteConnectivityStatus'
        'ConvertTo-BaselineRemoteConnectionMethod'
        'Get-BaselineRemoteConnectionMethodLabel'
    )
    foreach ($fn in $functions) {
        if ($fn.Name -in $wanted) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'ConvertFrom-BaselineRemoteTargetInput' {
    It 'returns no targets for empty input' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText ''
        $r.Targets.Count | Should -Be 0
        $r.Invalid.Count | Should -Be 0
    }

    It 'returns no targets for null input' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText $null
        $r.Targets.Count | Should -Be 0
    }

    It 'splits on commas, semicolons, pipes and whitespace' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText 'PC01, PC02; PC03|PC04 PC05'
        $r.Targets.Count | Should -Be 5
        $r.Targets[0] | Should -Be 'PC01'
        $r.Targets[4] | Should -Be 'PC05'
    }

    It 'deduplicates case-insensitively, keeping the first spelling' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText 'PC01, pc01, PC02'
        $r.Targets.Count | Should -Be 2
        $r.Targets[0] | Should -Be 'PC01'
        $r.Targets[1] | Should -Be 'PC02'
    }

    It 'accepts FQDNs' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText 'host.contoso.local'
        $r.Targets.Count | Should -Be 1
        $r.Invalid.Count | Should -Be 0
    }

    It 'accepts IPv4 addresses' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText '10.0.0.5, 192.168.1.1'
        $r.Targets.Count | Should -Be 2
        $r.Invalid.Count | Should -Be 0
    }

    It 'rejects garbage tokens into Invalid' {
        $r = ConvertFrom-BaselineRemoteTargetInput -InputText 'PC01, PC0!, ..bad, GOODHOST'
        $r.Targets | Should -Contain 'PC01'
        $r.Targets | Should -Contain 'GOODHOST'
        $r.Invalid | Should -Contain 'PC0!'
        $r.Invalid | Should -Contain '..bad'
    }
}

Describe 'New-BaselineRemoteTargetCredential' {
    It 'throws when username is empty' {
        { New-BaselineRemoteTargetCredential -Username '' -SecurePassword $null } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'throws when username is whitespace' {
        { New-BaselineRemoteTargetCredential -Username '   ' -SecurePassword $null } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'accepts a bare username' {
        $cred = New-BaselineRemoteTargetCredential -Username 'Administrator' -SecurePassword $null
        $cred | Should -BeOfType ([System.Management.Automation.PSCredential])
        $cred.UserName | Should -Be 'Administrator'
    }

    It 'accepts DOMAIN\User' {
        $cred = New-BaselineRemoteTargetCredential -Username 'CONTOSO\jdoe' -SecurePassword $null
        $cred.UserName | Should -Be 'CONTOSO\jdoe'
    }

    It 'accepts user@domain (UPN)' {
        $cred = New-BaselineRemoteTargetCredential -Username 'jdoe@contoso.com' -SecurePassword $null
        $cred.UserName | Should -Be 'jdoe@contoso.com'
    }

    It 'rejects multiple backslashes' {
        { New-BaselineRemoteTargetCredential -Username 'A\B\C' -SecurePassword $null } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'rejects mixed DOMAIN\User and UPN forms' {
        { New-BaselineRemoteTargetCredential -Username 'CONTOSO\jdoe@contoso.com' -SecurePassword $null } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'rejects DOMAIN\User missing the user part' {
        { New-BaselineRemoteTargetCredential -Username 'CONTOSO\' -SecurePassword $null } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'preserves the supplied SecureString' {
        $secure = ConvertTo-SecureString -String 'Hunter2!' -AsPlainText -Force
        $cred = New-BaselineRemoteTargetCredential -Username 'Administrator' -SecurePassword $secure
        $cred.GetNetworkCredential().Password | Should -Be 'Hunter2!'
    }
}

Describe 'Format-BaselineRemoteConnectivityStatus' {
    It 'returns empty array for null input' {
        $r = Format-BaselineRemoteConnectivityStatus -Result $null
        @($r).Count | Should -Be 0
    }

    It 'formats a reachable target with the check icon' {
        $input = @(
            [pscustomobject]@{ ComputerName = 'PC01'; Reachable = $true; Status = 'Reachable'; BlockedByPolicy = $false; Error = $null }
        )
        $out = @(Format-BaselineRemoteConnectivityStatus -Result $input)
        $out.Count | Should -Be 1
        $out[0].State | Should -Be 'Reachable'
        $out[0].Display | Should -Match 'PC01'
        $out[0].Display | Should -Match 'Reachable'
        $out[0].Icon | Should -Be ([char]0x2714).ToString()
    }

    It 'formats an unreachable target with the cross icon and reason' {
        $input = @(
            [pscustomobject]@{ ComputerName = 'PC02'; Reachable = $false; Status = 'Unreachable'; BlockedByPolicy = $false; Error = 'WinRM not enabled' }
        )
        $out = @(Format-BaselineRemoteConnectivityStatus -Result $input)
        $out[0].State | Should -Be 'Unreachable'
        $out[0].Display | Should -Match 'PC02'
        $out[0].Display | Should -Match 'WinRM not enabled'
    }

    It 'flags blocked-by-policy targets distinctly' {
        $input = @(
            [pscustomobject]@{ ComputerName = 'PC03'; Reachable = $false; Status = 'Blocked'; BlockedByPolicy = $true; Error = 'Remote orchestration disabled by GPO' }
        )
        $out = @(Format-BaselineRemoteConnectivityStatus -Result $input)
        $out[0].State | Should -Be 'Blocked'
        $out[0].Display | Should -Match 'GPO'
    }

    It 'skips entries without a computer name' {
        $input = @(
            [pscustomobject]@{ ComputerName = ''; Reachable = $false; Status = 'Unreachable'; BlockedByPolicy = $false; Error = 'x' }
            [pscustomobject]@{ ComputerName = 'PC04'; Reachable = $true; Status = 'Reachable'; BlockedByPolicy = $false; Error = $null }
        )
        $out = @(Format-BaselineRemoteConnectivityStatus -Result $input)
        $out.Count | Should -Be 1
        $out[0].ComputerName | Should -Be 'PC04'
    }

    It 'returns one entry per input result' {
        $input = @(
            [pscustomobject]@{ ComputerName = 'A'; Reachable = $true;  Status = 'Reachable';   BlockedByPolicy = $false; Error = $null }
            [pscustomobject]@{ ComputerName = 'B'; Reachable = $false; Status = 'Unreachable'; BlockedByPolicy = $false; Error = 'down' }
            [pscustomobject]@{ ComputerName = 'C'; Reachable = $false; Status = 'Blocked';     BlockedByPolicy = $true;  Error = 'policy' }
        )
        $out = @(Format-BaselineRemoteConnectivityStatus -Result $input)
        $out.Count | Should -Be 3
    }
}

Describe 'ConvertTo-BaselineRemoteConnectionMethod' {
    It 'falls back to WinRM for null / empty input' {
        ConvertTo-BaselineRemoteConnectionMethod -Method $null  | Should -Be 'WinRM'
        ConvertTo-BaselineRemoteConnectionMethod -Method ''     | Should -Be 'WinRM'
        ConvertTo-BaselineRemoteConnectionMethod -Method '   '  | Should -Be 'WinRM'
    }

    It 'normalizes WinRM HTTP aliases' {
        ConvertTo-BaselineRemoteConnectionMethod -Method 'WinRM'           | Should -Be 'WinRM'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'WinRM (HTTP)'    | Should -Be 'WinRM'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'wsman'           | Should -Be 'WinRM'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'PSRemoting'      | Should -Be 'WinRM'
    }

    It 'normalizes WinRM HTTPS aliases' {
        ConvertTo-BaselineRemoteConnectionMethod -Method 'WinRMHttps'         | Should -Be 'WinRMHttps'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'WinRM over HTTPS'   | Should -Be 'WinRMHttps'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'winrm-ssl'          | Should -Be 'WinRMHttps'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'HTTPS'              | Should -Be 'WinRMHttps'
    }

    It 'normalizes SSH aliases' {
        ConvertTo-BaselineRemoteConnectionMethod -Method 'SSH'                              | Should -Be 'SSH'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'SSH (PowerShell over OpenSSH)'    | Should -Be 'SSH'
        ConvertTo-BaselineRemoteConnectionMethod -Method 'OpenSSH'                          | Should -Be 'SSH'
    }

    It 'falls back to WinRM for unknown values' {
        ConvertTo-BaselineRemoteConnectionMethod -Method 'banana' | Should -Be 'WinRM'
    }
}

Describe 'Get-BaselineRemoteConnectionMethodLabel' {
    It 'returns the friendly banner label' {
        Get-BaselineRemoteConnectionMethodLabel -Method 'WinRM'      | Should -Be 'WinRM'
        Get-BaselineRemoteConnectionMethodLabel -Method 'WinRMHttps' | Should -Be 'WinRM/HTTPS'
        Get-BaselineRemoteConnectionMethodLabel -Method 'SSH'        | Should -Be 'SSH'
    }

    It 'normalizes friendly inputs before labeling' {
        Get-BaselineRemoteConnectionMethodLabel -Method 'WinRM (HTTP)'  | Should -Be 'WinRM'
        Get-BaselineRemoteConnectionMethodLabel -Method 'HTTPS'         | Should -Be 'WinRM/HTTPS'
        Get-BaselineRemoteConnectionMethodLabel -Method 'OpenSSH'       | Should -Be 'SSH'
    }
}
