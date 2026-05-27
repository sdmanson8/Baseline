# Baseline v1.0.0

<p align="center">
  <a href="https://github.com/sdmanson8/Baseline_dev/releases/latest">
    <kbd>
      <img alt="Download Beta Release" src="https://img.shields.io/badge/Download%20Beta%20Release-151B23?style=for-the-badge&labelColor=151B23">
    </kbd>
  </a>
  &nbsp;
  <a href="https://github.com/sdmanson8/Baseline/releases/latest">
    <kbd>
      <img alt="Download Stable Release" src="https://img.shields.io/badge/Download%20Stable%20Release-151B23?style=for-the-badge&labelColor=151B23">
    </kbd>
  </a>
</p>

<p align="center">
  Preview-first Windows configuration, optimization, update management, and deployment tooling for Windows 10 and Windows 11.
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/ef431953-c31f-4347-b62a-c51e381c5e69" alt="Baseline GUI hero screenshot" width="1072">
</p>

---

## Table of Contents

- [What is Baseline?](#what-is-baseline)
- [Supported platforms](#supported-platforms)
- [Why Baseline is different](#why-baseline-is-different)
- [Presets](#presets)
- [Key features](#key-features)
- [Screenshots](#screenshots)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Command-line examples](#command-line-examples)
- [GUI modes](#gui-modes)
- [Advanced usage](#advanced-usage)
- [Quality & validation](#quality--validation)
- [Known limitations](#known-limitations)
- [FAQ](#faq)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## What is Baseline?

Baseline is a PowerShell-based Windows utility focused on transparency, safety, and repeatable configuration.

Instead of running opaque tweak bundles, Baseline shows:
- what will change
- what risk level applies
- whether a restart is required
- how recovery works where possible

Baseline includes:
- a modern WPF GUI
- manifest-backed tweak metadata
- preset-driven workflows
- Preview Run planning
- Windows Update management
- gaming profiles
- software management
- Windows setup media tooling
- headless automation support

---

## Supported platforms

| Platform | Status |
|---|---|
| Windows 10 x64 | Supported |
| Windows 11 | Supported |
| Windows 11 ARM64 | Supported |
| Windows 10 LTSC 2019 | Supported |
| Windows 11 LTSC 2024 | Supported |
| Windows Server 2016–2025 | Best effort / untested |

PowerShell 5.1 is required.

---

## Why Baseline is different

Most Windows tweak tools expose little or no metadata about what they change.

Baseline is designed differently:

- **Preview-first execution** — review planned changes before applying them
- **Manifest-backed tweaks** — risk labels, restart requirements, reversibility, and recovery guidance are stored as metadata
- **Preset semantics** — `Minimal`, `Basic`, `Balanced`, and `Advanced` are intentionally scoped instead of acting as a single “run everything” button
- **Structured results** — execution summaries, logs, and recovery hints remain visible after runs
- **Separated workflows** — optimization, gaming, updates, apps, and deployment remain isolated instead of mixed together
- **Headless support** — automation and scripted deployment are supported without the GUI

---

## Presets

Recommended starting point: **Basic**

Safe Mode beginner starting point: **Minimal**

| Preset | Intended for | Summary |
|---|---|---|
| Minimal | Safe Mode beginners | Conservative maintenance and quality-of-life changes |
| Basic | Most users | Lower-risk cleanup, usability, and privacy improvements |
| Balanced | Enthusiasts | Broader privacy, performance, and configuration changes |
| Advanced | Experienced users only | Higher-impact tuning, debloat, and hardening |

> `Advanced` is not the “best” preset. It is the expert preset and should only be used by users who understand the compatibility and recovery tradeoffs involved.

---

## Key features

### Preview-first workflow
- pre-flight validation
- plan summary
- visual preview
- structured post-run results

### GUI experience
- Optimize mode
- Gaming mode
- Windows Updates mode
- Windows Setup Builder
- Software & Apps management
- search and filters
- Light/Dark/System themes
- runtime language switching

### Configuration tracking
- configuration profiles
- snapshots
- audit logs
- compliance checks
- recovery guidance

### Gaming workflows
- Casual
- Competitive
- Streaming / Content
- Troubleshooting

### Windows setup tooling
- ISO edition detection
- deployment plan preview
- ISO / USB / folder output
- build reporting

### Automation support
- headless execution
- preset automation
- profile application
- compliance verification
- dry-run support

---

## Screenshots

### Windows 10 GUI

<p align="center">
  <img src="https://github.com/user-attachments/assets/1926b16f-8c18-4bf8-a149-a5b3ed2e67a0" alt="Windows 10 GUI" width="1072">
</p>

### Windows 11 GUI

<p align="center">
  <img src="https://github.com/user-attachments/assets/46dc692e-81ce-4400-a46a-ebb956c8f088" alt="Windows 11 GUI" width="1072">
</p>

---

## Installation

Download the latest release from GitHub Releases.

### Stable releases
- `Baseline-<version>-stable.zip`

The archive contains:
- `Baseline-<version>-setup.exe`

Current stable releases are unsigned, so Windows SmartScreen may display a warning on first launch.

To continue:
1. Click **More info**
2. Click **Run anyway**

Optional SHA-256 verification:

```powershell
Get-FileHash .\Baseline-<version>.zip -Algorithm SHA256
```

---

## Quick start

### Beginner workflow

1. Launch Baseline
2. Select `Minimal` or `Basic`
3. Click `Preview Run`
4. Review planned changes
5. Click `Apply Tweaks`
6. Restart if prompted

---

## Command-line examples

### Launch GUI

```powershell
.\Baseline.exe
```

### Apply preset

```powershell
.\Baseline.exe -Preset Basic
```

### Dry run

```powershell
.\Baseline.exe -Preset Balanced -DryRun
```

### Apply configuration profile

```powershell
.\Baseline.exe -ProfilePath .\baseline-profile.json
```

### Export a first-logon command for autounattend

Export a configuration profile from the GUI, then use the first-logon command export to create a `FirstLogonCommands` XML snippet. The generated command runs `Baseline.exe --configfile "<profile.json>" --apply` during Windows setup first logon.

### Compliance check

```powershell
.\Baseline.exe -ComplianceCheck -ProfilePath .\baseline-profile.json
```

### Interactive console mode

```powershell
.\Baseline.exe -ConsoleGui
```

---

## GUI modes

| Mode | Purpose |
|---|---|
| Optimize | Privacy, UI, system behavior, apps, and configuration workflows |
| Gaming | Gaming-focused tuning and gaming profiles |
| Windows Updates | Windows Update controls and repair actions |
| Windows Setup Builder | ISO and deployment-media workflows |
| Software & Apps | Package management through WinGet and Chocolatey |

---

## Advanced usage

Additional documentation is available in:
- `docs/Automation.md`
- `docs/Remoting.md`
- `docs/CLI.md`
- `docs/MediaBuilder.md`
- `docs/DeveloperGuide.md`

Developer notes are available in:
- `dev_docs/MODELS.md`
- `dev_docs/STATE.md`
- `dev_docs/Roadmap.md`
- `dev_docs/RuntimeCache.md`

---

## Quality & validation

Baseline includes:
- unit tests
- manifest validation
- preset validation
- contract tests
- smoke tests
- integration testing
- GitHub Actions CI validation

Desktop-specific validation is performed on real Windows environments where required.

---

## Known limitations

- Remote execution is advanced/experimental and should not be treated as a replacement for enterprise device-management tooling.
- Managed or domain-enrolled systems may enforce policies that override Baseline behavior.
- Some changes may still require restore points or manual recovery.

---

## FAQ

### Which preset should I start with?

`Basic` is recommended for most users. In Safe Mode, start with `Minimal`.

### Should I use `Advanced`?

Only if you understand the compatibility, hardening, and recovery implications involved.

### Can Baseline automatically undo everything?

No. Some actions are reversible, some restore Windows defaults, and some may require manual recovery or restore points.

### Does Baseline support unattended automation?

Yes. Presets, profiles, dry-runs, and compliance checks all support headless execution.

---

## Disclaimer

- Review changes before applying them.
- Create a restore point before higher-impact changes.
- Work, school, domain, or MDM-managed devices should be reviewed with the appropriate administrator before use.
- Third-party security suites and OEM modifications may affect behavior.

---

## License

See the repository license file for licensing information.
