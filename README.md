# Baseline v3.0.0 (beta)

<p align="center">
  <strong>A modular Windows configuration, compliance, and hardening utility for Windows 10 and Windows 11.</strong>
</p>

<p align="center">
  Baseline provides a manifest-driven PowerShell 5.1 toolkit with a WPF GUI, compliance tracking, audit trails, configuration profiles, presets, and headless execution.
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/ef431953-c31f-4347-b62a-c51e381c5e69" alt="Baseline GUI hero screenshot" width="1072">
</p>

---

## Table of Contents

- [Overview](#overview)
- [Supported platforms](#supported-platforms)
- [Why Baseline is different](#why-baseline-is-different)
- [Key features](#key-features)
- [Presets](#presets)
- [Screenshots](#screenshots)
- [Start Guide](#start-guide)
- [Repository layout](#repository-layout)
- [Developer tooling](#developer-tooling)
- [Quality & Validation](#quality--validation)
- [Known limitations](#known-limitations)
- [FAQ / troubleshooting](#faq--troubleshooting)

## Overview

Baseline is a PowerShell-based utility for configuring, auditing, hardening, and tracking Windows 10 and Windows 11 installations.

It includes:

- a WPF desktop GUI with search, filters, risk labels, preset selection, and per-monitor DPI awareness
- configuration tracking: compliance drift detection, system state snapshots, configuration profiles, and audit trails
- pre-flight checks, plan summary, and visual diff view before any changes are applied
- structured post-run results with per-tweak status, recovery hints, and filter pills
- headless execution for scripted or repeatable runs, including scheduled automation
- multi-machine targeting via PowerShell Remoting (CLI preview, untested on Server)
- modular manifests for tweaks, metadata, and presets
- logging, validation, and metadata tooling for maintainability
- coverage across privacy, telemetry, security, Defender, UI, taskbar, Start menu, OneDrive, UWP apps, networking, gaming, and system behavior

## Supported platforms

<table>
  <tr>
    <td align="center">Windows 10</td>
    <td align="center">Windows 11</td>
  </tr>
  <tr>
    <td align="left"><a href="https://support.microsoft.com/topic/windows-10-update-history-8127c2c6-6edf-4fdf-8b9f-0f7be1ef3562"><img src="https://img.shields.io/badge/Windows%2010%20x64-PowerShell%205.1-green?labelColor=151B23&color=151B23&style=for-the-badge"></a></td>
    <td align="left"><a href="https://support.microsoft.com/topic/windows-11-version-25h2-update-history-99c7f493-df2a-4832-bd2d-6706baa0dec0"><img src="https://img.shields.io/badge/Windows%2011-PowerShell%205.1-green?labelColor=151B23&color=151B23&style=for-the-badge"></a></td>
  </tr>
  <tr>
    <td align="left"><a href="https://support.microsoft.com/topic/windows-10-and-windows-server-2019-update-history-725fc2e1-4443-6831-a5ca-51ff5cbcb059"><img src="https://img.shields.io/badge/Windows%2010-LTSC%202019-green?labelColor=151B23&color=151B23&style=for-the-badge"></a></td>
    <td align="left"><a href="https://support.microsoft.com/topic/windows-11-version-24h2-update-history-0929c747-1815-4543-8461-0160d16f15e5"><img src="https://img.shields.io/badge/Windows%2011-ARM64-green?labelColor=151B23&color=151B23&style=for-the-badge"></a></td>
  </tr>
  <tr>
    <td></td>
    <td align="left"><a href="https://support.microsoft.com/topic/windows-11-version-24h2-update-history-0929c747-1815-4543-8461-0160d16f15e5"><img src="https://img.shields.io/badge/Windows%2011%20LTSC%202024-PowerShell%205.1-green?labelColor=151B23&color=151B23&style=for-the-badge"></a></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="https://img.shields.io/badge/Windows%20Server%202016--2025-Best--effort%2C%20untested-gray?labelColor=151B23&color=151B23&style=for-the-badge"></td>
  </tr>
</table>

## Why Baseline is different

Most Windows tweak repos optimize for either maximum aggression or maximum simplicity. Baseline optimizes for **trust**:

- **Manifest-backed metadata** — every tweak carries risk labels, restart flags, reversibility metadata, and recovery guidance instead of living in opaque script blocks
- **Preview-first execution** — pre-flight checks, plan summary, and visual diff before anything runs
- **Configuration tracking** — compliance drift detection, system state snapshots, configuration profiles, and append-only audit trails
- **Preset semantics** — four named presets with clear scope and honest warnings instead of a single "run everything" button
- **Scenario modes** — purpose-built profiles for Game Mode, Workstation, Privacy, and Recovery that stay separate from the core preset ladder
- **Controlled opinionation** — headless presets, scheduled automation, and logging for repeatable setups instead of one-off script runs

The goal is not to strip Windows as aggressively as possible. The goal is to give power users a controlled, auditable way to apply and track Windows configuration changes over time.

## Presets

Recommended starting point: **Basic**

Safe Mode beginner starting point: **Minimal**

| Preset | Recommended for | Not recommended for | Summary |
| --- | --- | --- | --- |
| Minimal | Safe Mode beginners who want the most conservative first run | Users expecting broader tuning or privacy changes on the first pass | Recommended Safe Mode first step with small quality-of-life and maintenance changes |
| Basic | Most users and shared PCs | Users who want deeper, opinionated changes | Low-risk cleanup and usability improvements |
| Balanced | Enthusiasts who accept moderate tradeoffs | Work, family, or domain-managed PCs | Broader privacy, performance, and system changes |
| Advanced | Experienced users who knowingly accept higher-impact changes | Normal users and managed devices | Expert tuning, debloat, and hardening |

Balanced is the point where a restore point is a good idea. Advanced is the expert preset and should be treated as expert-only.

> Before you run **Advanced**
>
> Create a restore point if you can, review Preview Run carefully, and expect changes to Windows features, update behavior, networking, security, and compatibility.

Baseline ships with four built-in presets:

- **Minimal** — recommended first step in Safe Mode; smallest baseline of practical quality-of-life and maintenance tweaks
- **Basic** — lower-risk usability, privacy, and cleanup recommendations
- **Balanced** — broader privacy, performance, and system configuration changes
- **Advanced** — expert tuning, debloat, and hardening for experienced users

## Warning philosophy

Baseline is intentionally opinionated about when it warns and when it stays conservative.

- `Minimal` and `Basic` are meant to stay out of uninstall/remove and higher-friction hardening territory
- `Balanced` is where privacy, performance, and workflow tradeoffs become more noticeable, so Preview Run and a restore point are recommended
- `Advanced` is not the "best" preset. It is the expert preset for users who knowingly accept higher compatibility and recovery risk
- Risk labels, restart indicators, Preview Run, and restore guidance are part of the product, not decoration

## Key features

- **State tracking and compliance**
  - system state snapshots (pre-run and post-run capture, export, import)
  - portable configuration profiles (export your setup as JSON, reapply later)
  - compliance drift detection with one-click "Fix Drift" remediation
  - append-only audit trail with timeline view and HTML/Markdown export
  - scheduled automation via Windows Scheduled Tasks
  - multi-machine targeting via PowerShell Remoting (CLI preview, untested on Server)

- **UX clarity and safety**
  - automated pre-flight checks (admin, disk space, WMI, VSS, system restore)
  - plan summary panel showing what will change before execution
  - visual diff view (current state vs. planned post-run state)
  - structured post-run results with status filter pills and recovery hints
  - per-monitor DPI awareness for crisp rendering on high-DPI displays

- **Preset-driven configuration**
  - Minimal, Basic, Balanced, Advanced
  - Safe Mode / Expert Mode gating

- **GUI workflow**
  - category tabs with icon headers
  - quick search and multi-filter panel (risk, category, selected-only, gaming-related)
  - risk and impact labels with inline details and rationale
  - Dark and Light theme with session persistence
  - localization with runtime language switching

- **Headless workflow**
  - run individual functions directly
  - automate repeatable configurations with presets
  - dry-run mode for inspecting planned changes
  - compliance checks with JSON profile input

- **Manifest-driven design**
  - tweak metadata stored in JSON (~275 entries across 16 category files)
  - preset definitions stored separately from implementation
  - validation tooling for duplicate entries, missing metadata, and ownership mismatches

- **Scenario modes**
  - Game Mode with Casual, Competitive, Streaming, and Troubleshooting profiles
  - Workstation, Privacy, and Recovery scenario workflows
  - environment-aware recommendation text based on detected hardware and software
  - profile-driven defaults that stay separate from the core preset ladder

- **Operational tooling**
  - file logging with thread-safe Named Mutex protection
  - GUI log forwarding with color-coded viewer
  - bootstrap/launcher support
  - GUI settings import/export, restore snapshot, and single-level undo
  - helper modules for environment, registry, packages, maintenance, taskbar, and error handling

## Screenshots

Windows 10 GUI
<p align="center">
  <img src="https://github.com/user-attachments/assets/1926b16f-8c18-4bf8-a149-a5b3ed2e67a0" alt="Windows 10 GUI" width="1072">
</p>

Windows 10 Non-Interactive
<p align="center">
  <img src="https://github.com/user-attachments/assets/4b21309f-f131-4909-b4c8-3fbe55d41be5" alt="Windows 10 Non-Interactive" width="1072">
</p>

Windows 11 GUI
<p align="center">
  <img src="https://github.com/user-attachments/assets/46dc692e-81ce-4400-a46a-ebb956c8f088" alt="Windows 11 GUI" width="1072">
</p>

Windows 11 Non-Interactive
<p align="center">
  <img src="https://github.com/user-attachments/assets/9fff35f8-a232-4044-b5ee-b831bda7430e" alt="Windows 11 Non-Interactive" width="1072">
</p>

## Start Guide

### Safe Mode beginner start guide

1. Open Baseline
2. Select `Minimal`
3. Click `Preview Run`
4. Click `Apply Tweaks`
5. Restart if prompted

### Local launch (recommended)

```powershell
.\run.cmd
```

### Direct PowerShell launch

```powershell
.\Baseline.ps1
```

> **Note:** If your execution policy blocks unsigned scripts, run `Set-ExecutionPolicy Bypass -Scope Process` first. This restricts the bypass to the current session only.

### Headless / noninteractive run

```powershell
.\Baseline.ps1 -Preset Basic
```
```powershell
.\Baseline.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", "UWPApps -Uninstall"
```
```powershell
.\Baseline.ps1 -GameModeProfile Competitive
```

> **Note:** Headless runs may require `Set-ExecutionPolicy Bypass -Scope Process` if your execution policy blocks unsigned scripts.

### Dry run (preview without applying)

```powershell
.\Baseline.ps1 -Preset Balanced -DryRun
```

### Compliance check

```powershell
.\Baseline.ps1 -ComplianceCheck -ProfilePath .\my-profile.json
```

### Remote targeting (preview)

```powershell
.\Baseline.ps1 -TargetComputer SERVER01,SERVER02 -ComplianceCheck -ProfilePath .\my-profile.json
```

### Remote bootstrap (advanced)

For convenience, you can download and launch directly from GitHub:

```powershell
iwr https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex
```

> **Security note:** This uses pipe-to-IEX with no integrity verification beyond HTTPS/TLS. For higher assurance, download the archive manually, verify the commit hash, and run Baseline.ps1 directly.

### Interactive session / tab completion

```powershell
Set-ExecutionPolicy Bypass -Scope Process; .\Completion\Interactive.ps1
```

Then run commands such as:

```powershell
Baseline -Preset Basic
```
```powershell
Baseline -Preset .\Module\Data\Presets\Minimal.json
```
```powershell
Baseline -GameModeProfile Competitive
```
```powershell
Baseline -ScenarioProfile Privacy
```

To run a preset through the raw bootstrap flow, set `BASELINE_PRESET` first:

```powershell
$env:BASELINE_PRESET = 'Basic'
iwr https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex
```

The bootstrap flow downloads the repository archive, extracts it to a temporary folder, and launches the standard entry point. When `BASELINE_PRESET` is present, the preset is forwarded into the noninteractive runner.

Preview Run lets you inspect every change before it is applied. In Safe Mode, the GUI surfaces `Minimal`, `Apply Tweaks`, and `Undo Selection Change` as the beginner path. Standard mode keeps the existing `Basic`, `Run Tweaks`, and `Restore Snapshot` wording, while Expert Mode keeps `Run Tweaks` but also uses `Undo Selection Change`. Scenario-mode actions for Workstation, Privacy, and Recovery remain available alongside Import Settings and Export Settings. Post-run summaries can also export a rollback profile when direct undo commands are available. That rollback export is separate from `Undo Selection Change` and from restoring Windows defaults.

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
powershell -File .\Tools\Validate-ManifestData.ps1
```

### Add generated metadata to manifests

```powershell
powershell -File .\Tools\Add-MissingMetadata.ps1
```

### Generate preset files from manifest metadata

```powershell
powershell -File .\Tools\Generate-PresetFiles.ps1 -DryRun
```

The generator currently targets the lower-risk preset tiers and is meant to reduce drift between metadata and curated preset files.

### Validate generated preset files

```powershell
powershell -File .\Tools\Test-PresetGeneration.ps1
```

This generates fresh `Minimal`, `Basic`, and `Balanced` preset files and validates them against manifest policy. The same check runs in GitHub Actions alongside validation of the checked-in preset files.

### Build a release zip

```powershell
powershell -File .\Tools\New-ReleasePackage.ps1
```

This creates `dist/Baseline-<version>.zip` with the public release layout and excludes planning files by default.

## Quality & Validation

Baseline includes 29 dedicated test scripts covering:

- **Unit tests**: registry helpers, environment detection, preset resolution, error handling, game mode helpers, package management
- **Contract tests**: manifest structure, tweak metadata, GUI function capture, observable state
- **Smoke tests**: full preset execution, module loading, GUI construction boundaries
- **Fixture tests**: execution summary with clean/partial/retryable/restore scenarios
- **Integration tests**: end-to-end execution on supported Windows editions

Automated CI runs on every push. Desktop-specific tests (WPF rendering, service manipulation, package installation) require a local or self-hosted Windows VM — the tested matrix is documented in Tests/Integration/README.md.

## Known limitations

- **Icon system**: The FluentSystemIcons UI architecture is built, but the GUI currently uses its text-only fallback. The full visual icon rollout will land in an upcoming beta update.
- **Remote deployment**: Multi-machine targeting via `-TargetComputer` is CLI-only; a GUI management panel for remote targets is planned for a future release.

## FAQ / troubleshooting

- Which preset should I start with? In Safe Mode, start with `Minimal` for the most conservative first run. Outside Safe Mode, `Basic` remains the default recommendation for most users.
- When should I use `Advanced`? Only after reviewing Preview Run and only when you are comfortable with feature removals, harder-to-reverse changes, and manual recovery if something conflicts with your setup.
- A tweak failed. What should I try first? Re-run Baseline as administrator, reboot, review the Preview Run output, and check the detailed log before retrying.
- Can Baseline automatically undo everything? No. Some changes expose direct undo commands, some only return to supported Windows defaults, and some still rely on restore points or manual recovery. Uninstall/remove actions deserve extra care.
- How do I run a compliance check? Export a configuration profile from the GUI (or create one from a preset via the CLI), then run `.\Baseline.ps1 -ComplianceCheck -ProfilePath .\profile.json`.

## Disclaimer / support scope

- Baseline is intended for the supported Windows versions listed above and for users with local admin control over the device.
- Review changes before applying them. Baseline is a configuration utility, not a risk-free cleanup button.
- Create a restore point or backup before `Balanced`, `Advanced`, large app removal, or unfamiliar changes.
- Managed, work, school, or domain-enrolled devices should be reviewed with the appropriate admin team before use.
- Third-party security suites, OEM utilities, and heavily customized images can change outcomes and may require manual troubleshooting.

## Notes

- Baseline is intended for users who want explicit control over Windows behavior.
- Some tweaks may require administrator rights.
- Some tweaks may require a restart to fully apply.
- Higher-risk and advanced changes should be reviewed carefully before use.

## License

See the repository license file for licensing information.
