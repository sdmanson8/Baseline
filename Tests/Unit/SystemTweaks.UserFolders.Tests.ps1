Set-StrictMode -Version Latest

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script:ModulePath = Join-Path $script:RepoRoot 'Module/Regions/SystemTweaks/UserFolders.psm1'
$script:ModuleUnderTest = Import-Module -Force -DisableNameChecking -PassThru $script:ModulePath

InModuleScope $script:ModuleUnderTest {
    Describe 'SystemTweaks.UserFolders' {
        BeforeAll {
        foreach ($name in @('Write-ConsoleStatus', 'LogInfo', 'LogWarning', 'LogError'))
        {
            if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue))
            {
                function global:Write-ConsoleStatus { param([string]$Action, [string]$Status) }
                function global:LogInfo { param([string]$Message) }
                function global:LogWarning { param([string]$Message) }
                function global:LogError { param([string]$Message) }
                break
            }
        }

        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineUserFolders_' + [Guid]::NewGuid().ToString('N'))
        $script:SourceRoot = Join-Path $script:TempRoot 'Source'
        $script:DestinationRoot = Join-Path $script:TempRoot 'Destination'
        $script:DefaultRoot = Join-Path $script:TempRoot 'Default'
        New-Item -ItemType Directory -Path $script:SourceRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:DestinationRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:DefaultRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $script:SourceRoot 'notes.txt') -Value 'source file' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:SourceRoot 'desktop.ini') -Value 'old desktop ini' -Encoding UTF8
    }

        AfterAll {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot))
        {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

        BeforeEach {
        $script:CallOrder = New-Object 'System.Collections.Generic.List[string]'

        Mock -CommandName Write-ConsoleStatus -MockWith { }
        Mock -CommandName LogInfo -MockWith { }
        Mock -CommandName LogWarning -MockWith { }
        Mock -CommandName LogError -MockWith { }
        Mock -CommandName Get-BaselineUserFolderDefinition -MockWith {
            [pscustomobject]@{
                Folder         = 'Documents'
                DisplayName    = 'Documents'
                RegistryName   = 'Personal'
                GuidName       = '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'
                ShellNamespace = 'shell:Personal'
                DefaultPath    = $script:DefaultRoot
            }
        }
        Mock -CommandName Get-BaselineUserFolderCurrentPath -MockWith { $script:SourceRoot }
        Mock -CommandName Test-BaselineUserFolderDestination -MockWith { $true }
        Mock -CommandName Invoke-BaselineUserFolderKnownFolderRedirect -MockWith { $false }
        Mock -CommandName Move-Item -MockWith {
            [void]$script:CallOrder.Add(("MoveItem:{0}" -f $LiteralPath))
            $targetPath = Join-Path $Destination (Split-Path -Path $LiteralPath -Leaf)
            [System.IO.File]::Move($LiteralPath, $targetPath)
        }
        Mock -CommandName Set-RegistryValueSafe -MockWith {
            [void]$script:CallOrder.Add(("Registry:{0}" -f $Name))
            return $null
        }
    }

        Describe 'Get-BaselineUserFolderDefinitions' {
            It 'returns the six default user folders' {
                $defs = @(Get-BaselineUserFolderDefinitions)
                @($defs.Folder) | Should -Be @('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
            }
        }

        Describe 'Set-BaselineUserFolderLocation' {
            It 'moves existing files before the registry redirect on a custom path' {
                $result = Set-BaselineUserFolderLocation -Folder Documents -Path $script:DestinationRoot

                $result.Folder | Should -Be 'Documents'
                Test-Path -LiteralPath (Join-Path $script:DestinationRoot 'notes.txt') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $script:SourceRoot 'notes.txt') | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $script:DestinationRoot 'desktop.ini') | Should -BeTrue

                $joinedOrder = ($script:CallOrder -join '|')
                $joinedOrder | Should -Match 'MoveItem'
                $joinedOrder | Should -Match 'Registry:Personal'
                ($joinedOrder.IndexOf('MoveItem')) | Should -BeLessThan ($joinedOrder.IndexOf('Registry:Personal'))
            }

            It 'restores the default path without moving files back' {
                $result = Set-BaselineUserFolderLocation -Folder Documents -Default

                $result.Mode | Should -Be 'Default'
                ($script:CallOrder -join '|') | Should -Not -Match 'MoveItem'
                $script:CallOrder | Should -Contain 'Registry:Personal'
                $script:CallOrder | Should -Contain 'Registry:{F42EE2D3-909F-4907-8871-4C22FC0BF756}'
            }

            It 'fails fast when the destination drive is removable' {
                Mock -CommandName Test-BaselineUserFolderDestination -MockWith { $false }

                { Set-BaselineUserFolderLocation -Folder Documents -Path 'D:\Users\Test\Documents' } | Should -Throw
            }
        }
    }
}
