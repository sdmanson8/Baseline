# DeploymentMediaBuilderDialog.ps1
#
# Guided Windows installation media workflow. This parent keeps the public dot-source entry point stable.
# DeploymentMediaBuilder split rollback checkpoint: re-inline the files below in this fixed order to restore the pre-split module.

. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.Validation.ps1')
. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.Execution.ps1')
. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.Dialog.ps1')
