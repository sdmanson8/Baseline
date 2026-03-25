# Baseline

<p align="center">
  <strong>A modular Windows debloater, optimizer, and hardening utility for Windows 10, Windows 11, and Windows Server.</strong>
</p>

<p align="center">
  Baseline provides a manifest-driven PowerShell 5.1 toolkit with a GUI, presets, logging, validation, and headless execution.
</p>

---

## Overview

Baseline is a PowerShell-based utility for configuring, debloating, tuning, and hardening supported Windows installations.

It includes:

- a desktop GUI with search, filters, risk labels, and preset selection
- headless execution for scripted or repeatable runs
- modular manifests for tweaks, metadata, and presets
- logging, validation, and metadata tooling for maintainability
- coverage across privacy, telemetry, security, Defender, UI, taskbar, Start menu, OneDrive, UWP apps, networking, gaming, and system behavior

## Supported operating systems

Baseline supports **PowerShell 5.1** on:

- **Windows 10**: 2019 to current, **x86 / x64 / ARM64**
- **Windows 11**: current, **x64 / ARM64**
- **Windows Server**: **2016 through 2025**

## Key features

- **Preset-driven configuration**
  - Minimal
  - Safe
  - Balanced
  - Aggressive

- **GUI workflow**
  - category tabs
  - quick search
  - risk and impact labels
  - inline details and rationale
  - preview-before-run flow

- **Headless workflow**
  - run individual functions directly
  - automate repeatable configurations
  - use presets as a baseline for unattended setups

- **Manifest-driven design**
  - tweak metadata stored in JSON
  - preset definitions stored separately from implementation
  - validation tooling for duplicate entries, missing metadata, and ownership mismatches

- **Operational tooling**
  - file logging
  - GUI log forwarding
  - bootstrap/launcher support
  - helper modules for environment, registry, packages, maintenance, taskbar, and error handling

## Screenshots

Windows 10
<p align="center">
  <img src="https://github.com/user-attachments/assets/0a17d0bb-d6e2-4a39-b1c7-d44edf4bc2ba" alt="Windows 10 GUI" width="1072">
</p>

Windows 11
<p align="center">
  <img src="https://github.com/user-attachments/assets/b44c5b14-8e95-46a9-aae3-50adfb3df7de" alt="Windows 11 GUI" width="1072">
</p>

## Getting started

### Local launch

```powershell
.\run.cmd
```

### Direct PowerShell launch

```powershell
.\Baseline.ps1
```

### Headless / noninteractive run

```powershell
.\Baseline.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", "UninstallUWPApps"
```

### Interactive session / tab completion

```powershell
. .\Completion\Interactive.ps1
```

## Remote bootstrap

```powershell
iwr https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex
```

The bootstrap flow downloads the repository archive, extracts it to a temporary folder, and launches the standard entry point.

## Presets

Baseline ships with four built-in presets:

- **Minimal** — smallest baseline of practical quality-of-life and maintenance tweaks
- **Safe** — lower-risk usability, privacy, and cleanup recommendations
- **Balanced** — broader privacy, performance, and system configuration changes
- **Aggressive** — advanced tuning, debloat, and hardening for experienced users

## Repository layout

```text
run.cmd             Local launcher
Baseline.ps1    Main launcher and GUI/headless entry point
Bootstrap/          Remote bootstrap script
Completion/         Interactive session bootstrap and tab completion
Tools/              Validation and maintenance scripts
Assets/             Bundled binaries, icons, and support scripts
Localizations/      Translation strings
Module/             Feature modules, GUI logic, manifests, and data slices
```

## Developer tooling

### Validate manifest ownership / duplicates

```powershell
pwsh -File .\Tools\Validate-ManifestData.ps1
```

### Add generated metadata to manifests

```powershell
pwsh -File .\Tools\Add-MissingMetadata.ps1
```

## Notes

- Baseline is intended for users who want explicit control over Windows behavior.
- Some tweaks may require administrator rights.
- Some tweaks may require a restart to fully apply.
- Higher-risk and advanced changes should be reviewed carefully before use.

## License

See the repository license file for licensing information.
