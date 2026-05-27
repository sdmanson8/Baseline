Set-StrictMode -Version Latest

BeforeAll {
    $registryHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    . $registryHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RansomwareFtype.Helpers.ps1'
    . $filePath

    $script:sandboxBase = "HKCU:\Software\Baseline_RansomwareFtype_Tests_$([guid]::NewGuid().ToString('N'))"
    $script:classesRoot = Join-Path $script:sandboxBase 'Classes'
    $script:backupRoot  = Join-Path $script:sandboxBase 'Backup'
    $env:BASELINE_FTYPE_CLASSES_ROOT = $script:classesRoot
    $env:BASELINE_FTYPE_BACKUP_ROOT  = $script:backupRoot

    function Reset-FtypeSandbox
    {
        if (Test-Path -LiteralPath $script:sandboxBase)
        {
            Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:classesRoot -Force | Out-Null
        New-Item -Path $script:backupRoot  -Force | Out-Null
    }

    function Set-FakeAssociation
    {
        param(
            [Parameter(Mandatory)][string]$Extension,
            [Parameter(Mandatory)][string]$ProgID,
            [Parameter(Mandatory)][string]$OpenCommand
        )
        $extKey = Join-Path $script:classesRoot $Extension
        New-Item -Path $extKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $extKey -Name '(default)' -Value $ProgID -Force

        $cmdKey = Join-Path (Join-Path (Join-Path $script:classesRoot $ProgID) 'shell\open') 'command'
        New-Item -Path $cmdKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $cmdKey -Name '(default)' -Value $OpenCommand -Force
    }

    function Get-OpenCommand
    {
        param(
            [Parameter(Mandatory)][string]$ProgID
        )
        $cmdKey = Join-Path (Join-Path (Join-Path $script:classesRoot $ProgID) 'shell\open') 'command'
        if (-not (Test-Path -LiteralPath $cmdKey)) { return $null }
        $item = Get-ItemProperty -LiteralPath $cmdKey -ErrorAction SilentlyContinue
        if (-not $item) { return $null }
        return [string]$item.'(default)'
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:sandboxBase)
    {
        Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath Env:BASELINE_FTYPE_CLASSES_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath Env:BASELINE_FTYPE_BACKUP_ROOT  -ErrorAction SilentlyContinue
}

Describe 'Get-BaselineRansomwareFtypeExtensions' {
    It 'returns the canonical risky extension list' {
        $exts = Get-BaselineRansomwareFtypeExtensions
        $exts | Should -Contain '.bat'
        $exts | Should -Contain '.cmd'
        $exts | Should -Contain '.js'
        $exts | Should -Contain '.vbs'
        $exts | Should -Contain '.hta'
        $exts | Should -Contain '.wsf'
        $exts | Should -Contain '.reg'
        $exts | Should -Contain '.msc'
        $exts | Should -Contain '.rdg'
        $exts | Should -Contain '.application'
        $exts | Should -Contain '.deploy'
    }

    It 'returns extensions in lowercase with leading dots' {
        $exts = Get-BaselineRansomwareFtypeExtensions
        foreach ($e in $exts) {
            $e | Should -MatchExactly '^\.[a-z0-9]+$'
        }
    }

    It 'returns a stable order across invocations' {
        $first  = Get-BaselineRansomwareFtypeExtensions
        $second = Get-BaselineRansomwareFtypeExtensions
        ($first -join ',') | Should -Be ($second -join ',')
    }
}

Describe 'Get-BaselineRansomwareFtypeClassesRoot' {
    AfterEach {
        $env:BASELINE_FTYPE_CLASSES_ROOT = $script:classesRoot
    }

    It 'returns the env override when set' {
        $env:BASELINE_FTYPE_CLASSES_ROOT = 'HKCU:\Software\Foo'
        Get-BaselineRansomwareFtypeClassesRoot | Should -Be 'HKCU:\Software\Foo'
    }

    It 'trims trailing backslashes from the override' {
        $env:BASELINE_FTYPE_CLASSES_ROOT = 'HKCU:\Software\Foo\'
        Get-BaselineRansomwareFtypeClassesRoot | Should -Be 'HKCU:\Software\Foo'
    }

    It 'falls through to HKLM:\Software\Classes when no override is set' {
        Remove-Item -LiteralPath Env:BASELINE_FTYPE_CLASSES_ROOT -ErrorAction SilentlyContinue
        Get-BaselineRansomwareFtypeClassesRoot | Should -Be 'HKLM:\Software\Classes'
    }
}

Describe 'Get-BaselineRansomwareFtypeBackupRoot' {
    AfterEach {
        $env:BASELINE_FTYPE_BACKUP_ROOT = $script:backupRoot
    }

    It 'returns the env override when set' {
        $env:BASELINE_FTYPE_BACKUP_ROOT = 'HKCU:\Software\Backup'
        Get-BaselineRansomwareFtypeBackupRoot | Should -Be 'HKCU:\Software\Backup'
    }

    It 'falls through to HKLM:\Software\Baseline\RansomwareFtype when no override is set' {
        Remove-Item -LiteralPath Env:BASELINE_FTYPE_BACKUP_ROOT -ErrorAction SilentlyContinue
        Get-BaselineRansomwareFtypeBackupRoot | Should -Be 'HKLM:\Software\Baseline\RansomwareFtype'
    }
}

Describe 'Get-BaselineRansomwareFtypeNotepadCommand' {
    It 'returns the canonical Notepad command string' {
        Get-BaselineRansomwareFtypeNotepadCommand | Should -Be '%SystemRoot%\System32\notepad.exe "%1"'
    }
}

Describe 'Get-BaselineFtypeAssociation' {
    BeforeEach { Reset-FtypeSandbox }

    It 'returns ProgID and OpenCommand when both exist' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand '%SystemRoot%\System32\WScript.exe "%1" %*'
        $assoc = Get-BaselineFtypeAssociation -Extension '.vbs'
        $assoc.Extension         | Should -Be '.vbs'
        $assoc.ProgID            | Should -Be 'VBSFile'
        $assoc.ProgIDExists      | Should -BeTrue
        $assoc.OpenCommand       | Should -Be '%SystemRoot%\System32\WScript.exe "%1" %*'
        $assoc.OpenCommandExists | Should -BeTrue
    }

    It 'returns ProgIDExists=$false when the extension is unregistered' {
        $assoc = Get-BaselineFtypeAssociation -Extension '.nonexistent'
        $assoc.ProgIDExists      | Should -BeFalse
        $assoc.OpenCommandExists | Should -BeFalse
        $assoc.ProgID            | Should -BeNullOrEmpty
        $assoc.OpenCommand       | Should -BeNullOrEmpty
    }

    It 'returns OpenCommandExists=$false when ProgID has no open verb' {
        $extKey = Join-Path $script:classesRoot '.orphan'
        New-Item -Path $extKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $extKey -Name '(default)' -Value 'OrphanProgID' -Force
        New-Item -Path (Join-Path $script:classesRoot 'OrphanProgID') -Force | Out-Null

        $assoc = Get-BaselineFtypeAssociation -Extension '.orphan'
        $assoc.ProgIDExists      | Should -BeTrue
        $assoc.ProgID            | Should -Be 'OrphanProgID'
        $assoc.OpenCommandExists | Should -BeFalse
    }

    It 'normalises extension to lowercase' {
        Set-FakeAssociation -Extension '.bat' -ProgID 'BatchFile' -OpenCommand 'cmd.exe /c "%1"'
        $assoc = Get-BaselineFtypeAssociation -Extension '.BAT'
        $assoc.Extension | Should -Be '.bat'
        $assoc.ProgID    | Should -Be 'BatchFile'
    }

    It 'prepends a leading dot when missing' {
        Set-FakeAssociation -Extension '.bat' -ProgID 'BatchFile' -OpenCommand 'cmd.exe /c "%1"'
        $assoc = Get-BaselineFtypeAssociation -Extension 'bat'
        $assoc.Extension | Should -Be '.bat'
    }

    It 'honours an explicit -ClassesRoot override' {
        $altRoot = Join-Path $script:sandboxBase 'AltClasses'
        New-Item -Path $altRoot -Force | Out-Null
        $extKey = Join-Path $altRoot '.alt'
        New-Item -Path $extKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $extKey -Name '(default)' -Value 'AltProgID' -Force

        $assoc = Get-BaselineFtypeAssociation -Extension '.alt' -ClassesRoot $altRoot
        $assoc.ProgID | Should -Be 'AltProgID'
    }
}

Describe 'Set-BaselineRansomwareFtypeMitigation' {
    BeforeEach { Reset-FtypeSandbox }

    It 'redirects the open command to Notepad' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand '%SystemRoot%\System32\WScript.exe "%1" %*'
        $result = Set-BaselineRansomwareFtypeMitigation -Extension '.vbs'

        $result.Mitigated     | Should -BeTrue
        $result.BackupCreated | Should -BeTrue
        $result.AlreadyMitigated | Should -BeFalse
        Get-OpenCommand -ProgID 'VBSFile' | Should -Be '%SystemRoot%\System32\notepad.exe "%1"'
    }

    It 'creates a backup of the original command' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand '%SystemRoot%\System32\WScript.exe "%1" %*'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        $backupKey = Join-Path $script:backupRoot 'VBSFile'
        Test-Path -LiteralPath $backupKey | Should -BeTrue
        $backup = Get-ItemProperty -LiteralPath $backupKey
        $backup.'(default)'   | Should -Be '%SystemRoot%\System32\WScript.exe "%1" %*'
        $backup.Extension     | Should -Be '.vbs'
        $backup.MitigatedAt   | Should -Match '^\d{4}-\d{2}-\d{2}T'
    }

    It 'does not overwrite an existing backup on re-run' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'original-command'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        # Pretend something else corrupted the live key, then re-mitigate.
        $cmdKey = Join-Path (Join-Path (Join-Path $script:classesRoot 'VBSFile') 'shell\open') 'command'
        Set-ItemProperty -LiteralPath $cmdKey -Name '(default)' -Value 'something-else' -Force

        $result = Set-BaselineRansomwareFtypeMitigation -Extension '.vbs'
        $result.Mitigated     | Should -BeTrue
        $result.BackupCreated | Should -BeFalse

        $backupKey = Join-Path $script:backupRoot 'VBSFile'
        $backup = Get-ItemProperty -LiteralPath $backupKey
        $backup.'(default)' | Should -Be 'original-command'
    }

    It 'reports AlreadyMitigated when the command already points at Notepad' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand '%SystemRoot%\System32\notepad.exe "%1"'
        $result = Set-BaselineRansomwareFtypeMitigation -Extension '.vbs'
        $result.AlreadyMitigated | Should -BeTrue
        $result.Mitigated        | Should -BeFalse
        $result.BackupCreated    | Should -BeFalse
    }

    It 'skips when the extension has no ProgID' {
        $result = Set-BaselineRansomwareFtypeMitigation -Extension '.unregistered'
        $result.Skipped    | Should -BeTrue
        $result.SkipReason | Should -Be 'NoProgID'
        $result.Mitigated  | Should -BeFalse
    }

    It 'honours -WhatIf without writing' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' -WhatIf | Out-Null

        Get-OpenCommand -ProgID 'VBSFile' | Should -Be 'wscript-original'
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'VBSFile') | Should -BeFalse
    }
}

Describe 'Restore-BaselineRansomwareFtypeMitigation' {
    BeforeEach { Reset-FtypeSandbox }

    It 'restores the original command from the backup' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        $result = Restore-BaselineRansomwareFtypeMitigation -Extension '.vbs'
        $result.Restored | Should -BeTrue
        Get-OpenCommand -ProgID 'VBSFile' | Should -Be 'wscript-original'
    }

    It 'removes the backup key after restore' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        Restore-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'VBSFile') | Should -BeFalse
    }

    It 'reports SkipReason=NoBackup when no backup exists' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'something'
        $result = Restore-BaselineRansomwareFtypeMitigation -Extension '.vbs'
        $result.Restored   | Should -BeFalse
        $result.Skipped    | Should -BeTrue
        $result.SkipReason | Should -Be 'NoBackup'
    }

    It 'reports SkipReason=NoProgID for unregistered extensions' {
        $result = Restore-BaselineRansomwareFtypeMitigation -Extension '.unregistered'
        $result.Skipped    | Should -BeTrue
        $result.SkipReason | Should -Be 'NoProgID'
    }

    It 'honours -WhatIf without writing' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        Restore-BaselineRansomwareFtypeMitigation -Extension '.vbs' -WhatIf | Out-Null
        Get-OpenCommand -ProgID 'VBSFile' | Should -Be '%SystemRoot%\System32\notepad.exe "%1"'
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'VBSFile') | Should -BeTrue
    }
}

Describe 'Get-BaselineRansomwareFtypeStatus' {
    BeforeEach { Reset-FtypeSandbox }

    It 'classifies a registered un-mitigated extension as Original' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        $status = @(Get-BaselineRansomwareFtypeStatus -Extensions @('.vbs'))
        $status.Count       | Should -Be 1
        $status[0].State    | Should -Be 'Original'
        $status[0].ProgID   | Should -Be 'VBSFile'
        $status[0].BackupPresent | Should -BeFalse
    }

    It 'classifies a Baseline-mitigated extension as Mitigated' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand 'wscript-original'
        Set-BaselineRansomwareFtypeMitigation -Extension '.vbs' | Out-Null

        $status = @(Get-BaselineRansomwareFtypeStatus -Extensions @('.vbs'))
        $status[0].State         | Should -Be 'Mitigated'
        $status[0].BackupPresent | Should -BeTrue
    }

    It 'classifies an out-of-band Notepad redirect as MitigatedNoBackup' {
        Set-FakeAssociation -Extension '.vbs' -ProgID 'VBSFile' -OpenCommand '%SystemRoot%\System32\notepad.exe "%1"'
        $status = @(Get-BaselineRansomwareFtypeStatus -Extensions @('.vbs'))
        $status[0].State         | Should -Be 'MitigatedNoBackup'
        $status[0].BackupPresent | Should -BeFalse
    }

    It 'classifies an unregistered extension as Unregistered' {
        $status = @(Get-BaselineRansomwareFtypeStatus -Extensions @('.nonesuch'))
        $status[0].State  | Should -Be 'Unregistered'
        $status[0].ProgID | Should -BeNullOrEmpty
    }

    It 'iterates the canonical extension list when -Extensions is omitted' {
        $status = Get-BaselineRansomwareFtypeStatus
        $expected = Get-BaselineRansomwareFtypeExtensions
        $status.Count | Should -Be $expected.Count
        ($status | ForEach-Object Extension) -join ',' | Should -Be ($expected -join ',')
    }
}
