# Baseline Release Plan

- [ ] Detailed release-readiness, product strategy, preset governance, UX, gaming mode, and GitHub launch recommendations
- [ ] Current GUI reference
- [ ] Prepared for GitHub release planning

---

## 1. Executive summary

- [ ] **Current position**: Baseline is not just a debloat script. It is a modular Windows configuration platform with manifests, presets, helper libraries, GUI execution, logging, and a growing safety model. That places it above most one-file scripts immediately.
- [ ] **Release recommendation**: Public beta for advanced users is realistic now. A broad public launch aimed at normal users should wait until preset semantics, warning flow, restore guidance, and failure handling are tightened.
- [ ] **How to stand out**: WinUtil wins on reach, Sophia wins on depth, and most debloat repos win only on simplicity. Baseline can win on trust, clarity, and controlled opinionation: cleaner presets, stronger recovery UX, a legitimate gaming mode, and a polished GitHub package.
- [ ] **Primary differentiator**: A manifest-backed, GUI-driven Windows configuration utility with understandable presets, strong warnings, preview-first execution, and scenario-based modes.

---

## 2. What Baseline should be in the market

- [ ] **Recommended one-line product description**:
- [ ] *Baseline is a modular Windows debloater, optimizer, and hardening utility for Windows 10, Windows 11, and Windows Server.*
- [ ] Baseline helps users clean up Windows, apply privacy and UX improvements, enable sensible performance tweaks, and optionally apply advanced hardening changes through a guided GUI or headless automation.
- [ ] Baseline should emphasize that presets, warnings, and restore recommendations exist to make powerful changes understandable, not to pretend the tool is risk-free.

### Baseline should compete on four attributes

- [ ] **Trust**: manifest-backed metadata, warnings, preview, restore guidance, and transparent descriptions.
- [ ] **Clarity**: the user should understand what a preset will do and why it exists.
- [ ] **Coverage**: cleanup, privacy, UI, gaming, security, and maintenance from one interface.
- [ ] **Control**: headless execution, preset export/import, and module-driven organization.

### Baseline should avoid these traps

- [ ] Looking like “another aggressive debloat script.”
- [ ] Treating every preset as just a different tweak count.
- [ ] Marketing Advanced as the “best” preset.
- [ ] Overpromising reversibility.
- [ ] Shipping a strong GUI with weak preset discipline.

---

## 3. Preset redesign: the highest-priority release task

- [ ] **Why this matters**: The biggest risk before release is not code quality. It is preset semantics. If the “Safe” and “Balanced” experiences do not feel exactly like their names imply, users will lose trust quickly.

### Recommended preset ladder

- [ ] **Minimal** — Small quality-of-life changes with minimal behavior changes.
- [ ] **Safe** — Recommended for most users. Low-risk cleanup and usability improvements.
- [ ] **Balanced** — More privacy and system tuning with moderate tradeoffs.
- [ ] **Advanced** — Experienced users only. Higher-risk, opinionated system changes.
- [ ] **Gaming Mode** — Scenario mode, not a global preset; focused on latency, compatibility, and gaming quality-of-life.

### Rules to enforce in code

- [ ] Use manifest metadata as the source of truth. Preset JSON should not silently contradict the manifest tier model.
- [ ] If an item is marked high risk, not restorable, or strongly workflow-sensitive, it should never appear in Safe.
- [ ] Balanced may include moderate-risk items, but it should still avoid destructive debloat, invasive hardening, or anything likely to break normal Office, OneDrive, gaming, or network sharing workflows.
- [ ] Advanced should be presented as an expert preset, not as the “best” preset.
- [ ] Preset generation should become automated: build presets from metadata tags and a small allowlist/denylist rule system instead of maintaining multiple manual sources of truth forever.

### Preset governance recommendations

- [ ] Add `Tier`, `Risk`, `Impact`, `Restorable`, `RequiresRestart`, `ScenarioTags`, and `WorkflowSensitivity` as validated metadata.
- [ ] Add preset lint rules:
  - [ ] Safe cannot include `High` risk.
  - [ ] Safe cannot include `Restorable = false` unless explicitly approved.
  - [ ] Safe cannot include uninstall/removal actions unless explicitly allowlisted.
  - [ ] Balanced cannot include workflow-breaking hardening unless explicitly tagged as `AdvancedOnly = false`.
  - [ ] Advanced can include high-risk items, but must expose stronger UX warnings.
- [ ] Add a `ReasonIncluded` field or generated explanation so Preview Run can explain why each tweak belongs to a preset.

### Practical preset tasks

- [ ] Rename the preset file to `Advanced.json`.
- [ ] Audit all items currently included in Safe and remove anything that can break:
  - [ ] updates
  - [ ] OneDrive / sync
  - [ ] Office / Adobe workflows
  - [ ] network sharing / discovery
  - [ ] gaming / Xbox
  - [ ] remote access / admin workflows
- [ ] Review Balanced to make sure it contains moderate tradeoffs only.
- [ ] Split current aggressive philosophy into:
  - [ ] `Advanced (General)`
  - [ ] later optional scenario sets such as `Advanced Privacy` and `Advanced Hardening` if needed.

---

## 4. Advanced preset warning and normal-user guidance

### Rename the expert preset to Advanced and make the warning smarter, not just scarier

- [ ] The word “Advanced” sounds like a power-user option with tradeoffs.
- [ ] The warning dialog should explain categories of impact, not just say “high risk.”
- [ ] The dialog should recommend creating a restore point before continuing, and for Advanced it should strongly recommend it.

### Recommended modal structure

- [ ] **Title**: Advanced preset warning
- [ ] **Body**: This preset is intended for experienced users and may remove or disable Windows features, change update/network/security behavior, affect compatibility, and include changes that are difficult to undo.
- [ ] **Summary panel**:
  - [ ] selected count
  - [ ] medium-risk count
  - [ ] high-risk count
  - [ ] restart-required count
  - [ ] not-fully-restorable count
- [ ] **Buttons**:
  - [ ] Cancel
  - [ ] Create Restore Point
  - [ ] Preview Run
  - [ ] Continue Anyway

### Preset card copy for normal users

- [ ] **Minimal** — Small quality-of-life changes with minimal behavior changes.
- [ ] **Safe** — Recommended for most users. Low-risk cleanup and usability improvements.
- [ ] **Balanced** — More privacy and system tuning with moderate tradeoffs.
- [ ] **Advanced** — Experienced users only. Higher-risk, opinionated system changes.

### Restore point guidance

- [ ] Recommend a restore point before **Balanced**.
- [ ] Strongly recommend a restore point before **Advanced**.
- [ ] Add inline banner text when Balanced or Advanced is selected.
- [ ] Add optional “Create Restore Point” action directly in the flow.
- [ ] If restore-point creation fails, surface that clearly and continue only after acknowledgment.

### Normal-user expectation guidance

- [ ] In the README and GUI, clearly state:
  - [ ] Safe is the recommended default for normal users.
  - [ ] Balanced is for enthusiasts who understand moderate tradeoffs.
  - [ ] Advanced is not recommended for work/shared/family/domain-managed PCs.
- [ ] Add “Best for” and “Not recommended for” text under each preset.

---

## 5. GUI and UX recommendations

### The GUI is already one of Baseline’s strongest assets. The goal is not a redesign; it is refinement.

- [ ] Make the preset explanation panel clearer. When a user chooses a preset, show what it prioritizes, what it avoids, and who it is for.
- [ ] Add a compact “impact summary” bar above Preview Run: selected tweaks, high-risk, restart-required, restorable, and categories touched.
- [ ] Add visual differentiation between toggles, one-time actions, and uninstall/remove operations.
- [ ] Use stronger grouping inside categories: privacy, cleanup, compatibility, performance, hardening, and troubleshooting.
- [ ] Add “Show only selected”, “Show high-risk”, “Show restorable only”, and “Show gaming-related” filters.
- [ ] Expose a restore recommendation banner whenever Balanced or Advanced is selected.
- [ ] Add a “Why this preset includes this” section in Preview Run so users can understand the intent behind each batch.

### Recommended UX additions

- [ ] Add badges/icons for:
  - [ ] Toggle
  - [ ] Choice
  - [ ] Action
  - [ ] Uninstall / Remove
  - [ ] Requires restart
  - [ ] Not fully restorable
- [ ] Add a “Current state” chip where possible:
  - [ ] Enabled
  - [ ] Disabled
  - [ ] Default
  - [ ] Custom / Mixed
- [ ] Add a “Scenario tags” row in details: gaming, privacy, Office, network, Defender, update, UI.
- [ ] Add a “Blast radius” explanation for medium/high-risk items.
- [ ] Improve Preview Run output with sections:
  - [ ] Will change
  - [ ] Already in desired state
  - [ ] Requires restart
  - [ ] High-risk changes
- [ ] Add a post-run “What changed” summary.

### UI quality polish items

- [ ] Reduce repeated “Why this matters” clutter by using expandable details or a right-hand details pane.
- [ ] Make row spacing consistent between tabs.
- [ ] Ensure filter/search state is obvious when active.
- [ ] Add clearer persistent state for Advanced Mode and Light/Dark Mode.
- [ ] Ensure hidden advanced items cannot remain selected invisibly when Advanced Mode is turned off.

---

## 6. Add a real Gaming Mode

- [ ] **Why Gaming Mode matters**: Gaming is one of the cleanest ways for Baseline to stand out. A dedicated mode is easier to market than generic “performance tweaks,” and your manifests already include a gaming category with solid starting points.

### What Gaming Mode should be

- [ ] A focused mode for gaming systems, not a “disable everything” preset.
- [ ] Built around lower latency, clean overlays, optional Xbox adjustments, GPU-related compatibility settings, and conservative background reductions.
- [ ] Context-aware: keep it friendly for gamers who use Game Bar, overlays, Xbox services, or anti-cheat sensitive setups.

### Recommended Gaming Mode structure

- [ ] **Core gaming baseline**: GPU Scheduling, optional visual/latency tweaks, conservative background cleanup, and user-chosen Game Bar behavior.
- [ ] **Troubleshooting bucket**: Fullscreen Optimizations, Multiplane Overlay, network adapter power savings, and other “only if needed” fixes.
- [ ] **Competitive mode bucket**: stronger latency/performance tweaks with explicit warnings.
- [ ] **Streaming/content mode bucket**: preserve overlays, microphone, notifications, capture features, and Xbox integrations if desired.

### Rules for Gaming Mode

- [ ] Do not automatically disable Game Bar or Xbox features inside Gaming Mode. Make these choices explicit because many users rely on them.
- [ ] Keep Fullscreen Optimizations in a troubleshooting group because the manifest already treats disabling it as high risk.
- [ ] Offer profile variants such as Casual, Competitive, and Troubleshoot.
- [ ] Add a “Detect installed gaming apps / GPU vendors / Xbox components” step later if smarter defaults are desired.

### Concrete Gaming Mode deliverables

- [ ] Add a dedicated Gaming Mode screen or wizard.
- [ ] Add profile cards:
  - [ ] Casual Gaming
  - [ ] Competitive Gaming
  - [ ] Troubleshooting
  - [ ] Streaming / Content Creation
- [ ] Add explicit decision points for:
  - [ ] Game Bar
  - [ ] Xbox services
  - [ ] notifications
  - [ ] Fullscreen Optimizations
  - [ ] overlay preservation
- [ ] Add a gaming-specific Preview Run explanation.
- [ ] Add a gaming-specific rollback profile later.

---

## 7. Execution, logging, and recovery: the trust layer

- [ ] Normalize failures into clear categories: access denied, reboot required, already in desired state, missing dependency, unsupported OS/build, not applicable, network/download failure, partial success.
- [ ] Add per-item recovery hints and retry actions where safe.
- [ ] Separate “failed” from “skipped” and “not applicable.” This reduces false alarm fatigue.
- [ ] Add an end-of-run remediation panel with “Retry failed items” and “Open detailed log.”
- [ ] If restore point creation is available, link it before large or expert runs.

### Recommended failure summary output

- [ ] Successful changes
- [ ] Already in desired state
- [ ] Skipped by preset policy or unsupported environment
- [ ] Failed and recoverable
- [ ] Failed and manual intervention required
- [ ] Restart required to complete or verify

### Recovery and trust improvements

- [ ] Add machine-readable failure codes in the execution engine.
- [ ] Add canned remediation guidance:
  - [ ] run as admin
  - [ ] reboot and retry
  - [ ] unsupported on this build
  - [ ] blocked by current system state
  - [ ] network/download unavailable
- [ ] Add a “Retry all recoverable failures” button.
- [ ] Add a post-run export that includes a concise summary plus the raw detailed log.
- [ ] Expose partial success states where a tweak changed some but not all intended sub-actions.

---

## 8. GitHub release package and README strategy

- [ ] Lead with Baseline as the product name and keep “Windows debloater / optimizer / hardening utility” in the subtitle.
- [ ] Open the README with a polished hero screenshot and a very short value statement.
- [ ] Add a compatibility table: Windows 10 2019-current x86/x64/arm64, Windows 11 current x64/arm64, Server 2016-2025, PowerShell 5.1.
- [ ] Explain preset philosophy early. Most README readers will decide whether they trust the project based on that section alone.
- [ ] Include a “Recommended for normal users: Safe” statement high on the page.
- [ ] Add a dedicated “Before you run Advanced” warning block in the README.
- [ ] Include examples for GUI launch, headless execution, manifest validation, bootstrap, and preset import/export.

### What the first screen of your README should communicate

- [ ] What Baseline is.
- [ ] What operating systems and architectures it supports.
- [ ] Why it is different from one-off debloat scripts.
- [ ] Which preset normal users should choose.
- [ ] Why advanced users may still want it over older tools.

### README structure recommendation

- [ ] Hero screenshot
- [ ] One-paragraph product description
- [ ] Support matrix
- [ ] Why Baseline exists
- [ ] Preset overview
- [ ] Warning / restore guidance
- [ ] Quick start
- [ ] Screenshots
- [ ] Headless usage
- [ ] Validation and developer tooling
- [ ] FAQ / troubleshooting
- [ ] Disclaimer / support scope

### GitHub release packaging

- [ ] Ship a clean zip with consistent structure.
- [ ] Include release notes with:
  - [ ] preset changes
  - [ ] new modules
  - [ ] breaking changes
  - [ ] known issues
- [ ] Add changelog discipline before launch.
- [ ] Include a short “Who should use this release?” section in each release.

---

## 9. How Baseline stands out on top

### To win attention in a crowded space, Baseline needs a sharper identity than “another Windows tweak script.”

- [ ] Own the phrase **modular Windows configuration utility**. This sounds more serious than “debloater” alone.
- [ ] Win on preset trust. If users believe Safe really is safe, that becomes a major differentiator.
- [ ] Win on transparency. Preview Run, detailed descriptions, restart indicators, and restore recommendations should feel first-class.
- [ ] Win on scenario modes. Gaming Mode is the obvious first one; later Baseline can add Workstation, Privacy, and Recovery profiles.
- [ ] Win on quality of documentation. Most repos in this category undersell or oversell themselves. A clean README, screenshots, warning model, and change log will make Baseline look more mature immediately.

### Recommended positioning statements

- [ ] Baseline is not a one-click “strip Windows” script.
- [ ] Baseline is a guided configuration utility with presets, preview, and metadata-backed warnings.
- [ ] Baseline favors understandable opinionation over blind batch changes.
- [ ] Baseline is built for users who want control without living entirely in raw PowerShell.

---

## 10. Recommended roadmap before GitHub release

### Phase 1 — release critical

- [x] Rename the expert preset to Advanced.
- [ ] Tighten Safe so it truly matches its promise.
- [ ] Add Advanced warning modal with restore recommendation.
- [ ] Add preset explanation cards.
- [ ] Audit uninstall/remove actions in all mainstream presets.
- [ ] Add README warning philosophy and supported platform table.

### Phase 2 — trust and polish

- [ ] Add normalized failure categories.
- [ ] Add retry guidance and end-of-run recovery panel.
- [ ] Add impact summary bar.
- [ ] Add better toggle/action/remove visual distinction.
- [ ] Add selected/high-risk/restorable filters.

### Phase 3 — differentiation

- [ ] Ship Gaming Mode.
- [ ] Add scenario tags and scenario-aware filtering.
- [ ] Add better post-run summary / report export.
- [ ] Add preset generation from metadata.

### Phase 4 — leadership

- [ ] Add Workstation / Privacy / Recovery modes.
- [ ] Add smarter environment detection.
- [ ] Add better rollback / restore workflows.
- [ ] Add automated preset validation in CI.

---

## 11. Release readiness checklist

### Pass criteria

- [ ] Safe preset contains only low-regret items and is the recommended default.
- [ ] Advanced warning clearly explains what may happen and recommends a restore point.
- [ ] README presents Baseline as a polished product, not a raw script dump.
- [ ] Preset JSON and manifest tiers no longer contradict each other silently.
- [ ] Gaming Mode exists or is clearly on the near-term roadmap.
- [ ] Users can distinguish toggle vs action vs uninstall behavior easily.
- [ ] Log output is supplemented by recovery guidance, not just raw status lines.
- [ ] Balanced and Advanced both surface restore recommendations.
- [ ] Preview Run clearly summarizes risk, restart, and reversibility.

### Fail criteria

- [ ] Safe includes medium/high-friction networking, update, uninstall, or hardening behavior without clear justification.
- [ ] Advanced is still marketed as the best or fastest option instead of the expert option.
- [ ] The project launches publicly without a restore-point recommendation or clear preset philosophy.
- [ ] The GUI can hide advanced selections while still executing them silently.
- [ ] Failure output still treats “not applicable” as “failed.”

---

## 12. Final recommendation

- [ ] Baseline is already strong enough to attract attention.
- [ ] The top priority is to make the preset model match user expectations exactly.
- [ ] Safe must earn trust.
- [ ] Balanced must stay reasonable.
- [ ] Advanced must be honest, explicit, and expert-focused.
- [ ] Gaming Mode is the best next feature to help Baseline stand out.
- [ ] The combination that can put Baseline on top is:
  - [ ] better preset governance
  - [ ] a more informative warning/restore flow
  - [ ] polished recovery UX
  - [ ] scenario-driven modes
  - [ ] high-quality GitHub presentation

### Bottom line

- [ ] **Public beta for advanced users**: realistic now.
- [ ] **Broad public recommendation for normal users**: wait until preset discipline, restore guidance, and recovery UX are tightened.
- [ ] **Most important win condition**: make the product feel controlled, not just powerful.
