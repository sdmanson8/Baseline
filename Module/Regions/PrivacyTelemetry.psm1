using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

$subModuleRoot = Join-Path $PSScriptRoot 'PrivacyTelemetry'
if (Test-Path $subModuleRoot)
{
    foreach ($subModule in (Get-ChildItem -Path $subModuleRoot -Filter '*.psm1' -File))
    {
        Import-Module $subModule.FullName -Force -Global
    }
}

Export-ModuleMember -Function '*'
