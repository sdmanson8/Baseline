# Full Change Log

All notable user-visible changes to Baseline are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project uses [Semantic Versioning](https://semver.org/).

---

## 3.1.0-beta | 2026-04-26

### Changed

- Version bumped from 3.0.0 to 3.1.0 across module manifest, entry scripts, and asset scripts.

### Fixed

- **Explorer file-extension toggle** (`Module/Regions/UIPersonalization/UIPersonalization.Explorer.psm1`) — `FileExtensions -Show`/`-Hide` no longer fails on fresh user profiles or `LocalSystem` execution contexts where `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` does not yet exist. Both code paths now create the key with `New-Item -Force` when missing before writing `HideFileExt`. (#2)
- **GUI module load in bare shells** (`Module/GUICommon.psm1`) — `[System.Windows.Media.BrushConverter]::new()` was instantiated at module-load before any WPF assembly was loaded, throwing `TypeNotFound` in headless / integration-test PowerShell hosts. Added `Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction SilentlyContinue` ahead of the instantiation so the WPF type system is available when `Import-Module Baseline` is run outside the embedded launcher. (#3)
- **DispatcherTimer null-pump crash on cleanup** (`Module/GUI/ExecutionOrchestration.ps1`) — the run timer's `Add_Tick` handler invoked `$Script:ExecutionPumpTickFn` by reference. If a tick fired after cleanup cleared the script-scope variable, the dispatcher threw `Cannot invoke null`. The handler now captures the function in a local closure (`$executionPumpTickFn = $Script:ExecutionPumpTickFn` + `.GetNewClosure()`) so any in-flight tick after cleanup still resolves to the original scriptblock and exits cleanly. (#4)
- **HKCU subkey-guard sweep across 14 region modules** — all bare `New-ItemProperty -Path "HKCU:\..."` writes that targeted subkeys not guaranteed to exist on fresh user profiles or under `LocalSystem` were converted to the existing `Set-RegistryValueSafe` helper (`Module/SharedHelpers/Registry.Helpers.ps1`), which internally creates the parent key with `New-Item -Force` when missing. Affected files: `Module/Regions/UIPersonalization/UIPersonalization.Explorer.psm1` (37 sites: 13 to `Explorer\Advanced`, 6 to `Explorer\ControlPanel`, 2 to `Explorer\OperationStatusManager`, plus base-key writes) (#5); `Module/Regions/UIPersonalization/UIPersonalization.Appearance.psm1` (4 sites: `Explorer\Advanced\DisallowShaking`, `Themes\Personalize\AppsUseLightTheme`) (#6); `Module/Regions/UIPersonalization/UIPersonalization.Icons.psm1` (6 sites: `Explorer\Advanced\SnapAssist`, `Themes\Personalize\SystemUsesLightTheme`, `Explorer\StuckRects3\Settings`) (#7); `Module/Regions/UIPersonalization/UIPersonalization.Taskbar.psm1` (TaskbarAl, SearchboxTaskbarMode, IsDynamicSearchBoxEnabled, ShowTaskViewButton, TaskbarGlomLevel, ShowCopilotButton, TaskbarCompanion, TaskbarEndTask) plus a parent-side `Test-Path`/`New-Item` guard before the `& powershell_temp.exe -Command {…}` subshell since the subshell cannot see `Set-RegistryValueSafe` (#8); `Module/Regions/StartMenu.psm1` (5 sites: `Start_AccountNotifications`, `Start_IrisRecommendations`, `Start_Layout`) (#9); `Module/Regions/Taskbar.psm1` plus a parent-side guard before the `Invoke-UCPDBypassed -ScriptBlock {…}` wrapper for the same reason (#10); `Module/Regions/TaskbarClock.psm1` (4 sites: `ShowClockInNotificationCenter`, `ShowSecondsInSystemClock`) (#11); `Module/Regions/Cursors.psm1` (59 sites under `HKCU:\Control Panel\Cursors` — largest single offender) (#12); `Module/Regions/Gaming.psm1` (2 sites: `GameBar\ShowStartupPanel`) (#13); `Module/Regions/ContextMenu.psm1` (1 site: `MultipleInvokePromptMinimum`) (#14); `Module/Regions/Defender/Defender.CoreProtection.psm1` (2 sites: `Windows Security Health\State\AccountProtection_MicrosoftAccount_Disconnected`, `AppAndBrowser_EdgeSmartScreenOff`) (#15); `Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1` (3 sites: `DiagTrack\ShowedToastAtLevel`, `Windows Error Reporting\Disabled`) (#16); `Module/Regions/PrivacyTelemetry/PrivacyTelemetry.PrivacySettings.psm1` (3 sites: `AdvertisingInfo\Enabled`, `HttpAcceptLanguageOptOut`) (#17); `Module/Regions/PrivacyTelemetry/PrivacyTelemetry.SystemSettings.psm1` (2 sites: `TailoredExperiencesWithDiagnosticDataEnabled`) (#18). All sites that already used inline `Test-Path`/`New-Item` guards were left unchanged.
- **Swallowed exceptions in actionable startup paths** — `catch { $null = $_ }` blocks around `Initialize-GuiDetectCache`, `Initialize-BaselineUserPreferences`, `Initialize-NewBadgeService`, and the GUI version-detection regex now emit `LogWarning` with the underlying `Exception.Message` so first-launch initialization failures surface in the daily log instead of being silently dropped. Cleanup/dispose paths (timer stops, dispatcher invocations, splash window close) remain silent because their exceptions are non-actionable. (#19)
- **Popup pickers for UWP Apps, Windows Features (capabilities + features), and Scheduled Tasks** (`Module/Regions/UWPApps.psm1`, `Module/Regions/System/System.WindowsFeatures.psm1`, `Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1`) — picker windows did not call `Set-GuiWindowChromeTheme` after loading their XAML, so the OS-drawn title bar stayed on the default light Windows chrome regardless of the GUI's current theme. In dark mode this produced the visual mismatch the rest of the GUI did not show (every other dialog already routed through this helper). All 5 picker XAML loads now invoke `Set-GuiWindowChromeTheme` against `$Script:CurrentThemeName` immediately after `XamlReader.Load`, behind a `Get-Command` guard so it no-ops if the helper isn't loaded in a child runspace. (#1)

---

## 3.0.0-beta | 2026-04-06

### Added

- **State Tracking & Compliance**
  - System state snapshots: pre-run and post-run capture, export, import, and comparison
  - Configuration profiles: portable JSON profiles built from presets or manual selection
  - Compliance drift detection: scan system state against a profile, highlight Compliant/Drifted/Unknown, one-click "Fix Drift"
  - Audit trail: append-only JSON Lines log of every execution with timestamp, tweak, old/new values, user, and machine
  - Audit viewer: GUI timeline with filter-by-action, HTML/Markdown export, and clear-old-entries
  - Scheduled automation: register/unregister Baseline as a Windows Scheduled Task for recurring compliance checks
  - Multi-machine targeting (CLI preview, untested on Server): deploy profiles or run compliance checks against remote machines via PowerShell Remoting

- **UX Clarity & Flow Redesign**
  - Pre-flight checks: admin elevation, disk space, WMI health, VSS service, event log, system restore validation
  - Plan summary panel: grouped view of Will Change / Already Set / Requires Restart / High Risk before execution
  - Visual diff view: side-by-side current state vs. planned post-run state
  - Structured post-run results: color-coded result cards with status filter pills, lazy loading, and per-tweak recovery hints
  - Per-monitor DPI awareness (V2 with shcore fallback) for crisp rendering on high-DPI displays
  - Runtime language switching with session persistence and auto-detection from system locale
  - Localization framework with per-language JSON files
  - Deterministic execution labeling and dependency surfacing

- **Icon UX System**
  - FluentSystemIcons font architecture with IconRegistry and IconFactory
  - Icon usage tiers: Primary Actions (mandatory), Navigation (mandatory), Status (conditional)
  - Icon size system: 16-20px buttons, 16px tabs, 12-14px status, 12px logs
  - Semantic color rules inheriting from theme palette
  - Screen-by-screen integration for header, tabs, presets, search/filter, gaming, preview, execution, and dialogs
  - Text-only fallback for graceful degradation when font is unavailable
  - Spacing, responsive, and accessibility rules

- **Preset Redesign & Governance**
  - Renamed expert preset to Advanced with `Advanced.json`
  - Tightened Basic to better match its low-risk promise
  - Added preset policy linting: Minimal, Basic, and Balanced reject uninstall/remove/delete actions
  - Added `WorkflowSensitivity` normalization and validation
  - Advanced warning modal with impact categories, restore-point guidance, and recommended buttons
  - Preset explanation cards with honest descriptions of scope and risk

- **GUI & UX Polish**
  - Impact summary bar with visual differentiation for toggles, choices, actions, and uninstall/remove
  - Selected-only, high-risk-only, restorable-only, and gaming-related filters
  - Badges and state chips for toggle/action/remove behavior, restart, reversibility, and current state
  - Scenario tags, blast-radius explanations, grouped Preview Run sections
  - Safe Mode as conservative default, clearing hidden advanced selections when Expert Mode turns off
  - Compact "Details" toggle replacing verbose "Why this matters" blocks
  - Consistent row spacing between tabs
  - Persistent state indicators for Expert Mode and Light/Dark Mode
  - Compact language-popup search box with live filtering by language name or code

- **Execution, Logging & Recovery**
  - Separated failed, skipped, not applicable, and restart-pending outcomes
  - Run summaries that surface successful changes and restart-required outcomes explicitly
  - Linked restore-point creation before larger or higher-risk guided runs
  - Concrete remediation hints for recovery guidance

- **Gaming Tab Expansion**
  - New tweak implementations for gaming performance
  - Data and manifest wiring for gaming entries
  - Normal vs Expert Mode classification for gaming tweaks

- **Architecture Hardening**
  - Eliminated false `failed!` outcomes in restore/default flows
  - Eliminated mid-run interactive dialogs for batch execution
  - Metadata consistency sweep across all manifest entries
  - Naming and repo standardization sweep
  - Post-run remediation text for common failure classes (access denied, reboot required, missing dependency, network)
  - Retry support limited to Direct-recovery, restorable, non-removal, non-action items only
  - Package/install/uninstall operations shown as a distinct summary category

- **Security & Architecture**
  - Per-monitor DPI awareness via SetProcessDpiAwarenessContext P/Invoke (user32.dll) with SetProcessDpiAwareness fallback (shcore.dll)
  - SHA-256 checksum validation for all remote downloads (C++ Redistributables, .NET runtimes)
  - DWM window chrome interop for native dark/light title bar and Win11 rounded corners
  - AST-based command parsing replacing all Invoke-Expression usage

- **Testing & Validation**
  - Headless GUI composition/contract tests for dialog creation paths
  - Headless tests for Safe/Expert/Game Mode transitions
  - Headless tests for responsive tab/dropdown switching
  - Headless tests for preview count generation
  - Headless tests for restore/default wording paths
  - Headless tests for icon/text fallback behavior
  - Focused unit coverage for localization directory resolution and language selector icon family/glyph wiring
  - Desktop integration matrix validated: Win10 + Win11

- **Codebase Audit Remediation**
  - Resolved public positioning contradiction between README and release strategy
  - Cleaned launch trust surface: local launch primary, iwr|iex demoted to advanced
  - Added historical context note to changelog
  - Automated GUI test layer added: 6 test categories
  - Desktop integration matrix run and documented: Win10 + Win11 validated
  - GUI state surface reduction across top 5 files by $Script: references
  - Large module extraction: 14 sub-modules extracted from System, UIPersonalization, PrivacyTelemetry, SystemTweaks, Defender
  - Runtime Write-Host audit across 10 files
  - ExecutionPolicy Bypass audit across 6 files with documentation
  - Invoke-Expression/iex audit with safety comments
  - Quality & Validation section added to README
  - Release/documentation pack labeled and separated

### Changed

- Version bumped from 2.0.0 to 3.0.0 across module manifest, entry scripts, and asset scripts
- Window sizing now clamps MinWidth, MinHeight, and dimensions to the available work area so the GUI fits on low-resolution screens (e.g. 1024x768)
- GUI.psm1 further modularized: 35 extracted scripts in Module/GUI/ (up from 14), core orchestrator at ~2,970 lines
- Region modules extracted: System.psm1 (5 sub-modules), UIPersonalization.psm1 (3), PrivacyTelemetry.psm1 (2), SystemTweaks.psm1 (2), Defender.psm1 (2)
- Tab content architecture: TabControl used as header-only strip with manual content management via single ScrollViewer
- Button styling rebuilt with programmatic ControlTemplate via FrameworkElementFactory (7 variants)
- CheckBox toggle-switch implemented as custom XAML ControlTemplate with animated thumb
- Brush caching system with frozen SolidColorBrush instances for thread-safe WPF rendering
- ObservableState pub/sub system dispatches to UI thread via Dispatcher.Invoke at DataBind priority
- Filter cache invalidation consolidated to single FilterGeneration integer
- Session state schema upgraded to version 9
- Execution background runspace uses fresh module import with ConcurrentQueue-only communication
- Localization strings corrected: "Windows 11 23H2" changed to "Windows 10 (1903 and later) and Windows 11" across 46 language files
- Local launch promoted to primary path in README; remote bootstrap demoted to advanced section
- Preview Run and execution summary dialog chrome now source their labels from the active localization set

### Fixed

- GUI window no longer overflows screen on high-DPI displays due to missing DPI awareness
- GUI now fits 1024x768 and other low-resolution screens by clamping to available work area
- Header toolbar no longer clips the language button — dynamic MinWidth adjustment measures actual header width at render time
- Language selector now resolves bundled localization files reliably across module and extracted GUI roots, restores saved language from the same resolved path, and keeps the header globe icon on the shared Fluent System Icons pipeline
- GUI localization no longer falls back to English when a non-English language is selected; hashtable-backed localization lookups now resolve correctly across the live interface
- Restored sessions and startup initialization now reapply the selected language to active controls instead of leaving existing GUI content in English
- Light theme no longer makes the custom minimize, maximize, and close buttons effectively disappear; caption buttons now restyle with the active title-bar theme
- Zero remaining Invoke-Expression usage in production code (AST-based parsing throughout)
- Eliminated false `failed!` outcomes on edge cases where registry values were never created
- Eliminated mid-run interactive dialogs blocking batch execution
- Logging no longer silently broken after module force-import in background runspace
- WPF event handler function scope resolution fixed for dispatcher closures
- Manifest options array double-nesting resolved
- Preset/scenario button active state now syncs correctly across tabs
- Preview Run status summaries, action labels, and expand/collapse hints no longer remain hard-coded in English when another language is active

---

## 2.1.0-beta | 2026-03-25

### Added

- GUI with search, filters, risk labels, preset selection, and preview-before-run workflow
- Four built-in presets: Minimal, Basic, Balanced, Advanced
- Game Mode with Casual, Competitive, Streaming, and Troubleshooting profiles
- Scenario modes for Workstation, Privacy, and Recovery workflows
- Environment-aware recommendation text based on detected gaming hardware and software
- Preview Run showing what will change, what is already desired, what is risky, and what can be undone
- Post-run summary with outcome classification, remediation hints, retry guidance, and next-step actions
- Headless execution with preset, function, Game Mode profile, and scenario profile support
- Interactive session bootstrap with tab completion for functions, presets, and profiles
- Remote bootstrap one-liner for downloading and launching from GitHub
- Manifest-driven tweak metadata with risk, recovery, restart, and preset-tier classification
- Manifest validation tooling for duplicates, missing metadata, and ownership mismatches
- Preset generation from manifest metadata for Minimal, Basic, and Balanced tiers
- Release packaging helper for building clean public zip archives
- Recovery metadata: RecoveryLevel (Direct, DefaultsOnly, RestorePoint, Manual) and Restorable flags
- Retry support limited to trustworthy failure categories with explicit reasoning
- Blast radius and scenario-impact text in preview and detail views
- File logging, GUI log forwarding, and structured execution outcome tracking
- Settings import/export and restore snapshot actions
- Helper modules for environment, registry, packages, maintenance, taskbar, error handling, and advanced startup
- Coverage across privacy, telemetry, security, Defender, UI, taskbar, Start menu, context menu, cursors, OneDrive, UWP apps, networking, gaming, and system behavior
- Windows AI removal helper with non-interactive and GUI execution support
- Support for Windows 10, Windows 11, and Windows Server 2016 through 2025

### Changed

- Renamed the project to Baseline across all scripts, modules, and documentation
- Replaced all bare `Remove-ItemProperty -ErrorAction Stop` restore paths with `Remove-RegistryValueSafe` across every region module (ContextMenu, Gaming, StartMenuApps, System, SystemTweaks, Taskbar added to previously converted StartMenu, UIPersonalization, PrivacyTelemetry, OSHardening)
- Guarded `RawUI.WindowTitle` and interactive host assumptions behind `Test-InteractiveHost` checks
- Downgraded optional sub-step misses in coarse wrapper actions (e.g., Performance Tuning) to skipped or not applicable instead of failed
- Improved post-run remediation text for common failure classes including access denied, reboot required, missing dependency, and network failures
- Limited retry to Direct-recovery, restorable, non-removal, non-action items only
- Batch execution now runs fully headless with no mid-run interactive dialogs
- Package/install/uninstall operations shown as a distinct summary category with heavier treatment than simple toggles
- Extracted Game Mode logic from Manifest.Helpers into dedicated GameMode.Helpers module
- Extracted Scenario Mode logic into dedicated ScenarioMode.Helpers module
- Extracted preset resolution logic from entry script into Preset.Helpers module
- Extracted recovery/undo logic into dedicated Recovery.Helpers module
- Moved Game Mode data files into organized Module/Data/GameMode/ subdirectory
- Reduced Manifest.Helpers from 1,760 to 641 lines by splitting responsibilities
- Reduced Baseline.ps1 from 548 to 443 lines — now purely a launcher/dispatcher
- Reduced GUI.psm1 from 14,172 to 9,892 lines by extracting five function groups into Module/GUI/ (ExecutionSummary, PreviewBuilders, PresetManagement, GameModeUI, SessionState)
- Added shared state documentation (Module/GUI/STATE.md) classifying all 111 $Script: variables
- Added shared object models reference (Module/GUI/MODELS.md) documenting 6 canonical object shapes
- Added smoke-test script (Tools/Test-SmokeTest.ps1) for release validation
- Added scenario expansion policy documentation in ScenarioMode.Helpers.ps1

## 2.1.0-beta | 2026-03-21

- Minor changes to the GUI

## 1.0.0-beta | 2026-03-17

- Initial Commit
