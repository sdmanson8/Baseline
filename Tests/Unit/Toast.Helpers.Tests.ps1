Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Toast.Helpers.ps1'
    . $filePath
}

Describe 'New-BaselineToastXml' {
    It 'produces a well-formed ToastGeneric document with title and body' {
        $xml = New-BaselineToastXml -Title 'Cleanup' -Body 'Run cleanup now?'

        $doc = [xml]$xml
        $doc.toast.visual.binding.template | Should -Be 'ToastGeneric'
        # Title is the first <text> child of <binding>; body lives in subgroup.
        $doc.toast.visual.binding.text | Should -Be 'Cleanup'
        $doc.toast.visual.binding.group.subgroup.text.'#text' | Should -Be 'Run cleanup now?'
        $doc.toast.visual.binding.group.subgroup.text.'hint-style' | Should -Be 'body'
        $doc.toast.visual.binding.group.subgroup.text.'hint-wrap' | Should -Be 'true'
    }

    It 'defaults to long duration and the standard notification audio' {
        $xml = New-BaselineToastXml -Title 'T' -Body 'B'

        $doc = [xml]$xml
        $doc.toast.duration | Should -Be 'Long'
        $doc.toast.audio.src | Should -Be 'ms-winsoundevent:notification.default'
    }

    It 'omits the actions element when no action label/protocol is supplied' {
        $xml = New-BaselineToastXml -Title 'T' -Body 'B'

        $doc = [xml]$xml
        # PSObject property absence check — actions node should not exist.
        $doc.toast.PSObject.Properties.Name | Should -Not -Contain 'actions'
    }

    It 'emits Run + dismiss actions when label and protocol are supplied' {
        $xml = New-BaselineToastXml -Title 'T' -Body 'B' -ActionLabel 'Run' -ActionProtocol 'WindowsCleanup'

        $doc = [xml]$xml
        $actions = @($doc.toast.actions.action)
        $actions.Count | Should -Be 2

        $actions[0].content | Should -Be 'Run'
        $actions[0].arguments | Should -Be 'WindowsCleanup:'
        $actions[0].activationType | Should -Be 'protocol'

        $actions[1].arguments | Should -Be 'dismiss'
        $actions[1].activationType | Should -Be 'system'
    }

    It 'preserves a trailing colon already present on the protocol argument' {
        $xml = New-BaselineToastXml -Title 'T' -Body 'B' -ActionLabel 'Run' -ActionProtocol 'WindowsCleanup:'

        $doc = [xml]$xml
        # Should be exactly one colon — not "WindowsCleanup::".
        $doc.toast.actions.action[0].arguments | Should -Be 'WindowsCleanup:'
    }

    It 'XML-escapes special characters in title and body' {
        $xml = New-BaselineToastXml -Title 'A & B <ok>' -Body '"quote" & ampersand'

        $doc = [xml]$xml
        $doc.toast.visual.binding.text | Should -Be 'A & B <ok>'
        $doc.toast.visual.binding.group.subgroup.text.'#text' | Should -Be '"quote" & ampersand'
        # Confirm escape happened in the raw XML, not just the parsed view.
        $xml | Should -Match '&amp;'
        $xml | Should -Match '&lt;ok&gt;'
    }

    It 'honours an explicit Short duration override' {
        $xml = New-BaselineToastXml -Title 'T' -Body 'B' -Duration 'Short'
        ([xml]$xml).toast.duration | Should -Be 'Short'
    }
}

Describe 'Test-BaselineToastRuntimeAvailable' {
    It 'returns a boolean without throwing on any host' {
        # We do not assert true/false because availability depends on the
        # host: Server Core, GitHub Actions Linux runners, etc. The contract
        # is graceful behavior, not the value.
        $result = Test-BaselineToastRuntimeAvailable
        $result | Should -BeOfType ([bool])
    }
}

Describe 'Send-BaselineToastXml' {
    It 'returns $false when the toast runtime is unavailable, without throwing' {
        # Override Test-BaselineToastRuntimeAvailable inside the loaded
        # script scope so Send-BaselineToastXml takes the unavailable path
        # regardless of host capability.
        function Test-BaselineToastRuntimeAvailable { return $false }

        try
        {
            $result = Send-BaselineToastXml -Xml '<toast/>' -AppId 'Baseline.Test'
            $result | Should -BeFalse
        }
        finally
        {
            Remove-Item -Path Function:\Test-BaselineToastRuntimeAvailable -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Register-BaselineToastApp' {
    BeforeEach {
        $script:registryWrites = [System.Collections.Generic.List[object]]::new()
        $script:registryItems = [System.Collections.Generic.HashSet[string]]::new()

        function Test-Path {
            param([Parameter(ValueFromPipeline)][string]$Path, [string]$LiteralPath)
            $candidate = if ($Path) { $Path } else { $LiteralPath }
            return $script:registryItems.Contains($candidate)
        }

        function New-Item {
            param([string]$Path, [string]$ItemType, [switch]$Force)
            [void]$script:registryItems.Add($Path)
            return [pscustomobject]@{ Path = $Path }
        }

        function New-ItemProperty {
            param(
                [string]$Path,
                [string]$Name,
                [object]$Value,
                [string]$PropertyType,
                [switch]$Force
            )
            [void]$script:registryWrites.Add([pscustomobject]@{
                Path = $Path
                Name = $Name
                Value = $Value
                PropertyType = $PropertyType
            })
            return [pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value }
        }

        function Remove-Item {
            param([string]$Path, [switch]$Recurse, [switch]$Force, [string]$ErrorAction)
            [void]$script:registryItems.Remove($Path)
        }
    }

    AfterEach {
        foreach ($name in @('Test-Path', 'New-Item', 'New-ItemProperty', 'Remove-Item'))
        {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It 'writes DisplayName and ShowInSettings under HKCR\AppUserModelId\<AppId>' {
        Register-BaselineToastApp -AppId 'Baseline.Test' -DisplayName 'Baseline Test'

        $expectedKey = 'Registry::HKEY_CLASSES_ROOT\AppUserModelId\Baseline.Test'
        $writes = @($script:registryWrites | Where-Object { $_.Path -eq $expectedKey })
        $writes.Name | Should -Contain 'DisplayName'
        $writes.Name | Should -Contain 'ShowInSettings'

        ($writes | Where-Object Name -eq 'DisplayName').Value | Should -Be 'Baseline Test'
        ($writes | Where-Object Name -eq 'ShowInSettings').Value | Should -Be 0
    }

    It 'sets ShowInSettings to 1 when -ShowInSettings:$true is passed' {
        Register-BaselineToastApp -AppId 'Baseline.Test' -DisplayName 'Baseline Test' -ShowInSettings $true

        $write = $script:registryWrites | Where-Object { $_.Name -eq 'ShowInSettings' }
        $write.Value | Should -Be 1
    }

    It 'registers a URL protocol when -ProtocolName and -ProtocolCommand are supplied' {
        Register-BaselineToastApp -AppId 'Baseline.Test' -DisplayName 'Baseline Test' `
            -ProtocolName 'BaselineCleanup' -ProtocolCommand 'powershell.exe -Command "echo hi"'

        $protocolKey = 'Registry::HKEY_CLASSES_ROOT\BaselineCleanup'
        $commandKey = 'Registry::HKEY_CLASSES_ROOT\BaselineCleanup\shell\open\command'

        $protocolWrites = @($script:registryWrites | Where-Object { $_.Path -eq $protocolKey })
        $protocolWrites.Name | Should -Contain '(default)'
        $protocolWrites.Name | Should -Contain 'URL Protocol'
        $protocolWrites.Name | Should -Contain 'EditFlags'
        ($protocolWrites | Where-Object Name -eq '(default)').Value | Should -Be 'URL:BaselineCleanup'
        ($protocolWrites | Where-Object Name -eq 'EditFlags').Value | Should -Be 2162688

        $commandWrite = $script:registryWrites | Where-Object { $_.Path -eq $commandKey -and $_.Name -eq '(default)' }
        $commandWrite.Value | Should -Be 'powershell.exe -Command "echo hi"'
    }

    It 'skips protocol registration when only ProtocolName is supplied (no command)' {
        Register-BaselineToastApp -AppId 'Baseline.Test' -DisplayName 'Baseline Test' -ProtocolName 'X'

        $protocolKey = 'Registry::HKEY_CLASSES_ROOT\X'
        $protocolWrites = @($script:registryWrites | Where-Object { $_.Path -eq $protocolKey })
        $protocolWrites.Count | Should -Be 0
    }
}

Describe 'Unregister-BaselineToastApp' {
    BeforeEach {
        $script:registryItems = [System.Collections.Generic.HashSet[string]]::new()
        $script:removedPaths = [System.Collections.Generic.List[string]]::new()

        function Test-Path {
            param([string]$Path, [string]$LiteralPath)
            $candidate = if ($Path) { $Path } else { $LiteralPath }
            return $script:registryItems.Contains($candidate)
        }

        function Remove-Item {
            param([string]$Path, [switch]$Recurse, [switch]$Force, [string]$ErrorAction)
            [void]$script:removedPaths.Add($Path)
            [void]$script:registryItems.Remove($Path)
        }
    }

    AfterEach {
        foreach ($name in @('Test-Path', 'Remove-Item'))
        {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It 'removes the AppId key when it exists' {
        $appKey = 'Registry::HKEY_CLASSES_ROOT\AppUserModelId\Baseline.Test'
        [void]$script:registryItems.Add($appKey)

        Unregister-BaselineToastApp -AppId 'Baseline.Test'

        $script:removedPaths | Should -Contain $appKey
    }

    It 'is a no-op when the AppId key does not exist' {
        Unregister-BaselineToastApp -AppId 'Baseline.NotPresent'
        $script:removedPaths.Count | Should -Be 0
    }

    It 'also removes the protocol key when -ProtocolName is supplied' {
        $appKey = 'Registry::HKEY_CLASSES_ROOT\AppUserModelId\Baseline.Test'
        $protocolKey = 'Registry::HKEY_CLASSES_ROOT\BaselineCleanup'
        [void]$script:registryItems.Add($appKey)
        [void]$script:registryItems.Add($protocolKey)

        Unregister-BaselineToastApp -AppId 'Baseline.Test' -ProtocolName 'BaselineCleanup'

        $script:removedPaths | Should -Contain $appKey
        $script:removedPaths | Should -Contain $protocolKey
    }
}
