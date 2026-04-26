# PowerShell module manifest for the Baseline loader module.
@{
    RootModule            = 'Baseline.psm1'
    ModuleVersion         = '3.1.0'
    Author                = 'sdmanson8'
    Description           = 'Module for Windows fine-tuning and automating the routine tasks'
    CompatiblePSEditions  = @('Core', 'Desktop')
    PowerShellVersion     = '5.1'
    ProcessorArchitecture = 'None'
    FunctionsToExport     = '*'
    PrivateData           = @{
        Prerelease = 'beta'
    }
}
