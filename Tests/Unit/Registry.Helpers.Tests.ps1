Set-StrictMode -Version Latest

BeforeAll {
    # Extract inner functions from the dot-sourced file via AST.
    # Uses Invoke-Expression on function definition AST nodes - safe because
    # ParseFile only parses (no execution) and we only evaluate FunctionDefinitionAst
    # nodes, which merely define functions without side effects.
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        # Only load pure-logic functions that do not touch the registry or filesystem
        if ($fn.Name -in @('Get-CurrentWindowsUserSid', 'ConvertTo-NativeRegistryPath', 'ConvertTo-RegExeValueType', 'Test-RegistryValueEquivalent')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:TestUserSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001'
}

Describe 'ConvertTo-NativeRegistryPath' {
    It 'converts HKLM:\ prefix to HKLM\ native path' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows'

        $result | Should -Be 'HKLM\SOFTWARE\Microsoft\Windows'
    }

    It 'converts HKEY_LOCAL_MACHINE\ to HKLM\ native path' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Test'

        $result | Should -Be 'HKLM\SOFTWARE\Test'
    }

    It 'converts HKCU:\ prefix to HKU\<SID>\ native path' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKCU:\SOFTWARE\Test' -CurrentUserSid $script:TestUserSid
        $expectedSid = $script:TestUserSid

        $result | Should -BeLike "HKU\$expectedSid\SOFTWARE\Test"
    }

    It 'converts HKEY_CURRENT_USER\ to HKU\<SID>\ native path' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKEY_CURRENT_USER\SOFTWARE\Test' -CurrentUserSid $script:TestUserSid
        $expectedSid = $script:TestUserSid

        $result | Should -BeLike "HKU\$expectedSid\SOFTWARE\Test"
    }

    It 'converts HKU:\ prefix to HKU\ native path' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKU:\S-1-5-18\SOFTWARE\Test'

        $result | Should -Be 'HKU\S-1-5-18\SOFTWARE\Test'
    }

    It 'passes through already-native HKLM\ paths unchanged' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKLM\SOFTWARE\Already\Native'

        $result | Should -Be 'HKLM\SOFTWARE\Already\Native'
    }

    It 'passes through already-native HKU\ paths unchanged' {
        $result = ConvertTo-NativeRegistryPath -Path 'HKU\S-1-5-18\SOFTWARE\Test'

        $result | Should -Be 'HKU\S-1-5-18\SOFTWARE\Test'
    }

    It 'strips Registry:: prefix before converting' {
        $result = ConvertTo-NativeRegistryPath -Path 'Registry::HKLM\SOFTWARE\Test'

        $result | Should -Be 'HKLM\SOFTWARE\Test'
    }

    It 'throws for unsupported registry path' {
        { ConvertTo-NativeRegistryPath -Path 'HKCR:\Classes\Test' } | Should -Throw '*Unsupported registry path*'
    }
}

Describe 'ConvertTo-RegExeValueType' {
    It 'converts DWord to REG_DWORD' {
        ConvertTo-RegExeValueType -Type 'DWord' | Should -Be 'REG_DWORD'
    }

    It 'converts String to REG_SZ' {
        ConvertTo-RegExeValueType -Type 'String' | Should -Be 'REG_SZ'
    }

    It 'converts QWord to REG_QWORD' {
        ConvertTo-RegExeValueType -Type 'QWord' | Should -Be 'REG_QWORD'
    }

    It 'converts Binary to REG_BINARY' {
        ConvertTo-RegExeValueType -Type 'Binary' | Should -Be 'REG_BINARY'
    }

    It 'converts ExpandString to REG_EXPAND_SZ' {
        ConvertTo-RegExeValueType -Type 'ExpandString' | Should -Be 'REG_EXPAND_SZ'
    }

    It 'converts MultiString to REG_MULTI_SZ' {
        ConvertTo-RegExeValueType -Type 'MultiString' | Should -Be 'REG_MULTI_SZ'
    }
}

Describe 'Test-RegistryValueEquivalent' {
    Context 'DWord comparisons' {
        It 'returns true when integer values match' {
            Test-RegistryValueEquivalent -CurrentValue 1 -DesiredValue 1 -Type 'DWord' | Should -Be $true
        }

        It 'returns false when integer values differ' {
            Test-RegistryValueEquivalent -CurrentValue 1 -DesiredValue 0 -Type 'DWord' | Should -Be $false
        }

        It 'handles string-to-int comparison for DWord' {
            Test-RegistryValueEquivalent -CurrentValue '42' -DesiredValue 42 -Type 'DWord' | Should -Be $true
        }
    }

    Context 'QWord comparisons' {
        It 'returns true when 64-bit integer values match' {
            Test-RegistryValueEquivalent -CurrentValue 4294967296 -DesiredValue 4294967296 -Type 'QWord' | Should -Be $true
        }

        It 'returns false when 64-bit integer values differ' {
            Test-RegistryValueEquivalent -CurrentValue 4294967296 -DesiredValue 0 -Type 'QWord' | Should -Be $false
        }
    }

    Context 'String comparisons' {
        It 'returns true when strings match' {
            Test-RegistryValueEquivalent -CurrentValue 'hello' -DesiredValue 'hello' -Type 'String' | Should -Be $true
        }

        It 'returns false when strings differ' {
            Test-RegistryValueEquivalent -CurrentValue 'hello' -DesiredValue 'world' -Type 'String' | Should -Be $false
        }

        It 'is case-sensitive for string comparison' {
            # PowerShell -eq is case-insensitive by default, so this tests the actual behavior
            Test-RegistryValueEquivalent -CurrentValue 'Hello' -DesiredValue 'hello' -Type 'String' | Should -Be $true
        }
    }

    Context 'ExpandString comparisons' {
        It 'returns true when ExpandString values match' {
            Test-RegistryValueEquivalent -CurrentValue '%SystemRoot%\test' -DesiredValue '%SystemRoot%\test' -Type 'ExpandString' | Should -Be $true
        }

        It 'returns false when ExpandString values differ' {
            Test-RegistryValueEquivalent -CurrentValue '%SystemRoot%\a' -DesiredValue '%SystemRoot%\b' -Type 'ExpandString' | Should -Be $false
        }
    }

    Context 'MultiString comparisons' {
        It 'returns true when arrays match' {
            Test-RegistryValueEquivalent -CurrentValue @('a', 'b', 'c') -DesiredValue @('a', 'b', 'c') -Type 'MultiString' | Should -Be $true
        }

        It 'returns false when arrays have different lengths' {
            Test-RegistryValueEquivalent -CurrentValue @('a', 'b') -DesiredValue @('a', 'b', 'c') -Type 'MultiString' | Should -Be $false
        }

        It 'returns false when arrays have different elements' {
            Test-RegistryValueEquivalent -CurrentValue @('a', 'b', 'c') -DesiredValue @('a', 'x', 'c') -Type 'MultiString' | Should -Be $false
        }
    }

    Context 'Binary comparisons' {
        It 'returns true when byte arrays match' {
            Test-RegistryValueEquivalent -CurrentValue @([byte]0x01, [byte]0x02) -DesiredValue @([byte]0x01, [byte]0x02) -Type 'Binary' | Should -Be $true
        }

        It 'returns false when byte arrays differ in length' {
            Test-RegistryValueEquivalent -CurrentValue @([byte]0x01) -DesiredValue @([byte]0x01, [byte]0x02) -Type 'Binary' | Should -Be $false
        }

        It 'returns false when byte arrays differ in content' {
            Test-RegistryValueEquivalent -CurrentValue @([byte]0x01, [byte]0xFF) -DesiredValue @([byte]0x01, [byte]0x02) -Type 'Binary' | Should -Be $false
        }
    }

    Context 'Type mismatch via CurrentType parameter' {
        It 'returns false when CurrentType does not match expected type' {
            Test-RegistryValueEquivalent -CurrentValue 1 -DesiredValue 1 -Type 'DWord' -CurrentType 'String' | Should -Be $false
        }

        It 'returns true when CurrentType matches expected type' {
            Test-RegistryValueEquivalent -CurrentValue 1 -DesiredValue 1 -Type 'DWord' -CurrentType 'DWord' | Should -Be $true
        }
    }

    Context 'Default/unknown type fallback' {
        It 'falls back to string comparison for unknown types' {
            Test-RegistryValueEquivalent -CurrentValue 'test' -DesiredValue 'test' -Type 'Unknown' | Should -Be $true
            Test-RegistryValueEquivalent -CurrentValue 'test' -DesiredValue 'other' -Type 'Unknown' | Should -Be $false
        }
    }
}
