# Test Strategy

## Unit Tests (`Tests/Unit/`)

Pester-based tests that extract inner functions via AST and test pure logic
without importing the full module graph or requiring a Windows environment.

Current coverage spans SharedHelpers, GUI extracted files, and region modules
(37 test files). Tests typically use `[System.Management.Automation.Language.Parser]`
to extract individual functions from source files and execute them in isolation.

Run locally: `Invoke-Pester ./Tests/Unit -Output Detailed`

### Contract Tests

Tests that validate structural invariants of the codebase at the function level:

- `ManifestContract.Tests.ps1` — validates manifest data schemas and field
  constraints against the actual JSON files.
- `GuiFunctionCapture.Tests.ps1` — verifies that late-bind `$Script:` captures
  in `GUI.psm1` match the functions they are intended to reference.
- `GuiLayoutInitialization.Tests.ps1` — validates GUI layout construction
  patterns.

### Fixture Tests (`Tests/Fixtures/`)

Data-driven tests that validate pure-logic functions against known-good
input/output pairs stored as JSON fixtures:

- `Tests/Fixtures/ExecutionSummary/` — fixtures for execution summary
  classification: `CleanSuccess.json`, `PartialFailure.json`,
  `GameModeRun.json`, `RestoreDefaults.json`.

Fixtures decouple test data from test logic, making it easier to add regression
cases without modifying test code.

## Smoke Tests (`Tools/Test-SmokeTest.ps1`)

Validates structural invariants: manifest integrity, preset ladder superset
property, data file schema, and cross-module boundary contracts. Runs in CI
on every push/PR.

## Preset Validation (`Tools/Test-PresetGeneration.ps1`)

Regenerates the low-risk preset files (Minimal, Basic, Balanced) from manifest
metadata and validates them against preset policy. Runs alongside the smoke
tests in CI.

## Integration Tests (`Tests/Integration/`)

VM-based tests that execute real tweak functions against a live Windows
installation and verify system state changes. These require Administrator
privileges and should only run inside disposable VMs.

**Test runner:** `Tests/Integration/IntegrationTest.ps1`

```powershell
# All categories
pwsh -File ./Tests/Integration/IntegrationTest.ps1

# Single category, dry-run (skips destructive package operations)
pwsh -File ./Tests/Integration/IntegrationTest.ps1 -Category Registry -DryRun
```

**Focused registry test:** `Tests/Integration/Test-RegistryTweak.ps1`

Tests a single function's apply/undo cycle against a specific registry value.

**Categories:** Registry, Services, Packages, GroupPolicy, GameMode

**CI:** `.github/workflows/integration.yml` (manual dispatch only, Windows
Server runners). Desktop SKU coverage (Win 10/11) requires self-hosted runners.

See `Tests/Integration/README.md` for the full test matrix and prerequisites.

## Test Report Exporter (`Tools/Export-TestReport.ps1`)

Runs all test layers (smoke, unit, composition, preset) and outputs a
machine-readable JSON report with per-layer pass/fail/skip counts, durations,
and shields.io-compatible badge metadata.

```powershell
# Generate report at the default path (Tests/TestReport.json)
pwsh -File ./Tools/Export-TestReport.ps1

# Custom output path
pwsh -File ./Tools/Export-TestReport.ps1 -OutputPath ./artifacts/report.json
```

The report includes a `badge` object that can be consumed by CI to generate
status badges (shields.io endpoint format).

## Screenshot Drift Checks (`Tools/Test-ScreenshotDrift.ps1`)

Validates that README screenshot references are tracked in a manifest
(`Tests/Fixtures/ScreenshotManifest.json`) and flags potentially stale
screenshots based on age and source file modification dates.

```powershell
# Check for drift
pwsh -File ./Tools/Test-ScreenshotDrift.ps1

# Regenerate manifest after capturing fresh screenshots
pwsh -File ./Tools/Test-ScreenshotDrift.ps1 -UpdateManifest

# Use a shorter staleness threshold (30 days)
pwsh -File ./Tools/Test-ScreenshotDrift.ps1 -StaleDays 30
```

## Desktop OS Matrix (`Tests/Integration/DesktopMatrixResults.json`)

Archived results from running the test suite on real desktop OS installations.
Updated whenever a desktop validation pass is performed. See
`Tests/Integration/README.md` for the current matrix status.

## GUI Composition Tests (`Tests/GUI.Composition.Tests.ps1`)

Headless Pester tests that validate GUI contracts without rendering WPF windows:

- **Mode transition contracts** — verifies `Set-SafeModeState`, `Set-AdvancedModeState`, `Set-GameModeState` exist
- **Dialog creation contracts** — verifies `Show-PlanSummaryDialog`, `Show-ThemedDialog`, `Show-ExecutionSummaryDialog` exist
- **Icon fallback behavior** — validates text-only fallback when icon font is unavailable
- **Preview count generation** — validates `Get-TweakVisualMetadata` returns MatchesDesired, StateLabel, StateTone
- **Button chrome variants** — confirms all documented variants (Primary, Preview, Danger, DangerSubtle, Secondary, Subtle, Selection) are accepted
- **Theme management** — validates DarkTheme and LightTheme contain required color keys

Run locally: `Invoke-Pester ./Tests/GUI.Composition.Tests.ps1 -Output Detailed`

### Responsive Tab/Dropdown Switching (`Tests/Unit/ResponsiveTabDropdown.Tests.ps1`)

Headless contract tests that validate the adaptive tab layout without rendering:

- **XAML layout structure** — PrimaryTabHost, ScrollViewer, horizontal StackPanel, collapsed dropdown
- **Adaptive tab mode enforcement** — mode always set to 'tabs', no width-based dropdown toggle
- **Adaptive padding thresholds** — compact (8px) vs wide (16px) at 1400px breakpoint
- **SizeChanged handler registration** — resize triggers layout recalculation and BringIntoView
- **Tab selection and search integration** — LastStandardPrimaryTab tracking, search sentinel exclusion
- **TabManagement helper contracts** — visual styling, hover effects, keyboard focus, legacy stubs

Run locally: `Invoke-Pester ./Tests/Unit/ResponsiveTabDropdown.Tests.ps1 -Output Detailed`

### Remaining GUI test gaps

- Full end-to-end GUI flows require an interactive desktop session
