# Integration Tests

## Purpose

VM-based integration tests validate that Baseline actually works on real Windows
installations. Unlike unit tests (which extract functions via AST and test pure
logic) and smoke tests (which validate structural invariants), integration tests
execute real tweak functions against a live OS and verify that the system state
changes as expected.

## Test Matrix

| OS                    | Edition  | Runner / Image        | Status      |
|-----------------------|----------|-----------------------|-------------|
| Windows 11 24H2       | Pro      | Local desktop         | **Validated** (2026-04-04) |
| Windows 10 22H2       | —        | Self-hosted or local  | Planned     |
| Windows 11 23H2       | —        | Self-hosted or local  | Planned     |
| Windows Server 2022   | —        | `windows-2022`        | CI only     |

**Validated results** are archived in `Tests/Integration/DesktopMatrixResults.json`.

GitHub-hosted runners only provide Server SKUs. Desktop SKUs (Win 10/11)
require self-hosted runners or local execution inside a VM.

### Windows 11 Pro (Build 26100) — Validated 2026-04-04

| Layer                      | Passed | Failed | Skipped | Notes                                    |
|----------------------------|--------|--------|---------|------------------------------------------|
| Smoke tests                | 147    | 1      | 1       | Manifest validation: expected W-4 warning |
| Unit tests (Pester, PS5.1) | 1886   | 8      | 4       | 8 pre-existing failures (PS 5.1 edition) |
| Composition tests (PS5.1)  | 23     | 0      | 0       | Full pass on Desktop edition             |
| Responsive tab/dropdown    | 24     | 0      | 0       | Full pass                                |
| Preset generation          | Pass   | —      | —       | Golden-file match                        |

## Test Categories

| Category      | What it validates                                           |
|---------------|-------------------------------------------------------------|
| Registry      | Apply a toggle, verify the registry value, undo, verify restored |
| Services      | Disable a service, verify stopped, restore, verify running  |
| Packages      | Remove a safe UWP app, verify absent (skipped in DryRun)   |
| GroupPolicy   | Apply a Baseline policy-backed setting, verify, restore              |
| GameMode      | Verify Game Bar, CPU priority, DirectX flip model, and GPU scheduling writes, then restore |

## Prerequisites

1. **Administrator privileges** -- nearly all Baseline functions require elevation.
2. **Clean VM snapshot** -- tests should start from a known-good state.
3. **Restore after each test** -- the runner script creates a system restore point
   before testing and can revert afterward.
4. **Pester 5+** -- used for assertion syntax where applicable.
5. **No production machines** -- these tests modify real system state. Only run
   inside disposable VMs.

## Running Locally

```powershell
# Run all categories (requires admin, real Windows VM)
powershell -File ./Tests/Integration/IntegrationTest.ps1

# Run only registry tests
powershell -File ./Tests/Integration/IntegrationTest.ps1 -Category Registry

# Dry-run mode (skips destructive package operations)
powershell -File ./Tests/Integration/IntegrationTest.ps1 -DryRun

# Run the focused registry tweak test
powershell -File ./Tests/Integration/Test-RegistryTweak.ps1 -FunctionName FileExtensions -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ValueName HideFileExt -ApplyParam Show -ExpectedValue 0 -UndoParam Hide -UndoExpectedValue 1
```

## CI Integration

The workflow `.github/workflows/integration.yml` is configured for manual
dispatch only (`workflow_dispatch`) with three parallel jobs:

| Job              | Runner labels                                        | Status                |
|------------------|------------------------------------------------------|-----------------------|
| `server-2022`    | `windows-2022` (GitHub-hosted)                       | Active                |
| `win10-22h2`     | `[self-hosted, windows, desktop, win10-22h2]`        | Needs runner provisioning |
| `win11-23h2`     | `[self-hosted, windows, desktop, win11-23h2]`        | Needs runner provisioning |

### Self-hosted runner provisioning

Desktop-SKU jobs remain queued until a repo admin registers at least one
self-hosted runner with the matching label set. To provision:

1. On a clean Windows 10 22H2 or Windows 11 23H2 VM, run the runner installer
   from `Settings → Actions → Runners → New self-hosted runner`.
2. When prompted for labels, include **all four** of:
   `self-hosted`, `windows`, `desktop`, and the SKU label
   (`win10-22h2` or `win11-23h2`).
3. Configure the runner to run as a service with administrator privileges
   (Baseline tweaks require elevation).
4. Ensure the VM snapshot is restored between runs — the integration suite
   modifies real system state.

Once at least one matching runner is online and `idle`, dispatching the
workflow automatically routes the desktop-SKU jobs to it. The GitHub-hosted
`server-2022` job is unaffected by runner availability.
