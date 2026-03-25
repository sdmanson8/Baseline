# Win10_11Util
PowerShell utility script for Windows 10 / 11.

## Launch

Local:

```powershell
.\run.cmd
```

Direct PowerShell launch:

```powershell
.\Win10_11Util.ps1
```

Noninteractive / headless:

```powershell
.\Win10_11Util.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", "UninstallUWPApps"
```

Interactive session / tab completion:

```powershell
. .\Completion\Interactive.ps1
```

Validate manifest ownership / duplicates:

```powershell
pwsh -File .\Tools\Validate-ManifestData.ps1
```

Download and launch Win10_11Util:

```powershell
iwr https://raw.githubusercontent.com/sdmanson8/Win10_11Util/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex
```

The remote bootstrap downloads the repository archive, extracts it to a temp
folder, and launches the existing `run.cmd` entrypoint.

Layout:

```text
run.cmd         Local launcher
Win10_11Util.ps1  Main launcher and GUI/headless entrypoint
Bootstrap/     Remote bootstrap script
Completion/    Interactive session bootstrap and tab completion
Tools/         Developer validation and maintenance scripts
Assets/        Bundled binaries, icons, and support scripts
Localizations/  Translation strings
Module/        Feature modules, GUI logic, module manifest, and data slices
```
