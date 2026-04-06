using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

$subModuleRoot = Join-Path $PSScriptRoot 'OSHardening'
if (Test-Path $subModuleRoot)
{
    foreach ($subModule in (Get-ChildItem -Path $subModuleRoot -Filter '*.psm1' -File))
    {
        Import-Module $subModule.FullName -Force -Global
    }
}

#region OS Hardening

# --- Reversal coverage ---
# Most functions in this file apply one-way hardening (Disable-*, Update-*, Protect-*).
# Only Disable-RemoteCommands and Update-Protocols have been converted to Toggle
# functions with -Enable/-Disable parameters. The remaining ~24 functions have no
# built-in reversal because:
#   1. Many settings (cipher suites, key exchanges, hash algorithms) have no single
#      "default" - the correct value depends on the Windows build and edition.
#   2. Reversing STIG-style hardening requires knowing the pre-change state, which
#      is not captured today (restore-point is the recommended safety net).
#   3. The manifest marks these as RecoveryLevel = 'Manual' or 'RestorePoint',
#      and the execution summary surfaces this to the user.
# Future: capture pre-change registry snapshots per-function for targeted rollback.

#endregion OS Hardening

Export-ModuleMember -Function '*'
