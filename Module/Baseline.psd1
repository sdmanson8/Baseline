# PowerShell module manifest for the Baseline loader module.
@{
    RootModule            = 'Baseline.psm1'
    ModuleVersion         = '2.0.0'
    Author                = 'sdmanson8'
    Description           = 'Module for Windows fine-tuning and automating the routine tasks'
    CompatiblePSEditions  = @('Core', 'Desktop')
    ProcessorArchitecture = 'None'
    FunctionsToExport     = '*'
}
