# Full Change Log

All notable user-visible changes to Baseline are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project uses [Semantic Versioning](https://semver.org/).

---

## 1.0.0 | 2026-05-27

### Added
- **Graphical User Interface (GUI)**
  - Full GUI with search, filters, risk labels, preset selection, and a preview‑before‑run workflow.
  - Four built‑in presets: Minimal, Basic, Balanced, Advanced (formerly “Expert”).
  - Game Mode with four profiles: Casual, Competitive, Streaming, Troubleshooting.
  - Scenario modes: Workstation, Privacy, Recovery.
  - Environment‑aware recommendation text based on detected gaming hardware/software.
  - Preview Run showing planned changes, already‑set items, risky actions, and undoable tweaks.
  - Post‑run summary with outcome classification, remediation hints, retry guidance, and next‑step actions.
  - Per‑monitor DPI awareness (V2 + shcore fallback) for crisp rendering on high‑DPI displays.
  - Runtime language switching with session persistence and auto‑detection from system locale.
  - Localization framework with per‑language JSON files (79 languages, full apps coverage).
  - Icon UX system based on FluentSystemIcons with semantic colour rules and text fallback.
  - Redesigned navigation around workflow modes: Optimize, Gaming, Updates, Apps, Setup Builder.
  - Compact language‑popup search box with live filtering.
  - Persistent state indicators for Expert Mode and Light/Dark Mode.
  - Impact summary bar with visual differentiation for toggles, choices, actions, and removals.
  - Badges and state chips for toggle/action/remove behaviour, restart requirement, reversibility, and current state.
  - Compact “Details” toggle replacing verbose “Why this matters” blocks.
- **State Tracking & Compliance**
  - System state snapshots: pre‑run and post‑run capture, export, import, and comparison.
  - Configuration profiles: portable JSON profiles built from presets or manual selection.
  - Compliance drift detection – scan system against a profile, highlight Compliant / Drifted / Unknown, one‑click “Fix Drift”.
  - Audit trail: append‑only JSON Lines log of every execution with timestamp, tweak, old/new values, user, and machine.
  - Audit viewer: GUI timeline with filter‑by‑action, HTML/Markdown export, and clear‑old‑entries.
  - Scheduled automation: register/unregister Baseline as a Windows Scheduled Task for recurring compliance checks.
  - Multi‑machine targeting: deploy profiles or run compliance checks against remote machines via PowerShell Remoting.
- **Execution, Logging & Recovery**
  - Structured post‑run results with colour‑coded cards, status filter pills, lazy loading, and per‑tweak recovery hints.
  - Separate outcome categories: failed, skipped, not applicable, restart pending.
  - Run summaries that explicitly surface successful changes and restart‑required outcomes.
  - Linked restore‑point creation before larger or higher‑risk guided runs.
  - Concrete remediation hints for recovery guidance.
  - Retry support limited to Direct‑recovery, restorable, non‑removal, non‑action items only.
  - Package/install/uninstall operations shown as a distinct summary category.
- **Setup & Deployment**
  - Windows Setup Builder / Deployment Media Builder.
  - ARM64 launcher support.
  - Remote bootstrap one‑liner for downloading and launching from GitHub.
  - Interactive session bootstrap with tab completion for functions, presets, and profiles.
  - Headless execution with preset, function, Game Mode profile, and scenario profile support.
  - Auto‑update checks.
  - Remote connectivity probes and managed remote workflow hardening.
- **Tweaks & Features**
  - Gaming profile workflows with new performance tweaks.
  - Software & Apps queued‑action system.
  - OS hardening GUI workflows.
  - WSL install flow.
  - Expanded Windows parity coverage.
  - Windows AI removal helper with non‑interactive and GUI execution support.
  - Manifest‑driven tweak metadata with risk, recovery, restart, and preset‑tier classification.
  - Recovery metadata: RecoveryLevel (Direct, DefaultsOnly, RestorePoint, Manual) and Restorable flags.
  - Blast radius and scenario‑impact text in preview and detail views.
  - Environment, registry, packages, maintenance, taskbar, error handling, and advanced startup helper modules.
  - Coverage across privacy, telemetry, security, Defender, UI, taskbar, Start menu, context menu, cursors, OneDrive, UWP apps, networking, gaming, and system behaviour.
- **Security & Architecture**
  - SHA‑256 checksum validation for all remote downloads (C++ Redistributables, .NET runtimes).
  - DWM window chrome interop for native dark/light title bar and Windows 11 rounded corners.
  - AST‑based command parsing replacing dynamic expression execution (zero remaining dynamic execution in production code).
  - Per‑monitor DPI awareness via SetProcessDpiAwarenessContext P/Invoke (user32.dll) with SetProcessDpiAwareness fallback (shcore.dll).
- **Testing & Validation**
  - Headless GUI composition/contract tests for dialog creation, Safe/Expert/Game Mode transitions, responsive tab/dropdown switching, preview count generation, icon/text fallback.
  - Focused unit coverage for localization directory resolution, language selector wiring, application execution routing, update handling, Delivery Optimization policy, feature/metred connection updates, etc.
  - Desktop integration matrix validated for Windows 10 and Windows 11.
  - Manifest validation tooling for duplicates, missing metadata, and ownership mismatches.
  - Preset generation from manifest metadata for Minimal, Basic, Balanced tiers.
  - Release packaging helper for building clean public zip archives.

### Changed
- **Project identity** – Renamed the utility from Win10_11Util to Baseline across all scripts, modules, and documentation.
- **GUI navigation** – Redesigned around workflow modes (Optimize, Gaming, Updates, Apps, Setup Builder).
- **Preset system** – Renamed “Expert” preset to “Advanced” with Advanced.json. Tightened Basic to better match its low‑risk promise. Added preset policy linting – Minimal, Basic, Balanced reject uninstall/remove/delete actions. Added advanced warning modal with impact categories, restore‑point guidance, and recommended buttons.
- **Onboarding** – Preset onboarding moved into Initial Setup. Shared filter behaviour unified across workflow modes.
- **Apps catalog** – Restructured into category‑based manifests.
- **Logging** – Simplified lifecycle; recreated on startup.
- **Deployment Media Builder** – Progress reporting redesigned.
- **Localisation** – Visible copy polished across multiple languages; 79 new languages added with full apps coverage.
- **Window sizing** – Now clamps MinWidth, MinHeight, and dimensions to the available work area so the GUI fits on low‑resolution screens (e.g. 1024×768).
- **Module organisation** –
  - GUI.psm1 modularised into 35 scripts under Module/GUI/ (up from 14).
  - Region modules split: System.psm1 (5 sub‑modules), UIPersonalization.psm1 (3), PrivacyTelemetry.psm1 (2), SystemTweaks.psm1 (2), Defender.psm1 (2).
  - Manifest.Helpers reduced from 1 760 to 641 lines.
  - Baseline.ps1 reduced from 548 to 443 lines – now purely a launcher/dispatcher.
  - GUI.psm1 reduced from 14 172 to 9 892 lines by extracting five function groups into Module/GUI/.
  - Game Mode logic moved to GameMode.Helpers, Scenario Mode to ScenarioMode.Helpers, preset resolution to Preset.Helpers, recovery/undo logic to Recovery.Helpers.
- **Tab content architecture** – TabControl used as header‑only strip with manual content management via a single ScrollViewer.
- **Button styling** – Rebuilt with programmatic ControlTemplate via FrameworkElementFactory (7 variants).
- **CheckBox** – Implemented as custom XAML ControlTemplate with animated thumb (toggle‑switch).
- **Brush caching** – Frozen SolidColorBrush instances for thread‑safe WPF rendering.
- **Observable state** – Pub/sub system dispatches to UI thread via Dispatcher.Invoke at DataBind priority.
- **Filter cache** – Invalidation consolidated to a single FilterGeneration integer.
- **Session state** – Schema upgraded to version 9.
- **Execution background runspace** – Uses fresh module import with ConcurrentQueue‑only communication.
- **Localisation strings** – Corrected “Windows 11 23H2” to “Windows 10 (1903 and later) and Windows 11” across 46 language files.
- **Launch strategy** – Local launch promoted to primary path in README; remote bootstrap demoted to advanced section.
- **Preview Run and execution summary** – Dialog chrome now sources labels from the active localisation set.
- **Safe Mode** – Now the conservative default; clears hidden advanced selections when Expert Mode is turned off.
- **Recovery and failure handling** –
  - Eliminated false failed! outcomes in restore/default flows.
  - Eliminated mid‑run interactive dialogs for batch execution.
  - Post‑run remediation text added for common failure classes (access denied, reboot required, missing dependency, network).
  - Downgraded optional sub‑step misses in coarse wrapper actions (e.g. Performance Tuning) to skipped or not applicable instead of failed.
  - Batch execution now runs fully headless with no mid‑run interactive dialogs.
- **Registry safety** – Replaced all bare New-ItemProperty and Remove-ItemProperty calls with Set-RegistryValueSafe and Remove-RegistryValueSafe helpers across 14 region modules (ContextMenu, Gaming, StartMenuApps, System, SystemTweaks, Taskbar, StartMenu, UIPersonalization, PrivacyTelemetry, OSHardening, Cursors, Defender, etc.), ensuring parent keys are created when missing.
- **Interactive host assumptions** – Guarded RawUI.WindowTitle and interactive host checks behind Test-InteractiveHost.

### Fixed
- **GUI layout & rendering**
  - Window no longer overflows screen on high‑DPI displays (missing DPI awareness added).
  - GUI now fits 1024×768 and other low‑resolution screens.
  - Header toolbar no longer clips the language button – dynamic MinWidth adjustment measures actual header width at render time.
  - Light theme no longer makes custom minimise/maximise/close buttons disappear; caption buttons now restyle with the active title‑bar theme.
  - Theme synchronisation issues in popup windows resolved.
- **Localisation**
  - Language selector now resolves bundled localisation files reliably across module roots; restores saved language from the same resolved path; keeps header globe icon on the shared Fluent System Icons pipeline.
  - GUI localisation no longer falls back to English when a non‑English language is selected; hashtable‑backed lookups resolve correctly across the live interface.
  - Restored sessions and startup initialisation now reapply the selected language to active controls instead of leaving existing GUI content in English.
- **Execution & stability**
  - Zero remaining dynamic expression execution in production code (AST‑based parsing throughout).
  - Eliminated false failed! outcomes on edge cases where registry values were never created.
  - Eliminated mid‑run interactive dialogs blocking batch execution.
  - Logging no longer silently broken after module force‑import in background runspace.
  - WPF event handler function scope resolution fixed for dispatcher closures.
  - DispatcherTimer null‑pump crash on cleanup fixed – handler now captures function in a local closure.
  - Swallowed exceptions in actionable startup paths (Initialize-GuiDetectCache, etc.) now emit LogWarning with the underlying message.
  - GUI mode transitions no longer leak unrelated UI surfaces.
  - Multiple Deployment Media Builder worker and callback failures resolved.
  - Incorrect GUI/headless exit‑code reporting fixed.
  - Various registry, helper, and startup initialisation failures corrected.
- **Specific tweak & module fixes**
  - Explorer file‑extension toggle (FileExtensions -Show/-Hide) no longer fails on fresh user profiles or LocalSystem execution contexts.
  - GUI module load in bare shells fixed by adding WPF assemblies before [System.Windows.Media.BrushConverter] instantiation.
  - Popup pickers for UWP Apps, Windows Features, and Scheduled Tasks now call Set-GuiWindowChromeTheme after loading XAML, fixing the OS‑drawn title bar staying on default light chrome in dark mode.
  - Manifest options array double‑nesting resolved.
  - Preset/scenario button active state now syncs correctly across tabs.
  - Preview Run status summaries, action labels, and expand/collapse hints no longer remain hard‑coded in English when another language is active.
- **Code quality & documentation**
  - Resolved public positioning contradiction between README and release strategy.
  - Cleaned launch trust surface – local launch primary, downloaded‑file bootstrap documented as advanced.
  - Added historical context note to changelog.
  - Automated GUI test layer added (6 test categories).
  - Desktop integration matrix run and documented for Win10 + Win11.
  - GUI state surface reduced across top 5 files by $Script: references.
  - Runtime Write-Host audited across 10 files.
  - ExecutionPolicy Bypass audited across 6 files with documentation.
  - Remote expression execution audited with safety comments.
  - Quality & Validation section added to README.
  - Release/documentation pack labelled and separated.

---

## 0.0.0 | 2026-03-21

- Initial Commit
