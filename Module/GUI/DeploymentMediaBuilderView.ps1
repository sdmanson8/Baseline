# DeploymentMediaBuilderView.ps1
#
# Inline Deployment Media Builder view. This parent keeps the public dot-source entry point stable.
# DeploymentMediaBuilder split rollback checkpoint: re-inline the files below in this fixed order to restore the pre-split module.

. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.UI.ps1')
. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.Unattend.ps1')
. (Join-Path $PSScriptRoot 'DeploymentMediaBuilder/DeploymentMediaBuilder.Events.ps1')
